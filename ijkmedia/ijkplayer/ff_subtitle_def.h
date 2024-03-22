//
//  ff_subtitle_def.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/3/5.
//

#ifndef ff_subtitle_def_h
#define ff_subtitle_def_h

#include <stdio.h>

typedef struct FFSubtitleBuffer {
    int width, height, stride;
    unsigned char *data;
    int isImg;
    int usedAss;
    int refCount;
} FFSubtitleBuffer;

FFSubtitleBuffer *ff_subtitle_buffer_alloc_image(int width, int height, int bpc);
FFSubtitleBuffer *ff_subtitle_buffer_alloc_text(const char *text);

void ff_subtitle_buffer_append_text(FFSubtitleBuffer* sb, const char *text);
FFSubtitleBuffer * ff_subtitle_buffer_retain(FFSubtitleBuffer *);
void ff_subtitle_buffer_release(FFSubtitleBuffer **);

#endif /* ff_subtitle_def_h */
