//
//  IJKInternalRenderView.m
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2023/4/6.
//

#import "IJKInternalRenderView.h"
#if TARGET_OS_OSX
#import "IJKSDLGLView.h"
#endif
#import "IJKMetalView.h"

@implementation IJKInternalRenderView

#if TARGET_OS_OSX
+ (UIView<IJKVideoRenderingProtocol> *)createGLRenderView
{
#if TARGET_OS_IOS || TARGET_OS_TV
    CGRect rect = [[UIScreen mainScreen] bounds];
#else
    CGRect rect = [[[NSScreen screens] firstObject]frame];
#endif
    rect.origin = CGPointZero;
    return [[IJKSDLGLView alloc] initWithFrame:rect];
}
#endif

+ (UIView<IJKVideoRenderingProtocol> *)createMetalRenderView
{
#if TARGET_OS_IOS || TARGET_OS_TV
    CGRect rect = [[UIScreen mainScreen] bounds];
#else
    CGRect rect = [[[NSScreen screens] firstObject]frame];
#endif
    rect.origin = CGPointZero;
    return [[IJKMetalView alloc] initWithFrame:rect];
}

@end
