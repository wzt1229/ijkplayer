//
//  IJKMetalBasePipeline.h
//  FFmpegTutorial-macOS
//
//  Created by qianlongxu on 2022/11/23.
//  Copyright © 2022 Matt Reach's Awesome FFmpeg Tutotial. All rights reserved.
//

// IJKMetalBasePipeline is an abstract class, subclass must be override many methods.

@import MetalKit;
#import "IJKMetalShaderTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface IJKMetalBasePipeline : NSObject

+ (nullable id <MTLBuffer>)createMatrix:(id<MTLDevice>)device
                             matrixType:(IJKYUVToRGBMatrixType)matrixType
                             videoRange:(BOOL)videoRange;

//subclass override!
+ (NSString *)fragmentFuctionName;

- (void)updateVertexRatio:(CGSize)ratio
                   device:(id<MTLDevice>)device;

- (void)updateMVP:(id<MTLBuffer>)mvp;

//subclass override!
- (void)uploadTextureWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                          buffer:(CVPixelBufferRef)pixelBuffer
                    textureCache:(CVMetalTextureCacheRef)textureCache
                          device:(id<MTLDevice>)device
                colorPixelFormat:(MTLPixelFormat)colorPixelFormat;

@end

NS_ASSUME_NONNULL_END
