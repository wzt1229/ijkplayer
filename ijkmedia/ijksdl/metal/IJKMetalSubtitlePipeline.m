//
//  IJKMetalSubtitlePipeline.m
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/12/23.
//

#import "IJKMetalSubtitlePipeline.h"
#import "IJKMathUtilities.h"
#import "IJKMetalShaderTypes.h"

@interface IJKMetalSubtitlePipeline()
{
    // The Metal texture object to reference with an argument buffer.
    id<MTLTexture> _subTexture;
    id<MTLDevice> _device;
    MTLPixelFormat _colorPixelFormat;
}

// The render pipeline generated from the vertex and fragment shaders in the .metal shader file.
@property (nonatomic, strong) id<MTLRenderPipelineState> renderPipeline;
@property (nonatomic, strong) id<MTLBuffer> vertices;
@property (nonatomic, strong) id<MTLBuffer> mvp;
@property (nonatomic, assign) BOOL vertexChanged;
@property (nonatomic, strong) NSLock *pilelineLock;

@end

@implementation IJKMetalSubtitlePipeline

- (instancetype)initWithDevice:(id<MTLDevice>)device
              colorPixelFormat:(MTLPixelFormat)colorPixelFormat
{
    self = [super init];
    if (self) {
        NSAssert(device, @"device can't be nil!");
        _device = device;
        _colorPixelFormat = colorPixelFormat;
        _pilelineLock = [[NSLock alloc] init];
    }
    return self;
}

- (void)lock
{
    [self.pilelineLock lock];
}

- (void)unlock
{
    [self.pilelineLock unlock];
}

- (void)createRenderPipelineIfNeed
{
    if (self.renderPipeline) {
        return;
    }
    
    NSBundle* bundle = [NSBundle bundleForClass:[self class]];
    NSURL * libURL = [bundle URLForResource:@"default" withExtension:@"metallib"];
    
    NSError *error;
    
    id<MTLLibrary> defaultLibrary = [_device newLibraryWithURL:libURL error:&error];
    
    NSParameterAssert(defaultLibrary);
    // Load all the shader files with a .metal file extension in the project.
    //id<MTLLibrary> defaultLibrary = [device newDefaultLibrary];
    id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"subVertexShader"];
    NSAssert(vertexFunction, @"can't find subVertexShader Function!");
    id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"subtileFragmentShader"];
    NSAssert(vertexFunction, @"can't find subtileFragmentShader Function!");
    
    // Configure a pipeline descriptor that is used to create a pipeline state.
    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = _colorPixelFormat;
    
    //important! set subtitle need blending.
    //https://developer.apple.com/documentation/metal/mtlblendfactor/oneminussourcealpha
    pipelineStateDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    id<MTLRenderPipelineState> pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                                      error:&error]; // 创建图形渲染管道，耗性能操作不宜频繁调用
    // Pipeline State creation could fail if the pipeline descriptor isn't set up properly.
    //  If the Metal API validation is enabled, you can find out more information about what
    //  went wrong.  (Metal API validation is enabled by default when a debug build is run
    //  from Xcode.)
    NSAssert(pipelineState, @"Failed to create pipeline state: %@", error);
    self.renderPipeline = pipelineState;
}

- (void)updateSubtitleVertexIfNeed:(CGRect)rect
{
    if (!self.vertexChanged) {
        return;
    }
    
    self.vertexChanged = NO;
    
    float x = rect.origin.x;
    float y = rect.origin.y;
    float w = rect.size.width;
    float h = rect.size.height;
    /*
     triangle strip
       ^+
     V3|V4
     --|--->+
     V1|V2
     -->V1V2V3
     -->V2V3V4
     */

    IJKVertex quadVertices[4] =
    {   //顶点坐标；          纹理坐标；
        { { x,     y },     { 0.f, 1.f } },
        { { x + w, y },     { 1.f, 1.f } },
        { { x, y + h },     { 0.f, 0.f } },
        { { x + w, y + h }, { 1.f, 0.f } },
    };
    
    self.vertices = [_device newBufferWithBytes:quadVertices
                                         length:sizeof(quadVertices)
                                        options:MTLResourceStorageModeShared]; // 创建顶点缓存
}

- (void)doGenerateSubTexture:(CVPixelBufferRef)pixelBuff
                      device:(id<MTLDevice>)device
                        rect:(CGRect *)rect
{
    if (!pixelBuff) {
        return;
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
    _subTexture = [device newTextureWithDescriptor:textureDescriptor];
    
    MTLRegion region = {
        { 0, 0, 0 },                   // MTLOrigin
        {CVPixelBufferGetWidth(pixelBuff), CVPixelBufferGetHeight(pixelBuff), 1} // MTLSize
    };
    
    NSUInteger bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuff);
    
    [_subTexture replaceRegion:region
                   mipmapLevel:0
                     withBytes:src
                   bytesPerRow:bytesPerRow];
    
    CVPixelBufferUnlockBaseAddress(pixelBuff, kCVPixelBufferLock_ReadOnly);
    
    //截图的时候，按照画面实际大小截取的，显示的时候通常是 retain 屏幕，所以 scale 通常会小于 1；
    //没有这个scale的话，字幕可能会超出画面，位置跟观看时不一致。
    float swidth  = _subTexture.width  * self.scale;
    float sheight = _subTexture.height * self.scale;
    
    float width  = self.viewport.width;
    float height = self.viewport.height;
    //转化到 [-1,1] 的区间
    float y = self.subtitleBottomMargin * (height - sheight) / height * 2.0 - 1.0;
    
    if (width != 0 && height != 0) {
        *rect = (CGRect){
            - 1.0 * swidth / width,
            y,
            2.0 * (swidth / width),
            2.0 * (sheight / height)
        };
    }
}

- (void)uploadTextureWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                          buffer:(CVPixelBufferRef)pixelBuffer
{
    self.vertexChanged = YES;
    CGRect subRect;
    [self doGenerateSubTexture:pixelBuffer device:_device rect:&subRect];

    [encoder setFragmentTexture:_subTexture atIndex:IJKFragmentTextureIndexTextureY];

    [self updateSubtitleVertexIfNeed:subRect];
    // Pass in the parameter data.
    [encoder setVertexBuffer:self.vertices
                      offset:0
                     atIndex:IJKVertexInputIndexVertices]; // 设置顶点缓存
 
    [self createRenderPipelineIfNeed];
    
    // 设置渲染管道，以保证顶点和片元两个shader会被调用
    [encoder setRenderPipelineState:self.renderPipeline];
    
    // Draw the triangle.
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                vertexStart:0
                vertexCount:4]; // 绘制
}

@end

