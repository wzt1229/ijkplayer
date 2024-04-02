//
//  ff_sub_component.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/5/24.
//

#include "ff_sub_component.h"
#include "ff_frame_queue.h"
#include "ff_packet_list.h"
#include "ff_ass_steam_renderer.h"
#include "ff_ass_parser.h"
#include "ijksdl/ijksdl_texture.h"
#include "ff_subtitle_def_internal.h"

#define SUB_REF_MAX_LEN 16
#define SUB_MAX_KEEP_DU 3.0
#define SUB_MIN_KEEP_DU 0.5

typedef struct FFSubComponent{
    int st_idx;
    PacketQueue* packetq;
    Decoder decoder;
    FrameQueue* frameq;
    AVFormatContext *ic;
    int64_t seek_req;
    AVPacket *pkt;
    int eof;
    subComponent_retry_callback retry_callback;
    void *retry_opaque;
    FF_ASS_Renderer *assRenderer;
    int width, height;
    SDL_TextureOverlay *overlay;
    FFSubtitleBuffer* pre_list [SUB_REF_MAX_LEN];
}FFSubComponent;

static int stream_has_enough_packets(PacketQueue *queue, int min_frames)
{
    return queue->abort_request || queue->nb_packets > min_frames;
}

static int read_packets(FFSubComponent *sub)
{
    if (!sub) {
        return -1;
    }
    
    if (sub->eof) {
        return -2;
    }
    
    if (sub->ic) {
        sub->pkt->flags = 0;
        do {
            if (stream_has_enough_packets(sub->packetq, 5)) {
                return 1;
            }
            int ret = av_read_frame(sub->ic, sub->pkt);
            if (ret >= 0) {
                if (sub->pkt->stream_index != sub->st_idx) {
                    av_packet_unref(sub->pkt);
                    continue;
                }
                packet_queue_put(sub->packetq, sub->pkt);
                continue;
            } else if (ret == AVERROR_EOF) {
                packet_queue_put_nullpacket(sub->packetq, sub->pkt, sub->st_idx);
                sub->eof = 1;
                return 1;
            } else {
                return -3;
            }
        } while (sub->packetq->abort_request == 0);
    }
    return -4;
}

static int get_packet(FFSubComponent *sub, Decoder *d)
{
    while (sub->packetq->abort_request == 0) {
        
        if (sub->seek_req >= 0) {
            av_log(NULL, AV_LOG_DEBUG,"sub seek to:%lld\n",fftime_to_seconds(sub->seek_req));
            if (avformat_seek_file(sub->ic, -1, INT64_MIN, sub->seek_req, INT64_MAX, 0) < 0) {
                av_log(NULL, AV_LOG_WARNING, "%d: could not seek to position %lld\n",
                       sub->st_idx, sub->seek_req);
                sub->seek_req = -1;
                return -2;
            }
            sub->seek_req = -1;
            packet_queue_flush(sub->packetq);
            continue;
        }
        
        int r = packet_queue_get(d->queue, d->pkt, 0, &d->pkt_serial);
        if (r < 0) {
            return -1;
        } else if (r == 0) {
            if (read_packets(sub) >= 0) {
                continue;
            } else {
                av_usleep(1000 * 3);
            }
        } else {
            return 0;
        }
    }
    return -3;
}

static int decode_a_frame(FFSubComponent *sub, Decoder *d, AVSubtitle *pkt)
{
    int ret = AVERROR(EAGAIN);

    for (;sub->packetq->abort_request == 0;) {
        
        do {
            if (d->packet_pending) {
                d->packet_pending = 0;
            } else {
                int old_serial = d->pkt_serial;
                if (get_packet(sub, d) < 0)
                    return -1;
                if (old_serial != d->pkt_serial) {
                    avcodec_flush_buffers(d->avctx);
                    d->finished = 0;
                    d->next_pts = d->start_pts;
                    d->next_pts_tb = d->start_pts_tb;
                }
            }
            if (d->queue->serial == d->pkt_serial)
                break;
            av_packet_unref(d->pkt);
        } while (sub->packetq->abort_request == 0);

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

static void convert_pal(uint32_t *colors, size_t count, bool gray)
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
        colors[n] = r | (g << 8) | (b << 16) | (a << 24);
    }
}

/// the graphic subtitles' bitmap with pixel format AV_PIX_FMT_PAL8,
/// https://ffmpeg.org/doxygen/trunk/pixfmt_8h.html#a9a8e335cf3be472042bc9f0cf80cd4c5
/// need to be converted to RGBA32 before use

static FFSubtitleBuffer* convert_pal8_to_bgra(const AVSubtitleRect* rect)
{
    uint32_t pal[256] = {0};
    memcpy(pal, rect->data[1], rect->nb_colors * 4);
    convert_pal(pal, rect->nb_colors, 0);
    
    SDL_Rectangle r = (SDL_Rectangle){rect->x, rect->y, rect->w, rect->h};
    FFSubtitleBuffer *frame = ff_subtitle_buffer_alloc_image(r, 4);
    if (!frame) {
        return NULL;
    }
    frame->usedAss = 0;
    
    for (int y = 0; y < rect->h; y++) {
        uint8_t *in = rect->data[0] + y * rect->linesize[0];
        uint32_t *out = (uint32_t *)(frame->data + y * frame->stride);
        for (int x = 0; x < rect->w; x++)
            *out++ = pal[*in++];
    }
    return frame;
}

static int create_ass_renderer_if_need(FFSubComponent *com)
{
    if (com->assRenderer) {
        return 0;
    }
    enum AVMediaType codec_type = com->decoder.avctx->codec_type;
    enum AVCodecID   codec_id = com->decoder.avctx->codec_id;
    
    if (com->width > 0 && com->height > 0 && codec_type == AVMEDIA_TYPE_SUBTITLE && (codec_id == AV_CODEC_ID_ASS || codec_id == AV_CODEC_ID_SUBRIP)) {
        FF_ASS_Renderer *assRenderer = ff_ass_render_create_default(com->decoder.avctx->subtitle_header, com->decoder.avctx->subtitle_header_size, com->width, com->height, NULL);
        if (assRenderer && com->ic) {
            for (int i = 0; i < com->ic->nb_streams; i++) {
                AVStream *st = com->ic->streams[com->st_idx];
                assRenderer->iformat->set_attach_font(assRenderer, st);
            }
        }
        com->assRenderer = assRenderer;
    }
    return NULL == com->assRenderer;
}

static void free_pre_list(FFSubtitleBuffer *sbp [])
{
    if (sbp) {
        int count = 0;
        while (count < SUB_REF_MAX_LEN) {
            FFSubtitleBuffer *h = sbp[count];
            if (!h) {
                break;
            }
            ff_subtitle_buffer_release(&h);
            count++;
        }
    }
}

static int diff_list(FFSubtitleBuffer *sbp1 [], FFSubtitleBuffer *sbp2 [])
{
    for (int i = 0; i < SUB_REF_MAX_LEN; i++) {
        FFSubtitleBuffer *h1 = sbp1[i];
        FFSubtitleBuffer *h2 = sbp2[i];
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
            double pts = 0;
            if (sub.pts != AV_NOPTS_VALUE)
                pts = sub.pts / (double)AV_TIME_BASE;
            
            //av_log(NULL, AV_LOG_ERROR,"sub received frame:%f\n",pts);
            int serial = com->decoder.pkt_serial;
            if (com->packetq->serial == serial) {
                if (com->decoder.avctx->codec_id == AV_CODEC_ID_HDMV_PGS_SUBTITLE || com->decoder.avctx->codec_id == AV_CODEC_ID_FIRST_SUBTITLE) {
                    if (sub.num_rects > 0 && sub.rects[0]->type == SUBTITLE_BITMAP
                               && sub.rects[0]->data[0]
                               && sub.rects[0]->linesize[0]) {
                        FFSubtitleBuffer* sb = convert_pal8_to_bgra(sub.rects[0]);
                        if (sb) {
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
                                    float t = sp->pts - pre_pts - 0.1;
                                    t = t < SUB_MAX_KEEP_DU ? t : SUB_MAX_KEEP_DU;
                                    t = t < SUB_MIN_KEEP_DU ? 1.5 : t;
                                    pre->duration = t;
                                }
                            } else {
                                sp->duration = SUB_MAX_KEEP_DU;
                            }
                            sp->serial = serial;
                            sp->width  = com->decoder.avctx->width;
                            sp->height = com->decoder.avctx->height;
                            sp->shown = 0;
                            sp->sb = sb;
                            frame_queue_push(com->frameq);
                            pre_pts = sp->pts;
                            avsubtitle_free(&sub);
                        } else {
                            avsubtitle_free(&sub);
                            break;
                        }
                    }
                } else {
                    for (int i = 0; i < sub.num_rects; i++) {
                        char *ass_line = sub.rects[i]->ass;
                        if (!ass_line)
                            break;
                        if (!create_ass_renderer_if_need(com)) {
                            const float begin = pts + (float)sub.start_display_time / 1000.0;
                            float end = sub.end_display_time - sub.start_display_time;
                            ff_ass_process_chunk(com->assRenderer, ass_line, begin * 1000, end);
                        }
                    }
                    avsubtitle_free(&sub);
                }
            } else {
                pre_pts = 0;
                av_log(NULL, AV_LOG_DEBUG,"sub stream push old frame:%d\n",serial);
            }
        }
    }
    
    ff_ass_render_release(&com->assRenderer);
    com->retry_callback = NULL;
    com->retry_opaque = NULL;
    av_packet_free(&com->pkt);
    free_pre_list(com->pre_list);
    return 0;
}

int subComponent_blend_frame(FFSubComponent *com, float pts, FFSubtitleBuffer **buffer)
{
    if (!buffer || com->packetq->abort_request) {
        return -1;
    }
    if (com->assRenderer) {
        FF_ASS_Renderer *assRenderer = ff_ass_render_retain(com->assRenderer);
        int r = ff_ass_blend_frame(assRenderer, pts, buffer);
        ff_ass_render_release(&assRenderer);
        return r;
    } else {
        int serial = subComponent_get_serial(com);
        if (serial == -1) {
            return -2;
        }
        
        int r = -1;
        int rem = 0;
        while ((rem = frame_queue_nb_remaining(com->frameq)) > 0) {
            if (rem > 1) {
                Frame *sp2 = frame_queue_peek_next(com->frameq);
                if (pts > sp2->pts) {
                    frame_queue_next(com->frameq);
                    continue;
                }
            }
            Frame * sp = frame_queue_peek(com->frameq);
            if (sp->serial != serial) {
                frame_queue_next(com->frameq);
                continue;
            }
            float begin = sp->pts;
            float end = begin + sp->duration;
            
            if (pts > begin && pts < end) {
                if (!sp->shown) {
                    *buffer = ff_subtitle_buffer_retain(sp->sb);
                    r = 1;
                    sp->shown = 1;
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
}

static void replace_bitmap(SDL_TextureOverlay *overlay, FFSubtitleBuffer *frame)
{
    if (overlay && frame) {
        overlay->replaceRegion(overlay->opaque, frame->rect, frame->data);
    }
}

static void clean_dirty_texture(SDL_TextureOverlay *overlay)
{
    if (overlay) {
        overlay->clearDirtyRect(overlay);
    }
}

static void set_dirtyRect(SDL_TextureOverlay *overlay, SDL_Rectangle rect)
{
    if (overlay) {
        overlay->dirtyRect = rect;
    }
}

int subComponent_upload_frame(FFSubComponent *com, float pts, SDL_GPU *gpu, SDL_TextureOverlay **overlay)
{
    if (!overlay || com->packetq->abort_request) {
        return -1;
    }
    
    if (com->overlay && (com->overlay->w != com->width || com->overlay->h != com->height)) {
        SDL_TextureOverlayFreeP(&com->overlay);
    }
    if (!com->overlay) {
        com->overlay = gpu->createTexture(gpu->opaque, com->width, com->height);
    }
    *overlay = com->overlay;
    
    if (com->assRenderer) {
        FF_ASS_Renderer *assRenderer = ff_ass_render_retain(com->assRenderer);
        int r = ff_ass_upload_frame(assRenderer, pts, *overlay);
        ff_ass_render_release(&assRenderer);
        return r;
    } else {
        int serial = subComponent_get_serial(com);
        if (serial == -1) {
            return -2;
        }
        
        int total = 0;
        while ((total = frame_queue_nb_remaining(com->frameq)) > 0) {
            Frame *sp = frame_queue_peek(com->frameq);
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
            break;
        }
        
        FFSubtitleBuffer* buffers [SUB_REF_MAX_LEN] = { 0 };
        int idx = 0;
        for (int i = 0; i < total && idx < SUB_REF_MAX_LEN; i ++) {
            Frame *sp = frame_queue_peek_offset(com->frameq, i);
            if (sp && sp->sb && pts > sp->pts) {
                buffers[idx++] = ff_subtitle_buffer_retain(sp->sb);
                continue;
            } else {
                break;
            }
        }
        int count = idx;
        if (diff_list(com->pre_list, buffers)) {
            free_pre_list(com->pre_list);
            if (count > 0) {
                memcpy(com->pre_list, buffers, sizeof(buffers));
            } else {
                bzero(com->pre_list, sizeof(com->pre_list));
            }
            
            clean_dirty_texture(*overlay);
            if (count > 0) {
                SDL_Rectangle dirty_rect = {0};
                for (int i = 0; i < count; i++) {
                    FFSubtitleBuffer *sb = buffers[i];
                    replace_bitmap(*overlay, sb);
                    dirty_rect = SDL_union_rectangle(dirty_rect, sb->rect);
                }
                if (!isZeroRectangle(dirty_rect)) {
                    set_dirtyRect(*overlay, dirty_rect);
                }
                return 1;
            }
        } else {
            free_pre_list(buffers);
            return 0;
        }
        return -3;
    }
}

void subComponent_update_margin(FFSubComponent *com, int t, int b, int l, int r)
{
    if (com->assRenderer) {
        com->assRenderer->iformat->update_margin(com->assRenderer, t, b, l, r);
    }
}

int subComponent_open(FFSubComponent **subp, int stream_index, AVFormatContext* ic, AVCodecContext *avctx, PacketQueue* packetq, FrameQueue* frameq, subComponent_retry_callback callback, void *opaque, int vw, int vh)
{
    if (!subp) {
        return -1;
    }
    
    FFSubComponent *sub = av_mallocz(sizeof(FFSubComponent));
    if (!sub) {
        return -2;
    }
    
    assert(frameq);
    assert(packetq);
    
    sub->frameq = frameq;
    sub->packetq = packetq;
    sub->seek_req = -1;
    sub->ic = ic;
    sub->pkt = av_packet_alloc();
    sub->eof = 0;
    sub->retry_callback = callback;
    sub->retry_opaque = opaque;
    sub->width = vw;
    sub->height = vh;
    
    int ret = decoder_init(&sub->decoder, avctx, sub->packetq, NULL);
    
    if (ret < 0) {
        av_free(sub);
        return ret;
    }
    
    ret = decoder_start(&sub->decoder, subtitle_thread, sub, "ff_subtitle_dec");
    if (ret < 0) {
        decoder_destroy(&sub->decoder);
        av_free(sub);
        return ret;
    }
    sub->st_idx = stream_index;
    av_log(NULL, AV_LOG_INFO, "sub stream opened:%d,serial:%d\n", stream_index, packetq->serial);
    *subp = sub;
    return 0;
}

int subComponent_close(FFSubComponent **subp)
{
    if (!subp) {
        return -1;
    }
    FFSubComponent *sub = *subp;
    if (!sub) {
        return -2;
    }
    
    if (sub->st_idx == -1) {
        return -3;
    }
    sub->st_idx = -1;
    decoder_abort(&sub->decoder, sub->frameq);
    decoder_destroy(&sub->decoder);
    av_freep(subp);
    return 0;
}

int subComponent_get_stream(FFSubComponent *sub)
{
    if (sub) {
        return sub->st_idx;
    }
    return -1;
}

int subComponent_seek_to(FFSubComponent *sub, int sec)
{
    if (!sub || !sub->ic) {
        return -1;
    }
    if (sec < 0) {
        sec = 0;
    }
    sub->seek_req = seconds_to_fftime(sec);
    sub->eof = 0;
    return 0;
}

AVCodecContext * subComponent_get_avctx(FFSubComponent *sub)
{
    return sub ? sub->decoder.avctx : NULL;
}

int subComponent_get_serial(FFSubComponent *sub)
{
    return sub ? sub->packetq->serial : -1;
}
