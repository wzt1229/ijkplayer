//
//  ff_subtitle_ex.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/5/16.
//

#ifndef ff_subtitle_ex_h
#define ff_subtitle_ex_h

#include <stdio.h>

typedef struct FFSubtitle FFSubtitle;
typedef struct IJKEXSubtitle IJKEXSubtitle;
typedef struct IjkMediaMeta IjkMediaMeta;
typedef struct FrameQueue FrameQueue;
typedef struct PacketQueue PacketQueue;
typedef struct AVCodecContext AVCodecContext;
typedef struct AVStream AVStream;
typedef struct FFSubtitleBuffer FFSubtitleBuffer;
typedef struct SDL_TextureOverlay SDL_TextureOverlay;
typedef struct SDL_GPU SDL_GPU;

int exSub_create(IJKEXSubtitle **subp, FrameQueue * frameq, PacketQueue * pktq, int vw, int vh);
void exSub_reset_video_size(IJKEXSubtitle *sub, int vw, int vh);
int exSub_check_file_added(const char *file_name, IJKEXSubtitle *sub);
int exSub_addOnly_subtitle(IJKEXSubtitle *sub, const char *file_name, IjkMediaMeta *meta);
int exSub_add_active_subtitle(IJKEXSubtitle *sub, const char *file_name, IjkMediaMeta *meta);
int exSub_open_file_idx(IJKEXSubtitle *sub, int idx, int vw, int vh);
int exSub_close_current(IJKEXSubtitle *sub);
void exSub_subtitle_destroy(IJKEXSubtitle **sub);

//when return -1 means has not opened;
int exSub_get_opened_stream_idx(IJKEXSubtitle *sub);
//when return zero means succ;
int exSub_seek_to(IJKEXSubtitle *sub, float sec);
int exSub_contain_streamIdx(IJKEXSubtitle *sub, int idx);
AVCodecContext * exSub_get_avctx(IJKEXSubtitle *sub);
int exSub_get_serial(IJKEXSubtitle *sub);
AVStream *exSub_get_stream(IJKEXSubtitle *sub);
int exSub_blend_frame(IJKEXSubtitle *sub, float pts, FFSubtitleBuffer **buffer);
int exSub_upload_frame(IJKEXSubtitle *sub, float pts, SDL_GPU *gpu, SDL_TextureOverlay **overlay);
void exSub_update_margin(IJKEXSubtitle *sub, int t, int b, int l, int r);

#endif /* ff_subtitle_ex_h */
