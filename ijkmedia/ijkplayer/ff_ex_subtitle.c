//
//  ff_ex_subtitle.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/5/16.
//
// after activate not need seek, because video stream will be seeked.

#include "ff_ex_subtitle.h"
#include "libavformat/avformat.h"
#include "ff_ffplay_def.h"
#include "ff_frame_queue.h"
#include "ff_packet_list.h"
#include "ff_cmdutils.h"
#include "ff_ass_parser.h"
#include "ff_ffplay.h"

#define IJK_EX_SUBTITLE_STREAM_OFFSET   1000
#define IJK_EX_SUBTITLE_STREAM_MAX      1100

typedef struct _IJKEXSubtitle_Opaque{
    AVFormatContext *ic;
    AVCodecContext *avctx;
    int st_idx;
    AVStream *stream;
    
    FrameQueue frameq;
    PacketQueue pktq;
    Decoder subdec;
    
    int eof;
    int abort;
} IJKEXSubtitle_Opaque;

typedef struct IJKEXSubtitle {
    SDL_mutex* mutex;
    float delay;//(s)
    float delay_diff;
    float current_pts;
    IJKEXSubtitle_Opaque* opaque;
    char* pathArr[IJK_EX_SUBTITLE_STREAM_MAX - IJK_EX_SUBTITLE_STREAM_OFFSET];
    int   next_idx;
}IJKEXSubtitle;

void exSub_set_delay(IJKEXSubtitle *sub, float delay, float cp)
{
    if (sub) {
        float wantDisplay = cp - delay;
        if (sub->current_pts > wantDisplay) {
            sub->delay = delay;
            sub->delay_diff = 0.0f;
            exSub_seek_to(sub, wantDisplay-2);
        } else {
            //when no need seek,just apply the diff to output frame's pts
            float diff = delay - sub->delay;
            sub->delay_diff = diff;
        }
    }
}

float exSub_get_delay(IJKEXSubtitle *sub)
{
    return sub ? (sub->delay + sub->delay_diff) : 0.0f;
}

int exSub_get_opened_stream_idx(IJKEXSubtitle *sub)
{
    if (sub && sub->opaque && sub->opaque->stream) {
        return sub->opaque->st_idx;
    }
    return -1;
}

static double get_frame_real_begin_pts(IJKEXSubtitle *sub, Frame *sp)
{
    return sp->pts + (float)sp->sub.start_display_time / 1000.0;
}

static double get_frame_begin_pts(IJKEXSubtitle *sub, Frame *sp)
{
    return sp->pts + (float)sp->sub.start_display_time / 1000.0 + sub->delay + sub->delay_diff;
}

static double get_frame_end_pts(IJKEXSubtitle *sub, Frame *sp)
{
    return sp->pts + (float)sp->sub.end_display_time / 1000.0 + sub->delay + sub->delay_diff;
}

int exSub_drop_frames_lessThan_pts(IJKEXSubtitle *sub, float pts)
{
    if (!sub || !sub->opaque) {
        return -1;
    }
    Frame *sp, *sp2;
    FrameQueue *subpq = &sub->opaque->frameq;
    int q_serial = sub->opaque->pktq.serial;
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

int exSub_fetch_frame(IJKEXSubtitle *sub, float pts, char **text)
{
    if (!text) {
        return -1;
    }
    if (!sub || !sub->opaque || sub->opaque->st_idx == -1) {
        return -2;
    }
    int r = 1;
    FrameQueue *subpq = &sub->opaque->frameq;
    if (frame_queue_nb_remaining(subpq) > 0) {
        Frame * sp = frame_queue_peek(subpq);
        sub->current_pts = get_frame_real_begin_pts(sub, sp);
        float begin = sub->current_pts + sub->delay + sub->delay_diff;
        if (pts >= begin) {
            if (!sp->uploaded) {
                if (sp->sub.num_rects > 0) {
                    if (sp->sub.rects[0]->text) {
                        *text = av_strdup(sp->sub.rects[0]->text);
                    } else if (sp->sub.rects[0]->ass) {
                        *text = parse_ass_subtitle(sp->sub.rects[0]->ass);
                    } else {
                        assert(0);
                    }
                }
                r = 0;
                sp->uploaded = 1;
            }
        } else if (sp->uploaded) {
            //clean current display sub
            sp->uploaded = 0;
            r = -3;
        }
    }
    return r;
}

int exSub_seek_to(IJKEXSubtitle *sub, float sec)
{
    if (!sub || !sub->opaque) {
        return -1;
    }
    
    int ret = 0;
    
    SDL_LockMutex(sub->mutex);
    if (sub->opaque->ic) {
        int64_t seek_time = seconds_to_fftime(sec);
        
        if (avformat_seek_file(sub->opaque->ic, -1, INT64_MIN, seek_time, INT64_MAX, 0) < 0) {
            av_log(NULL, AV_LOG_WARNING, "%d: could not seek to position %lld\n",
                   sub->opaque->st_idx, seek_time);
            ret = -2;
        }
        sub->opaque->eof = 0;
        packet_queue_flush(&sub->opaque->pktq);
    }
    SDL_UnlockMutex(sub->mutex);
    return ret;
}

int exSub_frame_queue_size(IJKEXSubtitle *sub)
{
    if (sub && sub->opaque) {
        return sub->opaque->pktq.size;
    }
    return 0;
}

static int stream_has_enough_packets(AVStream *st, int stream_id, PacketQueue *queue, int min_frames)
{
    return stream_id < 0 ||
           queue->abort_request ||
           (st->disposition & AV_DISPOSITION_ATTACHED_PIC) ||
#ifdef FFP_MERGE
           queue->nb_packets > MIN_FRAMES && (!queue->duration || av_q2d(st->time_base) * queue->duration > 1.0);
#endif
           queue->nb_packets > min_frames;
}

int exSub_has_enough_packets(IJKEXSubtitle *sub, int min_frames)
{
    if (sub && sub->opaque) {
        return stream_has_enough_packets(sub->opaque->stream, sub->opaque->st_idx, &sub->opaque->pktq, min_frames);
    }
    return 1;
}

static IJKEXSubtitle * init_exSub_ifNeed(FFPlayer *ffp)
{
    if (!ffp || !ffp->is) {
        return NULL;
    }
    
    if (!ffp->is->exSub) {
        IJKEXSubtitle *sub = av_mallocz(sizeof(IJKEXSubtitle));
        
        sub->mutex = SDL_CreateMutex();
        if (NULL == sub->mutex) {
            av_free(sub);
            return NULL;
        }
        
        ffp->is->exSub = sub;
    }
    return ffp->is->exSub;
}

//0:eof; > 0:ok ; < 0:failed;
static int read_packets(IJKEXSubtitle *sub)
{
    if (!sub) {
        return -1;
    }
    
    IJKEXSubtitle_Opaque *opaque = sub->opaque;
    
    if (!opaque) {
        return -2;
    }
    
    if (opaque->eof) {
        return 0;
    }
    
    AVPacket *pkt = av_packet_alloc();
    if (!pkt) {
        av_log(NULL, AV_LOG_FATAL, "Could not allocate packet.\n");
        return -4;
    }
    
    int r = -5;
    if (opaque->ic) {
        pkt->flags = 0;
        do {
            int ret = av_read_frame(opaque->ic, pkt);
            if (ret >= 0) {
                if (pkt->stream_index != opaque->st_idx) {
                    av_packet_unref(pkt);
                    continue;
                }
                packet_queue_put(&opaque->pktq, pkt);
                r = 1;
                break;
            } else if (ret == AVERROR_EOF) {
                packet_queue_put_nullpacket(&opaque->pktq, pkt, opaque->st_idx);
                opaque->eof = 1;
                r = 0;
                break;
            } else {
                r = -6;
            }
        } while (1);
    }
    
    av_packet_free(&pkt);
    
    return r;
}

static int get_packet(IJKEXSubtitle *sub, AVPacket *pkt)
{
    if (!sub) {
        return -1;
    }
    
    IJKEXSubtitle_Opaque *opaque = sub->opaque;
    
    if (!opaque) {
        return -2;
    }
    
    Decoder* d = &opaque->subdec;
    
    if (packet_queue_get(d->queue, pkt, 0, &d->pkt_serial) != 1) {
        int r = read_packets(sub);
        if (r <= 0) {
            return -3;
        }
    } else {
        return 0;
    }
    
    return packet_queue_get(d->queue, pkt, 0, &d->pkt_serial) == 1;
}

//外挂字幕解码线程
static int decoder_loop(IJKEXSubtitle *sub)
{
    if (!sub) {
        return -1;
    }
    
    IJKEXSubtitle_Opaque *opaque = sub->opaque;
    
    if (!opaque) {
        return -2;
    }
    
    Decoder* d = &opaque->subdec;
    Frame *sp = NULL;
    int got_frame = 0;

    for (;;) {
        
        if (!(sp = frame_queue_peek_writable(&opaque->frameq)))
            return -100;

        int ret = 0;
        AVPacket pkt;

        for (;;) {
            if (d->queue->abort_request)
                return -100;
            do {
                if (d->packet_pending) {
                    av_packet_move_ref(&pkt, d->pkt);
                    d->packet_pending = 0;
                } else {
                    int old_serial = d->pkt_serial;
                    if (get_packet(sub, &pkt) < 0) {
                        return -3;
                    }
                    if (old_serial != d->pkt_serial) {
                        avcodec_flush_buffers(d->avctx);
                        d->finished = 0;
                        d->next_pts = d->start_pts;
                        d->next_pts_tb = d->start_pts_tb;
                    }
                }
            } while (d->queue->serial != d->pkt_serial);

            if (d->avctx->codec_type == AVMEDIA_TYPE_SUBTITLE) {
                ret = avcodec_decode_subtitle2(d->avctx, &sp->sub, &got_frame, &pkt);
                if (ret < 0) {
                    ret = AVERROR(EAGAIN);
                    return 0;
                } else {
                    if (got_frame && !pkt.data) {
                        d->packet_pending = 1;
                        av_packet_move_ref(d->pkt, &pkt);
                    }
                    break;
                }
            }
        }
        
        if (got_frame) {
            if (sp->sub.pts != AV_NOPTS_VALUE) {
                sp->pts = sp->sub.pts / (double)AV_TIME_BASE;
            }
            sp->serial = opaque->subdec.pkt_serial;
            sp->width  = opaque->subdec.avctx->width;
            sp->height = opaque->subdec.avctx->height;
            sp->uploaded = 0;

            /* now we can update the picture count */
            frame_queue_push(&opaque->frameq);
        }
        
        av_packet_unref(&pkt);
    }
    return 0;
}

//外挂字幕解码线程
static int decoder_thread(void *argv)
{
    IJKEXSubtitle *sub = (IJKEXSubtitle *)argv;
    while (sub && sub->opaque && !sub->opaque->abort) {
        int r = decoder_loop(sub);
        //abort
        if (r == -100) {
            break;
        } else {
            //has no sub need decoder,just wait 50ms.
            av_usleep(1000*50);
        }
    }
    return 0;
}

static IJKEXSubtitle_Opaque * createOpaque(const char *file_name)
{
    int err = 0;
    int ret = 0;
    
    IJKEXSubtitle_Opaque *opaque = NULL;
    AVCodecContext* avctx = NULL;
    
    AVFormatContext* ic = avformat_alloc_context();
    err = avformat_open_input(&ic, file_name, NULL, NULL);
    if (err < 0) {
        print_error(file_name, err);
        ret = -1;
        goto fail;
    }
    
    err = avformat_find_stream_info(ic, NULL);
    if (err < 0) {
        print_error(file_name, err);
        ret = -2;
        goto fail;
    }
    
    opaque = av_mallocz(sizeof(IJKEXSubtitle_Opaque));
    
    if (!opaque) {
        ret = -3;
        goto fail;
    }
    
    opaque->st_idx = -1;
    //字幕流的索引
    for (size_t i = 0; i < ic->nb_streams; ++i) {
        AVStream *stream = ic->streams[i];
        if (stream->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
            opaque->st_idx  = (int)i;
            opaque->stream = stream;
            stream->discard = AVDISCARD_DEFAULT;
        } else {
            stream->discard = AVDISCARD_ALL;
        }
    }
    
    if (!opaque->stream) {
        ret = -3;
        av_log(NULL, AV_LOG_WARNING, "none subtitle stream in %s\n",
                file_name);
        goto fail;
    }
    
    AVCodec* codec = avcodec_find_decoder(opaque->stream->codecpar->codec_id);
    if (!codec) {
        av_log(NULL, AV_LOG_WARNING, "could find codec:%s for %s\n",
                file_name, avcodec_get_name(opaque->stream->codecpar->codec_id));
        ret = -4;
        goto fail;
    }
    
    avctx = avcodec_alloc_context3(NULL);
    if (!avctx) {
        ret = -5;
        goto fail;
    }

    err = avcodec_parameters_to_context(avctx, opaque->stream->codecpar);
    if (err < 0) {
        print_error(file_name, err);
        ret = -6;
        goto fail;
    }
    //so important,ohterwise, sub frame has not pts.
    avctx->pkt_timebase = opaque->stream->time_base;
    
    if ((err = avcodec_open2(avctx, codec, NULL)) < 0) {
        print_error(file_name, err);
        ret = -7;
        goto fail;
    }
    
    if (frame_queue_init(&opaque->frameq, &opaque->pktq, SUBPICTURE_QUEUE_SIZE, 0) < 0) {
        ret = -8;
        goto fail;
    }

    if (packet_queue_init(&opaque->pktq) < 0) {
        ret = -9;
        goto fail;
    }
    
    opaque->ic = ic;
    opaque->eof = 0;
    opaque->avctx = avctx;
fail:
    if (ret < 0) {
        if (ic)
            avformat_close_input(&ic);
        if (avctx)
            avcodec_free_context(&avctx);
        if (opaque) {
            frame_queue_destory(&opaque->frameq);
            packet_queue_destroy(&opaque->pktq);
            av_free(opaque);
            opaque = NULL;
        }
    }
    
    return opaque;
}

static int convert_streamIdx(IJKEXSubtitle *sub, int idx)
{
    if (!sub) {
        return -1;
    }
    int arr_idx = -1;
    if (idx >= IJK_EX_SUBTITLE_STREAM_OFFSET && idx < IJK_EX_SUBTITLE_STREAM_MAX) {
        arr_idx = (idx - IJK_EX_SUBTITLE_STREAM_OFFSET) % (IJK_EX_SUBTITLE_STREAM_MAX - IJK_EX_SUBTITLE_STREAM_OFFSET);
    }
    return arr_idx;
}

static int exSub_open_filepath(IJKEXSubtitle *sub, const char *file_name, int idx)
{
    if (!sub) {
        return -1;
    }

    if (!file_name || strlen(file_name) == 0) {
        return -2;
    }
    
    IJKEXSubtitle_Opaque *opaque = createOpaque(file_name);
    if (opaque) {
        decoder_init(&opaque->subdec, opaque->avctx, &opaque->pktq, NULL);
        
        SDL_LockMutex(sub->mutex);
        sub->opaque = opaque;
        SDL_UnlockMutex(sub->mutex);
        
        decoder_start(&opaque->subdec, decoder_thread, sub, "ex_subtitle_thread");
        return 0;
    }
    return -3;
}

int exSub_open_file_idx(IJKEXSubtitle *sub, int idx)
{
    if (!sub) {
        return -1;
    }
    
    if (idx == -1) {
        return -2;
    }
    
    const char *file_name = sub->pathArr[idx];
    
    if (!file_name) {
        return -3;
    }
    
    if (exSub_open_filepath(sub, file_name, idx) != 0) {
        return -4;
    }
    
    return 0;
}


int exSub_close_current(IJKEXSubtitle *sub)
{
    if(!sub) {
        return -1;
    }
    
    IJKEXSubtitle_Opaque *opaque = sub->opaque;
    
    if(!opaque) {
        return -2;
    }

    SDL_LockMutex(sub->mutex);
    opaque->abort = 1;
    AVFormatContext *ic = opaque->ic;
    if (ic) {
        avformat_close_input(&ic);
        opaque->ic = NULL;
    }
    
    decoder_abort(&opaque->subdec, &opaque->frameq);
    decoder_destroy(&opaque->subdec);

    frame_queue_destory(&opaque->frameq);
    packet_queue_destroy(&opaque->pktq);

    av_freep(&sub->opaque);
    SDL_UnlockMutex(sub->mutex);
    return 0;
}

void exSub_subtitle_destroy(IJKEXSubtitle **subp)
{
    if (!subp) {
        return;
    }
    
    IJKEXSubtitle *sub = *subp;
    if (!sub) {
        return;
    }
    
    exSub_close_current(sub);

    SDL_LockMutex(sub->mutex);
    int sub_max = IJK_EX_SUBTITLE_STREAM_MAX - IJK_EX_SUBTITLE_STREAM_OFFSET;
    for (int i = 0; i < sub_max; i++) {
        if (sub->pathArr[i]) {
            av_free(sub->pathArr[i]);
        }
    }
    SDL_UnlockMutex(sub->mutex);
    
    SDL_DestroyMutex(sub->mutex);
    
    av_freep(subp);
}

static void ijkmeta_set_ex_subtitle_context_l(IjkMediaMeta *meta, struct AVFormatContext *ic, IJKEXSubtitle *sub, int actived)
{
    if (!meta || !ic || !sub)
        return;

    if (actived) {
        int stream_idx = (sub->next_idx - 1) % (IJK_EX_SUBTITLE_STREAM_MAX - IJK_EX_SUBTITLE_STREAM_OFFSET) + IJK_EX_SUBTITLE_STREAM_OFFSET;
        ijkmeta_set_int64_l(meta, IJKM_KEY_TIMEDTEXT_STREAM, stream_idx);
    }
    
    IjkMediaMeta *stream_meta = NULL;
    for (int i = 0; i < ic->nb_streams; i++) {
        AVStream *st = ic->streams[i];
        if (!st || !st->codecpar)
            continue;

        stream_meta = ijkmeta_create();
        if (!stream_meta)
            continue;

        AVCodecParameters *codecpar = st->codecpar;
        const char *codec_name = avcodec_get_name(codecpar->codec_id);
        if (codec_name)
            ijkmeta_set_string_l(stream_meta, IJKM_KEY_CODEC_NAME, codec_name);

        if (codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
            ijkmeta_set_string_l(stream_meta, IJKM_KEY_TYPE, IJKM_VAL_TYPE__TIMEDTEXT);
                
            ijkmeta_set_string_l(stream_meta, IJKM_KEY_EX_SUBTITLE_URL, ic->url);
        }

        AVDictionaryEntry *lang = av_dict_get(st->metadata, "language", NULL, 0);
        if (lang && lang->value)
            ijkmeta_set_string_l(stream_meta, IJKM_KEY_LANGUAGE, lang->value);

        AVDictionaryEntry *t = av_dict_get(st->metadata, "title", NULL, 0);
        if (t && t->value) {
            ijkmeta_set_string_l(stream_meta, IJKM_KEY_TITLE, t->value);
        } else {
            char title[64];
            snprintf(title, 64, "Track%d", sub->next_idx);
            ijkmeta_set_string_l(stream_meta, IJKM_KEY_TITLE, title);
        }
        
        int stream_idx = (sub->next_idx - 1) % (IJK_EX_SUBTITLE_STREAM_MAX - IJK_EX_SUBTITLE_STREAM_OFFSET) + IJK_EX_SUBTITLE_STREAM_OFFSET;
        ijkmeta_set_int64_l(stream_meta, IJKM_KEY_STREAM_IDX, stream_idx);

        ijkmeta_append_child_l(meta, stream_meta);
        stream_meta = NULL;
    }
}

int exSub_addOnly_subtitle(FFPlayer *ffp, const char *file_name)
{
    IJKEXSubtitle *sub = init_exSub_ifNeed(ffp);
    if (!sub) {
        return -1;
    }
    
    /* there is a length limit in avformat */
    if (strlen(file_name) + 1 > 1024) {
        av_log(sub, AV_LOG_ERROR, "subtitle path is too long:%s\n", __func__);
        return -2;
    }
    SDL_LockMutex(sub->mutex);
    //maybe already added.
    for (int i = 0; i < IJK_EX_SUBTITLE_STREAM_MAX - IJK_EX_SUBTITLE_STREAM_OFFSET; i++) {
        char* next = sub->pathArr[i];
        if (next && (0 == av_strncasecmp(next, file_name, 1024)))
            return 1;
    }
    SDL_UnlockMutex(sub->mutex);
    
    //if open failed not add to ex_sub_url.
    AVFormatContext* ic = avformat_alloc_context();
    int err = avformat_open_input(&ic, file_name, NULL, NULL);
    if (err < 0) {
        print_error(file_name, err);
        avformat_close_input(&ic);
        return -3;
    }
    
    SDL_LockMutex(sub->mutex);
    //recycle; release mem if the url array has been used
    int idx = sub->next_idx % (IJK_EX_SUBTITLE_STREAM_MAX - IJK_EX_SUBTITLE_STREAM_OFFSET);
    char* current = sub->pathArr[idx];
    if (current) {
        av_free(current);
    }
    sub->pathArr[idx] = av_strdup(file_name);
    sub->next_idx++;
    ijkmeta_set_ex_subtitle_context_l(ffp->meta, ic, sub, 0);
    SDL_UnlockMutex(sub->mutex);
    avformat_close_input(&ic);
    return 0;
}

int exSub_add_active_subtitle(FFPlayer *ffp, const char *file_name)
{
    /* there is a length limit in avformat */
    if (strlen(file_name) + 1 > 1024) {
        av_log(ffp, AV_LOG_ERROR, "subtitle path is too long:%s\n", __func__);
        return -2;
    }
    
    IJKEXSubtitle *sub = init_exSub_ifNeed(ffp);
    if (!sub) {
        return -1;
    }
    
    SDL_LockMutex(sub->mutex);
    //maybe already added.
    for (int i = 0; i < IJK_EX_SUBTITLE_STREAM_MAX - IJK_EX_SUBTITLE_STREAM_OFFSET; i++) {
        char* next = sub->pathArr[i];
        if (next && (0 == av_strncasecmp(next, file_name, 1024)))
            return 1;
    }
    SDL_UnlockMutex(sub->mutex);
    
    //close previous sub stream.
    int64_t old_idx = ijkmeta_get_int64_l(ffp->meta, IJKM_KEY_TIMEDTEXT_STREAM, -1);
    if (old_idx != -1) {
        ffp_set_stream_selected(ffp, (int)old_idx, 0);
    }
    
    //recycle; release memory if the url array has been used
    int idx = sub->next_idx % (IJK_EX_SUBTITLE_STREAM_MAX - IJK_EX_SUBTITLE_STREAM_OFFSET);
    
    int r = exSub_open_filepath(sub, file_name, idx);
    if (r != 0) {
        av_log(NULL, AV_LOG_ERROR, "could not open ex subtitle:(%d)%s\n", r, file_name);
        return -5;
    }
    
    SDL_LockMutex(sub->mutex);
    char* current = sub->pathArr[idx];
    if (current) {
        av_free(current);
    }
    sub->pathArr[idx] = av_strdup(file_name);
    sub->next_idx++;
    ijkmeta_set_ex_subtitle_context_l(ffp->meta, sub->opaque->ic, sub, 1);
    SDL_UnlockMutex(sub->mutex);
    return 0;
}

int exSub_contain_streamIdx(IJKEXSubtitle *sub, int idx)
{
    if (!sub) {
        return -1;
    }
    
    SDL_LockMutex(sub->mutex);
    int arr_idx = convert_streamIdx(sub, idx);
    if (NULL == sub->pathArr[arr_idx]) {
        av_log(sub, AV_LOG_ERROR, "invalid stream index %d is NULL\n", idx);
        arr_idx = -1;
    }
    SDL_UnlockMutex(sub->mutex);
    return arr_idx;
}
