//
//  ijk_custom_avio_smb2.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/9/13.
//

#include "ijk_custom_avio_protocol.h"

#include <libavformat/avio.h>
#include <libavutil/mem.h>
#include <libavutil/error.h>

#include <errno.h>
#include <fcntl.h>
#include <strings.h>
#include <smb2/smb2.h>
#include <smb2/libsmb2.h>
#include <smb2/libsmb2-raw.h>

#include "ijk_custom_avio.h"

typedef struct ijk_custom_avio_smb2 {
    struct smb2_context *smb2;
    struct smb2_url *url;
    struct smb2fh *fh;
    uint64_t offset;
    uint64_t file_size;
} ijk_custom_avio_smb2;

static int read_packet(void *ap, uint8_t *buf, int buf_size) {
    
    ijk_custom_avio_protocol *p = ap;
    if (!p || !p->opaque) {
        return 0;
    }
    ijk_custom_avio_smb2 *app = (ijk_custom_avio_smb2 *)p->opaque;
    int count = 0,total = 0;
    
    while ((count = smb2_pread(app->smb2, app->fh, buf, buf_size, app->offset)) != 0) {
        if (count == -EAGAIN) {
            continue;
        }
        if (count < 0) {
            fprintf(stderr, "Failed to read file. %s\n",
                    smb2_get_error(app->smb2));
            break;
        }
        app->offset += count;
        total += count;
        if (total >= buf_size) {
            break;
        }
    }
    
    return total;
}

static int write_packet(void *ap, uint8_t *buf, int buf_size) {
    ijk_custom_avio_protocol *p = ap;
    if (!p || !p->opaque) {
        return 0;
    }
    ijk_custom_avio_smb2 *app = (ijk_custom_avio_smb2 *)p->opaque;
    return smb2_write(app->smb2, app->fh, buf, buf_size);
}

static int64_t seek_packet(void *ap, int64_t offset, int whence) {
    
    ijk_custom_avio_protocol *p = ap;
    if (!p || !p->opaque) {
        return 0;
    }
    ijk_custom_avio_smb2 *app = (ijk_custom_avio_smb2 *)p->opaque;
    
    if (whence == AVSEEK_SIZE) {
        if (app->file_size == 0) {
            struct smb2_stat_64 st = {0};
            int64_t ret = smb2_stat(app->smb2, app->url->path, &st);
            app->file_size = ret < 0 ? AVERROR(errno) : st.smb2_size;
        }
        return app->file_size;
    } else {
        app->offset = offset;
    }
    return 0;
}

static void destroy(void *opaque) {
    
    if (!opaque) {
        return;
    }
    ijk_custom_avio_smb2 *app = (ijk_custom_avio_smb2 *)opaque;
    
    if (app) {
        if (app->fh && app->smb2) {
            smb2_close(app->smb2, app->fh);
        }
        if (app->smb2) {
            smb2_disconnect_share(app->smb2);
        }
        if (app->url) {
            smb2_destroy_url(app->url);
        }
        if (app->smb2) {
            smb2_destroy_context(app->smb2);
        }
        app->fh = NULL;
        app->smb2 = NULL;
        app->url = NULL;
        
    }
}

static void split2part(const char *str, char *userPart, char *pwdPart) {
    int i = 0;
    int userIndex = 0;
    int pwdIndex = 0;
    int foundDelimiter = 0;
    
    while (str[i]!= '\0') {
        if (str[i]== ':') {
            foundDelimiter = 1;
            i++;
            break;
        }
        userPart[userIndex++] = str[i++];
    }
    
    if (foundDelimiter) {
        while (str[i]!= '\0') {
            pwdPart[pwdIndex++] = str[i++];
        }
    }
    
    userPart[userIndex] = '\0';
    pwdPart[pwdIndex] = '\0';
}


static int init(ijk_custom_avio_smb2 *app, const char *aUrl)
{
    int err = 0;
    
    bzero(app, sizeof(ijk_custom_avio_smb2));
    
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
        char userPart[64] = {0};
        char pwdPart[64] = {0};
        split2part((char *)url->user, userPart, pwdPart);
        if (strlen(pwdPart) > 0) {
            smb2_set_password(app->smb2, pwdPart);
        }
        strcpy((char *)url->user, userPart);
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
    
    return 0;
failed:
    destroy(app);
    return err;
}

ijk_custom_avio_protocol * ijk_custom_io_create_smb2(const char *url)
{
    ijk_custom_avio_smb2 * app = av_malloc(sizeof(ijk_custom_avio_smb2));
    if (0 != init(app, url)) {
        av_free(app);
        return NULL;
    }
    
    ijk_custom_avio_protocol * protocol = av_malloc(sizeof(ijk_custom_avio_protocol));
    
    protocol->opaque = app;
    protocol->read_packet = &read_packet;
    protocol->seek_packet = &seek_packet;
    protocol->write_packet = &write_packet;
    protocol->destroy = &destroy;
    return protocol;
}
