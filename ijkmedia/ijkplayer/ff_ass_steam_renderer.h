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

typedef struct FF_ASS_Renderer FF_ASS_Renderer;
typedef struct AVStream AVStream;

typedef struct FF_ASS_Renderer_Format {
    const AVClass *priv_class;
    int priv_data_size;
    int (*init)(struct FF_ASS_Renderer *);
    int (*set_subtitle_header)(struct FF_ASS_Renderer *s, uint8_t *subtitle_header, int subtitle_header_size);
    void (*set_attach_font)(FF_ASS_Renderer *s, AVStream *st);
    void (*set_video_size)(struct FF_ASS_Renderer *s, int w, int h);
    void (*process_chunk)(struct FF_ASS_Renderer *, char *ass_line, int64_t start, int64_t duration);
    int  (*render_frame)(struct FF_ASS_Renderer *, double time_ms, FFSubtitleBuffer ** buffer);
    void (*update_margin)(FF_ASS_Renderer *s, int t, int b, int l, int r);
    void (*uninit)(struct FF_ASS_Renderer *);
} FF_ASS_Renderer_Format;

typedef struct FF_ASS_Renderer {
    void *priv_data;
    const FF_ASS_Renderer_Format *iformat;
    int refCount;
} FF_ASS_Renderer;

FF_ASS_Renderer *ff_ass_render_create_default(uint8_t *subtitle_header, int subtitle_header_size, int video_w, int video_h, AVDictionary *opts);

FF_ASS_Renderer * ff_ass_render_retain(FF_ASS_Renderer *ar);
void ff_ass_render_release(FF_ASS_Renderer **arp);

//buff need release
int ff_ass_render_image(FF_ASS_Renderer * assRenderer, float begin, FFSubtitleBuffer **buff);

void ff_ass_process_chunk(FF_ASS_Renderer * assRenderer, const char *ass_line, float begin, float end);

#endif /* ff_ass_steam_renderer_h */
