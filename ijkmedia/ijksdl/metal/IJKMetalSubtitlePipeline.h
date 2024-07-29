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

typedef enum : NSUInteger {
    IJKMetalSubtitleInFormatBRGA,
    IJKMetalSubtitleInFormatA8,
} IJKMetalSubtitleInFormat;

API_AVAILABLE(macos(10.13),ios(11.0),tvos(12.0))
@interface IJKMetalSubtitlePipeline : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>)device
                      inFormat:(IJKMetalSubtitleInFormat)inFormat
                     outFormat:(IJKMetalSubtitleOutFormat)outFormat;

- (BOOL)createRenderPipelineIfNeed;
- (void)updateSubtitleVertexIfNeed:(CGRect)rect;
- (void)drawTexture:(id)subTexture encoder:(id<MTLRenderCommandEncoder>)encoder;
- (void)drawTexture:(id)subTexture encoder:(id<MTLRenderCommandEncoder>)encoder colors:(void *)colors;

@end

NS_ASSUME_NONNULL_END
