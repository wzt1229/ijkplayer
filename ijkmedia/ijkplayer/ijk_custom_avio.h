//
//  ijk_custom_avio.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/9/11.
//

#ifndef ijk_custom_avio_h
#define ijk_custom_avio_h

#include <stdio.h>

typedef struct AVIOContext AVIOContext;
typedef void * IJKCustomIOContext;

int ijk_custom_io_protocol_matched(const char *url);
IJKCustomIOContext ijk_custom_io_create(const char *url);
void ijk_custom_io_destroy(IJKCustomIOContext * cp);
AVIOContext * ijk_custom_io_get_avio(IJKCustomIOContext c);
char * ijk_custom_io_get_dummy_url(IJKCustomIOContext c);

#endif /* ijk_custom_avio_h */
