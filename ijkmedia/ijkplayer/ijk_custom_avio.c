//
//  ijk_custom_avio.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/9/11.
//

#include "ijk_custom_avio.h"
#include <libavformat/avio.h>
#include <libavutil/mem.h>
#include <libavutil/error.h>

#include <strings.h>
#include <errno.h>
#include <fcntl.h>
#include <smb2/smb2.h>
#include <smb2/libsmb2.h>
#include <smb2/libsmb2-raw.h>

static int avio_ctx_buffer_size = 128*1024;

typedef struct avio_application {
    AVIOContext *avio_ctx;
    unsigned char *io_buffer;
    struct smb2_context *smb2;
    struct smb2_url *url;
    struct smb2fh *fh;
    uint64_t offset;
    uint64_t file_size;
    char *dummy_url;
} avio_application;

static int read_packet(void *opaque, uint8_t *buf, int buf_size) {
    
    avio_application *app = (avio_application *)opaque;
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

static int write_packet(void *opaque, uint8_t *buf, int buf_size) {
    avio_application *app = (avio_application *)opaque;
    return smb2_write(app->smb2, app->fh, buf, buf_size);
}

static int64_t seek_packet(void *opaque, int64_t offset, int whence) {
    avio_application *app = (avio_application *)opaque;
    
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

static void destroy(avio_application *app) {
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
        
        if (app->dummy_url) {
            av_free(app->dummy_url);
        }
//        wtf?who freed my buffer?
//        if (app->io_buffer) {
//            av_free(app->io_buffer);
//        }
        
        if (app->avio_ctx) {
            avio_context_free(&app->avio_ctx);
        }
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


static int init(avio_application *app, const char *aUrl)
{
    int err = 0;
    
    bzero(app, sizeof(avio_application));
    
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
    
    unsigned char *io_buffer = av_malloc(avio_ctx_buffer_size);
    app->io_buffer = io_buffer;
    
    if (!io_buffer) {
        goto failed;
    }
    
    AVIOContext *avio_ctx = avio_alloc_context(io_buffer, avio_ctx_buffer_size,
                                               0, app, &read_packet, &write_packet, &seek_packet);
    app->avio_ctx = avio_ctx;
    if (!avio_ctx) {
        fprintf(stderr, "Failed to alloc avio\n");
        goto failed;
    }
    
    return 0;
failed:
    destroy(app);
    return err;
}

static char *convert_scheme(const char *url, const char *scheme)
{
    const char *token = strstr(url, "://");
    int buffer_size = (int)strlen(token) + (int)strlen(scheme) + 1;
    char *buffer = av_malloc(buffer_size);
    bzero(buffer, buffer_size);
    
    memcpy(buffer, scheme, strlen(scheme));
    memcpy(buffer + strlen(scheme), token, strlen(token));
    return buffer;
}

int ijk_custom_io_protocol_matched(const char *url)
{
    if (strncmp(url, "smb2", 4) == 0) {
        return 1;
    }
    return 0;
}

IJKCustomIOContext ijk_custom_io_create(const char *url)
{
    avio_application * app = av_malloc(sizeof(avio_application));
    char *smb_url = convert_scheme(url, "smb");
    
    if (0 != init(app, smb_url)) {
        av_free(app);
        if (smb_url) {
            av_free(smb_url);
        }
        return NULL;
    }
    if (smb_url) {
        av_free(smb_url);
    }
    app->dummy_url = convert_scheme(url, "http");
    return app;
}

void ijk_custom_io_destroy(IJKCustomIOContext * cp)
{
    if (cp) {
        avio_application * app = (avio_application *) *cp;
        destroy(app);
        av_free(app);
        *cp = NULL;
    }
}

AVIOContext * ijk_custom_io_get_avio(IJKCustomIOContext c)
{
    avio_application * app = c;
    return app ? app->avio_ctx : NULL;
}

char * ijk_custom_io_get_dummy_url(IJKCustomIOContext c)
{
    avio_application * app = c;
    return app ? av_strdup(app->dummy_url) : NULL;
}
