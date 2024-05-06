//
//  IJKInternalRenderView.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2023/4/6.
//
//
// you can use below mthods, create ijk internal render view.

#import "IJKVideoRenderingProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface IJKInternalRenderView : NSObject

#if TARGET_OS_OSX
+ (UIView<IJKVideoRenderingProtocol> *)createGLRenderView;
#endif

+ (UIView<IJKVideoRenderingProtocol> *)createMetalRenderView NS_AVAILABLE(10_13, 11_0);

@end

NS_ASSUME_NONNULL_END
