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
    img->buffer = calloc(1, height * img->stride);
    memset(img->buffer, 0, img->stride * img->height);
    
    return img;
}

FFSubtitleBuffer *ff_gen_subtitle_text(const char *text)
{
    FFSubtitleBuffer *img = malloc(sizeof(FFSubtitleBuffer));
    bzero(img, sizeof(FFSubtitleBuffer));
    img->buffer = malloc(strlen(text) + 1);
    strcpy((char *)img->buffer, text);
    return img;
}
