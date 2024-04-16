//
//  ijksdl_gpu_opengl_compiler_macos.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/4/15.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IJKSDLOpenGLCompiler : NSObject

@property (copy) NSString *vsh;
@property (copy) NSString *fsh;

- (instancetype)initWithvsh:(NSString *)vshName
                        fsh:(NSString *)fshName;
- (BOOL)compileIfNeed;
- (void)active;
- (int)getUniformLocation:(const char *)name;
- (int)getAttribLocation:(const char *)name;

@end

NS_ASSUME_NONNULL_END
