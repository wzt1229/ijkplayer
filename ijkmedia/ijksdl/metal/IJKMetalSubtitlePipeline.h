//
//  IJKMetalSubtitlePipeline.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/12/23.
//

@import MetalKit;

NS_ASSUME_NONNULL_BEGIN

@interface IJKMetalSubtitlePipeline : NSObject

//current viewport,may not equal to drawable size.
@property (nonatomic, assign) CGSize viewport;
@property (nonatomic, assign) float scale;
@property (nonatomic, assign) float subtitleBottomMargin;
@property (nonatomic, assign) CGSize vertexRatio;

- (instancetype)initWithDevice:(id<MTLDevice>)device
              colorPixelFormat:(MTLPixelFormat)colorPixelFormat;

- (void)uploadTextureWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                          buffer:(CVPixelBufferRef)subPixelBuffer;

@end

NS_ASSUME_NONNULL_END
