//
//  ff_subtitle_def.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/3/5.
//

#ifndef ff_subtitle_def_h
#define ff_subtitle_def_h

#include <stdio.h>
#include "ijksdl_rectangle.h"

typedef struct FFSubtitleBuffer {
    int stride;
    SDL_Rectangle rect;
    unsigned char *data;
    int isImg;
    int usedAss;
    int refCount;
} FFSubtitleBuffer;

FFSubtitleBuffer * ff_subtitle_buffer_retain(FFSubtitleBuffer *);
void ff_subtitle_buffer_release(FFSubtitleBuffer **);

#endif /* ff_subtitle_def_h */
