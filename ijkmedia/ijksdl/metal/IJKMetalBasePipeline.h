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
NS_CLASS_AVAILABLE(10_13, 11_0)
@interface IJKMetalBasePipeline : NSObject

@property (nonatomic, assign) IJKYUVToRGBMatrixType convertMatrixType;
//current viewport,may not equal to drawable size.
@property (nonatomic, assign) CGSize viewport;
@property (nonatomic, assign) float rotateDegrees;
@property (nonatomic, assign) int rotateType;//x:1,y:2,z:3
@property (nonatomic, assign) float autoZRotateDegrees;
@property (nonatomic, assign) CGSize vertexRatio;
@property (nonatomic, assign) CGSize textureCrop;

//subclass override!
+ (NSString *)fragmentFuctionName;

- (instancetype)initWithDevice:(id<MTLDevice>)device
              colorPixelFormat:(MTLPixelFormat)colorPixelFormat;

- (void)lock;
- (void)unlock;

- (void)updateColorAdjustment:(vector_float4)c;

//subclass override!
- (NSArray<id<MTLTexture>>*)doGenerateTexture:(CVPixelBufferRef)pixelBuffer
                                 textureCache:(CVMetalTextureCacheRef)textureCache;

- (void)uploadTextureWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                          buffer:(CVPixelBufferRef)pixelBuffer
                    textureCache:(CVMetalTextureCacheRef)textureCache;
@end

NS_ASSUME_NONNULL_END
