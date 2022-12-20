//
//  IJKMetalView.h
//  FFmpegTutorial-macOS
//
//  Created by qianlongxu on 2022/11/22.
//  Copyright © 2022 Matt Reach's Awesome FFmpeg Tutotial. All rights reserved.
//

#import "IJKVideoRenderingProtocol.h"
@import MetalKit;

NS_ASSUME_NONNULL_BEGIN

@interface IJKMetalView : MTKView <IJKVideoRenderingProtocol>

@end

NS_ASSUME_NONNULL_END
