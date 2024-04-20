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
typedef struct SDL_TextureOverlay SDL_TextureOverlay;
typedef struct SDL_GPU SDL_GPU;

// lifecycle
int ff_sub_init(FFSubtitle **subp);
void ff_sub_abort(FFSubtitle *sub);
//call in voout thread,because internal fbo and texture were created in vout thread!
int ff_sub_destroy(FFSubtitle **subp);
//
int ff_inSub_open_component(FFSubtitle *sub, int stream_index, AVStream* st, AVCodecContext *avctx);
int ff_sub_close_current(FFSubtitle *sub);
void ff_sub_get_texture(FFSubtitle *sub, float pts, SDL_GPU *gpu, SDL_TextureOverlay **texture);
int ff_sub_drop_old_frames(FFSubtitle *sub);
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
//update ass renderer margin
void ff_sub_update_margin_ass(FFSubtitle *sub, int t, int b, int l, int r);

int ff_sub_packet_queue_flush(FFSubtitle *sub);
//return 1 means need refresh display
int ff_update_sub_preference(FFSubtitle *sub, IJKSDLSubtitlePreference* sp);
//for external subtitle.
int ff_exSub_addOnly_subtitle(FFSubtitle *sub, const char *file_name, IjkMediaMeta *meta);
int ff_exSub_add_active_subtitle(FFSubtitle *sub, const char *file_name, IjkMediaMeta *meta);
int ff_exSub_open_stream(FFSubtitle *sub, int stream);
int ff_exSub_check_file_added(const char *file_name, FFSubtitle *ffSub);
#endif /* ff_subtitle_h */
