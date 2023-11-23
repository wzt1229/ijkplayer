//
//  IJKMetalSubtitlePipeline.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/12/23.
//

@import MetalKit;

NS_ASSUME_NONNULL_BEGIN
NS_CLASS_AVAILABLE(10_13, 11_0)
@interface IJKMetalSubtitlePipeline : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>)device
              colorPixelFormat:(MTLPixelFormat)colorPixelFormat;
- (void)lock;
- (void)unlock;

- (BOOL)createRenderPipelineIfNeed;
- (void)uploadTextureWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                         texture:(id)subTexture
                            rect:(CGRect)subRect;

@end

NS_ASSUME_NONNULL_END
