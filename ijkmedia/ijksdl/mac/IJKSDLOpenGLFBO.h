//
//  IJKSDLOpenGLFBO.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/4/14.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IJKSDLOpenGLFBO : NSObject

@property(nonatomic, readonly) CGSize size;
@property(nonatomic, readonly) uint32_t texture;

- (instancetype)initWithSize:(CGSize)size;
- (BOOL)canReuse:(CGSize)size;
- (void)bind;

@end

NS_ASSUME_NONNULL_END
