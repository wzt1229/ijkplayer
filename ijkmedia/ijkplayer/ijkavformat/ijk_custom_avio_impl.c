//
//  ijk_custom_avio_impl.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/9/19.
//

#include "ijk_custom_avio_impl.h"

#include <string.h>
#include <libavformat/avio.h>
#include <libavutil/mem.h>
#include <libavutil/error.h>
#include <libavutil/avstring.h>
#include "ijk_custom_io_smb2_impl.h"

#define avio_ctx_buffer_size 128*1024

typedef struct ijk_custom_avio_opaque {
    ijk_custom_io_protocol *custom_io;
    AVIOContext *avio_ctx;
    unsigned char *io_buffer;
    char *dummy_url;
} ijk_custom_avio_opaque;

static void destroy(ijk_custom_avio_protocol **pp) {
    if (pp) {
        ijk_custom_avio_protocol *p = *pp;
        if (p) {
            ijk_custom_avio_opaque *avio = p->opaque;
            if (avio) {
                if (avio->custom_io) {
                    avio->custom_io->destroy(&avio->custom_io);
                }
                
                //malloc: double free for ptr 0x148008000
                //wtf?who freed my buffer?
                //                if (avio->io_buffer) {
                //                    av_free(avio->io_buffer);
                //                    avio->io_buffer = NULL;
                //                }
                
                if (avio->dummy_url) {
                    av_free(avio->dummy_url);
                    avio->dummy_url = NULL;
                }
                
                if (avio->avio_ctx) {
                    avio_context_free(&avio->avio_ctx);
                }
                
                av_free(avio);
                p->opaque = NULL;
            }
        }
        av_freep(pp);
    }
}

static AVIOContext * get_avio(ijk_custom_avio_protocol *protocol)
{
    if (!protocol) {
        return NULL;
    }
    ijk_custom_avio_opaque *avio = protocol->opaque;
    return avio ? avio->avio_ctx : NULL;
}

static char * get_dummy_url(ijk_custom_avio_protocol *protocol)
{
    if (!protocol) {
        return NULL;
    }
    ijk_custom_avio_opaque *avio = protocol->opaque;
    return avio ? avio->dummy_url : NULL;
}

static int read(void *opaque, uint8_t *buf, int buf_size) {
    if (!opaque) {
        return -1;
    }
    ijk_custom_avio_protocol *protocol = opaque;
    ijk_custom_avio_opaque *avio = protocol->opaque;
    if (!avio || !avio->custom_io) {
        return -1;
    }
    return avio->custom_io->read(avio->custom_io, buf, buf_size);
}

static int write(void *opaque, uint8_t *buf, int buf_size) {
    if (!opaque) {
        return -1;
    }
    ijk_custom_avio_protocol *protocol = opaque;
    ijk_custom_avio_opaque *avio = protocol->opaque;
    if (!avio || !avio->custom_io) {
        return -1;
    }
    return avio->custom_io->write(avio->custom_io, buf, buf_size);
}

static int64_t seek(void *opaque, int64_t offset, int whence)
{
    if (!opaque) {
        return -1;
    }
    ijk_custom_avio_protocol *protocol = opaque;
    ijk_custom_avio_opaque *avio = protocol->opaque;
    if (!avio || !avio->custom_io) {
        return -1;
    }
    
    if (whence == AVSEEK_SIZE) {
        return avio->custom_io->file_size(avio->custom_io);
    } else {
        return avio->custom_io->seek(avio->custom_io, offset, SEEK_SET);
    }
}

static ijk_custom_avio_protocol * create_avio_protocol(ijk_custom_io_protocol *io, const char *dummy_url)
{
    ijk_custom_avio_opaque *io_opaque = NULL;
    unsigned char *io_buffer = NULL;
    AVIOContext *avio_ctx = NULL;
    ijk_custom_avio_protocol *protocol = NULL;
    
    if (!io) {
        return NULL;
    }
    
    io_opaque = av_malloc(sizeof(ijk_custom_avio_opaque));
    if (!io_opaque) {
        goto failed;
    }
    io_opaque->custom_io = io;
    
    io_buffer = av_malloc(avio_ctx_buffer_size);
    if (!io_buffer) {
        goto failed;
    }
    
    io_opaque->io_buffer = io_buffer;
    io_opaque->dummy_url = av_strdup(dummy_url);
    
    protocol = av_malloc(sizeof(ijk_custom_avio_protocol));
    if (!protocol) {
        goto failed;
    }
    
    protocol->opaque = io_opaque;
    protocol->get_avio = &get_avio;
    protocol->get_dummy_url = &get_dummy_url;
    protocol->destroy = &destroy;
    
    avio_ctx = avio_alloc_context(io_buffer, avio_ctx_buffer_size,
                                  0, protocol, &read, &write, &seek);
    if (!avio_ctx) {
        goto failed;
    }
    io_opaque->avio_ctx = avio_ctx;
    return protocol;
    
failed:
    if (io_opaque) {
        av_free(io_opaque);
    }
    if (io_buffer) {
        av_free(io_buffer);
    }
    if (avio_ctx) {
        avio_context_free(&avio_ctx);
    }
    if (protocol) {
        av_free(protocol);
    }
    return NULL;
}

ijk_custom_avio_protocol * ijk_custom_avio_create(const char *url)
{
    if (av_strstart(url, "smb2", NULL)) {
        ijk_custom_io_protocol *io = ijk_custom_io_create_smb2(url);
        return create_avio_protocol(io, av_strireplace(url, "smb2", "http"));
    }
    return NULL;
}
