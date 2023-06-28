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
    id<MTLDevice> _device;
    MTLPixelFormat _colorPixelFormat;
}

// The render pipeline generated from the vertex and fragment shaders in the .metal shader file.
@property (nonatomic, strong) id<MTLRenderPipelineState> renderPipeline;
@property (nonatomic, strong) id<MTLBuffer> vertices;
@property (nonatomic, strong) id<MTLBuffer> mvp;
@property (nonatomic, assign) CGRect lastRect;
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

- (BOOL)createRenderPipelineIfNeed
{
    if (self.renderPipeline) {
        return YES;
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
    return YES;
}

- (void)updateSubtitleVertexIfNeed:(CGRect)rect
{
    if (CGRectEqualToRect(self.lastRect, rect)) {
        return;
    }
    
    self.lastRect = rect;
    
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

- (void)uploadTextureWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                         texture:(id)subTexture
                            rect:(CGRect)subRect
{
    [encoder setFragmentTexture:subTexture atIndex:IJKFragmentTextureIndexTextureY];

    [self updateSubtitleVertexIfNeed:subRect];
    // Pass in the parameter data.
    [encoder setVertexBuffer:self.vertices
                      offset:0
                     atIndex:IJKVertexInputIndexVertices];
 
    // 设置渲染管道，以保证顶点和片元两个shader会被调用
    [encoder setRenderPipelineState:self.renderPipeline];
    
    // Draw the triangle.
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                vertexStart:0
                vertexCount:4]; // 绘制
}

@end

