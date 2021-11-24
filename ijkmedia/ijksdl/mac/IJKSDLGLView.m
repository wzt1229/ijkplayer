/*
 * IJKSDLGLView.m
 *
 * Copyright (c) 2013 Bilibili
 * Copyright (c) 2013 Zhang Rui <bbcallen@gmail.com>
 *
 * based on https://github.com/kolyvan/kxmovie
 *
 * This file is part of ijkPlayer.
 *
 * ijkPlayer is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * ijkPlayer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with ijkPlayer; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#import "IJKSDLGLView.h"
#include "ijksdl/ijksdl_timer.h"
#import <CoreVideo/CVDisplayLink.h>
#include "ijksdl/ijksdl_gles2.h"
#import <OpenGL/gl.h>
#import <CoreVideo/CoreVideo.h>
#include "ijksdl_vout_overlay_videotoolbox.h"
#import <AVFoundation/AVFoundation.h>

typedef NS_ENUM(NSInteger, IJKSDLGLViewApplicationState) {
    IJKSDLGLViewApplicationUnknownState = 0,
    IJKSDLGLViewApplicationForegroundState = 1,
    IJKSDLGLViewApplicationBackgroundState = 2
};

@interface IJKSDLGLView()

@property(atomic,strong) NSRecursiveLock *glActiveLock;
@property(atomic) BOOL glActivePaused;
@property(atomic) CVPixelBufferRef currentPic;

@end

@implementation IJKSDLGLView{
    IJK_GLES2_Renderer *_renderer;
    int                 _rendererGravity;
    GLint               _backingWidth;
    GLint               _backingHeight;
    BOOL                _isRenderBufferInvalidated;

}

@synthesize isThirdGLView              = _isThirdGLView;
@synthesize scaleFactor                = _scaleFactor;
@synthesize fps                        = _fps;

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self setup];
        self.subtitlePreference = (IJKSDLSubtitlePreference){100,0xFFFFFF,0.1};
        self.rotatePreference = (IJKSDLRotatePreference){IJKSDLRotateNone,0.0};
        self.colorPreference = (IJKSDLColorConversionPreference){1.0,1.0,1.0};
    }
    return self;
}

- (void)setup
{
//    NSOpenGLPixelFormatAttribute attrs[] =
//    {
//        NSOpenGLPFADoubleBuffer,
//        NSOpenGLPFASampleAlpha,
//        NSOpenGLPFAColorSize, 32,
//        NSOpenGLPFASamples, 8,
//        NSOpenGLPFAAccelerated,
//        NSOpenGLPFADepthSize, 16,
//        // Must specify the 3.2 Core Profile to use OpenGL 3.2
//#if ESSENTIAL_GL_PRACTICES_SUPPORT_GL3
//        NSOpenGLPFAOpenGLProfile,
//        NSOpenGLProfileVersion3_2Core,
//#endif
//        0
//    };
    //kEAGLDrawablePropertyColorFormat kEAGLColorFormatRGBA8
    
//    NSOpenGLPixelFormatAttribute attrs[] =
//    {
//        NSOpenGLPFAColorSize, 32,
//        NSOpenGLPFADoubleBuffer,
//        NSOpenGLPFADepthSize, 24,
//        0
//    };
    
    NSOpenGLPixelFormatAttribute attrs[] =
    {
        NSOpenGLPFAAccelerated,
        NSOpenGLPFANoRecovery,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFADepthSize, 24,
        0
    };
    
//    NSOpenGLPixelFormatAttribute attrs[] =
//    {
//        NSOpenGLPFAAccelerated,
//        0
//    };

    
    NSOpenGLPixelFormat *pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    
    if (!pf)
    {
        ALOGE("No OpenGL pixel format");
    }
    
    NSOpenGLContext* context = [[NSOpenGLContext alloc] initWithFormat:pf shareContext:nil];
    
#if ESSENTIAL_GL_PRACTICES_SUPPORT_GL3 && defined(DEBUG)
    // When we're using a CoreProfile context, crash if we call a legacy OpenGL function
    // This will make it much more obvious where and when such a function call is made so
    // that we can remove such calls.
    // Without this we'd simply get GL_INVALID_OPERATION error for calling legacy functions
    // but it would be more difficult to see where that function was called.
    CGLEnable([context CGLContextObj], kCGLCECrashOnRemovedFunctions);
#endif
    
    [self setPixelFormat:pf];
    [self setOpenGLContext:context];
#if 1 || SUPPORT_RETINA_RESOLUTION
    // Opt-In to Retina resolution
    [self setWantsBestResolutionOpenGLSurface:YES];
#endif // SUPPORT_RETINA_RESOLUTION
}

- (BOOL)setupRenderer:(SDL_VoutOverlay *)overlay
{
    if (overlay == nil)
        return _renderer != nil;
    
    if (!IJK_GLES2_Renderer_isValid(_renderer) ||
        !IJK_GLES2_Renderer_isFormat(_renderer, overlay->format)) {
        
        IJK_GLES2_Renderer_reset(_renderer);
        IJK_GLES2_Renderer_freeP(&_renderer);
        
        _renderer = IJK_GLES2_Renderer_create(overlay);
        if (!IJK_GLES2_Renderer_isValid(_renderer))
            return NO;
        
        if (!IJK_GLES2_Renderer_use(_renderer))
            return NO;
        
        IJK_GLES2_Renderer_setGravity(_renderer, _rendererGravity, _backingWidth, _backingHeight);
        
        IJK_GLES2_Renderer_updateRotate(_renderer, self.rotatePreference.type, self.rotatePreference.degrees);
        
        IJK_GLES2_Renderer_updateAutoZRotate(_renderer, overlay->auto_z_rotate_degrees);
    }
    
    return YES;
}

- (void)invalidateRenderBuffer
{
    _isRenderBufferInvalidated = YES;
    [self display:nil subtitle:NULL];
}

- (void)layout
{
    [super layout];
    if (IJK_GLES2_Renderer_isValid(_renderer)) {
        
        NSRect viewRectPoints = [self bounds];
        
    #if SUPPORT_RETINA_RESOLUTION
        NSRect viewRectPixels = [self convertRectToBacking:viewRectPoints];
    #else //if !SUPPORT_RETINA_RESOLUTION
        // Points:Pixels is always 1:1 when not supporting retina resolutions
        NSRect viewRectPixels = viewRectPoints;
    #endif // !SUPPORT_RETINA_RESOLUTION
        
        _backingWidth = viewRectPixels.size.width;
        _backingHeight = viewRectPixels.size.height;
        
        IJK_GLES2_Renderer_setGravity(_renderer, _rendererGravity, _backingWidth, _backingHeight);
    }

//    [self invalidateRenderBuffer];
}

- (void)setScalingMode:(IJKMPMovieScalingMode)scalingMode
{
    switch (scalingMode) {
        case IJKMPMovieScalingModeFill:
            _rendererGravity = IJK_GLES2_GRAVITY_RESIZE;
            break;
        case IJKMPMovieScalingModeAspectFit:
            _rendererGravity = IJK_GLES2_GRAVITY_RESIZE_ASPECT;
            break;
        case IJKMPMovieScalingModeAspectFill:
            _rendererGravity = IJK_GLES2_GRAVITY_RESIZE_ASPECT_FILL;
            break;
    }
    _scalingMode = scalingMode;
    if (IJK_GLES2_Renderer_isValid(_renderer)) {
        IJK_GLES2_Renderer_setGravity(_renderer, _rendererGravity, _backingWidth, _backingHeight);
    }
    //[self invalidateRenderBuffer];
}

- (void)resetViewPort
{
    // We draw on a secondary thread through the display link. However, when
    // resizing the view, -drawRect is called on the main thread.
    // Add a mutex around to avoid the threads accessing the context
    // simultaneously when resizing.
    CGLLockContext([[self openGLContext] CGLContextObj]);
    
    // Get the view size in Points
    NSRect viewRectPoints = [self bounds];
    
#if SUPPORT_RETINA_RESOLUTION
    
    // Rendering at retina resolutions will reduce aliasing, but at the potential
    // cost of framerate and battery life due to the GPU needing to render more
    // pixels.
    
    // Any calculations the renderer does which use pixel dimentions, must be
    // in "retina" space.  [NSView convertRectToBacking] converts point sizes
    // to pixel sizes.  Thus the renderer gets the size in pixels, not points,
    // so that it can set it's viewport and perform and other pixel based
    // calculations appropriately.
    // viewRectPixels will be larger than viewRectPoints for retina displays.
    // viewRectPixels will be the same as viewRectPoints for non-retina displays
    NSRect viewRectPixels = [self convertRectToBacking:viewRectPoints];
    
#else //if !SUPPORT_RETINA_RESOLUTION
    
    // App will typically render faster and use less power rendering at
    // non-retina resolutions since the GPU needs to render less pixels.
    // There is the cost of more aliasing, but it will be no-worse than
    // on a Mac without a retina display.
    
    // Points:Pixels is always 1:1 when not supporting retina resolutions
    NSRect viewRectPixels = viewRectPoints;
    
#endif // !SUPPORT_RETINA_RESOLUTION
    
    _backingWidth = viewRectPixels.size.width;
    _backingHeight = viewRectPixels.size.height;
    // Set the new dimensions in our renderer
    glViewport(0, 0, _backingWidth, _backingHeight);
    CGLUnlockContext([[self openGLContext] CGLContextObj]);
}

- (void)displayInternal:(SDL_VoutOverlay *)overlay subtitle:(CVPixelBufferRef)subtitle
{
    if (![self setupRenderer:overlay]) {
        if (!overlay && !_renderer) {
            ALOGW("IJKSDLGLView: setupDisplay not ready\n");
        } else {
            ALOGE("IJKSDLGLView: setupDisplay failed\n");
        }
        return;
    }
    
    IJK_GLES2_Renderer_updateRotate(_renderer, self.rotatePreference.type, self.rotatePreference.degrees);
    IJK_GLES2_Renderer_updateSubtitleBottomMargin(_renderer, self.subtitlePreference.bottomMargin);
    if (_isRenderBufferInvalidated) {
        _isRenderBufferInvalidated = NO;
        [self resetViewPort];
        IJK_GLES2_Renderer_setGravity(_renderer, _rendererGravity, _backingWidth, _backingHeight);
    }
    CVPixelBufferRef img = (CVPixelBufferRef)IJK_GLES2_Renderer_getImage(_renderer, overlay);
    if (img) {
        if (self.currentPic) {
            CVPixelBufferRelease(self.currentPic);
            self.currentPic = NULL;
        }
        self.currentPic = CVPixelBufferRetain(img);
    }
    
    IJK_GLES2_Renderer_updateColorConversion(_renderer, self.colorPreference.brightness, self.colorPreference.saturation,self.colorPreference.contrast);
    
    if (!IJK_GLES2_Renderer_renderOverlay(_renderer, overlay))
        ALOGE("[EGL] IJK_GLES2_render failed\n");
    
    if (!IJK_GLES2_Renderer_renderSubtitle(_renderer, overlay,(void *)subtitle))
        ALOGE("[EGL] IJK_GLES2_render failed\n");
}

- (void)display:(SDL_VoutOverlay *)overlay subtitle:(CVPixelBufferRef)subtitle
{
    [[self openGLContext] makeCurrentContext];
    CGLLockContext([[self openGLContext] CGLContextObj]);
    [self displayInternal:overlay subtitle:(CVPixelBufferRef)subtitle];
    CGLFlushDrawable([[self openGLContext] CGLContextObj]);
    CGLUnlockContext([[self openGLContext] CGLContextObj]);
}

- (void)initGL
{
    // The reshape function may have changed the thread to which our OpenGL
    // context is attached before prepareOpenGL and initGL are called.  So call
    // makeCurrentContext to ensure that our OpenGL context current to this
    // thread (i.e. makeCurrentContext directs all OpenGL calls on this thread
    // to [self openGLContext])
    [[self openGLContext] makeCurrentContext];
    
    // Synchronize buffer swaps with vertical refresh rate
    GLint swapInt = 1;
    [[self openGLContext] setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];
}

- (void)prepareOpenGL
{
    [super prepareOpenGL];

    // Make all the OpenGL calls to setup rendering
    //  and build the necessary rendering objects
    [self initGL];
}

- (void)windowWillClose:(NSNotification*)notification
{
    // Stop the display link when the window is closing because default
    // OpenGL render buffers will be destroyed.  If display link continues to
    // fire without renderbuffers, OpenGL draw calls will set errors.
    // todo
}

- (void)reshape
{
    [super reshape];
    [self resetViewPort];
}

- (void)display_pixels:(IJKOverlay *)overlay
{
    
}

- (CGImageRef)snapshot
{
    CVPixelBufferRef pixelBuffer = CVPixelBufferRetain(self.currentPic);
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    
    static CIContext *context = nil;
    if (!context) {
        context = [CIContext contextWithOptions:NULL];
    }
    CGRect rect = CGRectMake(0,0,
                             CVPixelBufferGetWidth(pixelBuffer),
                             CVPixelBufferGetHeight(pixelBuffer));
    CGImageRef imageRef = [context createCGImage:ciImage fromRect:rect];
    CVPixelBufferRelease(pixelBuffer);
    return (CGImageRef)CFAutorelease(imageRef);
}

- (NSView *)hitTest:(NSPoint)point
{
    return nil;
}

- (BOOL)acceptsFirstResponder
{
    return NO;
}

- (BOOL)mouseDownCanMoveWindow
{
    return YES;
}

@end
