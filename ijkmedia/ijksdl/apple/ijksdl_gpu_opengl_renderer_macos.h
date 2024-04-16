//
//  ijksdl_gpu_opengl_renderer_macos.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/4/15.
//

#import <Foundation/Foundation.h>

@class IJKSDLOpenGLFBO;
@protocol IJKSDLSubtitleTextureWrapper;

@interface IJKSDLOpenGLSubRenderer : NSObject

- (void)setupOpenGLProgramIfNeed;
- (void)clean;
- (void)bindFBO:(IJKSDLOpenGLFBO *)fbo;
- (void)updateSubtitleVertexIfNeed:(CGRect)rect;
- (void)renderTexture:(id<IJKSDLSubtitleTextureWrapper>)subTexture;

@end
