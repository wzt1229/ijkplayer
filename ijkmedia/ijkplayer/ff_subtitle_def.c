//
//  ff_subtitle_def.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/3/5.
//

#include "ff_subtitle_def_internal.h"
#include <memory.h>
#include <stdlib.h>

FFSubtitleBuffer *ff_subtitle_buffer_alloc_rgba32(SDL_Rectangle rect)
{
    if (rect.stride == 0) {
        rect.stride = rect.w * 4;
    } else {
        rect.stride *= 4;
    }
    
    FFSubtitleBuffer *img = malloc(sizeof(FFSubtitleBuffer));
    bzero(img, sizeof(FFSubtitleBuffer));
    img->rect = rect;
    size_t size = rect.h * rect.stride;
    img->data = calloc(1, size);
    memset(img->data, 0, size);
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

int isFFSubtitleBufferArrayDiff(FFSubtitleBufferPacket *a1, FFSubtitleBufferPacket *a2)
{
    if (a1 == a2) {
        return 0;
    }
    
    if (!a1 || !a2) {
        return 1;
    }
    
    if (a1->len != a2->len) {
        return 1;
    }
    
    for (int i = 0; i < a1->len; i++) {
        FFSubtitleBuffer *h1 = a1->e[i];
        FFSubtitleBuffer *h2 = a2->e[i];
        if (h1 != h2) {
            return 1;
        } else if (h1 == NULL) {
            return 0;
        } else {
            continue;
        }
    }
    return 0;
}

void FreeSubtitleBufferArray(FFSubtitleBufferPacket *a)
{
    if (a) {
        while (a->len > 0) {
            ff_subtitle_buffer_release(&a->e[--a->len]);
        }
    }
}

void ResetSubtitleBufferArray(FFSubtitleBufferPacket *dst, FFSubtitleBufferPacket *src)
{
    if (!dst) {
        return;
    }
    FreeSubtitleBufferArray(dst);
    
    if (!src) {
        return;
    }
    
    int i = 0;
    while (dst->len <= SUB_REF_MAX_LEN && i < src->len) {
        dst->e[dst->len++] = ff_subtitle_buffer_retain(src->e[i++]);
    }
    dst->scale = src->scale;
    dst->bottom_margin = src->bottom_margin;
    dst->width = src->width;
    dst->height = src->height;
    dst->isAss = src->isAss;
}
