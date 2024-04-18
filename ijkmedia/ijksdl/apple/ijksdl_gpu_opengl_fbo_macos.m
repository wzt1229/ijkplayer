//
//  ijksdl_gpu_opengl_fbo_macos.m
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/4/15.
//

#import "ijksdl_gpu_opengl_fbo_macos.h"
#import "ijksdl_gles2.h"
#import "ijksdl_vout_ios_gles2.h"
#include <libavutil/log.h>

@interface IJKSDLOpenGLFBO()

@property(nonatomic, assign) GLuint fbo;
@property(nonatomic, readwrite) id<IJKSDLSubtitleTextureWrapper> texture;

@end

@implementation IJKSDLOpenGLFBO

- (void)dealloc
{
    //the fbo was created in vout thread, when stop player the fbo will dealloc in a background thread by call shutdown
    if (_fbo) {
        if ([[NSThread currentThread] isMainThread]) {
            glDeleteFramebuffers(1, &_fbo);
        } else {
            __block GLuint fbo = _fbo;
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                glDeleteFramebuffers(1, &fbo);
            }];
        }
    }
}

- (instancetype)initWithSize:(CGSize)size
{
    self = [super init];
    if (self) {
        uint32_t t;
        // Create a texture object that you apply to the model.
        glGenTextures(1, &t);
        GLenum target = GL_TEXTURE_RECTANGLE;//GL_TEXTURE_2D
        glBindTexture(target, t);

        // Set up filter and wrap modes for the texture object.
        glTexParameteri(target, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(target, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameteri(target, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(target, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

        // Allocate a texture image to which you can render to. Pass `NULL` for the data parameter
        // becuase you don't need to load image data. You generate the image by rendering to the texture.
        glTexImage2D(target, 0, GL_RGBA, size.width, size.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);

        glGenFramebuffers(1, &_fbo);
        glBindFramebuffer(GL_FRAMEBUFFER, _fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, target, t, 0);
        
        GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        if (GL_FRAMEBUFFER_COMPLETE == status) {
            _texture = IJKSDL_crate_openglTextureWrapper(t, size.width, size.height);
            glBindTexture(target, 0);
            return self;
        } else {
            glBindTexture(target, 0);
            av_log(NULL, AV_LOG_ERROR, "CheckFramebufferStatus:%x\n",status);
        #if DEBUG
            NSAssert(NO, @"Failed to make complete framebuffer object %x.", status);
        #endif
            return nil;
        }
    }
    return nil;
}

// Create texture and framebuffer objects to render and snapshot.
- (BOOL)canReuse:(CGSize)size
{
    if (CGSizeEqualToSize(CGSizeZero, size)) {
        return NO;
    }
    
    if ([self.texture w] == (int)size.width && [self.texture h] == (int)size.height && _fbo && _texture) {
        return YES;
    } else {
        return NO;
    }
}

- (CGSize)size
{
    return CGSizeMake([self.texture w], [self.texture h]);
}

- (void)bind
{
    // Bind the snapshot FBO and render the scene.
    glBindFramebuffer(GL_FRAMEBUFFER, _fbo);
}

@end

