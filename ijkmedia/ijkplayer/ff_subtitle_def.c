//
//  ff_subtitle_def.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/3/5.
//

#include "ff_subtitle_def.h"
#include <memory.h>
#include <stdlib.h>

FFSubtitleBuffer *ff_gen_subtitle_image(int width, int height, int bpc)
{
    FFSubtitleBuffer *img = malloc(sizeof(FFSubtitleBuffer));
    bzero(img, sizeof(FFSubtitleBuffer));
    img->isImg = 1;
    img->width = width;
    img->height = height;
    img->stride = width * bpc;
    size_t size = height * img->stride;
    img->buffer = calloc(1, size);
    memset(img->buffer, 0, height * img->stride);
    return img;
}

FFSubtitleBuffer *ff_gen_subtitle_text(const char *text)
{
    FFSubtitleBuffer *img = malloc(sizeof(FFSubtitleBuffer));
    bzero(img, sizeof(FFSubtitleBuffer));
    if (text) {
        img->buffer = malloc(strlen(text) + 1);
        strcpy((char *)img->buffer, text);
    }
    return img;
}

void ff_subtitlebuffer_append_text(FFSubtitleBuffer* sb, const char *text)
{
    if (sb && !sb->isImg && text && strlen(text)) {
        int size = (int)strlen(text) + 1;
        if (sb->buffer) {
            size += strlen((char *)sb->buffer);
            size += 1;//\n
            char *buf = (char *)malloc(size);
            unsigned char *start = (unsigned char *)buf;
            strcpy(buf, (char *)sb->buffer);
            buf += strlen((char *)sb->buffer);
            *buf = '\n';
            buf += 1;
            strcpy(buf, text);
            free(sb->buffer);
            sb->buffer = start;
        } else {
            sb->buffer = malloc(size);
            strcpy((char *)sb->buffer, text);
        }
    }
}
