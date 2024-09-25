//
//  ijk_custom_io_smb2_opaque_impl.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/9/19.
//
#include "ijk_custom_io_smb2_impl.h"
#include <libavutil/mem.h>
#include <libavutil/avstring.h>
#include <libavformat/urldecode.h>

#include <errno.h>
#include <fcntl.h>
#include <strings.h>

#include <smb2/smb2.h>
#include <smb2/libsmb2.h>
#include <smb2/libsmb2-raw.h>

typedef struct ijk_custom_io_smb2_opaque {
    struct smb2_context *smb2;
    struct smb2_url *url;
    struct smb2fh *fh;
    uint64_t offset;
    uint64_t file_size;
} ijk_custom_io_smb2_opaque;

static int read(ijk_custom_io_protocol *p, uint8_t *buf, int buf_size)
{
    if (!p || !p->opaque) {
        return 0;
    }
    ijk_custom_io_smb2_opaque *smb2 = (ijk_custom_io_smb2_opaque *)p->opaque;
    
    uint8_t *buf1 = buf;
    int buf_size1 = buf_size;
    
    while (buf_size1 > 0) {
        int read = smb2_read(smb2->smb2, smb2->fh, buf1, buf_size1);
        if (read == -EAGAIN) {
            continue;
        }
        if (read < 0) {
            fprintf(stderr, "Failed to read file. %s\n",
                    smb2_get_error(smb2->smb2));
            break;
        }
        if (read == 0) {
            //eof
            break;
        }
        smb2->offset += read;
        buf1 += read;
        buf_size1 -= read;
    }
    
    return buf_size - buf_size1;
}

static int write(ijk_custom_io_protocol *p, uint8_t *buf, int buf_size)
{
    if (!p || !p->opaque) {
        return 0;
    }
    ijk_custom_io_smb2_opaque *smb2 = (ijk_custom_io_smb2_opaque *)p->opaque;
    return smb2_write(smb2->smb2, smb2->fh, buf, buf_size);
}

static int64_t tell(ijk_custom_io_protocol *p)
{
    if (!p || !p->opaque) {
        return 0;
    }
    ijk_custom_io_smb2_opaque *smb2 = (ijk_custom_io_smb2_opaque *)p->opaque;
    return smb2->offset;
}

static int64_t file_size(ijk_custom_io_protocol *p)
{
    if (!p || !p->opaque) {
        return 0;
    }
    ijk_custom_io_smb2_opaque *smb2 = (ijk_custom_io_smb2_opaque *)p->opaque;
    
    if (smb2->file_size == -1) {
        struct smb2_stat_64 st = {0};
        int64_t ret = smb2_stat(smb2->smb2, smb2->url->path, &st);
        smb2->file_size = ret < 0 ? ret : st.smb2_size;
    }
    return smb2->file_size;
}

static int eof(ijk_custom_io_protocol *p) {
    if (!p || !p->opaque) {
        return 0;
    }
    ijk_custom_io_smb2_opaque *smb2 = (ijk_custom_io_smb2_opaque *)p->opaque;
    return smb2->offset == file_size(p);
}

static int64_t seek(ijk_custom_io_protocol *p, int64_t offset, int whence)
{
    if (!p || !p->opaque) {
        return 0;
    }
    ijk_custom_io_smb2_opaque *smb2 = (ijk_custom_io_smb2_opaque *)p->opaque;
    int64_t seeked = smb2_lseek(smb2->smb2, smb2->fh, offset, whence, NULL);
    smb2->offset = seeked;
    return seeked;
}

static void destroy_opaque(ijk_custom_io_smb2_opaque *opaque) {
    
    if (!opaque) {
        return;
    }
    
    if (opaque) {
        if (opaque->fh && opaque->smb2) {
            smb2_close(opaque->smb2, opaque->fh);
        }
        if (opaque->smb2) {
            smb2_disconnect_share(opaque->smb2);
            smb2_destroy_context(opaque->smb2);
        }
        if (opaque->url) {
            smb2_destroy_url(opaque->url);
        }
        opaque->fh = NULL;
        opaque->smb2 = NULL;
        opaque->url = NULL;
    }
}

static void destroy(ijk_custom_io_protocol **p)
{
    if (!p) {
        return;
    }
    ijk_custom_io_protocol *io = *p;
    if (io) {
        destroy_opaque(io->opaque);
    }
    av_freep(p);
}

static int init(ijk_custom_io_smb2_opaque *app, const char *aUrl)
{
    int err = 0;
    
    bzero(app, sizeof(ijk_custom_io_smb2_opaque));
    
    struct smb2_context *smb2 = smb2_init_context();
    app->smb2 = smb2;
    
    if (app->smb2 == NULL) {
        fprintf(stderr, "Failed to init context\n");
        err = -1;
        goto failed;
    }
    
    struct smb2_url *url = smb2_parse_url(app->smb2, aUrl);
    
    if (url == NULL) {
        fprintf(stderr, "Failed to parse url: %s\n",
                smb2_get_error(app->smb2));
        err = -2;
        goto failed;
    } else {
        char *user = strchr(url->user, ':');
        if (user) {
            *user = '\0';
            char *password = user + 1;
            if (strlen(password) > 0) {
                smb2_set_password(app->smb2, password);
            }
        }
        if (url->domain) {
            smb2_set_domain(app->smb2, url->domain);
        }
        app->url = url;
    }
    
    smb2_set_security_mode(smb2, SMB2_NEGOTIATE_SIGNING_ENABLED);
    if (smb2_connect_share(smb2, url->server, url->share, url->user) != 0) {
        printf("smb2_connect_share failed. %s\n", smb2_get_error(smb2));
        err = -3;
        goto failed;
    }
    
    struct smb2fh *fh = smb2_open(smb2, url->path, O_RDONLY);
    app->fh = fh;
    if (fh == NULL) {
        printf("smb2_open failed. %s\n", smb2_get_error(smb2));
        err = -4;
        goto failed;
    }
    app->file_size = -1;
    return 0;
failed:
    return err;
}

ijk_custom_io_protocol * ijk_custom_io_create_smb2(const char *url)
{
    ijk_custom_io_smb2_opaque * smb2_opaque = av_malloc(sizeof(ijk_custom_io_smb2_opaque));
    if (!smb2_opaque) {
        return NULL;
    }
    
    const char *smb_url = av_strireplace(url, "smb2", "smb");
    smb_url = ff_urldecode(smb_url, 0);
    
    if (0 != init(smb2_opaque, smb_url)) {
        destroy_opaque(smb2_opaque);
        av_free(smb2_opaque);
        return NULL;
    }
    
    ijk_custom_io_protocol * protocol = av_malloc(sizeof(ijk_custom_io_protocol));
    
    protocol->opaque = smb2_opaque;
    protocol->read = &read;
    protocol->write = &write;
    protocol->seek = &seek;
    protocol->tell = &tell;
    protocol->eof = &eof;
    protocol->file_size = &file_size;
    protocol->destroy = &destroy;
    return protocol;
}
