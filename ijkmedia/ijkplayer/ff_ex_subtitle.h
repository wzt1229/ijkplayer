//
//  ff_ex_subtitle.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/5/16.
//

#ifndef ff_ex_subtitle_h
#define ff_ex_subtitle_h

#include <stdio.h>

typedef struct FFPlayer FFPlayer;
typedef struct IJKEXSubtitle IJKEXSubtitle;

int exSub_addOnly_subtitle(FFPlayer *ffp, const char *file_name);
int exSub_add_active_subtitle(FFPlayer *ffp, const char *file_name);
int exSub_open_file_idx(IJKEXSubtitle *sub, int idx);
int exSub_close_current(IJKEXSubtitle *sub);
void exSub_subtitle_destroy(IJKEXSubtitle **sub);

//return value means dropped uploaded frame count rather than dropped frame count;
int exSub_drop_frames_lessThan_pts(IJKEXSubtitle *sub, float pts);
//return zero means out has content
int exSub_fetch_frame(IJKEXSubtitle *sub, float pts, char **text);

void exSub_set_delay(IJKEXSubtitle *sub, float delay, float cp);
float exSub_get_delay(IJKEXSubtitle *sub);

//when return -1 means has not opened;
int exSub_get_opened_stream_idx(IJKEXSubtitle *sub);
//when return zero means succ;
int exSub_seek_to(IJKEXSubtitle *sub, float sec);
int exSub_frame_queue_size(IJKEXSubtitle *sub);
int exSub_has_enough_packets(IJKEXSubtitle *sub, int min_frames);
int exSub_contain_streamIdx(IJKEXSubtitle *sub, int idx);

#endif /* ff_ex_subtitle_h */
