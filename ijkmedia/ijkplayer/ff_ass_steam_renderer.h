//
//  ff_ass_steam_renderer.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/3/5.
//

#ifndef ff_ass_steam_renderer_h
#define ff_ass_steam_renderer_h

#include <ass/ass.h>
#include <libavutil/log.h>
#include <libavutil/opt.h>
#include "ff_subtitle_def.h"

struct FF_ASS_Renderer; struct AVFormatContext;
typedef struct FF_ASS_Renderer_Format {
    const AVClass *priv_class;
    int priv_data_size;
    int  (*init)(struct FF_ASS_Renderer *s, struct AVFormatContext *fmt, uint8_t *subtitle_header, int subtitle_header_size);
    void (*uninit)(struct FF_ASS_Renderer *);
    void (*set_video_size)(struct FF_ASS_Renderer *s, int w, int h);
    void (*process_chunk)(struct FF_ASS_Renderer *, char *ass_line, int64_t start, int64_t duration);
    void (*render_frame)(struct FF_ASS_Renderer *, double time_ms, FFSubtitleBuffer **img);
} FF_ASS_Renderer_Format;

typedef struct FF_ASS_Renderer {
    void *priv_data;
    const FF_ASS_Renderer_Format *iformat;
} FF_ASS_Renderer;

FF_ASS_Renderer *ffAss_create_default(struct AVFormatContext *fmt, uint8_t *subtitle_header, int subtitle_header_size, int video_w, int video_h, AVDictionary *opts);
void ffAss_destroy(FF_ASS_Renderer **sp);

#endif /* ff_ass_steam_renderer_h */
