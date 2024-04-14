//
//  ff_subtitle_def.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/3/5.
//

#ifndef ff_subtitle_def_h
#define ff_subtitle_def_h

#include <stdio.h>
#include <string.h>
#include "ijksdl_rectangle.h"

typedef struct FFSubtitleBuffer {
    SDL_Rectangle rect;
    unsigned char *data;
    int usedAss;
    int refCount;
} FFSubtitleBuffer;

FFSubtitleBuffer * ff_subtitle_buffer_retain(FFSubtitleBuffer *);
void ff_subtitle_buffer_release(FFSubtitleBuffer **);

typedef struct IJKSDLSubtitlePreference {
    char name[256];//font name
    float scale; //font scale,default 1.0
    uint32_t color;//text color
    uint32_t bgColor;//text bg color
    uint32_t strokeColor;//border color
    int strokeSize;//stroke size
    float bottomMargin;//[0.0,1.0]
} IJKSDLSubtitlePreference;

static inline IJKSDLSubtitlePreference ijk_subtitle_default_preference(void)
{
    return (IJKSDLSubtitlePreference){"", 1.0, 4294967295, 0, 255, 5, 0.025};
}

static inline int isIJKSDLSubtitlePreferenceEqual(IJKSDLSubtitlePreference* p1,IJKSDLSubtitlePreference* p2)
{
    if (!p1 || !p2) {
        return 0;
    }
    if (p1->scale != p2->scale ||
        p1->color != p2->color ||
        p1->bgColor != p2->bgColor ||
        p1->strokeColor != p2->strokeColor ||
        p1->strokeSize != p2->strokeSize ||
        p1->bottomMargin != p2->bottomMargin ||
        strcmp(p1->name, p2->name)
        ) {
        return 0;
    }
    return 1;
}

#endif /* ff_subtitle_def_h */
