//
//  ijksdl_gpu_opengl_fbo_macos.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/4/15.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol IJKSDLSubtitleTextureWrapper;
@interface IJKSDLOpenGLFBO : NSObject

@property(nonatomic, readonly) id<IJKSDLSubtitleTextureWrapper> texture;

- (instancetype)initWithSize:(CGSize)size;
- (BOOL)canReuse:(CGSize)size;
- (CGSize)size;
- (void)bind;

@end

NS_ASSUME_NONNULL_END
