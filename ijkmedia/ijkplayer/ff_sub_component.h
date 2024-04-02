//
//  ff_sub_component.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/5/20.
//

#ifndef ff_sub_component_h
#define ff_sub_component_h

#include <stdio.h>

typedef struct FFSubComponent FFSubComponent;
typedef struct AVStream AVStream;
typedef struct AVCodecContext AVCodecContext;
typedef struct PacketQueue PacketQueue;
typedef struct FrameQueue FrameQueue;
typedef struct AVFormatContext AVFormatContext;
typedef void (*subComponent_retry_callback)(void *opaque);
typedef struct FFSubtitleBuffer FFSubtitleBuffer;
typedef struct SDL_TextureOverlay SDL_TextureOverlay;
typedef struct SDL_GPU SDL_GPU;

//when hasn't ic, not support seek;
int subComponent_open(FFSubComponent **cp, int stream_index, AVFormatContext* ic, AVCodecContext *avctx, PacketQueue* packetq, FrameQueue* frameq, subComponent_retry_callback callback, void *opaque, int vw, int vh);
int subComponent_close(FFSubComponent **cp);
int subComponent_get_stream(FFSubComponent *com);
int subComponent_seek_to(FFSubComponent *com, int sec);
AVCodecContext * subComponent_get_avctx(FFSubComponent *com);
int subComponent_get_serial(FFSubComponent *com);
//buff need release
int subComponent_blend_frame(FFSubComponent *com, float pts, FFSubtitleBuffer **buffer);
int subComponent_upload_frame(FFSubComponent *com, float pts, SDL_GPU *gpu, SDL_TextureOverlay **overlay);
void subComponent_update_margin(FFSubComponent *com, int t, int b, int l, int r);
#endif /* ff_sub_component_h */
