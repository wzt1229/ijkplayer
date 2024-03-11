//
//  ff_subtitle.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/5/23.
//

#ifndef ff_subtitle_h
#define ff_subtitle_h

#include "ff_subtitle_def.h"

typedef struct FFSubtitle FFSubtitle;
typedef struct AVSubtitleRect AVSubtitleRect;
typedef struct AVStream AVStream;
typedef struct AVCodecContext AVCodecContext;
typedef struct AVPacket AVPacket;
typedef struct IjkMediaMeta IjkMediaMeta;
typedef struct AVFormatContext AVFormatContext;

// lifecycle
int ff_sub_init(FFSubtitle **subp);
void ff_sub_abort(FFSubtitle *sub);
int ff_sub_destroy(FFSubtitle **subp);
//
int ff_inSub_open_component(FFSubtitle *sub, int stream_index, AVStream* st, AVCodecContext *avctx);
int ff_sub_close_current(FFSubtitle *sub);
//less than zero means err, equal zero means keep, greater than zero means need show
int ff_sub_fetch_frame(FFSubtitle *sub, float pts, FFSubtitleBuffer ** buffer);

int ff_sub_frame_queue_size(FFSubtitle *sub);

int ff_sub_has_enough_packets(FFSubtitle *sub, int min_frames);

int ff_sub_put_null_packet(FFSubtitle *sub, AVPacket *pkt, int st_idx);

int ff_sub_put_packet(FFSubtitle *sub, AVPacket *pkt);

int ff_sub_get_opened_stream_idx(FFSubtitle *sub);
void ff_sub_seek_to(FFSubtitle *sub, float delay, float v_pts);
int ff_sub_set_delay(FFSubtitle *sub, float delay, float cp);
float ff_sub_get_delay(FFSubtitle *sub);
enum AVCodecID ff_sub_get_codec_id(FFSubtitle *sub);

// return 0 means not internal,but not means is external;
int ff_sub_isInternal_stream(FFSubtitle *sub, int stream);
// return 0 means not external,but not means is internal;
int ff_sub_isExternal_stream(FFSubtitle *sub, int stream);
//0 means has no sub;1 means internal sub;2 means external sub;
int ff_sub_current_stream_type(FFSubtitle *sub, int *outIdx);

//when video steam ic ready,call me.
void ff_sub_stream_ic_ready(FFSubtitle *sub, AVFormatContext* ic, int video_w, int video_h);
//use ass renderer
void ff_sub_use_libass(FFSubtitle *sub, int use, AVStream* st, uint8_t *subtitle_header, int subtitle_header_size);

int ff_inSub_packet_queue_flush(FFSubtitle *sub);
//for external subtitle.
int ff_exSub_addOnly_subtitle(FFSubtitle *sub, const char *file_name, IjkMediaMeta *meta);
int ff_exSub_add_active_subtitle(FFSubtitle *sub, const char *file_name, IjkMediaMeta *meta);
int ff_exSub_open_stream(FFSubtitle *sub, int stream);
int ff_exSub_check_file_added(const char *file_name, FFSubtitle *ffSub);
#endif /* ff_subtitle_h */
