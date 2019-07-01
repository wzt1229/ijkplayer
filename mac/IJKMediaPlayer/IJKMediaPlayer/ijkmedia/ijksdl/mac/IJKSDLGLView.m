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
#import "OpenGLRenderer.h"
#import <CoreVideo/CVDisplayLink.h>
typedef NS_ENUM(NSInteger, IJKSDLGLViewApplicationState) {
    IJKSDLGLViewApplicationUnknownState = 0,
    IJKSDLGLViewApplicationForegroundState = 1,
    IJKSDLGLViewApplicationBackgroundState = 2
};

@interface IJKSDLGLView()

@property(atomic,strong) NSRecursiveLock *glActiveLock;
@property(atomic) BOOL glActivePaused;
@property(atomic,strong) OpenGLRenderer* renderer;
@property(atomic) CVDisplayLinkRef displayLink;

@end

@implementation IJKSDLGLView

@synthesize isThirdGLView              = _isThirdGLView;
@synthesize scaleFactor                = _scaleFactor;
@synthesize fps                        = _fps;

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self setup];
    }
    return self;
}

- (void) display: (SDL_VoutOverlay *) overlay
{
    [_renderer setImage:overlay];
}

- (CVReturn) getFrameForTime:(const CVTimeStamp*)outputTime
{
    // There is no autorelease pool when this method is called
    // because it will be called from a background thread.
    // It's important to create one or app can leak objects.
    @autoreleasepool {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self drawView];
        });
    }
    return kCVReturnSuccess;
}

// This is the renderer output callback function
static CVReturn MyDisplayLinkCallback(CVDisplayLinkRef displayLink,
                                      const CVTimeStamp* now,
                                      const CVTimeStamp* outputTime,
                                      CVOptionFlags flagsIn,
                                      CVOptionFlags* flagsOut,
                                      void* displayLinkContext)
{
    CVReturn result = [(__bridge IJKSDLGLView*)displayLinkContext getFrameForTime:outputTime];
    return result;
}

- (void) setup
{
    NSOpenGLPixelFormatAttribute attrs[] =
    {
        NSOpenGLPFADoubleBuffer,
//        NSOpenGLPFAColorSize, 32,
//        NSOpenGLPFAAccelerated,
        NSOpenGLPFADepthSize, 16,
        // Must specify the 3.2 Core Profile to use OpenGL 3.2
#if ESSENTIAL_GL_PRACTICES_SUPPORT_GL3
        NSOpenGLPFAOpenGLProfile,
        NSOpenGLProfileVersion3_2Core,
#endif
        0
    };

    NSOpenGLPixelFormat *pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];

    if (!pf)
    {
        NSLog(@"No OpenGL pixel format");
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

#if SUPPORT_RETINA_RESOLUTION
    // Opt-In to Retina resolution
    [self setWantsBestResolutionOpenGLSurface:YES];
#endif // SUPPORT_RETINA_RESOLUTION
}

- (void) prepareOpenGL
{
    [super prepareOpenGL];

    // Make all the OpenGL calls to setup rendering
    //  and build the necessary rendering objects
    [self initGL];

    // Create a display link capable of being used with all active displays
    CVDisplayLinkRef displayLink;
    CVDisplayLinkCreateWithActiveCGDisplays(&displayLink);
    self.displayLink = displayLink;

    // Set the renderer output callback function
    CVDisplayLinkSetOutputCallback(self.displayLink, &MyDisplayLinkCallback, (__bridge void*)self);

    // Set the display link for the current renderer
    CGLContextObj cglContext = [[self openGLContext] CGLContextObj];
    CGLPixelFormatObj cglPixelFormat = [[self pixelFormat] CGLPixelFormatObj];
    CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(self.displayLink, cglContext, cglPixelFormat);

    // Activate the display link
    CVDisplayLinkStart(self.displayLink);

    // Register to be notified when the window closes so we can stop the displaylink
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowWillClose:)
                                                 name:NSWindowWillCloseNotification
                                               object:[self window]];
}

- (void) windowWillClose:(NSNotification*)notification
{
    // Stop the display link when the window is closing because default
    // OpenGL render buffers will be destroyed.  If display link continues to
    // fire without renderbuffers, OpenGL draw calls will set errors.

    CVDisplayLinkStop(self.displayLink);
}

- (void) initGL
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

    // Init our renderer.  Use 0 for the defaultFBO which is appropriate for
    // OSX (but not iOS since iOS apps must create their own FBO)
    _renderer = [[OpenGLRenderer alloc] init];
}

- (void)reshape
{
    [super reshape];

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

    // Set the new dimensions in our renderer
    [_renderer resizeWithWidth:viewRectPixels.size.width
                     AndHeight:viewRectPixels.size.height];

    CGLUnlockContext([[self openGLContext] CGLContextObj]);
}

- (void)renewGState
{
    // Called whenever graphics state updated (such as window resize)

    // OpenGL rendering is not synchronous with other rendering on the OSX.
    // Therefore, call disableScreenUpdatesUntilFlush so the window server
    // doesn't render non-OpenGL content in the window asynchronously from
    // OpenGL content, which could cause flickering.  (non-OpenGL content
    // includes the title bar and drawing done by the app with other APIs)
    [[self window] disableScreenUpdatesUntilFlush];

    [super renewGState];
}

- (void) drawRect: (NSRect) theRect
{
    // Called during resize operations

    // Avoid flickering during resize by drawiing
    [self drawView];
}

- (void) drawView
{
    [[self openGLContext] makeCurrentContext];

    // We draw on a secondary thread through the display link
    // When resizing the view, -reshape is called automatically on the main
    // thread. Add a mutex around to avoid the threads accessing the context
    // simultaneously when resizing
    CGLLockContext([[self openGLContext] CGLContextObj]);

    [_renderer render];

    CGLFlushDrawable([[self openGLContext] CGLContextObj]);
    CGLUnlockContext([[self openGLContext] CGLContextObj]);
}

- (void) dealloc
{
    // Stop the display link BEFORE releasing anything in the view
    // otherwise the display link thread may call into the view and crash
    // when it encounters something that has been release
    CVDisplayLinkStop(self.displayLink);

    CVDisplayLinkRelease(self.displayLink);
}
@end
