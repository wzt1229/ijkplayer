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

- (void)setupPipelineIfNeed:(CVPixelBufferRef)pixelBuffer
{
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
    
    if (clazz) {
        [self setupPipelineWithClazz:clazz];
    }
}

- (void)setupPipelineWithClazz:(Class)clazz
{
    if (self.metalPipeline) {
        if ([self.metalPipeline class] != clazz) {
            NSAssert(NO, @"wrong pixel format:%@",NSStringFromClass(clazz));
        } else {
            return;
        }
    }
    self.metalPipeline = [clazz new];
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

/// Called whenever the view needs to render a frame.
- (void)drawRect:(NSRect)dirtyRect
{
    // Create a new command buffer for each render pass to the current drawable.
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";
    // Obtain a renderPassDescriptor generated from the view's drawable textures.
    MTLRenderPassDescriptor *renderPassDescriptor = self.currentRenderPassDescriptor;
    //MTLRenderPassDescriptor描述一系列attachments的值，类似GL的FrameBuffer；同时也用来创建MTLRenderCommandEncoder
    if(renderPassDescriptor) {
//        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0f); // 设置默认颜色
        
        // Create a render command encoder.
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        // Set the region of the drawable to draw into.
        
        [renderEncoder setViewport:(MTLViewport){0.0, 0.0, self.drawableSize.width, self.drawableSize.height, -1.0, 1.0 }]; // 设置显示区域
        
        CVPixelBufferRef pixelBuffer = self.currentAttach.currentVideoPic;
        
        if (pixelBuffer) {
            [self setupPipelineIfNeed:pixelBuffer];
            [self createMVPIfNeed];
            [self.metalPipeline updateMVP:self.mvp];
            
            CGSize ratio = [self computeNormalizedRatio:pixelBuffer];
            [self.metalPipeline updateVertexRatio:ratio device:self.device];
            //upload textures
            [self.metalPipeline uploadTextureWithEncoder:renderEncoder
                                                  buffer:pixelBuffer
                                            textureCache:_metalTextureCache
                                                  device:self.device
                                        colorPixelFormat:self.colorPixelFormat];
        }
        [renderEncoder endEncoding]; // 结束
        // Schedule a present once the framebuffer is complete using the current drawable.
        [commandBuffer presentDrawable:self.currentDrawable]; // 显示
    }
    // Finalize rendering here & push the command buffer to the GPU.
    [commandBuffer commit]; // 提交；
}

- (CGImageRef)snapshot
{
    CVPixelBufferRef pixelBuffer = self.currentAttach.currentVideoPic;
    if (!pixelBuffer) {
        return nil;
    }
    
    int width  = (int)CVPixelBufferGetWidth(pixelBuffer);
    int height = (int)CVPixelBufferGetHeight(pixelBuffer);
    
    CGSize targetSize = CGSizeMake(width, height);
    
    if (![self.offscreenRendering canReuse:targetSize]) {
        self.offscreenRendering = [IJKMetalOffscreenRendering alloc];
    }
    
    MTLRenderPassDescriptor * passDescriptor = [self.offscreenRendering offscreenRender:CGSizeMake(width, height) device:self.device];
    if (!passDescriptor) {
        return NULL;
    }
    
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:passDescriptor];
    
    if (!renderEncoder) {
        return NULL;
    }
    
    // Set the region of the drawable to draw into.
    [renderEncoder setViewport:(MTLViewport){0.0, 0.0, targetSize.width, targetSize.height, -1.0, 1.0}];
    
    [self.metalPipeline updateMVP:self.mvp];
    
    CGSize ratio = [self computeNormalizedRatio:pixelBuffer];
    [self.metalPipeline updateVertexRatio:ratio device:self.device];
    //upload textures
    [self.metalPipeline uploadTextureWithEncoder:renderEncoder
                                          buffer:pixelBuffer
                                    textureCache:_metalTextureCache
                                          device:self.device
                                colorPixelFormat:self.colorPixelFormat];
    
    [renderEncoder endEncoding];
    [commandBuffer commit];
    
    return [self.offscreenRendering snapshot];
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
    
//    //generate current subtitle.
//    CVPixelBufferRef subRef = NULL;
//    if (sub.text.length > 0) {
//        subRef = [self _generateSubtitlePixel:sub.text];
//    } else if (sub.pixels != NULL) {
//        subRef = [self _generateSubtitlePixelFromPicture:sub];
//    }
//    attach.sub = sub;
//    attach.currentSubtitle = subRef;
//
//    if (self.subtitlePreferenceChanged) {
//        self.subtitlePreferenceChanged = NO;
//    }
//    //hold the attach as current.
    
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
        // TODO here
//        if (IJK_GLES2_Renderer_isValid(_renderer)) {
//            IJK_GLES2_Renderer_updateColorConversion(_renderer, _colorPreference.brightness, _colorPreference.saturation,_colorPreference.contrast);
//        }
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
    if (_subtitlePreference.bottomMargin != subtitlePreference.bottomMargin) {
        _subtitlePreference = subtitlePreference;
        // TODO here
//        if (IJK_GLES2_Renderer_isValid(_renderer)) {
//            IJK_GLES2_Renderer_updateSubtitleBottomMargin(_renderer, _subtitlePreference.bottomMargin);
//        }
    }
    
    if (_subtitlePreference.ratio != subtitlePreference.ratio || _subtitlePreference.color != subtitlePreference.color) {
        _subtitlePreference = subtitlePreference;
        self.subtitlePreferenceChanged = YES;
    }
}

- (void)setBackgroundColor:(uint8_t)r g:(uint8_t)g b:(uint8_t)b
{
    self.clearColor = (MTLClearColor){r/255.0, g/255.0, b/255.0, 1.0f};
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
