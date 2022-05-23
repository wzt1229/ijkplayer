//
//  ff_in_subtitle.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/5/20.
//

#include "ff_in_subtitle.h"
#include "ff_frame_queue.h"
#include "ff_packet_list.h"
#include "ff_ass_parser.h"

typedef struct FFINSubtitle{
    int st_idx;
    PacketQueue packetq;
    Decoder decoder;
    FrameQueue frameq;
    float delay;
    float current_pts;
    SDL_mutex* mutex;
}FFINSubtitle;

static double get_frame_real_begin_pts(FFINSubtitle *sub, Frame *sp)
{
    return sp->pts + (float)sp->sub.start_display_time / 1000.0;
}

static double get_frame_begin_pts(FFINSubtitle *sub, Frame *sp)
{
    return sp->pts + (float)sp->sub.start_display_time / 1000.0 + sub->delay;
}

static double get_frame_end_pts(FFINSubtitle *sub, Frame *sp)
{
    return sp->pts + (float)sp->sub.end_display_time / 1000.0 + sub->delay;
}

static int stream_has_enough_packets(int stream_id, PacketQueue *queue, int min_frames)
{
    return stream_id < 0 ||
           queue->abort_request ||
           queue->nb_packets > min_frames;
}

static int get_frame(Decoder *d)
{
    while (1) {
        int r = packet_queue_get(d->queue, d->pkt, 0, &d->pkt_serial);
        if (r < 0) {
            return -1;
        } else if (r == 0) {
            av_usleep(1000 * 3);
        } else {
            return 0;
        }
    }
}

static int decode_a_frame(Decoder *d, AVSubtitle *sub)
{
    int ret = AVERROR(EAGAIN);

    for (;;) {
        
        do {
            if (d->queue->nb_packets == 0)
                SDL_CondSignal(d->empty_queue_cond);
            if (d->packet_pending) {
                d->packet_pending = 0;
            } else {
                int old_serial = d->pkt_serial;
                if (get_frame(d) < 0)
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
        } while (1);

        int got_frame = 0;
        ret = avcodec_decode_subtitle2(d->avctx, sub, &got_frame, d->pkt);
        if (ret < 0) {
            ret = AVERROR(EAGAIN);
        } else {
            if (got_frame && !d->pkt->data) {
                d->packet_pending = 1;
            }
            ret = got_frame ? 0 : (d->pkt->data ? AVERROR(EAGAIN) : AVERROR_EOF);
        }
        av_packet_unref(d->pkt);
        
        if (ret >= 0)
            return 1;
    }
}

static int subtitle_thread(void *arg)
{
    FFINSubtitle *sub = arg;
    Frame *sp;
    int got_subtitle;
    double pts;

    for (;;) {
        if (!(sp = frame_queue_peek_writable(&sub->frameq)))
            return 0;
        
        if ((got_subtitle = decode_a_frame(&sub->decoder, &sp->sub)) < 0)
            break;

        pts = 0;
        if (got_subtitle) {
            if (sp->sub.pts != AV_NOPTS_VALUE)
                pts = sp->sub.pts / (double)AV_TIME_BASE;
            sp->pts = pts;
            sp->serial = sub->decoder.pkt_serial;
            sp->width = sub->decoder.avctx->width;
            sp->height = sub->decoder.avctx->height;
            sp->uploaded = 0;

            /* now we can update the picture count */
            frame_queue_push(&sub->frameq);
        }
    }
    return 0;
}

int inSub_drop_frames_lessThan_pts(FFINSubtitle *sub, float pts)
{
    if (!sub || sub->st_idx == -1) {
        return -1;
    }
    Frame *sp, *sp2;
    FrameQueue *subpq = &sub->frameq;
    int q_serial = sub->packetq.serial;
    int uploaded = 0;
    while (frame_queue_nb_remaining(subpq) > 0) {
        sp = frame_queue_peek(subpq);

        if (frame_queue_nb_remaining(subpq) > 1) {
            sp2 = frame_queue_peek_next(subpq);
        } else {
            sp2 = NULL;
        }
        
        //when video's pts greater than sub's pts need drop
        if (sp->serial != q_serial ||
            (pts > get_frame_end_pts(sub, sp)) ||
            (sp2 && pts > get_frame_begin_pts(sub, sp2))) {
            if (sp->uploaded) {
                uploaded ++;
            }
            frame_queue_next(subpq);
            continue;
        }
        break;
    }
    return uploaded;
}

int inSub_fetch_frame(FFINSubtitle *sub, float pts, char **text, AVSubtitleRect **bmp)
{
    if (!sub || sub->st_idx == -1) {
        return -1;
    }
    int r = 1;
    if (frame_queue_nb_remaining(&sub->frameq) > 0) {
        Frame * sp = frame_queue_peek(&sub->frameq);
        sub->current_pts = get_frame_real_begin_pts(sub, sp);
        float begin = sub->current_pts + sub->delay;
        if (pts >= begin) {
            if (!sp->uploaded) {
                if (sp->sub.num_rects > 0) {
                    if (sp->sub.rects[0]->text) {
                        *text = av_strdup(sp->sub.rects[0]->text);
                    } else if (sp->sub.rects[0]->ass) {
                        *text = parse_ass_subtitle(sp->sub.rects[0]->ass);
                    } else if (sp->sub.rects[0]->type == SUBTITLE_BITMAP
                               && sp->sub.rects[0]->data[0]
                               && sp->sub.rects[0]->linesize[0]) {
                        *bmp = sp->sub.rects[0];
                    } else {
                        assert(0);
                    }
                }
                r = 0;
                sp->uploaded = 1;
            }
        } else {
            if (sp->uploaded) {
                //clean current display sub
                sp->uploaded = 0;
                r = -3;
            }
        }
    }
    return r;
}

int inSub_flush_packet_queue(FFINSubtitle *sub)
{
    if (sub && sub->st_idx != -1) {
        packet_queue_flush(&sub->packetq);
        return 0;
    }
    return -1;
}

int inSub_frame_queue_size(FFINSubtitle *sub)
{
    if (sub && sub->st_idx != -1) {
        return sub->frameq.size;
    }
    return 0;
}

int inSub_has_enough_packets(FFINSubtitle *sub, int min_frames)
{
    if (sub && sub->st_idx != -1) {
        return stream_has_enough_packets(sub->st_idx, &sub->packetq, min_frames);
    }
    return 1;
}

int inSub_put_null_packet(FFINSubtitle *sub, AVPacket *pkt)
{
    if (sub && sub->st_idx != -1) {
        return packet_queue_put_nullpacket(&sub->packetq, pkt, sub->st_idx);
    }
    return -1;
}

int inSub_put_packet(FFINSubtitle *sub, AVPacket *pkt)
{
    if (sub && sub->st_idx != -1) {
        return packet_queue_put(&sub->packetq, pkt);
    }
    return -1;
}

int inSub_get_opened_stream_idx(FFINSubtitle *sub)
{
    if (sub) {
        return sub->st_idx;
    }
    return -1;
}

int inSub_set_delay(FFINSubtitle *sub, float delay, float cp)
{
    if (sub) {
        float wantDisplay = cp - delay;
        if (sub->current_pts > wantDisplay) {
            sub->delay = delay;
            return -1;
        } else {
            //when no need seek,just apply the diff to output frame's pts
            sub->delay = delay;
            return 0;
        }
    }
    return -2;
}

float inSub_get_delay(FFINSubtitle *sub)
{
    return sub ? sub->delay : 0.0f;
}

int inSub_close_current(FFINSubtitle **subp)
{
    if (!subp) {
        return -1;
    }
    FFINSubtitle *sub = *subp;
    if (!sub) {
        return -2;
    }
    if (sub->st_idx == -1) {
        return -3;
    }
    
    sub->st_idx = -1;
    
    decoder_abort(&sub->decoder, &sub->frameq);
    decoder_destroy(&sub->decoder);
    
    packet_queue_destroy(&sub->packetq);
    frame_queue_destory(&sub->frameq);
    
    av_freep(subp);
    return 0;
}

int inSub_create(FFINSubtitle **subp, int stream_index, AVStream * st, AVCodecContext *avctx, SDL_cond *empty_queue_cond)
{
    if (!subp) {
        return -1;
    }
    
    FFINSubtitle *sub = av_malloc(sizeof(FFINSubtitle));
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
    
    int ret = decoder_init(&sub->decoder, avctx, &sub->packetq, empty_queue_cond);
    
    if (ret < 0) {
        packet_queue_destroy(&sub->packetq);
        frame_queue_destory(&sub->frameq);
        av_free(sub);
        return ret;
    }
    ret = decoder_start(&sub->decoder, subtitle_thread, sub, "ff_subtitle_dec");
    if (ret < 0) {
        packet_queue_destroy(&sub->packetq);
        frame_queue_destory(&sub->frameq);
        decoder_destroy(&sub->decoder);
        av_free(sub);
        return ret;
    }
    sub->st_idx = stream_index;
    *subp = sub;
    return 0;
}
