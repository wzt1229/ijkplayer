//
//  ijk_custom_avio.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/9/11.
//

#include "ijk_custom_avio.h"
#include <libavformat/avio.h>
#include <libavutil/error.h>
#include <libavutil/mem.h>
#include <libavutil/avstring.h>
#include <strings.h>
#include "ijk_custom_avio_smb2.h"
#include "ijk_custom_avio_protocol.h"

void ijk_custom_avio_destroy(ijk_custom_avio_protocol **pp) {
    if (pp) {
        ijk_custom_avio_protocol *p = *pp;
        if (p) {
            if (p->dummy_url) {
                av_free(p->dummy_url);
            }
            //malloc: double free for ptr 0x148008000
            //wtf?who freed my buffer?
//            if (p->io_buffer) {
//                av_free(p->io_buffer);
//            }
            
            if (p->avio_ctx) {
                avio_context_free(&p->avio_ctx);
            }
            
            if (p->opaque) {
                p->destroy(p->opaque);
                av_free(p->opaque);
                p->opaque = NULL;
            }
        }
        av_freep(pp);
    }
}

int ijk_custom_io_protocol_matched(const char *url)
{
    if (strncmp(url, "smb2", 4) == 0) {
        return 1;
    }
    return 0;
}

ijk_custom_avio_protocol * ijk_custom_io_create(const char *url)
{
    const char *diskname = url;

    if (av_strstart(url, "smb2", &diskname)) {
        const char *smb_url = av_strireplace(url, "smb2", "smb");
        
        ijk_custom_avio_protocol *p = ijk_custom_io_create_smb2(smb_url);
        if (p) {
            
            p->dummy_url = av_strdup(av_strireplace(url, "smb2", "http"));
            
            unsigned char *io_buffer = av_malloc(avio_ctx_buffer_size);
            
            if (!io_buffer) {
                p->destroy(p->opaque);
            }
            p->io_buffer = io_buffer;
            AVIOContext *avio_ctx = avio_alloc_context(io_buffer, avio_ctx_buffer_size,
                                                       0, p, p->read_packet, p->write_packet, p->seek_packet);
            p->avio_ctx = avio_ctx;
            if (!avio_ctx) {
                fprintf(stderr, "Failed to alloc avio\n");
                p->destroy(p->opaque);
                ijk_custom_avio_destroy(&p);
            }
            return p;
        }
    }
    return NULL;
}

AVIOContext * ijk_custom_io_get_avio(ijk_custom_avio_protocol *p)
{
    return p ? p->avio_ctx : NULL;
}

char * ijk_custom_io_get_dummy_url(ijk_custom_avio_protocol *p)
{
    return p ? av_strdup(p->dummy_url) : NULL;
}
