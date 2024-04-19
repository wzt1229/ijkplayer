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

/*
 2022.10.19
 on low macOS (below 10.13) CGLLock is no effect for multiple NSOpenGLContext!
 multiple thread may get lock same time, and block in CGLFlushDrawable function.
 try use apple fence and flushBuffer instead of CGLFlushDrawable are no effect.
 so record IJKSDLGLView's count,when create more than one NSOpenGLContext just dispath all gl* task to main thread execute.
 */

/*
 2022.11.10
 SIGSEGV crash:
 - CVPixelBufferGetWidthOfPlane
 - upload_texture_use_IOSurface renderer_apple.m:118
 
 use global single thread display.
 */

/*
 2022.11.25
 macos 10.14 later use global single thread not smooth when create multil glview.
 */

#import "IJKSDLGLView.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CIContext.h>
#import <OpenGL/glext.h>
#import "ijksdl_timer.h"
#import "ijksdl_gles2.h"
#import "ijksdl_vout_overlay_ffmpeg_hw.h"
#import "IJKMediaPlayback.h"
#import "IJKSDLThread.h"
#import "../gles2/internal.h"
#import "ijksdl_vout_ios_gles2.h"
#import "ijksdl_gpu_opengl_fbo_macos.h"

#define kHDRAnimationMaxCount 90

static IJKSDLThread *__ijk_global_thread;

static IJKSDLThread * _globalThread_(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __ijk_global_thread = [[IJKSDLThread alloc] initWithName:@"ijk_global_render"];
        [__ijk_global_thread start];
    });
    return __ijk_global_thread;
}

// greather than 10.14 no need dispatch to global.
static bool _is_low_os_version(void)
{
    NSOperatingSystemVersion sysVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    if (sysVersion.majorVersion > 10) {
        return false;
    } else if (sysVersion.minorVersion >= 14) {
        return false;
    }
    return true;
}

static bool _is_need_dispath_to_global(void)
{
    bool low_os = _is_low_os_version();
    if (low_os) {
        return true;
    } else {
        return false;
    }
}

@interface IJKSDLGLView()

@property(atomic) IJKOverlayAttach *currentAttach;

@property(nonatomic) NSInteger videoDegrees;
//view size
@property(assign) CGSize viewSize;
@property(atomic) GLint backingWidth;
@property(atomic) GLint backingHeight;
@property(atomic) IJKSDLOpenGLFBO * fbo;
@property(atomic) IJKSDLThread *renderThread;
@property(assign) int hdrAnimationFrameCount;

@end

@implementation IJKSDLGLView
{
    IJK_GLES2_Renderer *_renderer;
    int    _rendererGravity;
}

@synthesize scalingMode = _scalingMode;
// rotate preference
@synthesize rotatePreference = _rotatePreference;
// color conversion preference
@synthesize colorPreference = _colorPreference;
// user defined display aspect ratio
@synthesize darPreference = _darPreference;
@synthesize preventDisplay;
@synthesize showHdrAnimation = _showHdrAnimation;

- (void)destroyRender
{
    IJK_GLES2_Renderer_freeP(&_renderer);
}

- (void)dealloc
{
    self.fbo = nil;
    if (_renderer) {
        if (self.renderThread && [NSThread currentThread] != self.renderThread.thread) {
            [self.renderThread performSelector:@selector(destroyRender) withTarget:self withObject:nil waitUntilDone:YES];
        } else {
            [self destroyRender];
        }
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (self.renderThread != __ijk_global_thread) {
        [self.renderThread stop];
    }
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        if (@available(macOS 10.13, *)) {
            if (_is_need_dispath_to_global()) {
                self.renderThread = _globalThread_();
            } else {
                self.renderThread = [[IJKSDLThread alloc] initWithName:@"ijk_renderer"];
                [self.renderThread start];
            }
        }
        [self setup];

        _rotatePreference   = (IJKSDLRotatePreference){IJKSDLRotateNone, 0.0};
        _colorPreference    = (IJKSDLColorConversionPreference){1.0, 1.0, 1.0};
        _darPreference      = (IJKSDLDARPreference){0.0};
        _rendererGravity    = IJK_GLES2_GRAVITY_RESIZE_ASPECT;
    }
    return self;
}

- (void)setup
{
    NSOpenGLPixelFormatAttribute attrs[] =
    {
        NSOpenGLPFAAccelerated,
        NSOpenGLPFANoRecovery,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFADepthSize, 24,
#if ! USE_LEGACY_OPENGL
        NSOpenGLPFAOpenGLProfile,NSOpenGLProfileVersion3_2Core,
#endif
//        NSOpenGLPFAAllowOfflineRenderers, 1,
        0
    };
   
    NSOpenGLPixelFormat *pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    
    if (!pf)
    {
        ALOGE("No OpenGL pixel format");
        return;
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
    [self setWantsBestResolutionOpenGLSurface:YES];
//    [self setWantsExtendedDynamicRangeOpenGLSurface:YES];
    
    ///Fix the default red background color on the Intel platform
    [[self openGLContext] makeCurrentContext];
    glClear(GL_COLOR_BUFFER_BIT);
    [[self openGLContext]flushBuffer];
}


- (void)setShowHdrAnimation:(BOOL)showHdrAnimation
{
    if (_showHdrAnimation != showHdrAnimation) {
        _showHdrAnimation = showHdrAnimation;
        self.hdrAnimationFrameCount = 0;
    }
}

- (void)videoZRotateDegrees:(NSInteger)degrees
{
    self.videoDegrees = degrees;
}

- (void)cleanSubtitle
{
    if (self.currentAttach.subTexture) {
        self.currentAttach.subTexture = nil;
        [self setNeedsRefreshCurrentPic];
    }
}

- (BOOL)setupRendererIfNeed:(IJKOverlayAttach *)attach
{
    if (attach == nil)
        return _renderer != nil;
    
    Uint32 cv_format = CVPixelBufferGetPixelFormatType(attach.videoPicture);
    
    if (!IJK_GLES2_Renderer_isValid(_renderer) ||
        !IJK_GLES2_Renderer_isFormat(_renderer, cv_format)) {
        
        IJK_GLES2_Renderer_reset(_renderer);
        IJK_GLES2_Renderer_freeP(&_renderer);
        int openglVer = 330;
    #if USE_LEGACY_OPENGL
        openglVer = 120;
    #endif
        
        _renderer = IJK_GLES2_Renderer_createApple(attach.videoPicture, openglVer);
        if (!IJK_GLES2_Renderer_isValid(_renderer))
            return NO;
        
        if (!IJK_GLES2_Renderer_init(_renderer))
            return NO;
        
        IJK_GLES2_Renderer_setGravity(_renderer, _rendererGravity, self.backingWidth, self.backingHeight);
        
        IJK_GLES2_Renderer_updateRotate(_renderer, _rotatePreference.type, _rotatePreference.degrees);
        
        IJK_GLES2_Renderer_updateAutoZRotate(_renderer, attach.autoZRotate);
        
        IJK_GLES2_Renderer_updateColorConversion(_renderer, _colorPreference.brightness, _colorPreference.saturation,_colorPreference.contrast);
        
        IJK_GLES2_Renderer_updateUserDefinedDAR(_renderer, _darPreference.ratio);
    } else {
        if (!IJK_GLES2_Renderer_useProgram(_renderer))
            return NO;
    }
    return YES;
}

- (void)setFrame:(NSRect)frame
{
    [super setFrame:frame];
}

- (void)reshape
{
    [super reshape];
    [self resetViewPort];
}

- (void)viewDidChangeBackingProperties
{
    [super viewDidChangeBackingProperties];
    //here need a delay,wait intenal right, otherwise display wrong picture size.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self resetViewPort];
    });
}

- (void)resetViewPort
{
    CGSize viewSize = [self bounds].size;
    CGSize viewSizePixels = [self convertSizeToBacking:viewSize];
    
    if (self.backingWidth != viewSizePixels.width || self.backingHeight != viewSizePixels.height) {
        self.backingWidth  = viewSizePixels.width;
        self.backingHeight = viewSizePixels.height;
        self.viewSize = viewSize;
        [self setNeedsRefreshCurrentPic];
    }
}

- (void)doUploadSubtitle:(IJKOverlayAttach *)attach viewport:(CGSize)viewport
{
    id<IJKSDLSubtitleTextureWrapper>subTexture = attach.subTexture;
    if (subTexture) {
        IJK_GLES2_Renderer_beginDrawSubtitle(_renderer);
        
        IJK_GLES2_Renderer_updateSubtitleVertex(_renderer, subTexture.w, subTexture.h);
        if (IJK_GLES2_Renderer_uploadSubtitleTexture(_renderer, subTexture.texture, subTexture.w, subTexture.h)) {
            IJK_GLES2_Renderer_drawArrays();
        } else {
            ALOGE("[GL] GLES2 Render Subtitle failed\n");
        }
        IJK_GLES2_Renderer_endDrawSubtitle(_renderer);
    }
}

- (void)doUploadVideoPicture:(IJKOverlayAttach *)attach
{
    if (attach.videoPicture) {
        if (IJK_GLES2_Renderer_updateVertex2(_renderer, attach.h, attach.w, attach.pixelW, attach.sarNum, attach.sarDen)) {
            float hdrPer = 1.0;
            if (self.showHdrAnimation) {
                if (self.hdrAnimationFrameCount == 0) {
                    [[NSNotificationCenter defaultCenter] postNotificationName:IJKMoviePlayerHDRAnimationStateChanged object:self userInfo:@{@"state":@(1)}];
                } else if (self.hdrAnimationFrameCount == kHDRAnimationMaxCount) {
                    [[NSNotificationCenter defaultCenter] postNotificationName:IJKMoviePlayerHDRAnimationStateChanged object:self userInfo:@{@"state":@(2)}];
                }
                
                if (self.hdrAnimationFrameCount <= kHDRAnimationMaxCount) {
                    self.hdrAnimationFrameCount++;
                    hdrPer = 1.0 * self.hdrAnimationFrameCount / kHDRAnimationMaxCount;
                }
            }
            IJK_GLES2_Renderer_updateHdrAnimationProgress(_renderer, hdrPer);
            if (IJK_GLES2_Renderer_uploadTexture(_renderer, (void *)attach.videoPicture)) {
                IJK_GLES2_Renderer_drawArrays();
            } else {
                ALOGE("[GL] Renderer_updateVertex failed\n");
            }
        } else {
            ALOGE("[GL] Renderer_updateVertex failed\n");
        }
    }
}

- (void)doRefreshCurrentAttach:(IJKOverlayAttach *)currentAttach
{
    if (!currentAttach) {
        return;
    }
    [self doDisplayVideoPicAndSubtitle:currentAttach];
}

- (void)doDisplayVideoPicAndSubtitle:(IJKOverlayAttach *)attach
{
    if (!attach) {
        return;
    }
    
    CGLLockContext([[self openGLContext] CGLContextObj]);
    [[self openGLContext] makeCurrentContext];

    if ([self setupRendererIfNeed:attach] && IJK_GLES2_Renderer_isValid(_renderer)) {
        // Bind the FBO to screen.
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(0, 0, self.backingWidth, self.backingHeight);
        glClear(GL_COLOR_BUFFER_BIT);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        IJK_GLES2_Renderer_setGravity(_renderer, _rendererGravity, self.backingWidth, self.backingHeight);
        //for video
        [self doUploadVideoPicture:attach];
        //for subtitle
        [self doUploadSubtitle:attach viewport:CGSizeMake(self.backingWidth, self.backingHeight)];
    } else {
        ALOGW("IJKSDLGLView: Renderer not ok.\n");
    }
    
    [[self openGLContext]flushBuffer];
    CGLUnlockContext([[self openGLContext] CGLContextObj]);
}

- (void)setNeedsRefreshCurrentPic
{
    //use single global thread!
    if (@available(macOS 10.13, *)) {
        [self.renderThread performSelector:@selector(doRefreshCurrentAttach:)
                                withTarget:self
                                withObject:self.currentAttach
                             waitUntilDone:NO];
    } else {
        [self doRefreshCurrentAttach:self.currentAttach];
    }
}

- (BOOL)displayAttach:(IJKOverlayAttach *)attach
{
    if (!attach) {
        ALOGW("IJKSDLGLView: overlay is nil\n");
        return NO;
    }
    //overlay is not thread safe, maybe need dispatch from sub thread to main thread,so hold overlay's property to GLView.
    //hold the attach as current.
    self.currentAttach = attach;
    
    if (self.preventDisplay) {
        return YES;
    }
    
    if (@available(macOS 10.13, *)) {
        [self.renderThread performSelector:@selector(doDisplayVideoPicAndSubtitle:)
                                withTarget:self
                                withObject:attach
                             waitUntilDone:NO];
    } else {
        [self doDisplayVideoPicAndSubtitle:attach];
    }
    return YES;
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
    
    glClearColor(0.0, 0.0, 0.0, 1.0f);
}

- (void)prepareOpenGL
{
    [super prepareOpenGL];

    // Make all the OpenGL calls to setup rendering
    //  and build the necessary rendering objects
    [self initGL];
}

#pragma mark - for snapshot

- (void)_snapshotEffectOriginWithSubtitle:(NSDictionary *)params
{
    BOOL containSub = [params[@"containSub"] boolValue];
    IJKOverlayAttach * attach = params[@"attach"];
    NSValue *ptrValue = params[@"outImg"];
    CGImageRef *outImg = (CGImageRef *)[ptrValue pointerValue];
    if (outImg) {
        *outImg = NULL;
    }
    if (!attach) {
        return;
    }
    
    CGLLockContext([[self openGLContext] CGLContextObj]);
    [[self openGLContext] makeCurrentContext];
    //[self setupRendererIfNeed:attach];
    CGImageRef img = NULL;
    if (IJK_GLES2_Renderer_isValid(_renderer)) {
        float videoSar = 1.0;
        if (attach.sarNum > 0 && attach.sarDen > 0) {
            videoSar = 1.0 * attach.sarNum / attach.sarDen;
        }
        CGSize picSize = CGSizeMake(CVPixelBufferGetWidth(attach.videoPicture) * videoSar, CVPixelBufferGetHeight(attach.videoPicture));
        //视频带有旋转 90 度倍数时需要将显示宽高交换后计算
        if (IJK_GLES2_Renderer_isZRotate90oddMultiple(_renderer)) {
            picSize = CGSizeMake(picSize.height, picSize.width);
        }
        
        //保持用户定义宽高比
        if (self.darPreference.ratio > 0) {
            float pic_width = picSize.width;
            float pic_height = picSize.height;
           
            if (pic_width / pic_height > self.darPreference.ratio) {
                pic_height = pic_width * 1.0 / self.darPreference.ratio;
            } else {
                pic_width = pic_height * self.darPreference.ratio;
            }
            picSize = CGSizeMake(pic_width, pic_height);
        }
        
        if (![self.fbo canReuse:picSize]) {
            self.fbo = [[IJKSDLOpenGLFBO alloc] initWithSize:picSize];
        }
        
        if (self.fbo) {
            if (attach.videoPicture) {
                [self.fbo bind];
                glViewport(0, 0, picSize.width, picSize.height);
                glClear(GL_COLOR_BUFFER_BIT);
                IJK_GLES2_Renderer_setGravity(_renderer, _rendererGravity, picSize.width, picSize.height);
                if (!IJK_GLES2_Renderer_resetVao(_renderer))
                    ALOGE("[GL] Renderer_resetVao failed\n");
                
                if (!IJK_GLES2_Renderer_uploadTexture(_renderer, (void *)attach.videoPicture))
                    ALOGE("[GL] Renderer_updateVertex failed\n");
                
                IJK_GLES2_Renderer_drawArrays();
            }
            
            if (containSub) {
                [self doUploadSubtitle:attach viewport:picSize];
            }
            img = [self _snapshotTheContextWithSize:picSize];
        } else {
            ALOGE("[GL] create fbo failed\n");
        }
        [[self openGLContext]flushBuffer];
    }
    CGLUnlockContext([[self openGLContext] CGLContextObj]);
    
    if (outImg && img) {
        *outImg = CGImageRetain(img);
    }
}

- (CGImageRef)_snapshot_origin:(IJKOverlayAttach *)attach
{
    CVPixelBufferRef pixelBuffer = CVPixelBufferRetain(attach.videoPicture);
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
    return imageRef ? (CGImageRef)CFAutorelease(imageRef) : NULL;
}

static CGContextRef _CreateCGBitmapContext(size_t w, size_t h, size_t bpc, size_t bpp, size_t bpr, int bmi)
{
    assert(bpp != 24);
    /*
     AV_PIX_FMT_RGB24 bpp is 24! not supported!
     Crash:
     2020-06-06 00:08:20.245208+0800 FFmpegTutorial[23649:2335631] [Unknown process name] CGBitmapContextCreate: unsupported parameter combination: set CGBITMAP_CONTEXT_LOG_ERRORS environmental variable to see the details
     2020-06-06 00:08:20.245417+0800 FFmpegTutorial[23649:2335631] [Unknown process name] CGBitmapContextCreateImage: invalid context 0x0. If you want to see the backtrace, please set CG_CONTEXT_SHOW_BACKTRACE environmental variable.
     */
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmapContext = CGBitmapContextCreate(
        NULL,
        w,
        h,
        bpc,
        bpr,
        colorSpace,
        bmi
    );
    
    CGColorSpaceRelease(colorSpace);
    if (bitmapContext) {
        return (CGContextRef)CFAutorelease(bitmapContext);
    }
    return NULL;
}

static CGImageRef _FlipCGImage(CGImageRef src)
{
    if (!src) {
        return NULL;
    }
    
    const size_t height = CGImageGetHeight(src);
    const size_t width  = CGImageGetWidth(src);
    const size_t bpc    = CGImageGetBitsPerComponent(src);
    const size_t bpr    = bpc * CGImageGetWidth(src);
    const CGContextRef ctx = _CreateCGBitmapContext(width,
                                              height,
                                              bpc,
                                              CGImageGetBitsPerPixel(src),
                                              bpr,
                                              CGImageGetBitmapInfo(src));
    CGContextTranslateCTM(ctx, 0, height);
    CGContextScaleCTM(ctx, 1.0, -1.0);
    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), src);
    CGImageRef dst = CGBitmapContextCreateImage(ctx);
    return (CGImageRef)CFAutorelease(dst);
}

- (CGImageRef)_snapshotTheContextWithSize:(const CGSize)size
{
    const int height = size.height;
    const int width  = size.width;
    
    GLint bytesPerRow = width * 4;
    const GLint bitsPerPixel = 32;
    CGContextRef ctx = _CreateCGBitmapContext(width, height, 8, 32, bytesPerRow, kCGBitmapByteOrderDefault | kCGImageAlphaNoneSkipLast);
    if (ctx) {
        void * bitmapData = CGBitmapContextGetData(ctx);
        if (bitmapData) {
            glPixelStorei(GL_PACK_ROW_LENGTH, 8 * bytesPerRow / bitsPerPixel);
            glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, bitmapData);
            CGImageRef cgImage = CGBitmapContextCreateImage(ctx);
            if (cgImage) {
                CGImageRef result = _FlipCGImage(cgImage);
                CFRelease(cgImage);
                return result;
            }
        }
    }
    return NULL;
}

- (void)_snapshot_screen:(NSValue *)ptrValue
{
    CGImageRef *outImg = (CGImageRef *)[ptrValue pointerValue];
    if (outImg) {
        *outImg = NULL;
    } else {
        return;
    }
    
    CGRect bounds = [self bounds];
    CGSize size = [self convertSizeToBacking:bounds.size];
    
    if (CGSizeEqualToSize(CGSizeZero, size)) {
        return;
    }
    
    NSOpenGLContext *openGLContext = [self openGLContext];
    if (!openGLContext) {
        return;
    }
    
    CGLLockContext([openGLContext CGLContextObj]);
    [openGLContext makeCurrentContext];
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    CGImageRef img = [self _snapshotTheContextWithSize:size];
    CGLUnlockContext([openGLContext CGLContextObj]);
    
    if (outImg && img) {
        *outImg = CGImageRetain(img);
    }
}

- (CGImageRef)snapshot:(IJKSDLSnapshotType)aType
{
    IJKOverlayAttach *attach = self.currentAttach;
    if (!attach) {
        return NULL;
    }
    
    switch (aType) {
        case IJKSDLSnapshot_Origin:
            return [self _snapshot_origin:attach];
        case IJKSDLSnapshot_Screen:
        {
            CGImageRef reuslt = NULL;
            NSValue * address = [NSValue valueWithPointer:(void *)&reuslt];
            if (@available(macOS 10.13, *)) {
                [self.renderThread performSelector:@selector(_snapshot_screen:)
                                        withTarget:self
                                        withObject:address
                                     waitUntilDone:YES];
            } else {
                [self _snapshot_screen:address];
            }
            return reuslt ? (CGImageRef)CFAutorelease(reuslt) : NULL;
        }
        case IJKSDLSnapshot_Effect_Origin:
        {
            CGImageRef reuslt = NULL;
            NSValue * address = [NSValue valueWithPointer:(void *)&reuslt];
            NSDictionary *params = @{
                @"containSub" : @(NO),
                @"attach" : attach,
                @"outImg" : address
            };
            if (@available(macOS 10.13, *)) {
                [self.renderThread performSelector:@selector(_snapshotEffectOriginWithSubtitle:)
                                        withTarget:self
                                        withObject:params
                                     waitUntilDone:YES];
            } else {
                [self _snapshotEffectOriginWithSubtitle:params];
            }
            return reuslt ? (CGImageRef)CFAutorelease(reuslt) : NULL;
        }
        case IJKSDLSnapshot_Effect_Subtitle_Origin:
        {
            CGImageRef reuslt = NULL;
            NSValue * address = [NSValue valueWithPointer:(void *)&reuslt];
            NSDictionary *params = @{
                @"containSub" : @(YES),
                @"attach" : attach,
                @"outImg" : address
            };
            if (@available(macOS 10.13, *)) {
                [self.renderThread performSelector:@selector(_snapshotEffectOriginWithSubtitle:)
                                        withTarget:self
                                        withObject:params
                                     waitUntilDone:YES];
            } else {
                [self _snapshotEffectOriginWithSubtitle:params];
            }
            return reuslt ? (CGImageRef)CFAutorelease(reuslt) : NULL;
        }
    }
}

#pragma mark - override setter methods

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
        IJK_GLES2_Renderer_setGravity(_renderer, _rendererGravity, self.backingWidth, self.backingHeight);
    }
}

- (void)setRotatePreference:(IJKSDLRotatePreference)rotatePreference
{
    if (_rotatePreference.type != rotatePreference.type || _rotatePreference.degrees != rotatePreference.degrees) {
        _rotatePreference = rotatePreference;
        if (IJK_GLES2_Renderer_isValid(_renderer)) {
            IJK_GLES2_Renderer_updateRotate(_renderer, _rotatePreference.type, _rotatePreference.degrees);
        }
    }
}

- (void)setColorPreference:(IJKSDLColorConversionPreference)colorPreference
{
    if (_colorPreference.brightness != colorPreference.brightness || _colorPreference.saturation != colorPreference.saturation || _colorPreference.contrast != colorPreference.contrast) {
        _colorPreference = colorPreference;
        if (IJK_GLES2_Renderer_isValid(_renderer)) {
            IJK_GLES2_Renderer_updateColorConversion(_renderer, _colorPreference.brightness, _colorPreference.saturation,_colorPreference.contrast);
        }
    }
}

- (void)setDarPreference:(IJKSDLDARPreference)darPreference
{
    if (_darPreference.ratio != darPreference.ratio) {
        _darPreference = darPreference;
        if (IJK_GLES2_Renderer_isValid(_renderer)) {
            IJK_GLES2_Renderer_updateUserDefinedDAR(_renderer, _darPreference.ratio);
        }
    }
}

- (void)setBackgroundColor:(uint8_t)r g:(uint8_t)g b:(uint8_t)b
{
    [[self openGLContext] makeCurrentContext];
    glClearColor(r/255.0, g/255.0, b/255.0, 1.0f);
}

- (id)context
{
    return self.openGLContext;
}

- (NSString *)name
{
    return @"OpenGL";
}

- (NSView *)hitTest:(NSPoint)point
{
    for (NSView *sub in [self subviews]) {
        NSPoint pointInSelf = [self convertPoint:point fromView:self.superview];
        NSPoint pointInSub = [self convertPoint:pointInSelf toView:sub];
        if (NSPointInRect(pointInSub, sub.bounds)) {
            return sub;
        }
    }
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
