//
//  IJKSDLOpenGLFBO.m
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/4/14.
//

#import "IJKSDLOpenGLFBO.h"
#import "ijksdl_gles2.h"

@interface IJKSDLOpenGLFBO()

@property(nonatomic, assign) GLuint fbo;
@property(nonatomic, readwrite) CGSize size;
@property(nonatomic, readwrite) uint32_t texture;

@end

@implementation IJKSDLOpenGLFBO

- (void)dealloc
{
    if (_fbo) {
        glDeleteFramebuffers(1, &_fbo);
    }
    
    if (_texture) {
        glDeleteTextures(1, &_texture);
    }
    
    _size = CGSizeZero;
}

- (instancetype)initWithSize:(CGSize)size
{
    self = [super init];
    if (self) {
        // Create a texture object that you apply to the model.
        glGenTextures(1, &_texture);
        glBindTexture(GL_TEXTURE_2D, _texture);

        // Set up filter and wrap modes for the texture object.
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

        // Allocate a texture image to which you can render to. Pass `NULL` for the data parameter
        // becuase you don't need to load image data. You generate the image by rendering to the texture.
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, size.width, size.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);

        glGenFramebuffers(1, &_fbo);
        glBindFramebuffer(GL_FRAMEBUFFER, _fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, _texture, 0);

        if (glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE) {
            _size = size;
            return self;
        } else {
        #if DEBUG
            NSAssert(NO, @"Failed to make complete framebuffer object %x.",  glCheckFramebufferStatus(GL_FRAMEBUFFER));
        #endif
            _size = CGSizeZero;
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
    
    if (CGSizeEqualToSize(_size, size) && _fbo && _texture) {
        return YES;
    } else {
        return NO;
    }
}

- (void)bind
{
    // Bind the snapshot FBO and render the scene.
    glBindFramebuffer(GL_FRAMEBUFFER, _fbo);
}

@end
