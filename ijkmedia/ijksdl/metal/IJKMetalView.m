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
#import <mach/mach_time.h>

// Header shared between C code here, which executes Metal API commands, and .metal files, which
// uses these types as inputs to the shaders.
#import "IJKMetalShaderTypes.h"
#import "IJKMathUtilities.h"
#import "IJKMetalBGRAPipeline.h"
#import "IJKMetalNV12Pipeline.h"
#import "IJKMetalYUV420PPipeline.h"
#import "IJKMetalUYVY422Pipeline.h"
#import "IJKMetalYUYV422Pipeline.h"
#import "IJKMetalOffscreenRendering.h"

#import "ijksdl_gles2.h"
#import "ijksdl_vout_overlay_videotoolbox.h"
#import "ijksdl_vout_ios_gles2.h"
#import "IJKSDLTextureString.h"
#import "IJKMediaPlayback.h"
#import "IJKMetalAttach.h"

@interface IJKMetalView ()
{
    CGRect _layerBounds;
    
    // The command queue used to pass commands to the device.
    id<MTLCommandQueue> _commandQueue;

    CVMetalTextureCacheRef _metalTextureCache;
}

@property (nonatomic, strong) __kindof IJKMetalBasePipeline *metalPipeline;
@property (nonatomic, strong) id<MTLBuffer> mvp;
@property (nonatomic, strong) IJKMetalOffscreenRendering * offscreenRendering;
@property (nonatomic, strong) IJKMetalAttach *currentAttach;

@property(nonatomic) NSInteger videoDegrees;
@property(nonatomic) CGSize videoNaturalSize;
@property(atomic) BOOL modelMatrixChanged;

//display window size / screen
@property(atomic) float displayScreenScale;
//display window size / video size
@property(atomic) float displayVideoScale;
@property(atomic) GLint backingWidth;
@property(atomic) GLint backingHeight;
@property(atomic) BOOL subtitlePreferenceChanged;

@end

@implementation IJKMetalView

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
    CFRelease(_metalTextureCache);
}

- (BOOL)_setup
{
    _subtitlePreference = (IJKSDLSubtitlePreference){1.0, 0xFFFFFF, 0.1};
    _rotatePreference   = (IJKSDLRotatePreference){IJKSDLRotateNone, 0.0};
    _colorPreference    = (IJKSDLColorConversionPreference){1.0, 1.0, 1.0};
    _darPreference      = (IJKSDLDARPreference){0.0};
    _displayScreenScale = 1.0;
    _displayVideoScale  = 1.0;
    
    self.device = MTLCreateSystemDefaultDevice();
    if (!self.device) {
        NSLog(@"No Support Metal.");
        return NO;
    }
    CVReturn ret = CVMetalTextureCacheCreate(kCFAllocatorDefault, NULL, self.device, NULL, &_metalTextureCache);
    if (ret != kCVReturnSuccess) {
        NSAssert(NO, @"Create MetalTextureCache Failed:%d.",ret);
    }
    // Create the command queue
    _commandQueue = [self.device newCommandQueue]; // CommandQueue是渲染指令队列，保证渲染指令有序地提交到GPU
    //设置模型矩阵，实现旋转
    _modelMatrixChanged = YES;
    self.autoResizeDrawable = NO;
    self.enableSetNeedsDisplay = YES;
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self _setup];
    }
    return self;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self _setup];
    }
    return self;
}

- (void)layout
{
    [super layout];
    _layerBounds = self.bounds;
}

- (CGSize)computeNormalizedRatio:(CVPixelBufferRef)img
{
    int frameWidth = (int)CVPixelBufferGetWidth(img);
    int frameHeight = (int)CVPixelBufferGetHeight(img);
    // Compute normalized quad coordinates to draw the frame into.
    CGSize normalizedSamplingSize = CGSizeMake(1.0, 1.0);
    
    //apply user dar
    if (self.darPreference.ratio > 0.001) {
        int zDegrees = 0;
        if (_rotatePreference.type == IJKSDLRotateZ) {
            zDegrees += _rotatePreference.degrees;
        }
        zDegrees += self.currentAttach.zRotateDegrees;
        
        float darRatio = self.darPreference.ratio;
        //when video's z rotate degrees is 90 odd multiple need swap user's ratio
        if (abs(zDegrees) / 90 % 2 == 1) {
            darRatio = 1.0 / darRatio;
        }
        
        if (self.currentAttach.overlayW / self.currentAttach.overlayH > darRatio) {
            frameHeight = frameWidth * 1.0 / darRatio;
        } else {
            frameWidth = frameHeight * darRatio;
        }
    }
    
    if (_scalingMode == IJKMPMovieScalingModeAspectFit || _scalingMode == IJKMPMovieScalingModeFill) {
        // Set up the quad vertices with respect to the orientation and aspect ratio of the video.
        CGRect vertexSamplingRect = AVMakeRectWithAspectRatioInsideRect(CGSizeMake(frameWidth, frameHeight), _layerBounds);
        
        CGSize cropScaleAmount = CGSizeMake(vertexSamplingRect.size.width/_layerBounds.size.width, vertexSamplingRect.size.height/_layerBounds.size.height);
        
        // hold max
        if (_scalingMode == IJKMPMovieScalingModeAspectFit) {
            if (cropScaleAmount.width > cropScaleAmount.height) {
                normalizedSamplingSize.width = 1.0;
                normalizedSamplingSize.height = cropScaleAmount.height/cropScaleAmount.width;
            }
            else {
                normalizedSamplingSize.height = 1.0;
                normalizedSamplingSize.width = cropScaleAmount.width/cropScaleAmount.height;
            }
        } else if (_scalingMode == IJKMPMovieScalingModeFill) {
            // hold min
            if (cropScaleAmount.width > cropScaleAmount.height) {
                normalizedSamplingSize.height = 1.0;
                normalizedSamplingSize.width = cropScaleAmount.width/cropScaleAmount.height;
            }
            else {
                normalizedSamplingSize.width = 1.0;
                normalizedSamplingSize.height = cropScaleAmount.height/cropScaleAmount.width;
            }
        }
    }
    return normalizedSamplingSize;
}

- (BOOL)setupPipelineIfNeed:(CVPixelBufferRef)pixelBuffer
{
    if (!pixelBuffer) {
        return NO;
    }
    Class clazz = NULL;
    OSType type = CVPixelBufferGetPixelFormatType(pixelBuffer);
    if (type == kCVPixelFormatType_32BGRA) {
        clazz = [IJKMetalBGRAPipeline class];
    } else if (type == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || type ==  kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
        clazz = [IJKMetalNV12Pipeline class];
    } else if (type == kCVPixelFormatType_420YpCbCr8PlanarFullRange || type ==  kCVPixelFormatType_420YpCbCr8Planar) {
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
    
    if (clazz) {
        return [self setupPipelineWithClazz:clazz];
    }
    return NO;
}

- (BOOL)setupPipelineWithClazz:(Class)clazz
{
    if (self.metalPipeline) {
        if ([self.metalPipeline class] != clazz) {
            NSAssert(NO, @"wrong pixel format:%@",NSStringFromClass(clazz));
            return NO;
        } else {
            return YES;
        }
    }
    self.metalPipeline = [clazz new];
    return !!self.metalPipeline;
}

- (void)displayAttach:(IJKMetalAttach *)attach
{
    if (!attach) {
        return;
    }
    
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:_cmd withObject:attach waitUntilDone:NO];
        return;
    }
    
    if (self.currentAttach.zRotateDegrees != attach.zRotateDegrees) {
        self.modelMatrixChanged = YES;
    }
    self.currentAttach = attach;
    
    if (self.preventDisplay) {
        return;
    }
    
    CVPixelBufferRef pixelBuffer = attach.currentVideoPic;
    if (!pixelBuffer) {
        return;
    }
    
    [self setNeedsDisplay:YES];
}

- (void)encoderPictureAndSubtitle:(id<MTLRenderCommandEncoder>)renderEncoder viewport:(CGSize)viewport
{
    // Set the region of the drawable to draw into.
    [renderEncoder setViewport:(MTLViewport){0.0, 0.0, viewport.width, viewport.height, -1.0, 1.0}]; // 设置显示区域
    
    CVPixelBufferRef pixelBuffer = self.currentAttach.currentVideoPic;
    
    if ([self setupPipelineIfNeed:pixelBuffer]) {
        self.metalPipeline.viewport = viewport;
        self.metalPipeline.drawableSize = self.drawableSize;
        self.metalPipeline.subtitleBottomMargin = self.subtitlePreference.bottomMargin;
        [self createMVPIfNeed];
        [self.metalPipeline updateMVP:self.mvp];
        bool applyAdjust = _colorPreference.brightness != 1.0 || _colorPreference.saturation != 1.0 || _colorPreference.contrast != 1.0;
        [self.metalPipeline updateColorAdjustment:(vector_float4){_colorPreference.brightness,_colorPreference.saturation,_colorPreference.contrast,applyAdjust?1.0:0.0}];
        CGSize ratio = [self computeNormalizedRatio:pixelBuffer];
        [self.metalPipeline updateVertexRatio:ratio device:self.device];
        //upload textures
        [self.metalPipeline uploadTextureWithEncoder:renderEncoder
                                              buffer:pixelBuffer
                                        textureCache:_metalTextureCache
                                              device:self.device
                                    colorPixelFormat:self.colorPixelFormat
                                      subPixelBuffer:self.currentAttach.currentSubtitle];
    }
    [renderEncoder endEncoding];
}

/// Called whenever the view needs to render a frame.
- (void)drawRect:(NSRect)dirtyRect
{
    // Obtain a renderPassDescriptor generated from the view's drawable textures.
    MTLRenderPassDescriptor *renderPassDescriptor = self.currentRenderPassDescriptor;
    //MTLRenderPassDescriptor描述一系列attachments的值，类似GL的FrameBuffer；同时也用来创建MTLRenderCommandEncoder
    if(!renderPassDescriptor) {
        return;
    }
        
    // Create a new command buffer for each render pass to the current drawable.
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";
    // Create a render command encoder.
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    [self encoderPictureAndSubtitle:renderEncoder viewport:self.drawableSize];
    // Schedule a present once the framebuffer is complete using the current drawable.
    [commandBuffer presentDrawable:self.currentDrawable];
    // Finalize rendering here & push the command buffer to the GPU.
    [commandBuffer commit]; //
}

- (CGImageRef)snapshot
{
    CVPixelBufferRef pixelBuffer = self.currentAttach.currentVideoPic;
    if (!pixelBuffer) {
        return NULL;
    }
    
    if (!self.offscreenRendering) {
        self.offscreenRendering = [IJKMetalOffscreenRendering alloc];
    }
    
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    return [self.offscreenRendering snapshot:pixelBuffer device:self.device commandBuffer:commandBuffer doUploadPicture:^(id<MTLRenderCommandEncoder> _Nonnull renderEncoder, CGSize viewport) {
        [self encoderPictureAndSubtitle:renderEncoder viewport:viewport];
    }];
}

- (CGImageRef)snapshot:(IJKSDLSnapshotType)aType
{
    switch (aType) {
        case IJKSDLSnapshot_Origin:
        case IJKSDLSnapshot_Screen:
        case IJKSDLSnapshot_Effect_Origin:
            return nil;
        case IJKSDLSnapshot_Effect_Subtitle_Origin:
            return [self snapshot];
    }
}

- (void)setNeedsRefreshCurrentPic
{
    //use single global thread!
    // TODO here
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
    
    IJKMetalAttach *attach = [[IJKMetalAttach alloc] init];

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
    
    [self displayAttach:attach];
}

- (void)createMVPIfNeed
{
    /// These are the view and projection transforms.
    matrix_float4x4 viewMatrix;
    
    if (self.modelMatrixChanged) {
        self.modelMatrixChanged = NO;
        float radian = radians_from_degrees(_rotatePreference.degrees);
        switch (_rotatePreference.type) {
            case IJKSDLRotateNone:
            {
                viewMatrix = matrix4x4_identity();
            }
                break;
            case IJKSDLRotateX:
            {
                viewMatrix = matrix4x4_rotation(radian, 1.0, 0.0, 0.0);
            }
                break;
            case IJKSDLRotateY:
            {
                viewMatrix = matrix4x4_rotation(radian, 0.0, 1.0, 0.0);
            }
                break;
            case IJKSDLRotateZ:
            {
                viewMatrix = matrix4x4_rotation(radian, 0.0, 0.0, 1.0);
            }
                break;
        }
        
        if (self.currentAttach.zRotateDegrees != 0) {
            float zRadin = radians_from_degrees(self.currentAttach.zRotateDegrees);
            viewMatrix = matrix_multiply(matrix4x4_rotation(zRadin, 0.0, 0.0, 1.0),viewMatrix);
        }
        IJKMVPMatrix mvp = {viewMatrix};
        self.mvp = [self.device newBufferWithBytes:&mvp
                                            length:sizeof(IJKMVPMatrix)
                                           options:MTLResourceStorageModeShared];
    }
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
        self.modelMatrixChanged = YES;
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
