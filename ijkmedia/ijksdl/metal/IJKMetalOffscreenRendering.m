//
//  IJKMetalOffscreenRendering.m
//  FFmpegTutorial-macOS
//
//  Created by Reach Matt on 2022/12/2.
//  Copyright © 2022 Matt Reach's Awesome FFmpeg Tutotial. All rights reserved.
//


#import "IJKMetalOffscreenRendering.h"
#import "IJKMetalFBO.h"
@import CoreImage;
@import Metal;

@interface IJKMetalOffscreenRendering ()
{
    IJKMetalFBO* _fbo;
}
@end

@implementation IJKMetalOffscreenRendering

- (CGImageRef)_snapshot
{
    CVPixelBufferRef pixelBuffer = CVPixelBufferRetain([_fbo pixelBuffer]);
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    
    static CIContext *context = nil;
    if (!context) {
        context = [CIContext contextWithOptions:NULL];
    }
    CGRect rect = CGRectMake(0,0,
                             CVPixelBufferGetWidth(pixelBuffer),
                             CVPixelBufferGetHeight(pixelBuffer));
    CGImageRef imageRef = [context createCGImage:ciImage fromRect:rect];
    CVPixelBufferRelease(pixelBuffer);
    return imageRef ? (CGImageRef)CFAutorelease(imageRef) : NULL;
}

- (CGImageRef)snapshot:(CGSize)targetSize
                device:(id <MTLDevice>)device
         commandBuffer:(id<MTLCommandBuffer>)commandBuffer
       doUploadPicture:(void(^)(id<MTLRenderCommandEncoder>))block
{
    if (![_fbo canReuse:targetSize]) {
        _fbo = [[IJKMetalFBO alloc] init:device size:targetSize];
    }
    
    id<MTLRenderCommandEncoder> renderEncoder = [_fbo createRenderEncoder:commandBuffer];
    
    if (!renderEncoder) {
        return NULL;
    }
    
    if (block) {
        block(renderEncoder);
    }
    [renderEncoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
    return [self _snapshot];
}

@end
