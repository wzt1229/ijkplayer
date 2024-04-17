//
//  IJKMetalSubtitlePipeline.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/12/23.
//

@import MetalKit;

NS_ASSUME_NONNULL_BEGIN

typedef enum : NSUInteger {
    IJKMetalSubtitleOutFormatDIRECT,
    IJKMetalSubtitleOutFormatSWAP_RB
} IJKMetalSubtitleOutFormat;

NS_CLASS_AVAILABLE(10_13, 11_0)
@interface IJKMetalSubtitlePipeline : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>)device
                     outFormat:(IJKMetalSubtitleOutFormat)outFormat;
- (void)lock;
- (void)unlock;

- (BOOL)createRenderPipelineIfNeed;
- (void)updateSubtitleVertexIfNeed:(CGRect)rect;
- (void)drawTexture:(id)subTexture encoder:(id<MTLRenderCommandEncoder>)encoder;

@end

NS_ASSUME_NONNULL_END
