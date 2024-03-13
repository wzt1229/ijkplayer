//
//  ff_ass_steam_renderer.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/3/5.
//

#include "ff_ass_steam_renderer.h"
#include "libavcodec/avcodec.h"
#include "libavformat/avformat.h"
#include "libavutil/avstring.h"
#include "libavutil/imgutils.h"
#include "libavutil/opt.h"
#include "libavutil/parseutils.h"

typedef struct FF_ASS_Context {
    const AVClass *priv_class;
    ASS_Library  *library;
    ASS_Renderer *renderer;
    ASS_Track    *track;
    
    char *fontsdir;
    char *charenc;
    char *force_style;
    int stream_index;
    int alpha;
    int original_w, original_h;
    int shaping;
} FF_ASS_Context;

#define OFFSET(x) offsetof(FF_ASS_Context, x)
#define FLAGS AV_OPT_FLAG_VIDEO_PARAM
    
const AVOption ff_ass_options[] = {
    {"fontsdir",       "set the directory containing the fonts to read",           OFFSET(fontsdir),   AV_OPT_TYPE_STRING,     {.str = NULL},  0, 0, FLAGS },
    {"alpha",          "enable processing of alpha channel",                       OFFSET(alpha),      AV_OPT_TYPE_BOOL,       {.i64 = 0   },         0,        1, FLAGS },
    {"charenc",      "set input character encoding", OFFSET(charenc),      AV_OPT_TYPE_STRING, {.str = NULL}, 0, 0, FLAGS},
    {"stream_index", "set stream index",             OFFSET(stream_index), AV_OPT_TYPE_INT,    { .i64 = -1 }, -1,       INT_MAX,  FLAGS},
    {"si",           "set stream index",             OFFSET(stream_index), AV_OPT_TYPE_INT,    { .i64 = -1 }, -1,       INT_MAX,  FLAGS},
    {"force_style",  "force subtitle style",         OFFSET(force_style),  AV_OPT_TYPE_STRING, {.str = NULL}, 0, 0, FLAGS},
    {NULL},
};

/* libass supports a log level ranging from 0 to 7 */
static const int ass_libavfilter_log_level_map[] = {
    [0] = AV_LOG_FATAL,     /* MSGL_FATAL */
    [1] = AV_LOG_ERROR,     /* MSGL_ERR */
    [2] = AV_LOG_WARNING,   /* MSGL_WARN */
    [3] = AV_LOG_WARNING,   /* <undefined> */
    [4] = AV_LOG_INFO,      /* MSGL_INFO */
    [5] = AV_LOG_INFO,      /* <undefined> */
    [6] = AV_LOG_VERBOSE,   /* MSGL_V */
    [7] = AV_LOG_DEBUG,     /* MSGL_DBG2 */
};

static void ass_log(int ass_level, const char *fmt, va_list args, void *ctx)
{
    const int ass_level_clip = av_clip(ass_level, 0,
        FF_ARRAY_ELEMS(ass_libavfilter_log_level_map) - 1);
    int level = ass_libavfilter_log_level_map[ass_level_clip];
    av_vlog(ctx, level, fmt, args);
}

/* Init libass */

static int init_libass(FF_ASS_Renderer *s)
{
    FF_ASS_Context *ass = s->priv_data;
    if (!ass) {
        return -1;
    }
    
    ass->library = ass_library_init();
    if (!ass->library) {
        av_log(ass, AV_LOG_ERROR, "Could not initialize libass.\n");
        return AVERROR(EINVAL);
    }
    
    ass_set_message_cb(ass->library, ass_log, ass);
    ass_set_fonts_dir(ass->library, ass->fontsdir);
    ass_set_extract_fonts(ass->library, 1);
    ass->renderer = ass_renderer_init(ass->library);
    
    if (!ass->renderer) {
        av_log(ass, AV_LOG_ERROR, "Could not initialize libass renderer.\n");
        return AVERROR(EINVAL);
    }

    ass->track = ass_new_track(ass->library);
    if (!ass->track) {
        av_log(s, AV_LOG_ERROR, "Could not create a libass track\n");
        return AVERROR(EINVAL);
    }
    
    return 0;
}

static void set_video_size(FF_ASS_Renderer *s, int w, int h)
{
    FF_ASS_Context *ass = s->priv_data;
    if (!ass) {
        return;
    }
    //放大两倍，使得 retina 屏显示清楚
    w *= 2;
    h *= 2;

    ass->original_w = w;
    ass->original_h = h;
    
    ass_set_frame_size(ass->renderer, w, h);
    ass_set_storage_size(ass->renderer, w, h);
    ass_set_font_scale(ass->renderer, 1.0);
    ass_set_cache_limits(ass->renderer, 3, 0);
    
//    ass_set_pixel_aspect(ass->renderer, (double)w / h /
//                         ((double)ass->original_w / ass->original_h));
//    if (ass->shaping != -1)
//        ass_set_shaper(ass->renderer, ass->shaping);
    
    ass_set_shaper(ass->renderer, ASS_SHAPING_COMPLEX);
}

static void blend_single(FFSubtitleBuffer * frame, ASS_Image *img)
{
    const int bpc = 4;
    uint8_t *src = img->bitmap;
    uint8_t *dst = frame->buffer + img->dst_y * frame->stride + img->dst_x * bpc;
    
    const uint32_t color = img->color;
    const uint8_t r_src = (color & 0xff000000) >> 24;
    const uint8_t g_src = (color & 0x00ff0000) >> 16;
    const uint8_t b_src = (color & 0x0000ff00) >> 8;
    //const uint8_t a_src = 0xff - (color & 0x000000ff);
    
    for (int y = 0; y < img->h; y++)
    {
        for (int x = 0; x < img->w; x++)
        {
            uint8_t *pixel = dst + x * 4;
            double alpha = (255 - src[x]) / 255.0;
            
            uint8_t r_dst = pixel[0];
            uint8_t g_dst = pixel[1];
            uint8_t b_dst = pixel[2];
            uint8_t a_dst = pixel[3];

            pixel[0] = (1 - alpha) * r_src + alpha * r_dst;
            pixel[1] = (1 - alpha) * g_src + alpha * g_dst;
            pixel[2] = (1 - alpha) * b_src + alpha * b_dst;
            pixel[3] = (1 - alpha) * src[x] + alpha * a_dst;
        }
        src += img->stride;
        dst += frame->stride;
    }
}

static void blend(FFSubtitleBuffer * frame, ASS_Image *img)
{
    int cnt = 0;
    while (img) {
        blend_single(frame, img);
        ++cnt;
        img = img->next;
    }
}

static FFSubtitleBuffer* render_frame(FF_ASS_Renderer *s, double time_ms)
{
    FF_ASS_Context *ass = s->priv_data;
    if (!ass) {
        return NULL;
    }
    
    ASS_Image *imgs = ass_render_frame(ass->renderer, ass->track, time_ms, NULL);

    if (imgs) {
        FFSubtitleBuffer* buff = ff_gen_subtitle_image(ass->original_w, ass->original_h, 4);
        buff->usedAss = 1;
        blend(buff, imgs);
        return buff;
    } else {
        av_log(NULL, AV_LOG_ERROR, "ass_render_frame NULL at time ms:%f\n", time_ms);
        return NULL;
    }
}

static const char * const font_mimetypes[] = {
    "font/ttf",
    "font/otf",
    "font/sfnt",
    "font/woff",
    "font/woff2",
    "application/font-sfnt",
    "application/font-woff",
    "application/x-truetype-font",
    "application/vnd.ms-opentype",
    "application/x-font-ttf",
    NULL
};

static int attachment_is_font(AVStream * st)
{
    const AVDictionaryEntry *tag = av_dict_get(st->metadata, "mimetype", NULL, AV_DICT_MATCH_CASE);
    if (tag) {
        for (int n = 0; font_mimetypes[n]; n++) {
            if (av_strcasecmp(font_mimetypes[n], tag->value) == 0)
                return 1;
        }
    }
    return 0;
}

static int set_stream(FF_ASS_Renderer *s, AVStream *st, uint8_t *subtitle_header, int subtitle_header_size)
{
    FF_ASS_Context *ass = s->priv_data;
    if (!ass) {
        return AVERROR(EINVAL);
    }
    
    /* Load attached fonts */
    if (st->codecpar->codec_type == AVMEDIA_TYPE_ATTACHMENT &&
        attachment_is_font(st)) {
        const AVDictionaryEntry *tag = av_dict_get(st->metadata, "filename", NULL,
                          AV_DICT_MATCH_CASE);

        if (tag) {
            av_log(s, AV_LOG_DEBUG, "Loading attached font: %s\n",
                   tag->value);
            ass_add_font(ass->library, tag->value,
                         (char *)st->codecpar->extradata,
                         st->codecpar->extradata_size);
        } else {
            av_log(s, AV_LOG_WARNING,
                   "Font attachment has no filename, ignored.\n");
        }
    }

    ass_set_fonts(ass->renderer, NULL, "sans-serif", ASS_FONTPROVIDER_AUTODETECT, NULL, 1);
    
    int ret = 0;
    if (ass->force_style) {
        char **list = NULL;
        char *temp = NULL;
        char *ptr = av_strtok(ass->force_style, ",", &temp);
        int i = 0;
        while (ptr) {
            av_dynarray_add(&list, &i, ptr);
            if (!list) {
                ret = AVERROR(ENOMEM);
                goto end;
            }
            ptr = av_strtok(NULL, ",", &temp);
        }
        av_dynarray_add(&list, &i, NULL);
        if (!list) {
            ret = AVERROR(ENOMEM);
            goto end;
        }
        ass_set_style_overrides(ass->library, list);
        av_free(list);
    }
    /* Decode subtitles and push them into the renderer (libass) */
    if (subtitle_header && subtitle_header_size > 0)
        ass_process_codec_private(ass->track,
                                  (char *)subtitle_header,
                                  subtitle_header_size);
end:
    
    return ret;
}

static void process_chunk(FF_ASS_Renderer *s, char *ass_line, long long start_time, long long duration)
{
    FF_ASS_Context *ass = s->priv_data;
    if (!ass) {
        return;
    }
    printf("ass_process_chunk:%s\n", ass_line);
    ass_process_chunk(ass->track, ass_line, (int)strlen(ass_line), start_time, duration);
}

static void uninit(FF_ASS_Renderer *s)
{
    FF_ASS_Context *ass = s->priv_data;
    if (!ass) {
        return;
    }
    if (ass->track)
        ass_free_track(ass->track);
    if (ass->renderer)
        ass_renderer_done(ass->renderer);
    if (ass->library)
        ass_library_done(ass->library);
}

static void *ass_context_child_next(void *obj, void *prev)
{
    return NULL;
}

static const AVClass subtitles_class = {
    .class_name = "ff_ass_subtitles",
    .item_name  = av_default_item_name,
    .option     = ff_ass_options,
    .version    = LIBAVUTIL_VERSION_INT,
    .child_next = ass_context_child_next,
};

FF_ASS_Renderer_Format ff_ass_default_format = {
    .priv_class     = &subtitles_class,
    .priv_data_size = sizeof(FF_ASS_Context),
    .init           = init_libass,
    .set_stream     = set_stream,
    .set_video_size = set_video_size,
    .process_chunk  = process_chunk,
    .render_frame   = render_frame,
    .uninit         = uninit,
};

static FF_ASS_Renderer *ffAss_create_with_format(FF_ASS_Renderer_Format* format, AVDictionary *opts)
{
    FF_ASS_Renderer *r = av_mallocz(sizeof(FF_ASS_Renderer));
    r->priv_data = av_mallocz(format->priv_data_size);
    if (!r->priv_data) {
        av_log(NULL, AV_LOG_ERROR, "ffAss_create:AVERROR(ENOMEM)");
        return NULL;
    }
    r->iformat = format;
    if (format->priv_class) {
        //非FF_ASS_Context的首地址，也就是第一个变量的地址赋值
        *(const AVClass**)r->priv_data = format->priv_class;
        av_opt_set_defaults(r->priv_data);
    }
    if (opts) {
        av_opt_set_dict(r->priv_data, &opts);
    }
    
    if (format->init(r)) {
        ffAss_destroy(&r);
        return NULL;
    }
    return r;
}

FF_ASS_Renderer *ffAss_create_default(AVStream *st, uint8_t *subtitle_header, int subtitle_header_size, int video_w, int video_h, AVDictionary *opts)
{
    FF_ASS_Renderer_Format* format = &ff_ass_default_format;
    FF_ASS_Renderer* r = ffAss_create_with_format(format, opts);
    if (r) {
        r->iformat->set_stream(r, st, subtitle_header, subtitle_header_size);
        r->iformat->set_video_size(r, video_w, video_h);
    }
    return r;
}

void ffAss_destroy(FF_ASS_Renderer **sp)
{
    if (!sp) return;
    FF_ASS_Renderer *s = *sp;
    
    if (s->iformat->uninit) {
        s->iformat->uninit(s);
    }
    
    if (s->iformat->priv_data_size)
        av_opt_free(s->priv_data);
    av_freep(&s->priv_data);
    av_freep(sp);
}
