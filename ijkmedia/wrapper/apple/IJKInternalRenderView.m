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
    return [[IJKSDLGLView alloc] init];
}
#endif

+ (UIView<IJKVideoRenderingProtocol> *)createMetalRenderView
{
    return [[IJKMetalView alloc] init];
}

@end
