//
//  ff_subtitle_def.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/3/5.
//

#include "ff_subtitle_def_internal.h"
#include <memory.h>
#include <stdlib.h>

FFSubtitleBuffer *ff_subtitle_buffer_alloc_image(SDL_Rectangle rect, int bpc)
{
    FFSubtitleBuffer *img = malloc(sizeof(FFSubtitleBuffer));
    bzero(img, sizeof(FFSubtitleBuffer));
    img->rect = rect;
    img->stride = rect.w * bpc;
    size_t size = rect.h * img->stride;
    img->data = calloc(1, size);
    memset(img->data, 0, rect.h * img->stride);
    img->refCount = 1;
    return img;
}

FFSubtitleBuffer * ff_subtitle_buffer_retain(FFSubtitleBuffer *sb)
{
    if (sb) {
        __atomic_add_fetch(&sb->refCount, 1, __ATOMIC_RELEASE);
    }
    return sb;
}

void ff_subtitle_buffer_release(FFSubtitleBuffer **sbp)
{
    if (sbp) {
        FFSubtitleBuffer *sb = *sbp;
        if (sb) {
            if (__atomic_add_fetch(&sb->refCount, -1, __ATOMIC_RELEASE) == 0) {
                free(sb->data);
                free(sb);
            }
            *sbp = NULL;
        }
    }
}

