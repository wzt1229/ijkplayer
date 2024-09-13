//
//  ijk_custom_avio_protocol.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/9/13.
//

#ifndef ijk_custom_avio_protocol_h
#define ijk_custom_avio_protocol_h

#include <stdio.h>

#define avio_ctx_buffer_size 128*1024

typedef struct AVIOContext AVIOContext;
typedef struct ijk_custom_avio_protocol {
    void *opaque;
    AVIOContext *avio_ctx;
    unsigned char *io_buffer;
    char *dummy_url;
    
    int (*read_packet)(void *, uint8_t *buf, int buf_size);
    int (*write_packet)(void *, uint8_t *buf, int buf_size);
    int64_t (*seek_packet)(void *, int64_t offset, int whence);
    void (*destroy)(void *opaque);
} ijk_custom_avio_protocol;

#endif /* ijk_custom_avio_protocol_h */
