//
//  IJKMetalBasePipeline.m
//  FFmpegTutorial-macOS
//
//  Created by qianlongxu on 2022/11/23.
//  Copyright © 2022 Matt Reach's Awesome FFmpeg Tutotial. All rights reserved.
//

#import "IJKMetalBasePipeline.h"

@interface IJKMetalBasePipeline()
{
    vector_float4 _colorAdjustment;
    // The Metal texture object to reference with an argument buffer.
    id<MTLTexture> _subTexture;
}

// The render pipeline generated from the vertex and fragment shaders in the .metal shader file.
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLBuffer> vertices;
@property (nonatomic, strong) id<MTLBuffer> mvp;
//@property (nonatomic, strong) id<MTLBuffer> rgbAdjustment;
// The buffer that contains arguments for the fragment shader.
@property (nonatomic, strong) id<MTLBuffer> fragmentShaderArgumentBuffer;
@property (nonatomic, strong) id <MTLArgumentEncoder> argumentEncoder;

@property (nonatomic, assign) NSUInteger numVertices;
@property (nonatomic, assign) CGSize vertexRatio;

@end

@implementation IJKMetalBasePipeline

+ (NSString *)fragmentFuctionName
{
    NSAssert(NO, @"subclass must be override!");
    return @"";
}

- (void)setConvertMatrixType:(IJKYUVToRGBMatrixType)convertMatrixType
{
    if (_convertMatrixType != convertMatrixType) {
        _convertMatrixType = convertMatrixType;
    }
}

- (IJKConvertMatrix)createMatrix:(IJKYUVToRGBMatrixType)matrixType
{
    IJKConvertMatrix matrix = {0.0};
    BOOL videoRange;
    switch (matrixType) {
        case IJKYUVToRGBBT601FullRangeMatrix:
        case IJKYUVToRGBBT601VideoRangeMatrix:
        {
            matrix.matrix = (matrix_float3x3){
                (simd_float3){1.0,    1.0,    1.0},
                (simd_float3){0.0,    -0.343, 1.765},
                (simd_float3){1.4,    -0.711, 0.0},
            };
            
            videoRange = matrixType == IJKYUVToRGBBT601VideoRangeMatrix;
        }
            break;
        case IJKYUVToRGBBT709FullRangeMatrix:
        case IJKYUVToRGBBT709VideoRangeMatrix:
        {
            matrix.matrix = (matrix_float3x3){
                (simd_float3){1.164,    1.164,  1.164},
                (simd_float3){0.0,      -0.213, 2.112},
                (simd_float3){1.793,    -0.533, 0.0},
            };
            
            videoRange = matrixType == IJKYUVToRGBBT709VideoRangeMatrix;
        }
            break;
        case IJKUYVYToRGBFullRangeMatrix:
        case IJKUYVYToRGBVideoRangeMatrix:
        {
            matrix.matrix = (matrix_float3x3){
                (simd_float3){1.164,  1.164,  1.164},
                (simd_float3){0.0,    -0.391, 2.017},
                (simd_float3){1.596,  -0.812, 0.0},
            };
            
            videoRange = matrixType == IJKUYVYToRGBVideoRangeMatrix;
        }
            break;
        case IJKYUVToRGBNoneMatrix:
        {
            return matrix;
        }
            break;
    }

    vector_float3 offset;
    if (videoRange) {
        offset = (vector_float3){ -(16.0/255.0), -0.5, -0.5};
    } else {
        offset = (vector_float3){ 0.0, -0.5, -0.5};
    }
    matrix.offset = offset;
    return matrix;
}

- (void)createPipelineState:(id<MTLDevice>)device
           colorPixelFormat:(MTLPixelFormat)colorPixelFormat
{
    NSAssert(device, @"device can't be nil!");
    
    NSString *fragmentName = [[self class] fragmentFuctionName];
    
    NSBundle* bundle = [NSBundle bundleForClass:[self class]];
    NSURL* bundleURL = [[bundle resourceURL] URLByAppendingPathComponent:@"MetalShader.bundle"];
    NSBundle* currentBundle = [NSBundle bundleWithURL: bundleURL];
    NSURL * libURL = [currentBundle URLForResource:@"default" withExtension:@"metallib"];
    
    NSError *error;
    
    id<MTLLibrary> defaultLibrary = [device newLibraryWithURL:libURL error:&error];
    
    // Load all the shader files with a .metal file extension in the project.
//    id<MTLLibrary> defaultLibrary = [device newDefaultLibrary];
    id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"mvpShader"];
    NSAssert(vertexFunction, @"can't find Vertex Function:vertexShader");
    id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:fragmentName];
    NSAssert(vertexFunction, @"can't find Fragment Function:%@",fragmentName);
    
    id <MTLArgumentEncoder> argumentEncoder =
        [fragmentFunction newArgumentEncoderWithBufferIndex:IJKFragmentBufferLocation0];
    
    NSUInteger argumentBufferLength = argumentEncoder.encodedLength;

    _fragmentShaderArgumentBuffer = [device newBufferWithLength:argumentBufferLength options:0];

    _fragmentShaderArgumentBuffer.label = @"Argument Buffer";
    
    [argumentEncoder setArgumentBuffer:_fragmentShaderArgumentBuffer offset:0];
    
    // Configure a pipeline descriptor that is used to create a pipeline state.
    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat; // 设置颜色格式
    
    id<MTLRenderPipelineState> pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                                      error:&error]; // 创建图形渲染管道，耗性能操作不宜频繁调用
    // Pipeline State creation could fail if the pipeline descriptor isn't set up properly.
    //  If the Metal API validation is enabled, you can find out more information about what
    //  went wrong.  (Metal API validation is enabled by default when a debug build is run
    //  from Xcode.)
    NSAssert(pipelineState, @"Failed to create pipeline state: %@", error);
    self.argumentEncoder = argumentEncoder;
    self.pipelineState = pipelineState;
}

- (void)updateVertexRatio:(CGSize)ratio
                   device:(id<MTLDevice>)device
{
    if (self.vertices && CGSizeEqualToSize(self.vertexRatio, ratio)) {
        return;
    }
    
    self.vertexRatio = ratio;
    
    float x = ratio.width;
    float y = ratio.height;
    /*
     triangle strip
       ^+
     V3|V4
     --|--->+
     V1|V2
     -->V1V2V3
     -->V2V3V4
     */

    const IJKVertex quadVertices[] =
    {   // 顶点坐标，分别是x、y、z、w；    纹理坐标，x、y；
        { { -1.0 * x, -1.0 * y, 0.0, 1.0 },  { 0.f, 1.f } },
        { {  1.0 * x, -1.0 * y, 0.0, 1.0 },  { 1.f, 1.f } },
        { { -1.0 * x,  1.0 * y, 0.0, 1.0 },  { 0.f, 0.f } },
        { {  1.0 * x,  1.0 * y, 0.0, 1.0 },  { 1.f, 0.f } },
    };
    
    self.vertices = [device newBufferWithBytes:quadVertices
                                        length:sizeof(quadVertices)
                                       options:MTLResourceStorageModeShared]; // 创建顶点缓存
    self.numVertices = sizeof(quadVertices) / sizeof(IJKVertex); // 顶点个数
}

- (void)updateMVP:(id<MTLBuffer>)mvp
{
    self.mvp = mvp;
}

- (void)updateColorAdjustment:(vector_float4)c
{
    _colorAdjustment = c;
}

- (void)doUploadTextureWithEncoder:(id<MTLArgumentEncoder>)encoder
                            buffer:(CVPixelBufferRef)pixelBuffer
                      textureCache:(CVMetalTextureCacheRef)textureCache
{
    
}

- (void)uploadTextureWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                          buffer:(CVPixelBufferRef)pixelBuffer
                    textureCache:(CVMetalTextureCacheRef)textureCache
                          device:(id<MTLDevice>)device
                colorPixelFormat:(MTLPixelFormat)colorPixelFormat
                  subPixelBuffer:(CVPixelBufferRef)subPixelBuffer
{
    NSAssert(self.vertices, @"you must update vertex ratio before call me.");
    // Pass in the parameter data.
    [encoder setVertexBuffer:self.vertices
                      offset:0
                     atIndex:IJKVertexInputIndexVertices]; // 设置顶点缓存
 
    if (self.mvp) {
        // Pass in the parameter data.
        [encoder setVertexBuffer:self.mvp
                          offset:0
                         atIndex:IJKVertexInputIndexMVP]; // 设置模型矩阵
    }
    
    if (!self.pipelineState) {
        [self createPipelineState:device
                 colorPixelFormat:colorPixelFormat];
    }
    
    [_argumentEncoder setArgumentBuffer:_fragmentShaderArgumentBuffer offset:0];
    
    [self doUploadTextureWithEncoder:_argumentEncoder buffer:pixelBuffer textureCache:textureCache];
    
    IJKSubtitleArguments subRect = {0};
    [self uploadSubTextureWithEncoder:_argumentEncoder buffer:subPixelBuffer device:device rect:&subRect];
    
    IJKFragmentShaderData * data = (IJKFragmentShaderData *)[_argumentEncoder constantDataAtIndex:IJKFragmentDataIndex];
    IJKConvertMatrix convertMatrix = [self createMatrix:self.convertMatrixType];
    convertMatrix.adjustment = _colorAdjustment;
    
    *data = (IJKFragmentShaderData) {convertMatrix,subRect};
    
    [encoder setFragmentBuffer:_fragmentShaderArgumentBuffer
                        offset:0
                       atIndex:IJKFragmentBufferLocation0];
    
    // 设置渲染管道，以保证顶点和片元两个shader会被调用
    [encoder setRenderPipelineState:self.pipelineState];
    
    // Draw the triangle.
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                vertexStart:0
                vertexCount:self.numVertices]; // 绘制
}

- (void)uploadSubTextureWithEncoder:(id<MTLArgumentEncoder>)encoder
                             buffer:(CVPixelBufferRef)pixelBuff
                             device:(id<MTLDevice>)device
                               rect:(IJKSubtitleArguments *)rect
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
    CVPixelBufferUnlockBaseAddress(pixelBuff,  kCVPixelBufferLock_ReadOnly);
    
    [encoder setTexture:_subTexture
                atIndex:IJKFragmentTextureIndexTextureSub]; // 设置纹理
    //截图的时候，按照画面实际大小截取的，显示的时候通常是 retain 屏幕，所以 scale 通常会小于 1；
    //没有这个scale的话，字幕可能会超出画面，位置跟观看时不一致。
    float scale = self.viewport.width / self.drawableSize.width;
    float swidth  = _subTexture.width  * scale;
    float sheight = _subTexture.height * scale;
    
    float width  = self.viewport.width;
    float height = self.viewport.height;
    float y = self.subtitleBottomMargin * (height - sheight) / height;
    
    if (width != 0 && height != 0) {
        IJKSubtitleArguments subRect = {
            1,
            (float)((width - swidth) / width / 2.0),
            y,
            (float)(swidth / width),
            (float)(sheight / height)
        };
        *rect = subRect;
    }
}

@end
