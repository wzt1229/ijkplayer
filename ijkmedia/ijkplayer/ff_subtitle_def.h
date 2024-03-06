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
    unsigned char *buffer;
    int isImg;//
    int usedAss;
} FFSubtitleBuffer;

FFSubtitleBuffer *ff_gen_subtitle_image(int width, int height, int bpc);
FFSubtitleBuffer *ff_gen_subtitle_text(const char *text);

#endif /* ff_subtitle_def_h */
