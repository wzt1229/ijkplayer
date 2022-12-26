//
//  IJKMetalAttach.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/12/5.
//


@import Foundation;
@import CoreVideo;

NS_ASSUME_NONNULL_BEGIN
@class IJKSDLSubtitle;
@interface IJKMetalAttach : NSObject

@property(atomic,nullable) CVPixelBufferRef currentVideoPic;
@property(atomic,nullable) CVPixelBufferRef currentSubtitle;

@property(nonatomic) float sar;
@property(nonatomic) int zRotateDegrees;
@property(nonatomic) IJKSDLSubtitle *sub;

@end

NS_ASSUME_NONNULL_END
