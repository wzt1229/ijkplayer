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
#import "ijksdl_vout_overlay_videotoolbox.h"
#import "ijksdl_vout_ios_gles2.h"
#import "IJKSDLTextureString.h"
#import "IJKMediaPlayback.h"
#import "IJKSDLThread.h"

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

@interface _IJKSDLGLViewAttach : NSObject

@property(atomic) CVPixelBufferRef currentVideoPic;
@property(atomic) CVPixelBufferRef currentSubtitle;

@property(nonatomic) int  sar_num;
@property(nonatomic) int  sar_den;
@property(nonatomic) Uint32 overlayFormat;
@property(nonatomic) Uint32 ffFormat;
@property(nonatomic) int zRotateDegrees;
@property(nonatomic) int overlayH;
@property(nonatomic) int overlayW;
@property(nonatomic) int bufferW;
@property(nonatomic) IJKSDLSubtitle *sub;

@end

@implementation _IJKSDLGLViewAttach

- (void)dealloc
{
    if (self.currentVideoPic) {
        CVPixelBufferRelease(self.currentVideoPic);
        self.currentVideoPic = NULL;
    }
    
    if (self.currentSubtitle) {
        CVPixelBufferRelease(self.currentSubtitle);
        self.currentSubtitle = NULL;
    }
}

@end

//for snapshot.

@interface _IJKSDLFBO : NSObject

@property(nonatomic) CGSize textureSize;
@property(nonatomic) GLuint fbo;
@property(nonatomic) GLuint colorTexture;

@end

@implementation _IJKSDLFBO

- (void)dealloc
{
    if (_fbo) {
        glDeleteFramebuffers(1, &_fbo);
    }
    
    if (_colorTexture) {
        glDeleteFramebuffers(1, &_colorTexture);
    }
    
    _textureSize = CGSizeZero;
}

// Create texture and framebuffer objects to render and snapshot.
- (BOOL)canReuse:(CGSize)size
{
    if (CGSizeEqualToSize(CGSizeZero, size)) {
        return NO;
    }
    
    if (CGSizeEqualToSize(_textureSize, size) && _fbo && _colorTexture) {
        return YES;
    } else {
        return NO;
    }
}

- (instancetype)initWithSize:(CGSize)size
{
    self = [super init];
    if (self) {
        // Create a texture object that you apply to the model.
        glGenTextures(1, &_colorTexture);
        glBindTexture(GL_TEXTURE_2D, _colorTexture);

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
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, _colorTexture, 0);

        if (glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE) {
            _textureSize = size;
            return self;
        } else {
        #if DEBUG
            NSAssert(NO, @"Failed to make complete framebuffer object %x.",  glCheckFramebufferStatus(GL_FRAMEBUFFER));
        #endif
            _textureSize = CGSizeZero;
            return nil;
        }
    }
    return nil;
}

- (void)bind
{
    // Bind the snapshot FBO and render the scene.
    glBindFramebuffer(GL_FRAMEBUFFER, _fbo);
}

@end

@interface IJKSDLGLView()

@property(atomic) _IJKSDLGLViewAttach *currentAttach;

@property(nonatomic) NSInteger videoDegrees;
@property(nonatomic) CGSize videoNaturalSize;
//display window size / screen
@property(atomic) float displayScreenScale;
//display window size / video size
@property(atomic) float displayVideoScale;
@property(atomic) GLint backingWidth;
@property(atomic) GLint backingHeight;
@property(atomic) BOOL subtitlePreferenceChanged;
@property(atomic) _IJKSDLFBO * fbo;
@property(atomic) IJKSDLThread *renderThread;

@end

@implementation IJKSDLGLView
{
    IJK_GLES2_Renderer *_renderer;
    int    _rendererGravity;
}

@synthesize scalingMode = _scalingMode;
@synthesize isThirdGLView = _isThirdGLView;
// subtitle preference
@synthesize subtitlePreference = _subtitlePreference;
// rotate preference
@synthesize rotatePreference = _rotatePreference;
// color conversion perference
@synthesize colorPreference = _colorPreference;
// user defined display aspect ratio
@synthesize darPreference = _darPreference;
@synthesize preventDisplay;

- (void)dealloc
{
    [self.renderThread performSelector:@selector(setFbo:)
                            withTarget:self
                            withObject:nil
                         waitUntilDone:YES];
    
    if (_renderer) {
        IJK_GLES2_Renderer_freeP(&_renderer);
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
        if (_is_need_dispath_to_global()) {
            self.renderThread = _globalThread_();
        } else {
            self.renderThread = [[IJKSDLThread alloc] initWithName:@"ijk_renderer"];
            [self.renderThread start];
        }
        [self setup];
        _subtitlePreference = (IJKSDLSubtitlePreference){1.0, 0xFFFFFF, 0.1};
        _rotatePreference   = (IJKSDLRotatePreference){IJKSDLRotateNone, 0.0};
        _colorPreference    = (IJKSDLColorConversionPreference){1.0, 1.0, 1.0};
        _darPreference      = (IJKSDLDARPreference){0.0};
        _displayScreenScale = 1.0;
        _displayVideoScale  = 1.0;
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
    
    ///Fix the default red background color on the Intel platform
    [[self openGLContext] makeCurrentContext];
    glClear(GL_COLOR_BUFFER_BIT);
    [[self openGLContext]flushBuffer];
}

- (void)videoZRotateDegrees:(NSInteger)degrees
{
    self.videoDegrees = degrees;
}

- (void)videoNaturalSizeChanged:(CGSize)size
{
    self.videoNaturalSize = size;
    CGRect viewBounds = [self bounds];
    if (!CGSizeEqualToSize(CGSizeZero, self.videoNaturalSize)) {
        self.displayVideoScale = FFMIN(1.0 * viewBounds.size.width / self.videoNaturalSize.width, 1.0 * viewBounds.size.height / self.videoNaturalSize.height);
    }
}

- (BOOL)setupRendererIfNeed:(_IJKSDLGLViewAttach *)attach
{
    if (!IJK_GLES2_Renderer_isValid(_renderer) ||
        !IJK_GLES2_Renderer_isFormat(_renderer, attach.overlayFormat)) {
        
        IJK_GLES2_Renderer_reset(_renderer);
        IJK_GLES2_Renderer_freeP(&_renderer);
        int openglVer = 330;
    #if USE_LEGACY_OPENGL
        openglVer = 120;
    #endif
        
        _renderer = IJK_GLES2_Renderer_create2(attach.overlayFormat,attach.ffFormat,openglVer);
        if (!IJK_GLES2_Renderer_isValid(_renderer))
            return NO;
        
        if (!IJK_GLES2_Renderer_use(_renderer))
            return NO;
        
        IJK_GLES2_Renderer_setGravity(_renderer, _rendererGravity, self.backingWidth, self.backingHeight);
        
        IJK_GLES2_Renderer_updateRotate(_renderer, _rotatePreference.type, _rotatePreference.degrees);
        
        IJK_GLES2_Renderer_updateAutoZRotate(_renderer, attach.zRotateDegrees);
        
        IJK_GLES2_Renderer_updateSubtitleBottomMargin(_renderer, _subtitlePreference.bottomMargin);
        
        IJK_GLES2_Renderer_updateColorConversion(_renderer, _colorPreference.brightness, _colorPreference.saturation,_colorPreference.contrast);
        
        IJK_GLES2_Renderer_updateUserDefinedDAR(_renderer, _darPreference.ratio);
    }
    return YES;
}

- (void)setFrame:(NSRect)frame
{
    [super setFrame:frame];
}

- (void)layout
{
    [super layout];
    [self resetViewPort];
}

- (void)reshape
{
    [super reshape];
    [self resetViewPort];
}

- (void)resetViewPort
{
    CGSize viewSize = [self bounds].size;
    CGSize viewSizePixels = [self convertSizeToBacking:viewSize];
    
    if (self.backingWidth != viewSizePixels.width || self.backingHeight != viewSizePixels.height) {
        self.backingWidth  = viewSizePixels.width;
        self.backingHeight = viewSizePixels.height;
        
        CGSize screenSize = [[NSScreen mainScreen]frame].size;
        self.displayScreenScale = FFMIN(1.0 * viewSize.width / screenSize.width,1.0 * viewSize.height / screenSize.height);
        if (!CGSizeEqualToSize(CGSizeZero, self.videoNaturalSize)) {
            self.displayVideoScale = FFMIN(1.0 * viewSize.width / self.videoNaturalSize.width,1.0 * viewSize.height / self.videoNaturalSize.height);
        }
        
        if (IJK_GLES2_Renderer_isValid(_renderer)) {
            IJK_GLES2_Renderer_setGravity(_renderer, _rendererGravity, self.backingWidth, self.backingHeight);
        }
    }
}

- (void)viewDidChangeBackingProperties
{
    [super viewDidChangeBackingProperties];
    [self resetViewPort];
}

- (CVPixelBufferRef)_generateSubtitlePixel:(NSString *)subtitle
{
    if (subtitle.length == 0) {
        return NULL;
    }
    
    IJKSDLSubtitlePreference sp = self.subtitlePreference;
        
    float ratio = sp.ratio;
    int32_t bgrValue = sp.color;
    //以800为标准，定义出字幕字体默认大小为30pt
    float scale = 1.0;
    CGSize screenSize = [[NSScreen mainScreen]frame].size;
    
    NSInteger degrees = self.videoDegrees;
    if (degrees / 90 % 2 == 1) {
        scale = screenSize.height / 800.0;
    } else {
        scale = screenSize.width / 800.0;
    }
    //字幕默认配置
    NSMutableDictionary * attributes = [[NSMutableDictionary alloc] init];
    
    UIFont *subtitleFont = [UIFont systemFontOfSize:ratio * scale * 60];
    [attributes setObject:subtitleFont forKey:NSFontAttributeName];
    
    NSColor *subtitleColor = [NSColor colorWithRed:((float)(bgrValue & 0xFF)) / 255.0 green:((float)((bgrValue & 0xFF00) >> 8)) / 255.0 blue:(float)(((bgrValue & 0xFF0000) >> 16)) / 255.0 alpha:1.0];
    
    [attributes setObject:subtitleColor forKey:NSForegroundColorAttributeName];
    
    IJKSDLTextureString *textureString = [[IJKSDLTextureString alloc] initWithString:subtitle withAttributes:attributes];
    
    return [textureString createPixelBuffer];
}

- (CVPixelBufferRef)_generateSubtitlePixelFromPicture:(IJKSDLSubtitle*)pict
{
    CVPixelBufferRef pixelBuffer = NULL;
    NSDictionary *options = @{
        (__bridge NSString*)kCVPixelBufferOpenGLCompatibilityKey : @YES,
        (__bridge NSString*)kCVPixelBufferIOSurfacePropertiesKey : [NSDictionary dictionary]
    };
    
    CVReturn ret = CVPixelBufferCreate(kCFAllocatorDefault, pict.w, pict.h, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)options, &pixelBuffer);
    
    NSParameterAssert(ret == kCVReturnSuccess && pixelBuffer != NULL);
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    uint8_t *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    int linesize = (int)CVPixelBufferGetBytesPerRow(pixelBuffer);

    uint8_t *dst_data[4] = {baseAddress,NULL,NULL,NULL};
    int dst_linesizes[4] = {linesize,0,0,0};

    const uint8_t *src_data[4] = {pict.pixels,NULL,NULL,NULL};
    const int src_linesizes[4] = {pict.w * 4,0,0,0};

    av_image_copy(dst_data, dst_linesizes, src_data, src_linesizes, AV_PIX_FMT_BGRA, pict.w, pict.h);
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    if (kCVReturnSuccess == ret) {
        return pixelBuffer;
    } else {
        return NULL;
    }
}

- (void)doUploadSubtitle:(_IJKSDLGLViewAttach *)attach
{
    if (attach.currentSubtitle) {
        float ratio = 1.0;
        if (attach.sub.pixels) {
            ratio = self.subtitlePreference.ratio * self.displayVideoScale * 1.5;
        } else {
            //for text subtitle scale display_scale.
            ratio *= self.displayScreenScale;
        }
        
        IJK_GLES2_Renderer_beginDrawSubtitle(_renderer);
        IJK_GLES2_Renderer_updateSubtitleVetex(_renderer, ratio * CVPixelBufferGetWidth(attach.currentSubtitle), ratio * CVPixelBufferGetHeight(attach.currentSubtitle));
        if (IJK_GLES2_Renderer_uploadSubtitleTexture(_renderer, (void *)attach.currentSubtitle)) {
            IJK_GLES2_Renderer_drawArrays();
        } else {
            ALOGE("[GL] GLES2 Render Subtitle failed\n");
        }
        IJK_GLES2_Renderer_endDrawSubtitle(_renderer);
    }
}

- (void)doUploadVideoPicture:(_IJKSDLGLViewAttach *)attach
{
    if (attach.currentVideoPic) {
        if (IJK_GLES2_Renderer_updateVetex2(_renderer, attach.overlayH, attach.overlayW, attach.bufferW, attach.sar_num, attach.sar_den)) {
            if (IJK_GLES2_Renderer_uploadTexture(_renderer, (void *)attach.currentVideoPic)) {
                IJK_GLES2_Renderer_drawArrays();
            } else {
                ALOGE("[GL] Renderer_updateVetex failed\n");
            }
        } else {
            ALOGE("[GL] Renderer_updateVetex failed\n");
        }
    }
}

- (void)doRefreshCurrentAttach:(_IJKSDLGLViewAttach *)currentAttach
{
    if (!currentAttach) {
        return;
    }
    
    //update subtitle if need
    if (self.subtitlePreferenceChanged) {
        if (currentAttach.sub.text) {
            if (currentAttach.currentSubtitle) {
                CVPixelBufferRelease(currentAttach.currentSubtitle);
                currentAttach.currentSubtitle = NULL;
            }
            currentAttach.currentSubtitle = [self _generateSubtitlePixel:currentAttach.sub.text];
        }
        self.subtitlePreferenceChanged = NO;
    }
    
    [self doDisplayVideoPicAndSubtitle:currentAttach];
}

- (void)doDisplayVideoPicAndSubtitle:(_IJKSDLGLViewAttach *)attach
{
    if (!attach) {
        return;
    }
    
    CGLLockContext([[self openGLContext] CGLContextObj]);
    [[self openGLContext] makeCurrentContext];
    [self setupRendererIfNeed:attach];
    
    if (IJK_GLES2_Renderer_isValid(_renderer)) {
        // Bind the FBO to screen.
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(0, 0, self.backingWidth, self.backingHeight);
        glClear(GL_COLOR_BUFFER_BIT);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        
        //for video
        [self doUploadVideoPicture:attach];
        //for subtitle
        [self doUploadSubtitle:attach];
    } else {
        ALOGW("IJKSDLGLView: Renderer not ok.\n");
    }
    
    [[self openGLContext]flushBuffer];
    CGLUnlockContext([[self openGLContext] CGLContextObj]);
}

- (void)setNeedsRefreshCurrentPic
{
    //use single global thread!
    [self.renderThread performSelector:@selector(doRefreshCurrentAttach:)
                            withTarget:self
                            withObject:self.currentAttach
                         waitUntilDone:NO];
}

- (void)display:(SDL_VoutOverlay *)overlay subtitle:(IJKSDLSubtitle *)sub
{
    if (!overlay) {
        ALOGW("IJKSDLGLView: overlay is nil\n");
        return;
    }
    
    //overlay is not thread safe, maybe need dispatch from sub thread to main thread,so hold overlay's property to GLView.
    Uint32 overlay_format = overlay->format;
    Uint32 ff_format;
    if (SDL_FCC__VTB == overlay_format) {
        ff_format = overlay->ff_format;
    }
    #if USE_FF_VTB
    else if (SDL_FCC__FFVTB == overlay_format) {
        ff_format = overlay->cv_format;
    }
    #endif
    else {
        ff_format = 0;
        NSAssert(NO, @"wtf?");
    }
    
    _IJKSDLGLViewAttach *attach = [[_IJKSDLGLViewAttach alloc] init];
    
    attach.ffFormat = ff_format;
    attach.overlayFormat = overlay_format;
    attach.zRotateDegrees = overlay->auto_z_rotate_degrees;
    attach.overlayW = overlay->w;
    attach.overlayH = overlay->h;
    attach.bufferW = SDL_VoutGetBufferWidth(overlay);
    //update video sar.
    if (overlay->sar_num > 0 && overlay->sar_den > 0) {
        attach.sar_num = overlay->sar_num;
        attach.sar_den = overlay->sar_den;
    }
    
    CVPixelBufferRef videoPic = SDL_Overlay_getCVPixelBufferRef(overlay);
    attach.currentVideoPic = CVPixelBufferRetain(videoPic);
    
    //generate current subtitle.
    CVPixelBufferRef subRef = NULL;
    if (sub.text.length > 0) {
        subRef = [self _generateSubtitlePixel:sub.text];
    } else if (sub.pixels != NULL) {
        subRef = [self _generateSubtitlePixelFromPicture:sub];
    }
    attach.sub = sub;
    attach.currentSubtitle = subRef;
    
    if (self.subtitlePreferenceChanged) {
        self.subtitlePreferenceChanged = NO;
    }
    //hold the attach as current.
    self.currentAttach = attach;
    
    if (self.preventDisplay) {
        return;
    }
    
    [self.renderThread performSelector:@selector(doDisplayVideoPicAndSubtitle:)
                            withTarget:self
                            withObject:attach
                         waitUntilDone:NO];
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

- (void)windowWillClose:(NSNotification*)notification
{
    // Stop the display link when the window is closing because default
    // OpenGL render buffers will be destroyed.  If display link continues to
    // fire without renderbuffers, OpenGL draw calls will set errors.
    // todo
}

#pragma mark - for snapshot

- (void)_snapshotEffectOriginWithSubtitle:(NSDictionary *)params
{
    BOOL containSub = [params[@"containSub"] boolValue];
    _IJKSDLGLViewAttach * attach = params[@"attach"];
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
        if (attach.sar_num > 0 && attach.sar_den > 0) {
            videoSar = 1.0 * attach.sar_num / attach.sar_den;
        }
        CGSize picSize = CGSizeMake(CVPixelBufferGetWidth(attach.currentVideoPic) * videoSar, CVPixelBufferGetHeight(attach.currentVideoPic));
        //视频带有旋转 90 度倍数时需要将显示宽高交换后计算
        if (IJK_GLES2_Renderer_isZRotate90oddMultiple(_renderer)) {
            float pic_width = picSize.width;
            float pic_height = picSize.height;
            float tmp = pic_width;
            pic_width = pic_height;
            pic_height = tmp;
            picSize = CGSizeMake(pic_width, pic_height);
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
            self.fbo = [[_IJKSDLFBO alloc] initWithSize:picSize];
        }
        
        if (self.fbo) {
            if (attach.currentVideoPic) {
                [self.fbo bind];
                glViewport(0, 0, picSize.width, picSize.height);
                glClear(GL_COLOR_BUFFER_BIT);
                
                if (!IJK_GLES2_Renderer_resetVao(_renderer))
                    ALOGE("[GL] Renderer_resetVao failed\n");
                
                if (!IJK_GLES2_Renderer_uploadTexture(_renderer, (void *)attach.currentVideoPic))
                    ALOGE("[GL] Renderer_updateVetex failed\n");
                
                IJK_GLES2_Renderer_drawArrays();
            }
            
            if (containSub) {
                [self doUploadSubtitle:attach];
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

- (CGImageRef)_snapshot_origin:(_IJKSDLGLViewAttach *)attach
{
    CVPixelBufferRef pixelBuffer = CVPixelBufferRetain(attach.currentVideoPic);
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
    CGContextRef ctx = _CreateCGBitmapContext(width, height, 8, 32, bytesPerRow, kCGBitmapByteOrderDefault |kCGImageAlphaNoneSkipLast);
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
    CGImageRef img = [self _snapshotTheContextWithSize:size];
    CGLUnlockContext([openGLContext CGLContextObj]);
    
    if (outImg && img) {
        *outImg = CGImageRetain(img);
    }
}

- (CGImageRef)snapshot:(IJKSDLSnapshotType)aType
{
    _IJKSDLGLViewAttach *attach = self.currentAttach;
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
            [self.renderThread performSelector:@selector(_snapshot_screen:)
                                    withTarget:self
                                    withObject:address
                                 waitUntilDone:YES];
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
            [self.renderThread performSelector:@selector(_snapshotEffectOriginWithSubtitle:)
                                    withTarget:self
                                    withObject:params
                                 waitUntilDone:YES];
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
            [self.renderThread performSelector:@selector(_snapshotEffectOriginWithSubtitle:)
                                    withTarget:self
                                    withObject:params
                                 waitUntilDone:YES];
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

- (void)setSubtitlePreference:(IJKSDLSubtitlePreference)subtitlePreference
{
    if (_subtitlePreference.bottomMargin != subtitlePreference.bottomMargin) {
        _subtitlePreference = subtitlePreference;
        if (IJK_GLES2_Renderer_isValid(_renderer)) {
            IJK_GLES2_Renderer_updateSubtitleBottomMargin(_renderer, _subtitlePreference.bottomMargin);
        }
    }
    
    if (_subtitlePreference.ratio != subtitlePreference.ratio || _subtitlePreference.color != subtitlePreference.color) {
        _subtitlePreference = subtitlePreference;
        self.subtitlePreferenceChanged = YES;
    }
}

- (void)setBackgroundColor:(uint8_t)r g:(uint8_t)g b:(uint8_t)b
{
    [[self openGLContext] makeCurrentContext];
    glClearColor(r/255.0, g/255.0, b/255.0, 1.0f);
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
