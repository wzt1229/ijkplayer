//
//  ff_in_subtitle.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/5/20.
//

#ifndef ff_in_subtitle_h
#define ff_in_subtitle_h

#include <stdio.h>

typedef struct FFPlayer FFPlayer;
typedef struct FFINSubtitle FFINSubtitle;
typedef struct AVSubtitleRect AVSubtitleRect;
typedef struct AVStream AVStream;
typedef struct AVCodecContext AVCodecContext;
typedef struct AVPacket AVPacket;
typedef struct SDL_cond SDL_cond;

int inSub_create(FFINSubtitle **subp, int stream_index, AVStream * st, AVCodecContext *avctx, SDL_cond *empty_queue_cond);

int inSub_drop_frames_lessThan_pts(FFINSubtitle *sub, float pts);
int inSub_fetch_frame(FFINSubtitle *sub, float pts, char **text, AVSubtitleRect **bmp);
int inSub_flush_packet_queue(FFINSubtitle *sub);
int inSub_frame_queue_size(FFINSubtitle *sub);
int inSub_has_enough_packets(FFINSubtitle *sub, int min_frames);
int inSub_put_null_packet(FFINSubtitle *sub, AVPacket *pkt);
int inSub_put_packet(FFINSubtitle *sub, AVPacket *pkt);
int inSub_get_opened_stream_idx(FFINSubtitle *sub);
//0:ok; -1:not match -2:fail
int inSub_set_delay(FFINSubtitle *sub, float delay, float cp);
float inSub_get_delay(FFINSubtitle *sub);
int inSub_close_current(FFINSubtitle **subp);

#endif /* ff_in_subtitle_h */
