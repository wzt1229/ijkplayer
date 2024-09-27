//
//  ijkbluray_custom_fs_smb2.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/9/13.
//

#include "ijkbluray_custom_fs.h"
#include "ijkblurayfsprotocol.h"
#include <libavformat/url.h>
#include <libavutil/mem.h>
#include <libavutil/error.h>
#include <libavutil/avstring.h>
#include <memory.h>

#ifndef UDF_BLOCK_SIZE
#  define UDF_BLOCK_SIZE  2048
#endif

typedef struct ff_builtin_io {
    URLContext *url_context;
    int64_t offset;
} ff_builtin_io;

static int64_t seek(ff_builtin_io *io, int64_t offset, int origin)
{
    if (!io) {
        return 0;
    }
    if (io->offset == offset) {
        return offset;
    }
    int64_t pos = io->url_context->prot->url_seek(io->url_context, offset, origin);
    io->offset = pos;
    return pos;
}

static int read(ff_builtin_io *io, uint8_t *buf, int buf_size)
{
    if (!io) {
        return 0;
    }
    
    uint8_t *buf1 = buf;
    int buf_size1 = buf_size;
    
    while (buf_size1 > 0) {
        int read = io->url_context->prot->url_read(io->url_context, buf1, buf_size1);
        if (read == AVERROR_EOF) {
            av_log(NULL, AV_LOG_INFO, "bluray costom fs read eof\n");
        }
        if (read <= 0){
            break;
        }
        
        io->offset += read;
        buf1 += read;
        buf_size1 -= read;
    }
    
    return buf_size - buf_size1;
}

static int read_blocks(void * fs_handle, void *buf, int lba, int num_blocks)
{
    ff_builtin_io * io = fs_handle;
    int got = -1;
    int64_t pos = (int64_t)lba * UDF_BLOCK_SIZE;
    
    seek(io, pos, SEEK_SET);
    int bytes = read(io, (uint8_t*)buf, num_blocks * UDF_BLOCK_SIZE);
    if (bytes > 0) {
        got = (int)(bytes / UDF_BLOCK_SIZE);
    }
    return got;
}

static void destroy_opaque(ff_builtin_io *p) {
    
    if (!p) {
        return;
    }
    
    ff_builtin_io *io = (ff_builtin_io *)p;
    
    if (io->url_context) {
        ffurl_closep(&io->url_context);
    }
}

void ijk_destroy_bluray_custom_access(fs_access **p)
{
    if (p) {
        fs_access *access = *p;
        if (access) {
            ff_builtin_io *io = access->fs_handle;
            if (io) {
                destroy_opaque(io);
                av_free(io);
            }
        }
        av_freep(p);
    }
}

static int interrupt_cb(void *ctx)
{
    return 0;
}


static int init(ff_builtin_io *app, const char *url)
{
    bzero(app, sizeof(ff_builtin_io));
    
    int ret = 0;
    
    char * protocol_whitelist = "ijkio,ijkhttphook,concat,http,tcp,https,tls,file,bluray2,smb2,dvd,rtmp,rtsp,rtp,srtp,udp";
    
    AVIOInterruptCB cb = {&interrupt_cb, app};
    
    ret = ffurl_open_whitelist(&app->url_context,
                               url,
                               AVIO_FLAG_READ,
                               &cb,
                               NULL,
                               protocol_whitelist,
                               NULL,
                               NULL);
    return ret < 0;
}

// 构建fs_access结构体
fs_access * ijk_create_bluray_custom_access(const char *url)
{
    ff_builtin_io * io = av_malloc(sizeof(ff_builtin_io));
    if (!io) {
        return NULL;
    }
    
    int ret = init(io, url);
    if (0 != ret) {
        av_log(NULL, AV_LOG_ERROR, "can't open url %s,error:%s",url,av_err2str(ret));
        destroy_opaque(io);
        av_free(io);
        return NULL;
    }
    
    if (io) {
        fs_access *access = av_malloc(sizeof(fs_access));
        access->fs_handle = io;
        access->read_blocks = read_blocks;
        return access;
    }
    return NULL;
}
