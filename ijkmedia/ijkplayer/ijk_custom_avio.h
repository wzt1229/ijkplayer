//
//  ijk_custom_avio.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/9/11.
//

#ifndef ijk_custom_avio_h
#define ijk_custom_avio_h

#include "ijk_custom_avio_protocol.h"

typedef struct AVIOContext AVIOContext;

int ijk_custom_io_protocol_matched(const char *url);
ijk_custom_avio_protocol * ijk_custom_io_create(const char *url);
void ijk_custom_avio_destroy(ijk_custom_avio_protocol **pp);
AVIOContext * ijk_custom_io_get_avio(ijk_custom_avio_protocol * c);
char * ijk_custom_io_get_dummy_url(ijk_custom_avio_protocol * c);

#endif /* ijk_custom_avio_h */
