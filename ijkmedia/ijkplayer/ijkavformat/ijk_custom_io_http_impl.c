//
//  ijk_custom_io_http_impl.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/9/19.
//

#include "ijk_custom_io_http_impl.h"
#include <libavutil/mem.h>
#include <libavutil/avstring.h>
#include <libavutil/error.h>
#include <libavformat/urldecode.h>
#include <libavformat/url.h>
#include <errno.h>
#include <fcntl.h>
#include <strings.h>

typedef struct ijk_custom_io_http_opaque {
    URLContext *url_context;
    int64_t offset;
} ijk_custom_io_http_opaque;

static int read(ijk_custom_io_protocol *p, uint8_t *buf, int buf_size)
{
    if (!p || !p->opaque) {
        return 0;
    }
    
    ijk_custom_io_http_opaque *http_opaque = (ijk_custom_io_http_opaque *)p->opaque;
    
    uint8_t *buf1 = buf;
    int buf_size1 = buf_size;
    
    while (buf_size1 > 0) {
        int read = http_opaque->url_context->prot->url_read(http_opaque->url_context, buf1, buf_size1);
        if (read == AVERROR_EOF) {
            printf("read eof\n");
        }
        if (read <= 0){
            break;
        }
        
        buf1 += read;
        buf_size1 -= read;
    }
    
    int read = buf_size - buf_size1;
    http_opaque->offset += read;
    
    return read;
}

static int write(ijk_custom_io_protocol *p, uint8_t *buf, int buf_size)
{
    if (!p || !p->opaque) {
        return 0;
    }
    ijk_custom_io_http_opaque *http_opaque = (ijk_custom_io_http_opaque *)p->opaque;
    int write = http_opaque->url_context->prot->url_write(http_opaque->url_context, buf, buf_size);
    return write;
}

static int64_t tell(ijk_custom_io_protocol *p)
{
    if (!p || !p->opaque) {
        return 0;
    }
    ijk_custom_io_http_opaque *http_opaque = (ijk_custom_io_http_opaque *)p->opaque;
    return http_opaque->offset;
}

static int64_t file_size(ijk_custom_io_protocol *p)
{
    if (!p || !p->opaque) {
        return 0;
    }
    ijk_custom_io_http_opaque *http_opaque = (ijk_custom_io_http_opaque *)p->opaque;
    int64_t size = http_opaque->url_context->prot->url_seek(http_opaque->url_context, 0, AVSEEK_SIZE);
    return size;
}

static int eof(ijk_custom_io_protocol *p)
{
    if (!p || !p->opaque) {
        return 0;
    }
    ijk_custom_io_http_opaque *smb2 = (ijk_custom_io_http_opaque *)p->opaque;
    return smb2->offset == file_size(p);
}

static int64_t seek(ijk_custom_io_protocol *p, int64_t offset, int origin)
{
    if (!p || !p->opaque) {
        return 0;
    }
    ijk_custom_io_http_opaque *http_opaque = (ijk_custom_io_http_opaque *)p->opaque;
    if (http_opaque->offset == offset) {
        return offset;
    }
    int64_t pos = http_opaque->url_context->prot->url_seek(http_opaque->url_context, offset, origin);
    http_opaque->offset = pos;
    return pos;
}

static void destroy_opaque(ijk_custom_io_http_opaque *p) {
    
    if (!p) {
        return;
    }
    
    ijk_custom_io_http_opaque *http_opaque = (ijk_custom_io_http_opaque *)p;
    
    if (http_opaque->url_context) {
        ffurl_closep(&http_opaque->url_context);
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
        av_free(io->opaque);
    }
    av_freep(p);
}

static int interrupt_cb(void *ctx)
{
    return 0;
}

static int init(ijk_custom_io_http_opaque *app, const char *url)
{
    bzero(app, sizeof(ijk_custom_io_http_opaque));
    
    int ret = 0;
    
    AVDictionary *inner_options = NULL;
    //    av_dict_copy(&inner_options, c->inner_options, 0);
    //        if (extra)
    //            av_dict_copy(&inner_options, extra, 0);
    
    const char *protocol_whitelist = "ijkio,ijkhttphook,concat,http,tcp,https,tls,file,bluray2,dvd,rtmp,rtsp,rtp,srtp,udp";
    
    AVIOInterruptCB cb = {&interrupt_cb, app};
    
    ret = ffurl_open_whitelist(&app->url_context,
                               url,
                               AVIO_FLAG_READ,
                               &cb,
                               &inner_options,
                               protocol_whitelist,
                               NULL,
                               NULL);
    return ret < 0;
}

ijk_custom_io_protocol * ijk_custom_io_create_http(const char *url)
{
    ijk_custom_io_http_opaque * http_opaque = av_malloc(sizeof(ijk_custom_io_http_opaque));
    if (!http_opaque) {
        return NULL;
    }
    
    //    const char *http_url = ff_urldecode(url, 0);
    
    if (0 != init(http_opaque, url)) {
        destroy_opaque(http_opaque);
        av_free(http_opaque);
        return NULL;
    }
    
    ijk_custom_io_protocol * protocol = av_malloc(sizeof(ijk_custom_io_protocol));
    
    protocol->opaque = http_opaque;
    protocol->read = &read;
    protocol->write = &write;
    protocol->seek = &seek;
    protocol->tell = &tell;
    protocol->eof = &eof;
    protocol->file_size = &file_size;
    protocol->destroy = &destroy;
    return protocol;
}
