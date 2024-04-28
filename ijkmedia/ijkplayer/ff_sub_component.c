//
//  ff_sub_component.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/5/24.
//

#include "ff_sub_component.h"
#include "ff_frame_queue.h"
#include "ff_packet_list.h"
#include "ff_ass_renderer.h"
#include "ijksdl/ijksdl_gpu.h"
#include "ff_subtitle_def_internal.h"

#define SUB_MAX_KEEP_DU 3.0

typedef struct FFSubComponent{
    int st_idx;
    PacketQueue* packetq;
    Decoder decoder;
    FrameQueue* frameq;
    subComponent_retry_callback retry_callback;
    void *retry_opaque;
    FF_ASS_Renderer *assRenderer;
    int bitmapRenderer;
    int video_width, video_height;
    int sub_width, sub_height;
    FFSubtitleBufferPacket sub_buffer_array;
    IJKSDLSubtitlePreference sp;
    int sp_changed;
}FFSubComponent;

static int decode_a_frame(FFSubComponent *com, Decoder *d, AVSubtitle *pkt)
{
    int ret = AVERROR(EAGAIN);

    for (;com->packetq->abort_request == 0;) {
        
        if (d->packet_pending) {
            d->packet_pending = 0;
        } else {
            int old_serial = d->pkt_serial;
            int get_pkt = packet_queue_get(d->queue, d->pkt, 0, &d->pkt_serial);
            //av_log(NULL, AV_LOG_ERROR, "sub packet_queue_get:%d\n",get_pkt);
            if (get_pkt < 0)
                return -1;
            if (get_pkt == 0) {
                av_usleep(1000 * 3);
                continue;
            }
            
            if (d->pkt->stream_index != com->st_idx) {
                av_packet_unref(d->pkt);
                continue;
            }
            if (old_serial != d->pkt_serial) {
                avcodec_flush_buffers(d->avctx);
                d->finished = 0;
                d->next_pts = d->start_pts;
                d->next_pts_tb = d->start_pts_tb;
                ff_ass_flush_events(com->assRenderer);
            }
        }
        if (d->queue->serial != d->pkt_serial)
        {
            av_packet_unref(d->pkt);
            continue;
        }

        int got_frame = 0;
        
        //av_log(NULL, AV_LOG_ERROR, "sub stream decoder pkt serial:%d,pts:%lld\n",d->pkt_serial,pkt->pts/1000);
        ret = avcodec_decode_subtitle2(d->avctx, pkt, &got_frame, d->pkt);
        if (ret >= 0) {
            if (got_frame && !d->pkt->data) {
                d->packet_pending = 1;
            }
            ret = got_frame ? 0 : (d->pkt->data ? AVERROR(EAGAIN) : AVERROR_EOF);
        }
        av_packet_unref(d->pkt);
        //Invalid UTF-8 in decoded subtitles text; maybe missing -sub_charenc option
        if (ret == AVERROR_INVALIDDATA) {
            return -1000;
        } else if (ret == -92) {
            //iconv convert failed
            return -1000;
        }
        if (ret >= 0)
            return 1;
    }
    return -2;
}

static void convert_pal_bgra(uint32_t *colors, size_t count, bool gray)
{
    for (int n = 0; n < count; n++) {
        uint32_t c = colors[n];
        uint32_t b = c & 0xFF;
        uint32_t g = (c >> 8) & 0xFF;
        uint32_t r = (c >> 16) & 0xFF;
        uint32_t a = (c >> 24) & 0xFF;
        if (gray)
            r = g = b = (r + g + b) / 3;
        // from straight to pre-multiplied alpha
        b = b * a / 255;
        g = g * a / 255;
        r = r * a / 255;
        colors[n] = b | (g << 8) | (r << 16) | (a << 24);
    }
}

/// the graphic subtitles' bitmap with pixel format AV_PIX_FMT_PAL8,
/// https://ffmpeg.org/doxygen/trunk/pixfmt_8h.html#a9a8e335cf3be472042bc9f0cf80cd4c5
/// need to be converted to RGBA32 before use

static FFSubtitleBuffer* convert_pal8_to_bgra(const AVSubtitleRect* rect)
{
    uint32_t pal[256] = {0};
    memcpy(pal, rect->data[1], rect->nb_colors * 4);
    convert_pal_bgra(pal, rect->nb_colors, 0);
    
    SDL_Rectangle r = (SDL_Rectangle){rect->x, rect->y, rect->w, rect->h, rect->linesize[0]};
    FFSubtitleBuffer *frame = ff_subtitle_buffer_alloc_rgba32(r);
    if (!frame) {
        return NULL;
    }
    
    for (int y = 0; y < rect->h; y++) {
        uint8_t *in = rect->data[0] + y * rect->linesize[0];
        uint32_t *out = (uint32_t *)(frame->data + y * frame->rect.stride);
        for (int x = 0; x < rect->w; x++)
            *out++ = pal[*in++];
    }
    return frame;
}

static void apply_preference(FFSubComponent *com)
{
    if (com->assRenderer) {
        int b = com->sp.bottomMargin * com->sub_height;
        com->assRenderer->iformat->update_bottom_margin(com->assRenderer, b);
        com->assRenderer->iformat->set_font_scale(com->assRenderer, com->sp.scale);
        com->sp_changed = 0;
    }
}

static int create_ass_renderer_if_need(FFSubComponent *com)
{
    if (com->assRenderer) {
        return 0;
    }
    
    int ratio = 1;
#ifdef __APPLE__
    //文本字幕放大两倍，使得 retina 屏显示清楚
    ratio = 2;
    com->sub_width  = com->video_width  * ratio;
    com->sub_height = com->video_height * ratio;
#endif
    
    com->assRenderer = ff_ass_render_create_default(com->decoder.avctx->subtitle_header, com->decoder.avctx->subtitle_header_size, com->sub_width, com->sub_height, NULL);
    
    apply_preference(com);
    
    return NULL == com->assRenderer;
}

static int create_bitmap_renderer_if_need(FFSubComponent *com)
{
    if (com->bitmapRenderer) {
        return 0;
    }
    com->bitmapRenderer = 1;
    com->sub_width = com->decoder.avctx->width;
    com->sub_height = com->decoder.avctx->height;
    if (!com->sub_width || !com->sub_height) {
        com->sub_width = com->video_width;
        com->sub_height = com->video_height;
    }
    return 0;
}

static int subtitle_thread(void *arg)
{
    FFSubComponent *com = arg;
    int got_subtitle;
    
    double pre_pts = 0;
    for (;com->packetq->abort_request == 0;) {
        AVSubtitle sub;
        got_subtitle = decode_a_frame(com, &com->decoder, &sub);
        
        if (got_subtitle == -1000) {
            if (com->retry_callback) {
                com->retry_callback(com->retry_opaque);
                return -1;
            }
            break;
        }
        
        if (got_subtitle < 0)
            break;
        
        if (got_subtitle) {
            //av_log(NULL, AV_LOG_ERROR,"sub received frame:%f\n",pts);
            int serial = com->decoder.pkt_serial;
            if (com->packetq->serial == serial) {
                
                double pts = 0;
                if (sub.pts != AV_NOPTS_VALUE)
                    pts = sub.pts / (double)AV_TIME_BASE;
                
                int count = 0;
                FFSubtitleBuffer* buffers [SUB_REF_MAX_LEN] = { 0 };
                for (int i = 0; i < sub.num_rects; i++) {
                    AVSubtitleRect *rect = sub.rects[i];
                    //AV_CODEC_ID_HDMV_PGS_SUBTITLE
                    //AV_CODEC_ID_FIRST_SUBTITLE
                    if (rect->type == SUBTITLE_BITMAP) {
                        if (rect->w <= 0 || rect->h <= 0) {
                            continue;
                        }
                        if (!create_bitmap_renderer_if_need(com)) {
                            FFSubtitleBuffer* sb = convert_pal8_to_bgra(rect);
                            if (sb) {
                                buffers[count++] = sb;
                            } else {
                                break;
                            }
                        }
                    } else {
                        char *ass_line = rect->ass;
                        if (!ass_line)
                            continue;
                        if (!create_ass_renderer_if_need(com)) {
                            const float begin = pts + (float)sub.start_display_time / 1000.0;
                            float end = sub.end_display_time - sub.start_display_time;
                            ff_ass_process_chunk(com->assRenderer, ass_line, begin * 1000, end);
                            count++;
                        }
                    }
                }
                
                if (count == 0) {
                    avsubtitle_free(&sub);
                    continue;
                }
                
                if (com->bitmapRenderer) {
                    Frame *sp = frame_queue_peek_writable(com->frameq);
                    if (com->packetq->abort_request || !sp) {
                        pre_pts = 0;
                        avsubtitle_free(&sub);
                        break;
                    }
                    sp->pts = pts + (float)sub.start_display_time / 1000.0;
                    if (sub.end_display_time != 4294967295) {
                        sp->duration = (float)(sub.end_display_time - sub.start_display_time) / 1000.0;
                    } else if (pre_pts){
                        Frame *pre = frame_queue_peek_pre_writable(com->frameq);
                        if (pre) {
                            float t = sp->pts - pre_pts;
                            pre->duration = t;
                        }
                    } else {
                        sp->duration = SUB_MAX_KEEP_DU;
                    }
                    sp->serial = serial;
                    sp->width  = com->sub_width;
                    sp->height = com->sub_height;
                    sp->shown = 0;
                    
                    if (count > 0) {
                        memcpy(sp->sub_list, buffers, count * sizeof(buffers[0]));
                    } else {
                        bzero(sp->sub_list, sizeof(sp->sub_list));
                    }
                    frame_queue_push(com->frameq);
                    pre_pts = sp->pts;
                }
            } else {
                pre_pts = 0;
                //av_log(NULL, AV_LOG_DEBUG,"sub stream push old frame:%d\n",serial);
            }
            avsubtitle_free(&sub);
        }
    }
    
    ff_ass_render_release(&com->assRenderer);
    com->retry_callback = NULL;
    com->retry_opaque = NULL;
    com->st_idx = -1;
    
    return 0;
}

static int subComponent_packet_pgs(FFSubComponent *com, float pts, FFSubtitleBufferPacket *packet)
{
    if (!com) {
        return -1;
    }
    
    int serial = com->packetq->serial;
    
    if (serial == -1) {
        return -2;
    }
    
    FFSubtitleBufferPacket buffer_array = { 0 };
    buffer_array.scale = com->sp.scale;
    buffer_array.width = com->sub_width;
    buffer_array.height = com->sub_height;
    buffer_array.bottom_margin = com->sp.bottomMargin * com->sub_height;
    
    int i = 0;
    
    while (buffer_array.len < SUB_REF_MAX_LEN) {
        Frame *sp = frame_queue_peek_offset(com->frameq, i);
        if (!sp) {
            break;
        }
        //drop old serial subs
        if (sp->serial != serial) {
            frame_queue_next(com->frameq);
            continue;
        }
        float end = sp->pts + sp->duration;
        //字幕显示时间已经结束了
        if (pts > end) {
            frame_queue_next(com->frameq);
            continue;
        }
        
        if (!sp->sub_list[0]) {
            i++;
            continue;
        }
        
        if (pts > sp->pts) {
            for (int j = 0; j < sizeof(sp->sub_list)/sizeof(sp->sub_list[0]); j++) {
                FFSubtitleBuffer *sb = sp->sub_list[j];
                if (sb) {
                    buffer_array.e[buffer_array.len++] = ff_subtitle_buffer_retain(sb);
                } else {
                    break;
                }
            }
            i++;
            continue;
        } else {
            break;
        }
    }
    
    if (com->sp_changed || isFFSubtitleBufferArrayDiff(&com->sub_buffer_array, &buffer_array)) {
        com->sp_changed = 0;
        if (buffer_array.len == 0 && com->sub_buffer_array.len == 0) {
            //clean subtitle
            return -1;
        }
        ResetSubtitleBufferArray(&com->sub_buffer_array, &buffer_array);
        ResetSubtitleBufferArray(packet, &buffer_array);
        FreeSubtitleBufferArray(&buffer_array);
        return 1;
    } else {
        if (buffer_array.len == 0) {
            //clean subtitle
            return -1;
        }
        FreeSubtitleBufferArray(&buffer_array);
        return 0;
    }
    return -3;
}

int subComponent_upload_buffer(FFSubComponent *com, float pts, FFSubtitleBufferPacket *packet)
{
    if (!com || com->packetq->abort_request || !packet) {
        return -1;
    }
    
    if (com->assRenderer) {
        FFSubtitleBuffer *buffer = NULL;
        FF_ASS_Renderer *assRenderer = ff_ass_render_retain(com->assRenderer);
        int r = ff_ass_upload_buffer(com->assRenderer, pts, &buffer);
        ff_ass_render_release(&assRenderer);
        if (r > 0) {
            FFSubtitleBufferPacket arr = {0};
            arr.scale = 1.0;
            arr.len = 1;
            arr.isAss = 1;
            arr.e[0] = buffer;
            arr.width = com->sub_width;
            arr.height = com->sub_height;
            *packet = arr;
        }
        return r;
    } else if (com->bitmapRenderer) {
        return subComponent_packet_pgs(com, pts, packet);
    } else {
        return -2;
    }
}

int subComponent_open(FFSubComponent **cp, int stream_index, AVStream* stream, PacketQueue* packetq, FrameQueue* frameq, const char *enc, subComponent_retry_callback callback, void *opaque, int vw, int vh)
{
    assert(frameq);
    assert(packetq);
    
    int r = 0;
    FFSubComponent *com = NULL;
    
    if (!cp) {
        return -1;
    }
    
    if (AVMEDIA_TYPE_SUBTITLE != stream->codecpar->codec_type) {
        return -2;
    }
    
    stream->discard = AVDISCARD_DEFAULT;
    AVCodecContext* avctx = avcodec_alloc_context3(NULL);
    if (!avctx) {
        return -3;
    }
    
    if (avcodec_parameters_to_context(avctx, stream->codecpar) < 0) {
        r = -4;
        goto fail;
    }
    
    //so important,ohterwise,sub frame has not pts.
    avctx->pkt_timebase = stream->time_base;
    if (enc) {
        avctx->sub_charenc = av_strdup(enc);
        avctx->sub_charenc_mode = FF_SUB_CHARENC_MODE_AUTOMATIC;
    }
    const AVCodec* codec = avcodec_find_decoder(stream->codecpar->codec_id);
    
    if (!codec) {
        r = -5;
        goto fail;
    }
    
    if (avcodec_open2(avctx, codec, NULL) < 0) {
        r = -6;
        goto fail;
    }
    
    com = av_mallocz(sizeof(FFSubComponent));
    if (!com) {
        r = -7;
        goto fail;
    }
    
    com->video_width = vw;
    com->video_height = vh;
    com->frameq = frameq;
    com->packetq = packetq;
    com->retry_callback = callback;
    com->retry_opaque = opaque;
    com->st_idx = stream_index;
    com->sp = ijk_subtitle_default_preference();
    
    int ret = decoder_init(&com->decoder, avctx, com->packetq, NULL);
    
    if (ret < 0) {
        r = -7;
        goto fail;
    }
    
    ret = decoder_start(&com->decoder, subtitle_thread, com, "ff_subtitle_dec");
    if (ret < 0) {
        r = -8;
        goto fail;
    }
    
    av_log(NULL, AV_LOG_INFO, "sub stream opened:%d use enc:%s,serial:%d\n", stream_index, enc, packetq->serial);
    *cp = com;
    return 0;
fail:
    decoder_destroy(&com->decoder);
    av_free(com);
    avcodec_free_context(&avctx);
    return r;
}

int subComponent_close(FFSubComponent **cp)
{
    if (!cp) {
        return -1;
    }
    FFSubComponent *com = *cp;
    if (!com) {
        return -2;
    }
    
    if (com->st_idx == -1) {
        return -3;
    }
    decoder_abort(&com->decoder, com->frameq);
    decoder_destroy(&com->decoder);
    FreeSubtitleBufferArray(&com->sub_buffer_array);
    av_freep(cp);
    return 0;
}

int subComponent_get_stream(FFSubComponent *com)
{
    if (com) {
        return com->st_idx;
    }
    return -1;
}

AVCodecContext * subComponent_get_avctx(FFSubComponent *com)
{
    return com ? com->decoder.avctx : NULL;
}

void subComponent_update_preference(FFSubComponent *com, IJKSDLSubtitlePreference* sp)
{
    if (!com) {
        return;
    }
    
    if (!isIJKSDLSubtitlePreferenceEqual(&com->sp, sp)) {
        com->sp = *sp;
        com->sp_changed = 1;
        apply_preference(com);
    }
}
