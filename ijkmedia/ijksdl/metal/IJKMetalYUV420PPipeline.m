//
//  IJKMetalYUV420PPipeline.m
//  FFmpegTutorial-macOS
//
//  Created by qianlongxu on 2022/11/24.
//  Copyright © 2022 Matt Reach's Awesome FFmpeg Tutotial. All rights reserved.
//

#import "IJKMetalYUV420PPipeline.h"

@implementation IJKMetalYUV420PPipeline

+ (NSString *)fragmentFuctionName
{
    return @"yuv420pFragmentShader";
}

- (void)doUploadTextureWithEncoder:(id<MTLArgumentEncoder>)encoder
                            buffer:(CVPixelBufferRef)pixelBuffer
                      textureCache:(CVMetalTextureCacheRef)textureCache
{
    OSType type = CVPixelBufferGetPixelFormatType(pixelBuffer);
    NSAssert((type == kCVPixelFormatType_420YpCbCr8PlanarFullRange || type ==  kCVPixelFormatType_420YpCbCr8Planar), @"wrong pixel format type, must be yuv420p.");
    
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    for (int i = 0; i < CVPixelBufferGetPlaneCount(pixelBuffer); i++) {
        size_t width  = CVPixelBufferGetWidthOfPlane(pixelBuffer, i);
        size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, i);
        
        CVMetalTextureRef textureRef = NULL; // CoreVideo的Metal纹理
        CVReturn status = CVMetalTextureCacheCreateTextureFromImage(NULL, textureCache, pixelBuffer, NULL, MTLPixelFormatR8Unorm, width, height, i, &textureRef);
        if (status == kCVReturnSuccess) {
            id<MTLTexture> texture = CVMetalTextureGetTexture(textureRef); // 转成Metal用的纹理
            CFRelease(textureRef);
            if (texture != nil) {
                [encoder setTexture:texture
                            atIndex:IJKFragmentTextureIndexTextureY + i]; // 设置纹理
            }
        }
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    CFTypeRef color_attachments = CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
    if (color_attachments && CFStringCompare(color_attachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == kCFCompareEqualTo) {
        self.convertMatrixType = type == kCVPixelFormatType_420YpCbCr8Planar ? IJKYUVToRGBBT601VideoRangeMatrix : IJKYUVToRGBBT601FullRangeMatrix;
    } else {
        self.convertMatrixType = IJKYUVToRGBBT709FullRangeMatrix;
    }
}

@end
