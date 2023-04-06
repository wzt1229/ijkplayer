//
//  IJKInternalRenderView.m
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2023/4/6.
//

#import "IJKInternalRenderView.h"
#import "IJKSDLGLView.h"
#import "IJKMetalView.h"

@implementation IJKInternalRenderView

+ (UIView<IJKVideoRenderingProtocol> *)createGLRenderView
{
    return [[IJKSDLGLView alloc] init];
}

+ (UIView<IJKVideoRenderingProtocol> *)createMetalRenderView
{
    return [[IJKMetalView alloc] init];
}

@end
