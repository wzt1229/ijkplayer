//
//  IJKMetalView.m
//  FFmpegTutorial-macOS
//
//  Created by qianlongxu on 2022/11/22.
//  Copyright © 2022 Matt Reach's Awesome FFmpeg Tutotial. All rights reserved.
//

#import "IJKMetalView.h"
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVUtilities.h>
#import <CoreImage/CIContext.h>
#import <mach/mach_time.h>

// Header shared between C code here, which executes Metal API commands, and .metal files, which
// uses these types as inputs to the shaders.
#import "IJKMetalShaderTypes.h"
#import "IJKMetalRenderer.h"
#import "IJKMetalSubtitlePipeline.h"
#import "IJKMetalOffscreenRendering.h"

#import "ijksdl_vout_ios_gles2.h"
#import "IJKSDLTextureString.h"
#import "IJKMediaPlayback.h"

#if TARGET_OS_IPHONE
typedef CGRect NSRect;
#endif

#define kHDRAnimationCount 90
#define kHDRAnimationDelayCount 20
#define kHDRAnimationMaxCount (kHDRAnimationDelayCount + kHDRAnimationCount)

@interface IJKMetalView ()

// The command queue used to pass commands to the device.
@property (nonatomic, strong) id<MTLCommandQueue>commandQueue;
@property (nonatomic, assign) CVMetalTextureCacheRef pictureTextureCache;
@property (atomic, strong) IJKMetalRenderer *picturePipeline;
@property (atomic, strong) IJKMetalSubtitlePipeline *subPipeline;
@property (nonatomic, strong) IJKMetalOffscreenRendering *offscreenRendering;
@property (atomic, strong) IJKOverlayAttach *currentAttach;
@property(atomic) BOOL subtitlePreferenceChanged;
//display window size / video size
@property(atomic) float displayVideoScale;
//display window size / screen size
@property(atomic) float subtitleExtScale;
//window's backingScaleFactor
@property(atomic) float backingScaleFactor;
@property(assign) int hdrAnimationFrameCount;

@end

@implementation IJKMetalView

@synthesize scalingMode = _scalingMode;
// subtitle preference
@synthesize subtitlePreference = _subtitlePreference;
// rotate preference
@synthesize rotatePreference = _rotatePreference;
// color conversion perference
@synthesize colorPreference = _colorPreference;
// user defined display aspect ratio
@synthesize darPreference = _darPreference;

@synthesize preventDisplay = _preventDisplay;
#if TARGET_OS_IOS
@synthesize scaleFactor = _scaleFactor;
#endif
@synthesize showHdrAnimation = _showHdrAnimation;

- (CGSize)screenSize
{
    static CGSize screenSize;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
    #if TARGET_OS_OSX
        screenSize = [[[NSScreen screens] firstObject]frame].size;
    #else
        screenSize = [[UIScreen mainScreen]bounds].size;
    #endif
    });
    return screenSize;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    CFRelease(_pictureTextureCache);
}

- (BOOL)prepareMetal
{
    _subtitlePreference = (IJKSDLSubtitlePreference){1.0, 0xFFFFFF, 0.1};
    _rotatePreference   = (IJKSDLRotatePreference){IJKSDLRotateNone, 0.0};
    _colorPreference    = (IJKSDLColorConversionPreference){1.0, 1.0, 1.0};
    _darPreference      = (IJKSDLDARPreference){0.0};
    _displayVideoScale  = 1.0;
    _subtitleExtScale = 1.0;
    
    self.device = MTLCreateSystemDefaultDevice();
    if (!self.device) {
        NSLog(@"No Support Metal.");
        return NO;
    }
    
    CVReturn ret = CVMetalTextureCacheCreate(kCFAllocatorDefault, NULL, self.device, NULL, &_pictureTextureCache);
    if (ret != kCVReturnSuccess) {
        NSLog(@"Create MetalTextureCache Failed:%d.",ret);
        self.device = nil;
        return NO;
    }
    //set default bg color.
    [self setBackgroundColor:0 g:0 b:0];
    // Create the command queue
    self.commandQueue = [self.device newCommandQueue];
    self.autoResizeDrawable = YES;
    // important;then use draw method drive rendering.
    self.enableSetNeedsDisplay = NO;
    self.paused = YES;
#if TARGET_OS_OSX
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidEndLiveResize:) name:NSWindowDidEndLiveResizeNotification object:nil];
#endif
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        if (![self prepareMetal]) {
            return nil;
        }
    }
    return self;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        if (![self prepareMetal]) {
            return nil;
        }
    }
    return self;
}

- (void)setShowHdrAnimation:(BOOL)showHdrAnimation
{
    if (_showHdrAnimation != showHdrAnimation) {
        _showHdrAnimation = showHdrAnimation;
        self.hdrAnimationFrameCount = 0;
    }
}

- (void)videoNaturalSizeChanged:(CGSize)size
{
    CGSize viewSize = [self bounds].size;
    self.displayVideoScale = FFMIN(1.0 * viewSize.width / size.width, 1.0 * viewSize.height / size.height);
}

- (void)cleanSubtitle
{
    IJKOverlayAttach * attach = self.currentAttach;
    if (attach && attach.subTexture) {
        attach.sub = nil;
        attach.subTexture = nil;
        [self setNeedsRefreshCurrentPic];
    }
}

- (CGSize)computeNormalizedVerticesRatio:(IJKOverlayAttach *)attach
{
    if (_scalingMode == IJKMPMovieScalingModeFill) {
        return CGSizeMake(1.0, 1.0);
    }
    
    int frameWidth = attach.w;
    int frameHeight = attach.h;
    
    //keep video AVRational
    if (attach.sarNum > 0 && attach.sarDen > 0) {
        frameWidth = 1.0 * attach.sarNum / attach.sarDen * frameWidth;
    }
    
    int zDegrees = 0;
    if (_rotatePreference.type == IJKSDLRotateZ) {
        zDegrees += _rotatePreference.degrees;
    }
    zDegrees += attach.autoZRotate;
    
    float darRatio = self.darPreference.ratio;
    
    CGSize drawableSize = self.drawableSize;
    //when video's z rotate degrees is 90 odd multiple
    if (abs(zDegrees) / 90 % 2 == 1) {
        //need swap user's ratio
        if (darRatio > 0.001) {
            darRatio = 1.0 / darRatio;
        }
        //need swap display size
        int tmp = drawableSize.width;
        drawableSize.width = drawableSize.height;
        drawableSize.height = tmp;
    }
    
    //apply user dar
    if (darRatio > 0.001) {
        if (1.0 * attach.w / attach.h > darRatio) {
            frameHeight = frameWidth * 1.0 / darRatio;
        } else {
            frameWidth = frameHeight * darRatio;
        }
    }
    
    float wRatio = drawableSize.width / frameWidth;
    float hRatio = drawableSize.height / frameHeight;
    float ratio  = 1.0f;
    
    if (_scalingMode == IJKMPMovieScalingModeAspectFit) {
        ratio = FFMIN(wRatio, hRatio);
    } else if (_scalingMode == IJKMPMovieScalingModeAspectFill) {
        ratio = FFMAX(wRatio, hRatio);
    }
    float nW = (frameWidth * ratio / drawableSize.width);
    float nH = (frameHeight * ratio / drawableSize.height);
    return CGSizeMake(nW, nH);
}

- (BOOL)setupSubPipelineIfNeed
{
    if (!self.subPipeline) {
        self.subPipeline = [[IJKMetalSubtitlePipeline alloc] initWithDevice:self.device colorPixelFormat:self.colorPixelFormat];
    }
    
    if ([self.subPipeline createRenderPipelineIfNeed]) {
        return YES;
    } else {
        ALOGI("create RenderPipeline failed.");
        self.subPipeline = nil;
        return NO;
    }
}

- (BOOL)setupPipelineIfNeed:(CVPixelBufferRef)pixelBuffer
{
    if (!pixelBuffer) {
        return NO;
    }
    if (self.picturePipeline) {
        if (![self.picturePipeline matchPixelBuffer:pixelBuffer]) {
            ALOGI("pixel format not match,need rebuild pipeline");
            self.picturePipeline = nil;
        } else {
            return YES;
        }
    }
    self.picturePipeline = [[IJKMetalRenderer alloc] initWithDevice:self.device colorPixelFormat:self.colorPixelFormat];
    if ([self.picturePipeline createRenderPipelineIfNeed:pixelBuffer]) {
        return YES;
    } else {
        ALOGI("create RenderPipeline failed.");
        self.picturePipeline = nil;
        return NO;
    }
}

- (void)encodePicture:(IJKOverlayAttach *)attach
        renderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
             viewport:(CGSize)viewport
                ratio:(CGSize)ratio
        hdrPercentage:(float)hdrPercentage
{
    [self.picturePipeline lock];
    self.picturePipeline.hdrPercentage = hdrPercentage;
    self.picturePipeline.autoZRotateDegrees = attach.autoZRotate;
    self.picturePipeline.rotateType = self.rotatePreference.type;
    self.picturePipeline.rotateDegrees = self.rotatePreference.degrees;
    
    bool applyAdjust = _colorPreference.brightness != 1.0 || _colorPreference.saturation != 1.0 || _colorPreference.contrast != 1.0;
    [self.picturePipeline updateColorAdjustment:(vector_float4){_colorPreference.brightness,_colorPreference.saturation,_colorPreference.contrast,applyAdjust ? 1.0 : 0.0}];
    self.picturePipeline.vertexRatio = ratio;
    
    self.picturePipeline.textureCrop = CGSizeMake(1.0 * (attach.pixelW - attach.w) / attach.pixelW, 1.0 * (attach.pixelH - attach.h) / attach.pixelH);
    
    // Set the region of the drawable to draw into.
    [renderEncoder setViewport:(MTLViewport){0.0, 0.0, viewport.width, viewport.height, -1.0, 1.0}];
    //upload textures
    [self.picturePipeline uploadTextureWithEncoder:renderEncoder
                                          textures:attach.videoTextures];
    [self.picturePipeline unlock];
}

- (void)encodeSubtitle:(id<MTLRenderCommandEncoder>)renderEncoder
              viewport:(CGSize)viewport
               texture:(id)subTexture
                  rect:(CGRect)subRect
{
    [self.subPipeline lock];
    // Set the region of the drawable to draw into.
    [renderEncoder setViewport:(MTLViewport){0.0, 0.0, viewport.width, viewport.height, -1.0, 1.0}];
    //upload textures
    [self.subPipeline uploadTextureWithEncoder:renderEncoder
                                       texture:subTexture
                                          rect:subRect];
    [self.subPipeline unlock];
}

/// Called whenever the view needs to render a frame.
- (void)drawRect:(NSRect)dirtyRect
{
    IJKOverlayAttach * attach = self.currentAttach;
    if (attach.videoTextures.count == 0) {
        return;
    }
    
    if (![self setupPipelineIfNeed:attach.videoPicture]) {
        return;
    }
    
    if (attach.subTexture && ![self setupSubPipelineIfNeed]) {
        return;
    }
    
    CGSize ratio = [self computeNormalizedVerticesRatio:attach];
    
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    
    // Obtain a renderPassDescriptor generated from the view's drawable textures.
    MTLRenderPassDescriptor *renderPassDescriptor = self.currentRenderPassDescriptor;
    //MTLRenderPassDescriptor描述一系列attachments的值，类似GL的FrameBuffer；同时也用来创建MTLRenderCommandEncoder
    if(!renderPassDescriptor) {
        ALOGE("renderPassDescriptor can't be nil");
        return;
    }
    // Create a render command encoder.
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
    [renderEncoder pushDebugGroup:@"encodePicture"];
    
    float hdrPer = 1.0;
    if (self.showHdrAnimation && [self.picturePipeline isHDR]) {
        if (self.hdrAnimationFrameCount == 0) {
            [[NSNotificationCenter defaultCenter] postNotificationName:IJKMoviePlayerHDRAnimationStateChanged object:self userInfo:@{@"state":@(1)}];
        } else if (self.hdrAnimationFrameCount == kHDRAnimationMaxCount) {
            [[NSNotificationCenter defaultCenter] postNotificationName:IJKMoviePlayerHDRAnimationStateChanged object:self userInfo:@{@"state":@(2)}];
        }
        if (self.hdrAnimationFrameCount <= kHDRAnimationMaxCount) {
            self.hdrAnimationFrameCount++;
            if (self.hdrAnimationFrameCount > kHDRAnimationDelayCount) {
                hdrPer = 1.0 * (self.hdrAnimationFrameCount - kHDRAnimationDelayCount) / kHDRAnimationCount;
            } else {
                hdrPer = 0.0;
            }
        }
    }
    CGSize viewport = self.drawableSize;
    [self encodePicture:attach
          renderEncoder:renderEncoder
               viewport:viewport
                  ratio:ratio
          hdrPercentage:hdrPer];
    
    if (attach.subTexture) {
        float subScale = 1.0;
        if (attach.sub.pixels) {
            subScale = self.displayVideoScale * 1.5;
        }
        //保证 Retina 屏幕显示的大小和非 Retina 屏幕上一样大
        /*
         为何，截图时有的乘以 backingScaleFactor ，有的不乘？
         当 viewport 是 retina 之后的像素值时，就需要乘，使得字幕也跟着变大；
         反之，单倍屏上，直接显示就可以了。
         */
        subScale *= self.backingScaleFactor;
        //实现，窗口放大，字幕放大效果
        subScale *= self.subtitleExtScale;
        CGRect rect = [self subTextureTargetRect:attach.subTexture scale:subScale viewport:viewport];
        
        [self encodeSubtitle:renderEncoder
                    viewport:viewport
                     texture:attach.subTexture
                        rect:rect];
    }
    [renderEncoder popDebugGroup];
    [renderEncoder endEncoding];
    // Schedule a present once the framebuffer is complete using the current drawable.
    id <CAMetalDrawable> currentDrawable = self.currentDrawable;
    if (!currentDrawable) {
        ALOGE("wtf?currentDrawable is nil!");
        return;
    }
    [commandBuffer presentDrawable:currentDrawable];
    // Finalize rendering here & push the command buffer to the GPU.
    [commandBuffer commit];
}

- (CGImageRef)_snapshotWithSubtitle:(BOOL)drawSub
{
    IJKOverlayAttach *attach = self.currentAttach;
    
    CVPixelBufferRef pixelBuffer = attach.videoPicture;
    if (!pixelBuffer) {
        return NULL;
    }
    
    if (!self.offscreenRendering) {
        self.offscreenRendering = [IJKMetalOffscreenRendering alloc];
    }
    
    float width  = (float)CVPixelBufferGetWidth(pixelBuffer);
    float height = (float)CVPixelBufferGetHeight(pixelBuffer);
    
    float darRatio = self.darPreference.ratio;
    
    int zDegrees = 0;
    if (_rotatePreference.type == IJKSDLRotateZ) {
        zDegrees += _rotatePreference.degrees;
    }
    zDegrees += attach.autoZRotate;
    //when video's z rotate degrees is 90 odd multiple
    if (abs(zDegrees) / 90 % 2 == 1) {
        int tmp = width;
        width = height;
        height = tmp;
    }
    
    //apply user dar
    if (darRatio > 0.001) {
        if (1.0 * width / height > darRatio) {
            height = width * 1.0 / darRatio;
        } else {
            width = height * darRatio;
        }
    }
    
    CGSize viewport = CGSizeMake(floorf(width), floorf(height));
    
    if (![self setupPipelineIfNeed:attach.videoPicture]) {
        return NULL;
    }
    
    if (drawSub && attach.subTexture && ![self setupSubPipelineIfNeed]) {
        return NULL;
    }
    
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    return [self.offscreenRendering snapshot:viewport device:self.device commandBuffer:commandBuffer doUploadPicture:^(id<MTLRenderCommandEncoder> _Nonnull renderEncoder) {
        
        [self encodePicture:attach
              renderEncoder:renderEncoder
                   viewport:viewport
                      ratio:CGSizeMake(1.0, 1.0)
              hdrPercentage:1.0];
        
        if (drawSub && attach.subTexture) {
            float subScale = 1.0;
            
            if (attach.sub.pixels) {
                subScale = self.displayVideoScale * 1.5;
            }
            
            {
                CGSize screenSize = [self screenSize];
                CGSize viewSize = viewport;
                //当前显示窗口相对屏幕的比例;实际上全屏时是1，非全屏小于1;
                float subtitleExtScale =  FFMIN(1.0 * viewSize.width / screenSize.width, 1.0 * viewSize.height / screenSize.height);
                subScale *= subtitleExtScale;
            }
            
            CGRect rect = [self subTextureTargetRect:attach.subTexture scale:subScale viewport:viewport];
            [self encodeSubtitle:renderEncoder
                        viewport:viewport
                         texture:attach.subTexture
                            rect:rect];
        }
    }];
}

- (CGImageRef)_snapshotOrigin:(IJKOverlayAttach *)attach
{
    CVPixelBufferRef pixelBuffer = CVPixelBufferRetain(attach.videoPicture);
    //[CIImage initWithCVPixelBuffer:options:] failed because its pixel format f420 is not supported.
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    if (!ciImage) {
        return NULL;
    }
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

- (CGImageRef)_snapshotScreen
{
    IJKOverlayAttach *attach = self.currentAttach;
    
    CVPixelBufferRef pixelBuffer = attach.videoPicture;
    if (!pixelBuffer) {
        return NULL;
    }
    
    if (!self.offscreenRendering) {
        self.offscreenRendering = [IJKMetalOffscreenRendering alloc];
    }
    
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    CGSize viewport = self.drawableSize;
    
    if (![self setupPipelineIfNeed:attach.videoPicture]) {
        return NULL;
    }
    
    if (attach.subTexture && ![self setupSubPipelineIfNeed]) {
        return NULL;
    }
    
    return [self.offscreenRendering snapshot:viewport device:self.device commandBuffer:commandBuffer doUploadPicture:^(id<MTLRenderCommandEncoder> _Nonnull renderEncoder) {
        CVPixelBufferRef pixelBuffer = attach.videoPicture;
        if (pixelBuffer) {
            CGSize ratio = [self computeNormalizedVerticesRatio:attach];
            [self encodePicture:attach
                  renderEncoder:renderEncoder
                       viewport:viewport
                          ratio:ratio
                  hdrPercentage:1.0];
        }
        
        if (attach.subTexture) {
            float subScale = 1.0;
            if (attach.sub.pixels) {
                subScale = self.displayVideoScale * 1.5;
            }
            
            float subtitleExtScale = [self computeSubtitleExtSacle];
            subScale *= subtitleExtScale;
            
            //viewport 取的是 retina 相关的，字幕需要等比例放大。
            subScale *= self.backingScaleFactor;
            
            CGRect rect = [self subTextureTargetRect:attach.subTexture scale:subScale viewport:viewport];

            [self encodeSubtitle:renderEncoder
                        viewport:viewport
                         texture:attach.subTexture
                            rect:rect];
        }
    }];
}

- (CGImageRef)snapshot:(IJKSDLSnapshotType)aType
{
    switch (aType) {
        case IJKSDLSnapshot_Origin:
            return [self _snapshotOrigin:self.currentAttach];
        case IJKSDLSnapshot_Screen:
            return [self _snapshotScreen];
        case IJKSDLSnapshot_Effect_Origin:
            return [self _snapshotWithSubtitle:NO];
        case IJKSDLSnapshot_Effect_Subtitle_Origin:
            return [self _snapshotWithSubtitle:YES];
    }
}

- (float)computeSubtitleExtSacle
{
    CGSize screenSize = [self screenSize];
    CGSize viewSize = [self bounds].size;
    //当前显示窗口相对屏幕的比例;实际上全屏时是1，非全屏小于1;
    return FFMIN(1.0 * viewSize.width / screenSize.width, 1.0 * viewSize.height / screenSize.height);
}

- (void)refreshSubtitleExtSacle
{
#if TARGET_OS_IOS
    self.backingScaleFactor = self.backingScaleFactor;
#else
    self.backingScaleFactor = self.window.backingScaleFactor;
#endif
    self.subtitleExtScale = [self computeSubtitleExtSacle];
}

#if TARGET_OS_IOS
- (UIImage *)snapshot
{
    CGImageRef cgImg = [self snapshot:IJKSDLSnapshot_Screen];
    return [[UIImage alloc]initWithCGImage:cgImg];
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    [self refreshSubtitleExtSacle];
}

#else

- (void)windowDidEndLiveResize:(NSNotification *)notifi
{
    [self refreshSubtitleExtSacle];
    if (notifi.object == self.window) {
        [self setNeedsRefreshCurrentPic];
    }
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize
{
    //call super is needed, otherwise some device [self bounds] is not right.
    [super resizeWithOldSuperviewSize:oldSize];
    [self refreshSubtitleExtSacle];
    if (!self.window.inLiveResize) {
        [self setNeedsRefreshCurrentPic];
    }
}

- (void)viewDidChangeBackingProperties
{
    [super viewDidChangeBackingProperties];
    //多显示器间切换，drawable还没来得及自动改变，因此先手动调整好；避免由于viewport不对导致字幕显示过大或过小。
    self.drawableSize = [self convertSizeToBacking:self.bounds.size];
    [self refreshSubtitleExtSacle];
    [self setNeedsRefreshCurrentPic];
}
#endif

- (void)setNeedsRefreshCurrentPic
{
    if (self.subtitlePreferenceChanged) {
        self.subtitlePreferenceChanged = NO;
        [self generateSubTexture:self.currentAttach];
    }
    [self draw];
}

- (CVPixelBufferRef)_generateSubtitlePixel:(NSString *)subtitle videoDegrees:(int)degrees
{
    if (subtitle.length == 0) {
        return NULL;
    }
    
    IJKSDLSubtitlePreference sp = self.subtitlePreference;

    //以800为标准，定义出字幕字体默认大小为30pt
    float scale = 1.0;
    CGSize screenSize = [self screenSize];
    if (degrees / 90 % 2 == 1) {
        scale = screenSize.height / 800.0;
    } else {
        scale = screenSize.width / 800.0;
    }
    //字幕默认配置
    NSMutableDictionary * attributes = [[NSMutableDictionary alloc] init];

    UIFont *subtitleFont = nil;
    if (strlen(sp.name)) {
        subtitleFont = [UIFont fontWithName:[[NSString alloc] initWithUTF8String:sp.name] size:scale * sp.size];
    }
    
    if (!subtitleFont) {
        subtitleFont = [UIFont systemFontOfSize:scale * sp.size];
    }
    [attributes setObject:subtitleFont forKey:NSFontAttributeName];
    [attributes setObject:int2color(sp.color) forKey:NSForegroundColorAttributeName];
    
    IJKSDLTextureString *textureString = [[IJKSDLTextureString alloc] initWithString:subtitle withAttributes:attributes withStrokeColor:int2color(sp.strokeColor) withStrokeSize:sp.strokeSize];
    
    return [textureString createPixelBuffer];
}

- (CVPixelBufferRef)_generateSubtitlePixelFromPicture:(IJKSDLSubtitle*)pict
{
    CVPixelBufferRef pixelBuffer = NULL;
    NSDictionary *options = @{
        (__bridge NSString*)kCVPixelBufferMetalCompatibilityKey : @YES,
        (__bridge NSString*)kCVPixelBufferIOSurfacePropertiesKey : [NSDictionary dictionary]
    };
    
    CVReturn ret = CVPixelBufferCreate(kCFAllocatorDefault, pict.w, pict.h, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)options, &pixelBuffer);
    
    if (ret != kCVReturnSuccess || pixelBuffer == NULL) {
        ALOGE("CVPixelBufferCreate subtitle failed:%d",ret);
        return NULL;
    }
    
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

- (void)generateSubTexture:(IJKOverlayAttach *)attach
{
    CVPixelBufferRef subRef = NULL;
    IJKSDLSubtitle *sub = attach.sub;
    if (sub) {
        if (sub.text.length > 0) {
            subRef = [self _generateSubtitlePixel:sub.text videoDegrees:attach.autoZRotate];
        } else if (sub.pixels != NULL) {
            subRef = [self _generateSubtitlePixelFromPicture:sub];
        }
    }
    attach.subTexture = [[self class] doGenerateSubTexture:subRef device:self.device];
    CVPixelBufferRelease(subRef);
}

mp_format * mp_get_metal_format(uint32_t cvpixfmt);

+ (NSArray<id<MTLTexture>> *)doGenerateTexture:(CVPixelBufferRef)pixelBuffer
                                  textureCache:(CVMetalTextureCacheRef)textureCache
{
    if (!pixelBuffer) {
        return nil;
    }
    
    NSMutableArray *result = [NSMutableArray array];
    
    OSType type = CVPixelBufferGetPixelFormatType(pixelBuffer);
    mp_format *ft = mp_get_metal_format(type);
    
    NSAssert(ft != NULL, @"wrong pixel format type.");
    
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    const bool planar = CVPixelBufferIsPlanar(pixelBuffer);
    const int planes  = (int)CVPixelBufferGetPlaneCount(pixelBuffer);
    assert(planar && planes == ft->planes || ft->planes == 1);
    
    for (int i = 0; i < ft->planes; i++) {
        size_t width  = CVPixelBufferGetWidthOfPlane(pixelBuffer, i);
        size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, i);
        MTLPixelFormat format = ft->formats[i];
        CVMetalTextureRef textureRef = NULL; // CoreVideo的Metal纹理
        CVReturn status = CVMetalTextureCacheCreateTextureFromImage(NULL, textureCache, pixelBuffer, NULL, format, width, height, i, &textureRef);
        if (status == kCVReturnSuccess) {
            id<MTLTexture> texture = CVMetalTextureGetTexture(textureRef); // 转成Metal用的纹理
            if (texture != nil) {
                [result addObject:texture];
            }
            CFRelease(textureRef);
        }
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    return result;
}

+ (id<MTLTexture>)doGenerateSubTexture:(CVPixelBufferRef)pixelBuff
                                device:(id<MTLDevice>)device
{
    if (!pixelBuff) {
        return nil;
    }
    
    OSType type = CVPixelBufferGetPixelFormatType(pixelBuff);
    if (type != kCVPixelFormatType_32BGRA) {
        ALOGE("generate subtitle texture must use 32BGRA pixelBuff");
        return nil;
    }
    
    CVPixelBufferLockBaseAddress(pixelBuff, kCVPixelBufferLock_ReadOnly);
    void *src = CVPixelBufferGetBaseAddress(pixelBuff);
    
    MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];

    // Indicate that each pixel has a blue, green, red, and alpha channel, where each channel is
    // an 8-bit unsigned normalized value (i.e. 0 maps to 0.0 and 255 maps to 1.0)
    textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
    // Set the pixel dimensions of the texture
    
    textureDescriptor.width  = CVPixelBufferGetWidth(pixelBuff);
    textureDescriptor.height = CVPixelBufferGetHeight(pixelBuff);
    
    // Create the texture from the device by using the descriptor
    id<MTLTexture> subTexture = [device newTextureWithDescriptor:textureDescriptor];
    
    MTLRegion region = {
        { 0, 0, 0 },                   // MTLOrigin
        {CVPixelBufferGetWidth(pixelBuff), CVPixelBufferGetHeight(pixelBuff), 1} // MTLSize
    };
    
    NSUInteger bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuff);
    
    [subTexture replaceRegion:region
                   mipmapLevel:0
                     withBytes:src
                   bytesPerRow:bytesPerRow];
    
    CVPixelBufferUnlockBaseAddress(pixelBuff, kCVPixelBufferLock_ReadOnly);
    
    return subTexture;
}

- (CGRect)subTextureTargetRect:(id<MTLTexture>)subTexture
                         scale:(float)scale
                      viewport:(CGSize)viewport
{
    float bottomMargin = self.subtitlePreference.bottomMargin;
    
    //没有这个scale的话，字幕可能会超出画面，位置跟观看时不一致。
    float swidth  = subTexture.width  * scale;
    float sheight = subTexture.height * scale;
    
    float width  = viewport.width;
    float height = viewport.height;
    //转化到 [-1,1] 的区间
    float y = bottomMargin * (height - sheight) / height * 2.0 - 1.0;
    
    if (width != 0 && height != 0) {
        return (CGRect){
            - 1.0 * swidth / width,
            y,
            2.0 * (swidth / width),
            2.0 * (sheight / height)
        };
    }
    return CGRectZero;
}

- (BOOL)displayAttach:(IJKOverlayAttach *)attach
{
    if (!attach) {
        ALOGW("IJKMetalView: overlay is nil\n");
        return NO;
    }
    
    if (self.subtitlePreferenceChanged || self.currentAttach.sub != attach.sub) {
        [self generateSubTexture:attach];
    } else if (self.currentAttach.sub) {
        //reuse the expensive texture.
        attach.subTexture = self.currentAttach.subTexture;
    }
    
    if (self.subtitlePreferenceChanged) {
        self.subtitlePreferenceChanged = NO;
    }
    
    //hold the attach as current.
    self.currentAttach = attach;
    
    if (self.preventDisplay) {
        return YES;
    }
    
    attach.videoTextures = [[self class] doGenerateTexture:attach.videoPicture textureCache:_pictureTextureCache];
    
    //not dispatch to main thread, use current sub thread (ff_vout) draw
    [self draw];
    
    return YES;
}

#pragma mark - override setter methods

- (void)setScalingMode:(IJKMPMovieScalingMode)scalingMode
{
    if (_scalingMode != scalingMode) {
        _scalingMode = scalingMode;
    }
}

- (void)setRotatePreference:(IJKSDLRotatePreference)rotatePreference
{
    if (_rotatePreference.type != rotatePreference.type || _rotatePreference.degrees != rotatePreference.degrees) {
        _rotatePreference = rotatePreference;
    }
}

- (void)setColorPreference:(IJKSDLColorConversionPreference)colorPreference
{
    if (_colorPreference.brightness != colorPreference.brightness || _colorPreference.saturation != colorPreference.saturation || _colorPreference.contrast != colorPreference.contrast) {
        _colorPreference = colorPreference;
    }
}

- (void)setDarPreference:(IJKSDLDARPreference)darPreference
{
    if (_darPreference.ratio != darPreference.ratio) {
        _darPreference = darPreference;
    }
}

- (void)setSubtitlePreference:(IJKSDLSubtitlePreference)subtitlePreference
{
    if (!isIJKSDLSubtitlePreferenceEqual(&_subtitlePreference, &subtitlePreference)) {
        _subtitlePreference = subtitlePreference;
        self.subtitlePreferenceChanged = YES;
    }
}

- (void)setBackgroundColor:(uint8_t)r g:(uint8_t)g b:(uint8_t)b
{
    self.clearColor = (MTLClearColor){r/255.0, g/255.0, b/255.0, 1.0f};
    //renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0f);
}

- (NSString *)name
{
    return @"Metal";
}

#if TARGET_OS_OSX

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
#else
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
    return NO;
}
#endif

@end
