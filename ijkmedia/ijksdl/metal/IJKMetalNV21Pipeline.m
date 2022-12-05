//
//  IJKMetalNV21Pipeline.m
//  FFmpegTutorial-macOS
//
//  Created by qianlongxu on 2022/11/23.
//  Copyright © 2022 Matt Reach's Awesome FFmpeg Tutotial. All rights reserved.
//

#import "IJKMetalNV21Pipeline.h"

@implementation IJKMetalNV21Pipeline

+ (NSString *)fragmentFuctionName
{
    return @"nv21FragmentShader";
}

@end
