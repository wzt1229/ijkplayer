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
#import "IJKMetalBGRAPipeline.h"
#import "IJKMetalNV12Pipeline.h"
#import "IJKMetalYUV420PPipeline.h"
#import "IJKMetalUYVY422Pipeline.h"
#import "IJKMetalYUYV422Pipeline.h"
#import "IJKMetalSubtitlePipeline.h"
#import "IJKMetalOffscreenRendering.h"

#import "ijksdl_vout_ios_gles2.h"
#import "IJKSDLTextureString.h"
#import "IJKMediaPlayback.h"

@interface IJKMetalView ()

// The command queue used to pass commands to the device.
@property (nonatomic, strong) id<MTLCommandQueue>commandQueue;
@property (nonatomic, assign) CVMetalTextureCacheRef pictureTextureCache;
@property (atomic, strong) __kindof IJKMetalBasePipeline *picturePipeline;
@property (atomic, strong) IJKMetalSubtitlePipeline *subPipeline;
@property (nonatomic, strong) IJKMetalOffscreenRendering *offscreenRendering;
@property (atomic, strong) IJKOverlayAttach *currentAttach;
@property(atomic) BOOL subtitlePreferenceChanged;
//display window size / video size
@property(atomic) float displayVideoScale;
//display window size / screen size
@property(atomic) float displayScreenScale;

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
@synthesize scaleFactor                = _scaleFactor;
#endif

- (void)dealloc
{
    CFRelease(_pictureTextureCache);
}

- (BOOL)prepareMetal
{
    _subtitlePreference = (IJKSDLSubtitlePreference){1.0, 0xFFFFFF, 0.1};
    _rotatePreference   = (IJKSDLRotatePreference){IJKSDLRotateNone, 0.0};
    _colorPreference    = (IJKSDLColorConversionPreference){1.0, 1.0, 1.0};
    _darPreference      = (IJKSDLDARPreference){0.0};
    _displayVideoScale  = 1.0;
    _displayScreenScale = 1.0;
    
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

#if TARGET_OS_IPHONE
typedef CGRect NSRect;
#endif

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

- (void)videoNaturalSizeChanged:(CGSize)size
{
    CGSize viewSize = [self bounds].size;
    self.displayVideoScale = FFMIN(1.0 * viewSize.width / size.width, 1.0 * viewSize.height / size.height);
#if TARGET_OS_OSX
    CGSize screenSize = [[NSScreen mainScreen]frame].size;
#else
    CGSize screenSize = [[UIScreen mainScreen]bounds].size;
#endif
    self.displayScreenScale = FFMIN(1.0 * viewSize.width / screenSize.width, 1.0 * viewSize.height / screenSize.height);
}

- (void)cleanSubtitle
{
    IJKOverlayAttach * attach = self.currentAttach;
    if (attach && attach.sub) {
        self.currentAttach.sub = nil;
        if (attach.subPicture) {
            CVPixelBufferRelease(attach.subPicture);
            self.currentAttach.subPicture = NULL;
        }
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

- (Class)pipelineClass:(CVPixelBufferRef)pixelBuffer
{
    if (!pixelBuffer) {
        return NULL;
    }
    Class clazz = NULL;
    OSType type = CVPixelBufferGetPixelFormatType(pixelBuffer);
    if (type == kCVPixelFormatType_32BGRA) {
        clazz = [IJKMetalBGRAPipeline class];
    } else if (type == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || type ==  kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
        clazz = [IJKMetalNV12Pipeline class];
    } else if (type == kCVPixelFormatType_420YpCbCr8PlanarFullRange || type == kCVPixelFormatType_420YpCbCr8Planar) {
        clazz = [IJKMetalYUV420PPipeline class];
    } else if (type == kCVPixelFormatType_422YpCbCr8) {
        clazz = [IJKMetalUYVY422Pipeline class];
    } else if (type == kCVPixelFormatType_422YpCbCr8FullRange || type == kCVPixelFormatType_422YpCbCr8_yuvs) {
        clazz = [IJKMetalYUYV422Pipeline class];
    } else {
        NSAssert(NO, @"no suopport pixel:%d",type);
    }
    //    Y'0 Cb Y'1 Cr kCVPixelFormatType_422YpCbCr8_yuvs
    //    Y'0 Cb Y'1 Cr kCVPixelFormatType_422YpCbCr8FullRange
    //    Cb Y'0 Cr Y'1 kCVPixelFormatType_422YpCbCr8
    
    return clazz;
}

- (BOOL)setupSubPipelineIfNeed:(CVPixelBufferRef)pixelBuffer
{
    if (!pixelBuffer) {
        return NO;
    }
    
    OSType type = CVPixelBufferGetPixelFormatType(pixelBuffer);
    if (type != kCVPixelFormatType_32BGRA) {
        return NO;
    }
    
    if (!self.subPipeline) {
        self.subPipeline = [[IJKMetalSubtitlePipeline alloc] initWithDevice:self.device colorPixelFormat:self.colorPixelFormat];
    }
    return !!self.subPipeline;
}

- (BOOL)setupPipelineIfNeed:(CVPixelBufferRef)pixelBuffer
{
    if (!pixelBuffer) {
        return NO;
    }
    Class clazz = [self pipelineClass:pixelBuffer];
    
    if (clazz) {
        if (self.picturePipeline) {
            if ([self.picturePipeline class] != clazz) {
                NSLog(@"pixel format changed:%@",NSStringFromClass(clazz));
                self.picturePipeline = nil;
            } else {
                return YES;
            }
        }
        self.picturePipeline = [[clazz alloc] initWithDevice:self.device colorPixelFormat:self.colorPixelFormat];
        return !!self.picturePipeline;
    }
    return NO;
}

- (void)encoderPicture:(IJKOverlayAttach *)attach
         renderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
              viewport:(CGSize)viewport
                 ratio:(CGSize)ratio
{
    // Set the region of the drawable to draw into.
    [renderEncoder setViewport:(MTLViewport){0.0, 0.0, viewport.width, viewport.height, -1.0, 1.0}];
    
    CVPixelBufferRef pixelBuffer = attach.videoPicture;
    
    if ([self setupPipelineIfNeed:pixelBuffer]) {
        [self.picturePipeline lock];
        self.picturePipeline.viewport = viewport;
        self.picturePipeline.autoZRotateDegrees = attach.autoZRotate;
        self.picturePipeline.rotateType = self.rotatePreference.type;
        self.picturePipeline.rotateDegrees = self.rotatePreference.degrees;
        
        bool applyAdjust = _colorPreference.brightness != 1.0 || _colorPreference.saturation != 1.0 || _colorPreference.contrast != 1.0;
        [self.picturePipeline updateColorAdjustment:(vector_float4){_colorPreference.brightness,_colorPreference.saturation,_colorPreference.contrast,applyAdjust ? 1.0 : 0.0}];
        self.picturePipeline.vertexRatio = ratio;
        
        self.picturePipeline.textureCrop = CGSizeMake(1.0 * (CVPixelBufferGetWidth(pixelBuffer) - attach.w) / CVPixelBufferGetWidth(pixelBuffer), 1.0 * (CVPixelBufferGetHeight(pixelBuffer) - attach.h) / CVPixelBufferGetHeight(pixelBuffer));
        //upload textures
        [self.picturePipeline uploadTextureWithEncoder:renderEncoder
                                                buffer:pixelBuffer
                                          textureCache:_pictureTextureCache];
        [self.picturePipeline unlock];
    }
}

- (BOOL)encoderSubtitle:(CVPixelBufferRef)pixelBuffer
          renderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               viewport:(CGSize)viewport
                  scale:(float)scale
{
    if (!pixelBuffer) {
        return NO;
    }
    // Set the region of the drawable to draw into.
    [renderEncoder setViewport:(MTLViewport){0.0, 0.0, viewport.width, viewport.height, -1.0, 1.0}];
    
    if ([self setupSubPipelineIfNeed:pixelBuffer]) {
        [self.subPipeline lock];
        self.subPipeline.viewport = viewport;
        self.subPipeline.scale = scale;
        self.subPipeline.subtitleBottomMargin = self.subtitlePreference.bottomMargin;
        //upload textures
        [self.subPipeline uploadTextureWithEncoder:renderEncoder
                                            buffer:pixelBuffer];
        [self.subPipeline unlock];
    }
    return YES;
}

/// Called whenever the view needs to render a frame.
- (void)drawRect:(NSRect)dirtyRect
{
    IJKOverlayAttach * attach = self.currentAttach;
    // Obtain a renderPassDescriptor generated from the view's drawable textures.
    MTLRenderPassDescriptor *renderPassDescriptor = self.currentRenderPassDescriptor;
    //MTLRenderPassDescriptor描述一系列attachments的值，类似GL的FrameBuffer；同时也用来创建MTLRenderCommandEncoder
    if(!renderPassDescriptor) {
        return;
    }
    
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    
    // Create a render command encoder.
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    {
        CVPixelBufferRef pixelBuffer = attach.videoPicture;
        if (pixelBuffer) {
            CGSize ratio = [self computeNormalizedVerticesRatio:attach];
            [self encoderPicture:attach
                   renderEncoder:renderEncoder
                        viewport:self.drawableSize
                           ratio:ratio];
        }
        
        if (attach.sub) {
            float ratio = 1.0;
            if (attach.sub.pixels) {
                ratio = self.subtitlePreference.ratio * self.displayVideoScale * 1.5;
            } else {
                //for text subtitle scale display_scale.
                ratio *= self.displayScreenScale;
            }
            [self encoderSubtitle:attach.subPicture
                    renderEncoder:renderEncoder
                         viewport:self.drawableSize
                            scale:ratio];
        }
    }
    
    [renderEncoder endEncoding];
    // Schedule a present once the framebuffer is complete using the current drawable.
    [commandBuffer presentDrawable:self.currentDrawable];
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
    
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    float width  = (float)CVPixelBufferGetWidth(pixelBuffer);
    float height = (float)CVPixelBufferGetHeight(pixelBuffer);
    
    //keep video AVRational
    if (attach.sarNum > 0 && attach.sarDen > 0) {
        width = 1.0 * attach.sarNum / attach.sarDen * width;
    }
    CGSize ratio = [self computeNormalizedVerticesRatio:attach];
    float scale = width / (ratio.width * self.drawableSize.width);
    float subScale = 1.0;
    
    if (attach.sub.pixels) {
        subScale = self.subtitlePreference.ratio * self.displayVideoScale * 1.5;
    } else {
        //for text subtitle scale display_scale.
        subScale *= self.displayScreenScale;
    }
    
    subScale *= scale;
    
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
    return [self.offscreenRendering snapshot:viewport device:self.device commandBuffer:commandBuffer doUploadPicture:^(id<MTLRenderCommandEncoder> _Nonnull renderEncoder) {
        [self encoderPicture:attach
               renderEncoder:renderEncoder
                    viewport:viewport
                       ratio:CGSizeMake(1.0, 1.0)];
        if (drawSub) {
            [self encoderSubtitle:attach.subPicture
                    renderEncoder:renderEncoder
                         viewport:viewport
                            scale:subScale];
        }
    }];
}

- (CGImageRef)_snapshotOrigin:(IJKOverlayAttach *)attach
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
    
    return [self.offscreenRendering snapshot:viewport device:self.device commandBuffer:commandBuffer doUploadPicture:^(id<MTLRenderCommandEncoder> _Nonnull renderEncoder) {
        CVPixelBufferRef pixelBuffer = attach.videoPicture;
        if (pixelBuffer) {
            CGSize ratio = [self computeNormalizedVerticesRatio:attach];
            [self encoderPicture:attach
                   renderEncoder:renderEncoder
                        viewport:viewport
                           ratio:ratio];
        }
        
        if (attach.sub) {
            float ratio = 1.0;
            if (attach.sub.pixels) {
                ratio = self.subtitlePreference.ratio * self.displayVideoScale * 1.5;
            } else {
                //for text subtitle scale display_scale.
                ratio *= self.displayScreenScale;
            }
            [self encoderSubtitle:attach.subPicture
                    renderEncoder:renderEncoder
                         viewport:viewport
                            scale:ratio];
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

#if TARGET_OS_IOS
- (UIImage *)snapshot
{
    CGImageRef cgImg = [self snapshot:IJKSDLSnapshot_Screen];
    return [[UIImage alloc]initWithCGImage:cgImg];
}
#endif

- (void)setNeedsRefreshCurrentPic
{
    if (self.subtitlePreferenceChanged) {
        self.subtitlePreferenceChanged = NO;
        [self generateSub:self.currentAttach];
    }
    [self draw];
}

- (CVPixelBufferRef)_generateSubtitlePixel:(NSString *)subtitle videoDegrees:(int)degrees
{
    if (subtitle.length == 0) {
        return NULL;
    }
    
    IJKSDLSubtitlePreference sp = self.subtitlePreference;
    
    float ratio = sp.ratio;
    int32_t bgrValue = sp.color;
    //以800为标准，定义出字幕字体默认大小为30pt
    float scale = 1.0;
#if TARGET_OS_IPHONE
    CGSize screenSize = [[UIScreen mainScreen]bounds].size;
#else
    CGSize screenSize = [[NSScreen mainScreen]frame].size;
#endif
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

- (void)generateSub:(IJKOverlayAttach *)attach
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
    attach.subPicture = subRef;
}

- (BOOL)displayAttach:(IJKOverlayAttach *)attach
{
    if (!attach) {
        ALOGW("IJKMetalView: overlay is nil\n");
        return NO;
    }
    
    NSAssert(SDL_FCC__VTB == attach.format || SDL_FCC__FFVTB == attach.format, @"wtf?");
    
    //generate current subtitle.
    [self generateSub:attach];
    
    if (self.subtitlePreferenceChanged) {
        self.subtitlePreferenceChanged = NO;
    }
    
    //hold the attach as current.
    self.currentAttach = attach;
    
    if (self.preventDisplay) {
        return YES;
    }
    
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
    if (_subtitlePreference.ratio != subtitlePreference.ratio ||
        _subtitlePreference.color != subtitlePreference.color ||
        _subtitlePreference.bottomMargin != subtitlePreference.bottomMargin) {
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
