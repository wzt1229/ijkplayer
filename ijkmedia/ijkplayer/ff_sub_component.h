//
//  ff_sub_component.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/5/20.
//

#ifndef ff_sub_component_h
#define ff_sub_component_h

#include <stdio.h>

typedef void (*subComponent_retry_callback)(void *opaque);

typedef struct FFSubComponent FFSubComponent;
typedef struct AVStream AVStream;
typedef struct AVCodecContext AVCodecContext;
typedef struct PacketQueue PacketQueue;
typedef struct FrameQueue FrameQueue;
typedef struct AVFormatContext AVFormatContext;
typedef struct IJKSDLSubtitlePreference IJKSDLSubtitlePreference;
typedef struct FFSubtitleBufferPacket FFSubtitleBufferPacket;

//when hasn't ic, not support seek;
int subComponent_open(FFSubComponent **cp, int stream_index, AVFormatContext* ic, AVCodecContext *avctx, PacketQueue* packetq, FrameQueue* frameq, subComponent_retry_callback callback, void *opaque, int vw, int vh);
int subComponent_close(FFSubComponent **cp);
int subComponent_get_stream(FFSubComponent *com);
int subComponent_seek_to(FFSubComponent *com, int sec);
AVCodecContext * subComponent_get_avctx(FFSubComponent *com);
int subComponent_get_serial(FFSubComponent *com);
int subComponent_upload_buffer(FFSubComponent *com, float pts, FFSubtitleBufferPacket *buffer_array);
void subComponent_update_preference(FFSubComponent *com, IJKSDLSubtitlePreference* sp);
int subComponent_eof_and_pkt_empty(FFSubComponent *com);

#endif /* ff_sub_component_h */
