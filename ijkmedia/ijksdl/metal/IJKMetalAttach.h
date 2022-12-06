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

@property(atomic) CVPixelBufferRef currentVideoPic;
@property(atomic) CVPixelBufferRef currentSubtitle;

@property(nonatomic) int  sar_num;
@property(nonatomic) int  sar_den;
@property(nonatomic) uint32 overlayFormat;
@property(nonatomic) uint32 ffFormat;
@property(nonatomic) int zRotateDegrees;
@property(nonatomic) int overlayH;
@property(nonatomic) int overlayW;
@property(nonatomic) int bufferW;
@property(nonatomic) IJKSDLSubtitle *sub;

@end

NS_ASSUME_NONNULL_END
