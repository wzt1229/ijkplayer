//
//  IJKMetalNV12Pipeline.m
//  FFmpegTutorial-macOS
//
//  Created by qianlongxu on 2022/11/23.
//  Copyright © 2022 Matt Reach's Awesome FFmpeg Tutotial. All rights reserved.
//

#import "IJKMetalNV12Pipeline.h"

@interface IJKMetalNV12Pipeline ()

@property (nonatomic, strong) id<MTLBuffer> convertMatrix;

@end

@implementation IJKMetalNV12Pipeline

+ (NSString *)fragmentFuctionName
{
    return @"nv12FragmentShader";
}

- (void)doUploadTextureWithEncoder:(id<MTLArgumentEncoder>)encoder
                            buffer:(CVPixelBufferRef)pixelBuffer
                      textureCache:(CVMetalTextureCacheRef)textureCache
{
    id<MTLTexture> textureY = nil;
    id<MTLTexture> textureUV = nil;
    
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    // textureY 设置
    {
        size_t width  = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
        size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
        MTLPixelFormat pixelFormat = MTLPixelFormatR8Unorm; // 这里的颜色格式不是RGBA

        CVMetalTextureRef texture = NULL; // CoreVideo的Metal纹理
        CVReturn status = CVMetalTextureCacheCreateTextureFromImage(NULL, textureCache, pixelBuffer, NULL, pixelFormat, width, height, 0, &texture);
        if (status == kCVReturnSuccess) {
            textureY = CVMetalTextureGetTexture(texture); // 转成Metal用的纹理
            CFRelease(texture);
        }
    }
    
    // textureUV 设置
    {
        size_t width  = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1);
        size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);
        MTLPixelFormat pixelFormat = MTLPixelFormatRG8Unorm; // 2-8bit的格式
        
        CVMetalTextureRef texture = NULL; // CoreVideo的Metal纹理
        CVReturn status = CVMetalTextureCacheCreateTextureFromImage(NULL, textureCache, pixelBuffer, NULL, pixelFormat, width, height, 1, &texture);
        if (status == kCVReturnSuccess) {
            textureUV = CVMetalTextureGetTexture(texture); // 转成Metal用的纹理
            CFRelease(texture);
        }
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    if (textureY != nil && textureUV != nil) {
        [encoder setTexture:textureY
                    atIndex:IJKFragmentTextureIndexTextureY]; // 设置纹理
        [encoder setTexture:textureUV
                    atIndex:IJKFragmentTextureIndexTextureU]; // 设置纹理
    }
    
    if (!self.convertMatrix) {
        OSType type = CVPixelBufferGetPixelFormatType(pixelBuffer);
        CFTypeRef color_attachments = CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
        if (color_attachments && CFStringCompare(color_attachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == kCFCompareEqualTo) {
            self.convertMatrixType = type ==  kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ? IJKYUVToRGBBT601VideoRangeMatrix : IJKYUVToRGBBT601FullRangeMatrix;
        } else {
            self.convertMatrixType = type ==  kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ? IJKYUVToRGBBT709VideoRangeMatrix : IJKYUVToRGBBT709FullRangeMatrix;
        }
    }
}

@end
