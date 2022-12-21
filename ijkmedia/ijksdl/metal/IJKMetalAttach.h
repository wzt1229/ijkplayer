//
//  IJKMetalAttach.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/12/5.
//


@import Foundation;
@import CoreVideo;
#import "IJKVideoRenderingProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface IJKMetalAttach : NSObject

@property(atomic,nullable) CVPixelBufferRef currentVideoPic;
@property(atomic,nullable) CVPixelBufferRef currentSubtitle;

@property(nonatomic) int  sar_num;
@property(nonatomic) int  sar_den;
@property(nonatomic) unsigned int overlayFormat;
@property(nonatomic) unsigned int ffFormat;
@property(nonatomic) int zRotateDegrees;
@property(nonatomic) IJKSDLSubtitle *sub;

@end

NS_ASSUME_NONNULL_END
