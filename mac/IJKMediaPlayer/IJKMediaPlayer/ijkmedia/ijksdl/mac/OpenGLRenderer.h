 /*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 The OpenGLRenderer class creates and draws objects.
  Most of the code is OS independent.
 */
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

typedef enum RcColorFormat {
    FMT_RGBA,
    FMT_YUV420P,
    FMT_NV12,
    FMT_VTB
}RcColorFormat;

typedef struct RcFrame {
    uint8_t *data[3];
    int width;
    int height;
    int linesize[3];
    int planes;
    RcColorFormat format;
} RcFrame;

@interface OpenGLRenderer : NSObject

- (void) resizeWithWidth:(GLuint)width AndHeight:(GLuint)height;
- (void) render;
- (void) setImage:(RcFrame*)overlay;

@end
