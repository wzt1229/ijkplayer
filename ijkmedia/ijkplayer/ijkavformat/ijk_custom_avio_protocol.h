//
//  ijk_custom_avio_protocol.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/9/13.
//

#ifndef ijk_custom_avio_protocol_h
#define ijk_custom_avio_protocol_h

#include <stdio.h>

typedef struct AVIOContext AVIOContext;
typedef struct ijk_custom_avio_protocol ijk_custom_avio_protocol;

typedef struct ijk_custom_avio_protocol {
    void *opaque;
    AVIOContext * (*get_avio)(ijk_custom_avio_protocol *);
    char * (*get_dummy_url)(ijk_custom_avio_protocol *);
    void (*destroy)(ijk_custom_avio_protocol **);
} ijk_custom_avio_protocol;

#endif /* ijk_custom_avio_protocol_h */
