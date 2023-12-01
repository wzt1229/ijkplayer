//
//  ff_subtitle_ex.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/5/16.
//
// after activate not need seek, because video stream will be seeked.

#include "ff_subtitle_ex.h"
#include "libavformat/avformat.h"
#include "ff_ffplay_def.h"
#include "ff_frame_queue.h"
#include "ff_packet_list.h"
#include "ff_ass_parser.h"
#include "ff_sub_component.h"

#define IJK_EX_SUBTITLE_STREAM_MAX_COUNT    100
#define IJK_EX_SUBTITLE_STREAM_MIN_OFFSET   1000
#define IJK_EX_SUBTITLE_STREAM_MAX_OFFSET   (IJK_EX_SUBTITLE_STREAM_MIN_OFFSET + IJK_EX_SUBTITLE_STREAM_MAX_COUNT)

static const char * ff_sub_backup_charenc[] = {"GBK","BIG5-2003"};//没有使用GB18030，否则会把BIG5编码显示成乱码
static const int ff_sub_backup_charenc_len = 2;

typedef struct IJKEXSubtitle {
    SDL_mutex* mutex;
    FFSubComponent* component;
    AVFormatContext* ic;
    int st_offset_idx;//相对于 IJK_EX_SUBTITLE_STREAM_MIN_OFFSET 的
    FrameQueue * frameq;
    PacketQueue * pktq;
    char* pathArr[IJK_EX_SUBTITLE_STREAM_MAX_COUNT];
    int next_idx;
    //当前使用的哪个备选字符
    int backup_charenc_idx;
}IJKEXSubtitle;

int exSub_create(IJKEXSubtitle **subp, FrameQueue * frameq, PacketQueue * pktq)
{
    if (!subp) {
        return -1;
    }
    
    IJKEXSubtitle *sub = av_malloc(sizeof(IJKEXSubtitle));
    if (!sub) {
        return -2;
    }
    bzero(sub, sizeof(IJKEXSubtitle));
    
    sub->mutex = SDL_CreateMutex();
    if (NULL == sub->mutex) {
        av_free(sub);
       return -2;
    }
    sub->frameq = frameq;
    sub->pktq = pktq;
    sub->st_offset_idx = -1;
    *subp = sub;
    return 0;
}

int exSub_get_opened_stream_idx(IJKEXSubtitle *sub)
{
    if (sub && sub->component) {
        return sub->st_offset_idx;
    }
    return -1;
}

int exSub_seek_to(IJKEXSubtitle *sub, float sec)
{
    if (!sub || !sub->component) {
        return -1;
    }
    return subComponent_seek_to(sub->component, sec);
}

static int convert_idx_from_stream(int idx)
{
    int arr_idx = -1;
    if (idx >= IJK_EX_SUBTITLE_STREAM_MIN_OFFSET && idx < IJK_EX_SUBTITLE_STREAM_MAX_OFFSET) {
        arr_idx = (idx - IJK_EX_SUBTITLE_STREAM_MIN_OFFSET) % IJK_EX_SUBTITLE_STREAM_MAX_COUNT;
    }
    return arr_idx;
}

static void retry_callback(void *opaque)
{
    IJKEXSubtitle *sub = opaque;
    if (!sub) {
        return;
    }
    
    SDL_LockMutex(sub->mutex);
    
    if (sub->backup_charenc_idx >= ff_sub_backup_charenc_len) {
        goto fail;
    }
    
    int stream_idx = subComponent_get_stream(sub->component);
    if (stream_idx == -1) {
        goto fail;
    }

    subComponent_close(&sub->component);
    //reopen
    if (!sub->ic) {
        goto fail;
    }
    
    AVCodecContext* avctx = avcodec_alloc_context3(NULL);
    if (!avctx) {
        goto fail;
    }
    
    if (stream_idx >= sub->ic->nb_streams) {
        goto fail;
    }
    
    AVStream *sub_st = sub->ic->streams[stream_idx];
    if (avcodec_parameters_to_context(avctx, sub_st->codecpar) < 0) {
        goto fail;
    }
    
    //so important,ohterwise,sub frame has not pts.
    avctx->pkt_timebase = sub_st->time_base;
    const char *enc = ff_sub_backup_charenc[sub->backup_charenc_idx];
    avctx->sub_charenc = av_strdup(enc);
    avctx->sub_charenc_mode = FF_SUB_CHARENC_MODE_AUTOMATIC;
    sub->backup_charenc_idx++;
    
    const AVCodec* codec = avcodec_find_decoder(sub_st->codecpar->codec_id);
    if (!codec) {
        goto fail;
    }
    
    if (avcodec_open2(avctx, codec, NULL) < 0) {
        goto fail;
    }

    if (subComponent_open(&sub->component, stream_idx, sub->ic, avctx, sub->pktq, sub->frameq, &retry_callback, (void *)sub) != 0) {
        goto fail;
    }
    subComponent_seek_to(sub->component, 0);
fail:
    SDL_UnlockMutex(sub->mutex);
    return;
}

static int exSub_open_filepath(IJKEXSubtitle *sub, const char *file_name, int idx)
{
    if (!sub) {
        return -1;
    }

    if (!file_name || strlen(file_name) == 0) {
        return -2;
    }
        
    int ret = 0;
    AVFormatContext* ic = NULL;
    AVCodecContext* avctx = NULL;
    
    if (avformat_open_input(&ic, file_name, NULL, NULL) < 0) {
        ret = -1;
        goto fail;
    }
    
    if (avformat_find_stream_info(ic, NULL) < 0) {
        ret = -2;
        goto fail;
    }

    if (ic) {
        av_log(NULL, AV_LOG_DEBUG, "ex subtitle demuxer:%s\n",ic->iformat->name);
    }
    AVStream *sub_st = NULL;
    int stream_id = -1;
    //字幕流的索引
    for (size_t i = 0; i < ic->nb_streams; ++i) {
        AVStream *stream = ic->streams[i];
        if (stream->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
            sub_st = stream;
            stream_id = (int)i;
            stream->discard = AVDISCARD_DEFAULT;
        } else {
            stream->discard = AVDISCARD_ALL;
        }
    }
    
    if (!sub_st) {
        ret = -3;
        av_log(NULL, AV_LOG_ERROR, "none subtitle stream in %s\n", file_name);
        goto fail;
    }
    
    const AVCodec* codec = avcodec_find_decoder(sub_st->codecpar->codec_id);
    if (!codec) {
        av_log(NULL, AV_LOG_WARNING, "could find codec:%s for %s\n",
                file_name, avcodec_get_name(sub_st->codecpar->codec_id));
        ret = -4;
        goto fail;
    }
    
    avctx = avcodec_alloc_context3(NULL);
    if (!avctx) {
        ret = -5;
        goto fail;
    }

    if (avcodec_parameters_to_context(avctx, sub_st->codecpar) < 0) {
        ret = -6;
        goto fail;
    }
    //so important,ohterwise,sub frame has not pts.
    avctx->pkt_timebase = sub_st->time_base;
    
    if (avcodec_open2(avctx, codec, NULL) < 0) {
        ret = -7;
        goto fail;
    }
    
    if (subComponent_open(&sub->component, stream_id, ic, avctx, sub->pktq, sub->frameq, &retry_callback, (void *)sub) != 0) {
        ret = -8;
        goto fail;
    }
    
    //reset to 0
    sub->backup_charenc_idx = 0;
    sub->ic = ic;
    sub->st_offset_idx = idx;
    return 0;
fail:
    if (ret < 0) {
        if (ic)
            avformat_close_input(&ic);
        if (avctx)
            avcodec_free_context(&avctx);
    }
    return ret;
}

int exSub_open_file_idx(IJKEXSubtitle *sub, int idx)
{
    if (!sub) {
        return -1;
    }
    
    if (idx == -1) {
        return -2;
    }
    
    int arr_idx = convert_idx_from_stream(idx);
    
    if (idx == -1) {
        return -3;
    }
    
    const char *file_name = sub->pathArr[arr_idx];
    
    if (!file_name) {
        return -4;
    }
    
    if (exSub_open_filepath(sub, file_name, idx) != 0) {
        return -5;
    }
    
    return 0;
}

int exSub_close_current(IJKEXSubtitle *sub)
{
    if(!sub) {
        return -1;
    }
    SDL_LockMutex(sub->mutex);
    int r = subComponent_close(&sub->component);
    if (sub->ic)
        avformat_close_input(&sub->ic);
    SDL_UnlockMutex(sub->mutex);
    return r;
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
    for (int i = 0; i < sub->next_idx; i++) {
        if (sub->pathArr[i]) {
            av_free(sub->pathArr[i]);
        }
    }
    SDL_UnlockMutex(sub->mutex);
    
    SDL_DestroyMutex(sub->mutex);
    
    av_freep(subp);
}

static void ijkmeta_set_ex_subtitle_context_l(IjkMediaMeta *meta, struct AVFormatContext *ic, IJKEXSubtitle *sub, int actived_stream)
{
    if (!meta || !sub)
        return;

    if (actived_stream != -1) {
        ijkmeta_set_int64_l(meta, IJKM_KEY_TIMEDTEXT_STREAM, actived_stream);
    }
    
    IjkMediaMeta *stream_meta = ijkmeta_create();
    if (!stream_meta)
        return;
    int idx = sub->next_idx - 1;
    char *url = sub->pathArr[idx];
    int stream_idx = idx + IJK_EX_SUBTITLE_STREAM_MIN_OFFSET;
    ijkmeta_set_int64_l(stream_meta, IJKM_KEY_STREAM_IDX, stream_idx);
    ijkmeta_set_string_l(stream_meta, IJKM_KEY_TYPE, IJKM_VAL_TYPE__TIMEDTEXT);
    ijkmeta_set_string_l(stream_meta, IJKM_KEY_EX_SUBTITLE_URL, url);
    char title[64] = {0};
    snprintf(title, 64, "Track%d", sub->next_idx);
    ijkmeta_set_string_l(stream_meta, IJKM_KEY_TITLE, title);
    
    ijkmeta_append_child_l(meta, stream_meta);
    
    if (!ic) {
        return;
    }
    for (int i = 0; i < ic->nb_streams; i++) {
        AVStream *st = ic->streams[i];
        if (st && st->codecpar) {
            AVCodecParameters *codecpar = st->codecpar;
            if (codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
                const char *codec_name = avcodec_get_name(codecpar->codec_id);
                if (codec_name)
                    ijkmeta_set_string_l(stream_meta, IJKM_KEY_CODEC_NAME, codec_name);

                AVDictionaryEntry *lang = av_dict_get(st->metadata, "language", NULL, 0);
                if (lang && lang->value)
                    ijkmeta_set_string_l(stream_meta, IJKM_KEY_LANGUAGE, lang->value);

                AVDictionaryEntry *t = av_dict_get(st->metadata, "title", NULL, 0);
                if (t && t->value) {
                    ijkmeta_set_string_l(stream_meta, IJKM_KEY_TITLE, t->value);
                }
                break;
            }
        }
    }
}

int exSub_addOnly_subtitle(IJKEXSubtitle *sub, const char *file_name, IjkMediaMeta *meta)
{
    if (!sub) {
        return -1;
    }

    if (exSub_check_file_added(file_name, sub)) {
        return 1;
    }
    
    if (sub->next_idx < IJK_EX_SUBTITLE_STREAM_MAX_COUNT) {
        SDL_LockMutex(sub->mutex);
        int idx = sub->next_idx;
        sub->pathArr[idx] = av_strdup(file_name);
        sub->next_idx++;
        ijkmeta_set_ex_subtitle_context_l(meta, NULL, sub, -1);
        SDL_UnlockMutex(sub->mutex);
    } else {
        return -2;
    }
    return 0;
}

int exSub_check_file_added(const char *file_name, IJKEXSubtitle *sub)
{
    SDL_LockMutex(sub->mutex);
    bool already_added = 0;
    //maybe already added.
    for (int i = 0; i < sub->next_idx; i++) {
        char* next = sub->pathArr[i];
        if (next && (0 == av_strcasecmp(next, file_name))) {
            already_added = 1;
            break;
        }
    }
    SDL_UnlockMutex(sub->mutex);
    return already_added;
}

int exSub_add_active_subtitle(IJKEXSubtitle *sub, const char *file_name, IjkMediaMeta *meta)
{
    if (!sub) {
        return -1;
    }
 
    if (exSub_check_file_added(file_name, sub)) {
        return 1;
    }
    
    int idx = sub->next_idx;
    
    if (idx < IJK_EX_SUBTITLE_STREAM_MAX_COUNT) {
        SDL_LockMutex(sub->mutex);
        int r = exSub_open_filepath(sub, file_name, idx + IJK_EX_SUBTITLE_STREAM_MIN_OFFSET);
        if (r != 0) {
            av_log(NULL, AV_LOG_ERROR, "could not open ex subtitle:(%d)%s\n", r, file_name);
            SDL_UnlockMutex(sub->mutex);
            return -2;
        }
        sub->pathArr[idx] = av_strdup(file_name);
        sub->next_idx++;
        ijkmeta_set_ex_subtitle_context_l(meta, sub->ic, sub, idx + IJK_EX_SUBTITLE_STREAM_MIN_OFFSET);
        SDL_UnlockMutex(sub->mutex);
        return 0;
    } else {
        return -3;
    }
}

int exSub_contain_streamIdx(IJKEXSubtitle *sub, int idx)
{
    if (!sub) {
        return 0;
    }
    
    SDL_LockMutex(sub->mutex);
    int arr_idx = convert_idx_from_stream(idx);
    if (arr_idx < 0 || arr_idx >= sub->next_idx || NULL == sub->pathArr[arr_idx]) {
        av_log(NULL, AV_LOG_ERROR, "invalid stream index %d is NULL\n", idx);
        arr_idx = -1;
    }
    SDL_UnlockMutex(sub->mutex);
    return arr_idx != -1;
}

AVCodecContext * exSub_get_avctx(IJKEXSubtitle *sub)
{
    return sub ? subComponent_get_avctx(sub->component) : NULL;
}

int exSub_get_serial(IJKEXSubtitle *sub)
{
    return sub ? subComponent_get_serial(sub->component) : -1;
}
