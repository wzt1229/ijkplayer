//
//  ff_subtitle.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/5/23.
//

#include "ff_subtitle.h"
#include "ff_frame_queue.h"
#include "ff_packet_list.h"
#include "ff_ass_parser.h"
#include "ff_subtitle_ex.h"
#include "ff_sub_component.h"
#include "ff_ffplay_debug.h"
#include "ff_ass_steam_renderer.h"

typedef struct FFSubtitle {
    PacketQueue packetq;
    FrameQueue frameq;
    float delay;
    float current_pts;
    int maxInternalStream;
    FFSubComponent* inSub;
    IJKEXSubtitle* exSub;
    int streamStartTime;//ic start_time (s)
    int video_w, video_h;
    int use_ass_renderer;
    FF_ASS_Renderer * assRenderer;
}FFSubtitle;

//---------------------------Private Functions--------------------------------------------------//

static double get_frame_real_begin_pts(FFSubtitle *sub, Frame *sp)
{
    return sp->pts + (float)sp->sub.start_display_time / 1000.0;
}

static double get_frame_begin_pts(FFSubtitle *sub, Frame *sp)
{
    return sp->pts + (float)sp->sub.start_display_time / 1000.0 + (sub ? sub->delay : 0.0);
}

static double get_frame_end_pts(FFSubtitle *sub, Frame *sp)
{
    if (sp->sub.end_display_time != 4294967295) {
        return sp->pts + (float)sp->sub.end_display_time / 1000.0 + (sub ? sub->delay : 0.0);
    } else {
        return sp->pts + 5 + (sub ? sub->delay : 0.0);
    }
}

static int stream_has_enough_packets(PacketQueue *queue, int min_frames)
{
    return queue->abort_request || queue->nb_packets > min_frames;
}

//---------------------------Public Common Functions--------------------------------------------------//

int ff_sub_init(FFSubtitle **subp)
{
    if (!subp) {
        return -1;
    }
    FFSubtitle *sub = av_mallocz(sizeof(FFSubtitle));
    
    if (!sub) {
        return -2;
    }
    
    if (packet_queue_init(&sub->packetq) < 0) {
        av_free(sub);
        return -3;
    }
    
    if (frame_queue_init(&sub->frameq, &sub->packetq, SUBPICTURE_QUEUE_SIZE, 0) < 0) {
        packet_queue_destroy(&sub->packetq);
        av_free(sub);
        return -4;
    }
    sub->delay = 0.0f;
    sub->current_pts = 0.0f;
    sub->maxInternalStream = -1;
    
    *subp = sub;
    return 0;
}

void ff_sub_abort(FFSubtitle *sub)
{
    if (!sub) {
        return;
    }
    packet_queue_abort(&sub->packetq);
}

int ff_sub_destroy(FFSubtitle **subp)
{
    if (!subp) {
        return -1;
    }
    FFSubtitle *sub = *subp;
    
    if (!sub) {
        return -2;
    }
    if (sub->inSub) {
        subComponent_close(&sub->inSub);
    } else if (exSub_get_opened_stream_idx(sub->exSub) != -1) {
        exSub_subtitle_destroy(&sub->exSub);
    }
    packet_queue_destroy(&sub->packetq);
    frame_queue_destory(&sub->frameq);
    
    if (sub->assRenderer) {
        ffAss_destroy(&sub->assRenderer);
    }
    sub->delay = 0.0f;
    sub->current_pts = 0.0f;
    sub->maxInternalStream = -1;
    
    av_freep(subp);
    return 0;
}

int ff_sub_close_current(FFSubtitle *sub)
{
    if (sub->inSub) {
        return subComponent_close(&sub->inSub);
    } else if (exSub_get_opened_stream_idx(sub->exSub) != -1) {
        return exSub_close_current(sub->exSub);
    }
    return -1;
}

static void ff_sub_clean_frame_queue(FFSubtitle *sub)
{
    if (!sub) {
        return;
    }
    FrameQueue *subpq = &sub->frameq;
    while (frame_queue_nb_remaining(subpq) > 0) {
        frame_queue_next(subpq);
    }
}

/// the graphic subtitles' bitmap with pixel format AV_PIX_FMT_PAL8,
/// https://ffmpeg.org/doxygen/trunk/pixfmt_8h.html#a9a8e335cf3be472042bc9f0cf80cd4c5
/// need to be converted to BGRA32 before use
/// PAL8 to BGRA32, bytes per line increased by multiplied 4
static FFSubtitleBuffer* convert_pal8_to_bgra(const AVSubtitleRect* rect)
{
    FFSubtitleBuffer *frame = ff_gen_subtitle_image(rect->w, rect->h, 4);
    if (!frame) {
        return NULL;
    }
    frame->usedAss = 0;
    //AV_PIX_FMT_RGB32 is handled in an endian-specific manner. An RGBA color is put together as: (A << 24) | (R << 16) | (G << 8) | B
    //This is stored as BGRA on little-endian CPU architectures and ARGB on big-endian CPUs.
    
    uint32_t colors[256];
    
    uint8_t *bgra = rect->data[1];
    if (bgra) {
        for (int i = 0; i < 256; ++i) {
            /* Colour conversion. */
            int idx = i * 4; /* again, 4 bytes per pixel */
            uint8_t a = bgra[idx],
            r = bgra[idx + 1],
            g = bgra[idx + 2],
            b = bgra[idx + 3];
            colors[i] = (b << 24) | (g << 16) | (r << 8) | a;
        }
    } else {
        bzero(colors, 256);
    }
    uint32_t *buff = (uint32_t *)frame->buffer;
    for (int y = 0; y < rect->h; ++y) {
        for (int x = 0; x < rect->w; ++x) {
            /* 1 byte per pixel */
            int coordinate = x + y * rect->linesize[0];
            /* 32bpp color table */
            int pos = rect->data[0][coordinate];
            if (pos < 256) {
                buff[x + (y * rect->w)] = colors[pos];
            } else {
                printf("%d\n",pos);
            }
        }
    }
    return frame;
}

static int generate_picture(Frame * sp, FF_ASS_Renderer * assRenderer, FFSubtitleBuffer **buffer, float begin, float end)
{
    sp->shown = 1;
    
    int r = 0;
    if (sp->sub.num_rects > 0) {
        if (sp->sub.rects[0]->text) {
            *buffer = ff_gen_subtitle_text(sp->sub.rects[0]->text);
        } else if (sp->sub.rects[0]->ass) {
            //ass -> image
            if (assRenderer) {
                for (int i = 0; i < sp->sub.num_rects; i++) {
                    char *ass_line = sp->sub.rects[i]->ass;
                    if (!ass_line)
                        break;
                    assRenderer->iformat->process_chunk(assRenderer, ass_line, begin * 1000, end);
                }
                int err = assRenderer->iformat->render_frame(assRenderer, begin * 1000 + 5, buffer);
                if (err) {
                    r = -1;
                    sp->shown = 0;
                }
            } else {
                *buffer = parse_ass_subtitle(sp->sub.rects[0]->ass);
            }
        } else if (sp->sub.rects[0]->type == SUBTITLE_BITMAP
                   && sp->sub.rects[0]->data[0]
                   && sp->sub.rects[0]->linesize[0]) {
            *buffer = convert_pal8_to_bgra(sp->sub.rects[0]);
        } else {
            av_log(NULL, AV_LOG_ERROR, "unknown subtitle");
        }
    }
    return r;
}

int ff_sub_fetch_frame(FFSubtitle *sub, float pts, FFSubtitleBuffer **buffer)
{
    if (!sub || !buffer) {
        return -1;
    }
    
    int serial = -1;
    
    if (sub->inSub) {
        if (subComponent_get_stream(sub->inSub) != -1) {
            serial = subComponent_get_serial(sub->inSub);
        }
    }
    
    if (serial == -1 && sub->exSub) {
        if (exSub_get_opened_stream_idx(sub->exSub) != -1) {
            serial = exSub_get_serial(sub->exSub);
            pts -= sub->streamStartTime;
        }
    }
    
    if (serial == -1) {
        return -2;
    }
    
    int r = -3;
    int rem = 0;
    int dropped = 0;
    while ((rem = frame_queue_nb_remaining(&sub->frameq)) > 0) {
        if (rem > 1) {
            Frame *sp2 = frame_queue_peek_next(&sub->frameq);
            if (pts > get_frame_begin_pts(sub, sp2)) {
                dropped++;
                frame_queue_next(&sub->frameq);
                continue;
            }
        }
        Frame * sp = frame_queue_peek(&sub->frameq);
        if (sp->serial != serial) {
            dropped++;
            frame_queue_next(&sub->frameq);
            continue;
        }
        sub->current_pts = get_frame_real_begin_pts(sub, sp);
        float begin = sub->current_pts + (sub ? sub->delay : 0.0);
        float end = get_frame_end_pts(sub, sp);
        
        if (pts > begin && pts < end) {
            if (!sp->shown) {
                //end ?? sp->sub.end_display_time
                int err = generate_picture(sp, sub->use_ass_renderer ? sub->assRenderer : NULL, buffer, begin, end);
                r = err ? -4 : 1;
            } else {
                r = 0;
            }
        } else {
            if (sp->shown) {
                sp->shown = 0;
            }
            //clean current display sub
            r = -3;
        }
        break;
    }
    return r;
}

int ff_sub_frame_queue_size(FFSubtitle *sub)
{
    if (sub) {
        return sub->frameq.size;
    }
    return 0;
}

int ff_sub_has_enough_packets(FFSubtitle *sub, int min_frames)
{
    if (sub) {
        return stream_has_enough_packets(&sub->packetq, min_frames);
    }
    return 1;
}

int ff_sub_put_null_packet(FFSubtitle *sub, AVPacket *pkt, int st_idx)
{
    if (sub) {
        return packet_queue_put_nullpacket(&sub->packetq, pkt, st_idx);
    }
    return -1;
}

int ff_sub_put_packet(FFSubtitle *sub, AVPacket *pkt)
{
    if (sub) {
        return packet_queue_put(&sub->packetq, pkt);
    }
    return -1;
}

int ff_sub_get_opened_stream_idx(FFSubtitle *sub)
{
    int idx = -1;
    if (sub) {
        if (sub->inSub) {
            idx = subComponent_get_stream(sub->inSub);
        }
        if (idx == -1 && sub->exSub) {
            idx = exSub_get_opened_stream_idx(sub->exSub);
        }
    }
    return idx;
}

void ff_sub_seek_to(FFSubtitle *sub, float delay, float v_pts)
{
    ff_sub_clean_frame_queue(sub);
    if (exSub_get_opened_stream_idx(sub->exSub) != -1) {
        v_pts -= sub->streamStartTime;
    }
    
    float wantDisplay = v_pts - delay;
    exSub_seek_to(sub->exSub, wantDisplay);
}

int ff_sub_set_delay(FFSubtitle *sub, float delay, float v_pts)
{
    if (!sub) {
        return -1;
    }
    if (exSub_get_opened_stream_idx(sub->exSub) != -1) {
        v_pts -= sub->streamStartTime;
    }
    
    float wantDisplay = v_pts - delay;
    //subtile's frame queue greater than can display pts
    if (sub->current_pts > wantDisplay) {
        float diff = fabsf(delay - sub->delay);
        sub->delay = delay;
        //need seek to wantDisplay;
        if (sub->inSub) {
            //after seek maybe can display want sub,but can't seek every dealy change,so when diff greater than 2s do seek.
            if (diff > 2) {
                ff_sub_clean_frame_queue(sub);
                //return 1 means need seek.
                return 1;
            }
            return -2;
        } else if (exSub_get_opened_stream_idx(sub->exSub) != -1) {
            ff_sub_clean_frame_queue(sub);
            exSub_seek_to(sub->exSub, wantDisplay-2);
            return 0;
        } else {
            return -3;
        }
    } else {
        //when no need seek,just apply the diff to output frame's pts
        sub->delay = delay;
        return 0;
    }
}

float ff_sub_get_delay(FFSubtitle *sub)
{
    return sub ? sub->delay : 0.0;
}

int ff_sub_isInternal_stream(FFSubtitle *sub, int stream)
{
    if (!sub) {
        return 0;
    }
    return stream >= 0 && stream <= sub->maxInternalStream;
}

int ff_sub_isExternal_stream(FFSubtitle *sub, int stream)
{
    if (!sub) {
        return 0;
    }
    return exSub_contain_streamIdx(sub->exSub, stream);
}

int ff_sub_current_stream_type(FFSubtitle *sub, int *outIdx)
{
    int type = 0;
    int idx = -1;
    if (sub) {
        if (sub->inSub) {
            idx = subComponent_get_stream(sub->inSub);
            type = 1;
        }
        if (idx == -1 && sub->exSub) {
            idx = exSub_get_opened_stream_idx(sub->exSub);
            if (idx != -1) {
                type = 2;
            }
        }
    }
    
    if (outIdx) {
        *outIdx = idx;
    }
    return type;
}

void ff_sub_stream_ic_ready(FFSubtitle *sub, AVFormatContext* ic, int video_w, int video_h)
{
    if (!sub) {
        return;
    }
    sub->video_w = video_w;
    sub->video_h = video_h;
    sub->streamStartTime = (int)fftime_to_seconds(ic->start_time);
    sub->maxInternalStream = ic->nb_streams;
}

void ff_sub_use_libass(FFSubtitle *sub, int use, AVStream* st, uint8_t *subtitle_header, int subtitle_header_size)
{
    if (use != 0) {
        use = 1;
    }
    if (sub->use_ass_renderer != use) {
        sub->use_ass_renderer = use;
    }
    if (use) {
        if (sub->assRenderer) {
            ffAss_destroy(&sub->assRenderer);
        }
        if (sub->video_w > 0 && sub->video_h > 0) {
            sub->assRenderer = ffAss_create_default(st, subtitle_header, subtitle_header_size, sub->video_w, sub->video_h, NULL);
        }
    }
}

int ff_inSub_open_component(FFSubtitle *sub, int stream_index, AVStream* st, AVCodecContext *avctx)
{
    if (sub->inSub || sub->exSub) {
        packet_queue_flush(&sub->packetq);
        ff_sub_clean_frame_queue(sub);
    }
    
    ff_sub_use_libass(sub, 1, st, avctx->subtitle_header, avctx->subtitle_header_size);
    return subComponent_open(&sub->inSub, stream_index, NULL, avctx, &sub->packetq, &sub->frameq, NULL, NULL);
}

enum AVCodecID ff_sub_get_codec_id(FFSubtitle *sub)
{
    if (!sub) {
        return -1;
    }
    AVCodecContext *avctx = NULL;
    int idx = -1;
    if (sub->inSub) {
        idx = subComponent_get_stream(sub->inSub);
        if (idx != -1) {
            avctx = subComponent_get_avctx(sub->inSub);
        }
    }
    if (idx == -1 && sub->exSub) {
        idx = exSub_get_opened_stream_idx(sub->exSub);
        if (idx != -1) {
            avctx = exSub_get_avctx(sub->exSub);
        }
    }
    
    return avctx ? avctx->codec_id : AV_CODEC_ID_NONE;
}

int ff_inSub_packet_queue_flush(FFSubtitle *sub)
{
    if (sub) {
        if (sub->inSub) {
            packet_queue_flush(&sub->packetq);
        }
        return 0;
    }
    return -1;
}

//---------------------------Internal Subtitle Functions--------------------------------------------------//

//

//---------------------------External Subtitle Functions--------------------------------------------------//

int ff_exSub_addOnly_subtitle(FFSubtitle *sub, const char *file_name, IjkMediaMeta *meta)
{
    if (!sub->exSub) {
        if (exSub_create(&sub->exSub, &sub->frameq, &sub->packetq) != 0) {
            return -1;
        }
    }
    
    return exSub_addOnly_subtitle(sub->exSub, file_name, meta);
}

int ff_exSub_add_active_subtitle(FFSubtitle *sub, const char *file_name, IjkMediaMeta *meta)
{
    if (!sub->exSub) {
        if (exSub_create(&sub->exSub, &sub->frameq, &sub->packetq) != 0) {
            return -1;
        }
    }
    packet_queue_flush(&sub->packetq);
    ff_sub_clean_frame_queue(sub);
    int err = exSub_add_active_subtitle(sub->exSub, file_name, meta);
    if (!err) {
        AVCodecContext * avctx = exSub_get_avctx(sub->exSub);
        AVStream *st = exSub_get_stream(sub->exSub);
        ff_sub_use_libass(sub, 1, st, avctx->subtitle_header, avctx->subtitle_header_size);
    }
    return err;
}

int ff_exSub_open_stream(FFSubtitle *sub, int stream)
{
    if (!sub->exSub) {
        return -1;
    }
    packet_queue_flush(&sub->packetq);
    ff_sub_clean_frame_queue(sub);
    
    int err = exSub_open_file_idx(sub->exSub, stream);
    if (!err) {
        AVCodecContext * avctx = exSub_get_avctx(sub->exSub);
        AVStream *st = exSub_get_stream(sub->exSub);
        ff_sub_use_libass(sub, 1, st, avctx->subtitle_header, avctx->subtitle_header_size);
    }
    return err;
}

int ff_exSub_check_file_added(const char *file_name, FFSubtitle *sub)
{
    if (!sub || !sub->exSub) {
        return -1;
    }
    return exSub_check_file_added(file_name, sub->exSub);
}
