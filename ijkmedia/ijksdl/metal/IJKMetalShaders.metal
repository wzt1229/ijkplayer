//
//  IJKMetalShaders.metal
//  FFmpegTutorial-macOS
//
//  Created by qianlongxu on 2022/11/23.
//  Copyright © 2022 Matt Reach's Awesome FFmpeg Tutotial. All rights reserved.
//

#include <metal_stdlib>

using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands.
#include "IJKMetalShaderTypes.h"

// Vertex shader outputs and fragment shader inputs
struct RasterizerData
{
    // The [[position]] attribute of this member indicates that this value
    // is the clip space position of the vertex when this structure is
    // returned from the vertex function.
    float4 clipSpacePosition [[position]];
    
//    // Since this member does not have a special attribute, the rasterizer
//    // interpolates its value with the values of the other triangle vertices
//    // and then passes the interpolated value to the fragment shader for each
//    // fragment in the triangle.
//    float4 color;
    
    float2 textureCoordinate; // 纹理坐标，会做插值处理
};

//float4 subtitle(float4 rgba,float2 texCoord,texture2d<float> subTexture,IJKSubtitleArguments subRect)
//{
//    if (!subRect.on) {
//        return rgba;
//    }
//
//    //翻转画面坐标系，这个会影响字幕在画面上的位置；翻转后从底部往上布局
//    texCoord.y = 1 - texCoord.y;
//
//    float sx = subRect.x;
//    float sy = subRect.y;
//    //限定字幕纹理区域
//    if (texCoord.x >= sx && texCoord.x <= (sx + subRect.w) && texCoord.y >= sy && texCoord.y <= (sy + subRect.h)) {
//        //在该区域内，将坐标缩放到 [0,1]
//        texCoord.x = (texCoord.x - sx) / subRect.w;
//        texCoord.y = (texCoord.y - sy) / subRect.h;
//        //flip the y
//        texCoord.y = 1 - texCoord.y;
//        constexpr sampler textureSampler (mag_filter::linear,
//                                          min_filter::linear);
//        // Sample the encoded texture in the argument buffer.
//        float4 textureSample = subTexture.sample(textureSampler, texCoord);
//        // Add the subtitle and color values together and return the result.
//        return float4((1.0 - textureSample.a) * rgba + textureSample);
//    }  else {
//        return rgba;
//    }
//}

/// @brief subtitle bgra fragment shader
/// @param stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
/// @param texture表明是纹理数据，IJKFragmentTextureIndexTextureY 是索引
fragment float4 subtileFragmentShader(RasterizerData input [[stage_in]],
                                   texture2d<float> textureY [[ texture(IJKFragmentTextureIndexTextureY) ]])
{
    // sampler是采样器
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    //auto converted bgra -> rgba
    float4 rgba = textureY.sample(textureSampler, input.textureCoordinate);
    return rgba;
}

#if __METAL_VERSION__ >= 200

struct IJKFragmentShaderArguments {
    texture2d<float> textureY [[ id(IJKFragmentTextureIndexTextureY) ]];
    texture2d<float> textureU [[ id(IJKFragmentTextureIndexTextureU) ]];
    texture2d<float> textureV [[ id(IJKFragmentTextureIndexTextureV) ]];
    device IJKConvertMatrix * convertMatrix [[ id(IJKFragmentMatrixIndexConvert) ]];
};

vertex RasterizerData subVertexShader(uint vertexID [[vertex_id]],
             constant IJKVertex *vertices [[buffer(IJKVertexInputIndexVertices)]])
{
    RasterizerData out;
    out.clipSpacePosition = float4(vertices[vertexID].position, 0.0, 1.0);
    out.textureCoordinate = vertices[vertexID].textureCoordinate;
    return out;
}

//支持mvp矩阵
vertex RasterizerData mvpShader(uint vertexID [[vertex_id]],
             constant IJKVertexData & data [[buffer(IJKVertexInputIndexVertices)]])
{
    RasterizerData out;
    IJKVertex _vertex = data.vertexes[vertexID];
    float4 position = float4(_vertex.position, 0.0, 1.0);
    out.clipSpacePosition = data.modelMatrix * position;
    out.textureCoordinate = _vertex.textureCoordinate;
    return out;
}

float3 rgb_adjust(float3 rgb,float4 rgbAdjustment) {
    //C 是对比度值，B 是亮度值，S 是饱和度
    float B = rgbAdjustment.x;
    float S = rgbAdjustment.y;
    float C = rgbAdjustment.z;
    float on= rgbAdjustment.w;
    if (on > 0.99) {
        rgb = (rgb - 0.5) * C + 0.5;
        rgb = rgb + (0.75 * B - 0.5) / 2.5 - 0.1;
        float3 intensity = float3(rgb * float3(0.299, 0.587, 0.114));
        return intensity + S * (rgb - intensity);
    } else {
        return rgb;
    }
}

/// @brief bgra fragment shader
/// @param stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
/// @param texture表明是纹理数据，IJKFragmentTextureIndexTextureY 是索引
fragment float4 bgraFragmentShader(RasterizerData input [[stage_in]],
                                   device IJKFragmentShaderArguments & fragmentShaderArgs [[ buffer(IJKFragmentBufferLocation0) ]])
{
    // sampler是采样器
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    texture2d<float> textureY = fragmentShaderArgs.textureY;
    //auto converted bgra -> rgba
    float4 rgba = textureY.sample(textureSampler, input.textureCoordinate);
    //color adjustment
    device IJKConvertMatrix* convertMatrix = fragmentShaderArgs.convertMatrix;
    return float4(rgb_adjust(rgba.rgb, convertMatrix->adjustment),rgba.a);
}

/// @brief argb fragment shader
/// @param stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
/// @param texture表明是纹理数据，IJKFragmentTextureIndexTextureY 是索引
fragment float4 argbFragmentShader(RasterizerData input [[stage_in]],
                                   device IJKFragmentShaderArguments & fragmentShaderArgs [[ buffer(IJKFragmentBufferLocation0) ]])
{
    // sampler是采样器
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    texture2d<float> textureY = fragmentShaderArgs.textureY;
    //auto converted bgra -> rgba;but data is argb,so target is grab
    float4 grab = textureY.sample(textureSampler, input.textureCoordinate);
    //color adjustment
    device IJKConvertMatrix* convertMatrix = fragmentShaderArgs.convertMatrix;
    return float4(rgb_adjust(grab.gra, convertMatrix->adjustment),grab.b);
}

/// @brief nv12 fragment shader
/// @param stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
/// @param texture表明是纹理数据，IJKFragmentTextureIndexTextureY/UV 是索引
/// @param buffer表明是缓存数据，IJKFragmentBufferIndexMatrix是索引
fragment float4 nv12FragmentShader(RasterizerData input [[stage_in]],
                                   device IJKFragmentShaderArguments & fragmentShaderArgs [[ buffer(IJKFragmentBufferLocation0) ]])
{
    // sampler是采样器
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    texture2d<float> textureY = fragmentShaderArgs.textureY;
    texture2d<float> textureUV = fragmentShaderArgs.textureU;
    
    float3 yuv = float3(textureY.sample(textureSampler,  input.textureCoordinate).r,
                        textureUV.sample(textureSampler, input.textureCoordinate).rg);
    
    device IJKConvertMatrix* convertMatrix = fragmentShaderArgs.convertMatrix;
    float3 rgb = convertMatrix->matrix * (yuv + convertMatrix->offset);
    //color adjustment
    return float4(rgb_adjust(rgb,convertMatrix->adjustment),1.0);
}

// mark -hdr helps

// [arib b67 eotf
float arib_b67_inverse_oetf(float x)
{
    constexpr float ARIB_B67_A = 0.17883277;
    constexpr float ARIB_B67_B = 0.28466892;
    constexpr float ARIB_B67_C = 0.55991073;
    
    // Prevent negative pixels expanding into positive values.
    x = max(x, 0.0);
    if (x <= 0.5)
    x = (x * x) * (1.0 / 3.0);
    else
    x = (exp((x - ARIB_B67_C) / ARIB_B67_A) + ARIB_B67_B) / 12.0;
    return x;
}
float ootf_1_2(float x)
{
    return x < 0.0 ? x : pow(x, 1.2);
}
float arib_b67_eotf(float x)
{
    return ootf_1_2(arib_b67_inverse_oetf(x));
}
// arib b67 eotf]

// [st 2084 eotf

float st_2084_eotf(float x)
{
    constexpr float ST2084_M1 = 0.1593017578125;
    constexpr float ST2084_M2 = 78.84375;
    constexpr float ST2084_C1 = 0.8359375;
    constexpr float ST2084_C2 = 18.8515625;
    constexpr float ST2084_C3 = 18.6875;
//    constexpr float FLT_MIN = 1.17549435082228750797e-38;
    
    float xpow = pow(x, float(1.0 / ST2084_M2));
    float num = max(xpow - ST2084_C1, 0.0);
    float den = max(ST2084_C2 - ST2084_C3 * xpow, FLT_MIN);
    return pow(num/den, 1.0 / ST2084_M1);
}
// st 2084 eotf]

// [tonemap hable
float hableF(float inVal)
{
    //fix xcode error:Too many arguments provided to function-like macro invocation
    float a = 0.15;
    float b = 0.50;
    float c = 0.10;
    float d = 0.20;
    float e = 0.02;
    float f = 0.30;
    return (inVal * (inVal * a + b * c) + d * e) / (inVal * (inVal * a + b) + d * f) - e / f;
}
// tonemap hable]

// [bt709
float rec_1886_inverse_eotf(float x)
{
    return x < 0.0 ? 0.0 : pow(x, 1.0 / 2.4);
}

float rec_1886_eotf(float x)
{
    return x < 0.0 ? 0.0 : pow(x, 2.4);
}
// bt709]
// mark -hdr helps

#define FFMAX(a,b) ((a) > (b) ? (a) : (b))
#define FFMAX3(a,b,c) FFMAX(FFMAX(a,b),c)


/// @brief hdr BiPlanar fragment shader
/// @param stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
/// @param texture表明是纹理数据，IJKFragmentTextureIndexTextureY/UV 是索引
/// @param buffer表明是缓存数据，IJKFragmentBufferIndexMatrix是索引
fragment float4 hdrBiPlanarFragmentShader(RasterizerData input [[stage_in]],
                                   device IJKFragmentShaderArguments & fragmentShaderArgs [[ buffer(IJKFragmentBufferLocation0) ]])
{
    // sampler是采样器
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    texture2d<float> textureY = fragmentShaderArgs.textureY;
    texture2d<float> textureUV = fragmentShaderArgs.textureU;
    
    float3 yuv = float3(textureY.sample(textureSampler,  input.textureCoordinate).r,
                        textureUV.sample(textureSampler, input.textureCoordinate).rg);
    //使用 BT.2020 矩阵转为RGB
    device IJKConvertMatrix* convertMatrix = fragmentShaderArgs.convertMatrix;
    
    float3 rgb10bit = convertMatrix->matrix * (yuv + convertMatrix->offset);
    
    // 1、HDR 非线性电信号转为 HDR 线性光信号（EOTF）
    float peak_luminance = 50.0;
    float3 myFragColor;
    
    if (convertMatrix->transferFun == IJKColorTransferFuncPQ) {
       float to_linear_scale = 10000.0 / peak_luminance;
       myFragColor = to_linear_scale * float3(st_2084_eotf(rgb10bit.r), st_2084_eotf(rgb10bit.g), st_2084_eotf(rgb10bit.b));
    } else if (convertMatrix->transferFun == IJKColorTransferFuncHLG) {
       float to_linear_scale = 1000.0 / peak_luminance;
       myFragColor = to_linear_scale * float3(arib_b67_eotf(rgb10bit.r), arib_b67_eotf(rgb10bit.g), arib_b67_eotf(rgb10bit.b));
    } else {
       myFragColor = float3(rec_1886_eotf(rgb10bit.r), rec_1886_eotf(rgb10bit.g), rec_1886_eotf(rgb10bit.b));
    }

    // 2、HDR 线性光信号做颜色空间转换（Color Space Converting）
    // color-primaries REC_2020 to REC_709
    matrix_float3x3 rgb2xyz2020 = matrix_float3x3(0.6370, 0.1446, 0.1689,
                           0.2627, 0.6780, 0.0593,
                           0.0000, 0.0281, 1.0610);
    matrix_float3x3 xyz2rgb709 = matrix_float3x3(3.2410, -1.5374, -0.4986,
                          -0.9692, 1.8760, 0.0416,
                          0.0556, -0.2040, 1.0570);
    myFragColor *= rgb2xyz2020 * xyz2rgb709;

    // 3、HDR 线性光信号色调映射为 SDR 线性光信号（Tone Mapping）
    float sig = FFMAX(FFMAX3(myFragColor.r, myFragColor.g, myFragColor.b), 1e-6);
    float sig_orig = sig;
    float peak = 10.0;
    sig = hableF(sig) / hableF(peak);
    myFragColor *= sig / sig_orig;

    // 4、SDR 线性光信号转 SDR 非线性电信号（OETF）
    myFragColor = float3(rec_1886_inverse_eotf(myFragColor.r), rec_1886_inverse_eotf(myFragColor.g), rec_1886_inverse_eotf(myFragColor.b));
    //color adjustment
    return float4(rgb_adjust(myFragColor,convertMatrix->adjustment),1.0);
}

/// @brief yuv420p fragment shader
/// @param stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
/// @param texture表明是纹理数据，IJKFragmentTextureIndexTextureY/U/V 是索引
/// @param buffer表明是缓存数据，IJKFragmentBufferIndexMatrix是索引
fragment float4 yuv420pFragmentShader(RasterizerData input [[stage_in]],
                                      device IJKFragmentShaderArguments & fragmentShaderArgs [[ buffer(IJKFragmentBufferLocation0) ]])
{
    // sampler是采样器
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    texture2d<float> textureY = fragmentShaderArgs.textureY;
    texture2d<float> textureU = fragmentShaderArgs.textureU;
    texture2d<float> textureV = fragmentShaderArgs.textureV;
    
    float3 yuv = float3(textureY.sample(textureSampler, input.textureCoordinate).r,
                        textureU.sample(textureSampler, input.textureCoordinate).r,
                        textureV.sample(textureSampler, input.textureCoordinate).r);
    
    device IJKConvertMatrix* convertMatrix = fragmentShaderArgs.convertMatrix;
    float3 rgb = convertMatrix->matrix * (yuv + convertMatrix->offset);
    //color adjustment
    return float4(rgb_adjust(rgb,convertMatrix->adjustment),1.0);
}

/// @brief uyvy422 fragment shader
/// @param stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
/// @param texture表明是纹理数据，IJKFragmentTextureIndexTextureY 是索引
/// @param buffer表明是缓存数据，IJKFragmentBufferIndexMatrix是索引
fragment float4 uyvy422FragmentShader(RasterizerData input [[stage_in]],
                                      device IJKFragmentShaderArguments & fragmentShaderArgs [[ buffer(IJKFragmentBufferLocation0) ]])
{
    // sampler是采样器
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    texture2d<float> textureY = fragmentShaderArgs.textureY;
    float3 tc = textureY.sample(textureSampler, input.textureCoordinate).rgb;
    float3 yuv = float3(tc.g, tc.b, tc.r);
    
    device IJKConvertMatrix* convertMatrix = fragmentShaderArgs.convertMatrix;
    float3 rgb = convertMatrix->matrix * (yuv + convertMatrix->offset);
    //color adjustment 
    return float4(rgb_adjust(rgb,convertMatrix->adjustment),1.0);
}

#else

vertex RasterizerData subVertexShader(uint vertexID [[vertex_id]],
             constant IJKVertex *vertices [[buffer(IJKVertexInputIndexVertices)]])
{
    RasterizerData out;
    out.clipSpacePosition = float4(vertices[vertexID].position, 0.0, 1.0);
    out.textureCoordinate = vertices[vertexID].textureCoordinate;
    return out;
}

//支持mvp矩阵
vertex RasterizerData mvpShader(uint vertexID [[vertex_id]],
             constant IJKVertexData & data [[buffer(IJKVertexInputIndexVertices)]])
{
    RasterizerData out;
    IJKVertex _vertex = data.vertexes[vertexID];
    float4 position = float4(_vertex.position, 0.0, 1.0);
    out.clipSpacePosition = data.modelMatrix * position;
    out.textureCoordinate = _vertex.textureCoordinate;
    return out;
}

float3 rgb_adjust(float3 rgb,float4 rgbAdjustment) {
    //C 是对比度值，B 是亮度值，S 是饱和度
    float B = rgbAdjustment.x;
    float S = rgbAdjustment.y;
    float C = rgbAdjustment.z;
    float on= rgbAdjustment.w;
    if (on > 0.99) {
        rgb = (rgb - 0.5) * C + 0.5;
        rgb = rgb + (0.75 * B - 0.5) / 2.5 - 0.1;
        float3 intensity = float3(rgb * float3(0.299, 0.587, 0.114));
        return intensity + S * (rgb - intensity);
    } else {
        return rgb;
    }
}

/// @brief bgra fragment shader
/// @param stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
/// @param texture表明是纹理数据，IJKFragmentTextureIndexTextureY 是索引
fragment float4 bgraFragmentShader(RasterizerData input [[stage_in]],
                                   texture2d<float> textureY [[ texture(IJKFragmentTextureIndexTextureY) ]],
                                   constant IJKConvertMatrix &convertMatrix [[ buffer(IJKFragmentMatrixIndexConvert) ]])
{
    // sampler是采样器
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    //auto converted bgra -> rgba
    float4 rgba = textureY.sample(textureSampler, input.textureCoordinate);
    //color adjustment
    return float4(rgb_adjust(rgba.rgb, convertMatrix.adjustment),rgba.a);
}

/// @brief argb fragment shader
/// @param stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
/// @param texture表明是纹理数据，IJKFragmentTextureIndexTextureY 是索引
fragment float4 argbFragmentShader(RasterizerData input [[stage_in]],
                                   texture2d<float> textureY [[ texture(IJKFragmentTextureIndexTextureY) ]],
                                   constant IJKConvertMatrix &convertMatrix [[ buffer(IJKFragmentMatrixIndexConvert) ]])
{
    // sampler是采样器
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    //auto converted bgra -> rgba
    float4 grab = textureY.sample(textureSampler, input.textureCoordinate);
    //color adjustment
    return float4(rgb_adjust(grab.gra, convertMatrix.adjustment),grab.b);
}

/// @brief nv12 fragment shader
/// @param stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
/// @param texture表明是纹理数据，IJKFragmentTextureIndexTextureY/UV 是索引
/// @param buffer表明是缓存数据，IJKFragmentBufferIndexMatrix是索引
fragment float4 nv12FragmentShader(RasterizerData input [[stage_in]],
                                   texture2d<float> textureY  [[ texture(IJKFragmentTextureIndexTextureY)  ]],
                                   texture2d<float> textureUV [[ texture(IJKFragmentTextureIndexTextureU) ]],
                                   constant IJKConvertMatrix &convertMatrix [[ buffer(IJKFragmentMatrixIndexConvert) ]])
{
    // sampler是采样器
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    
    float3 yuv = float3(textureY.sample(textureSampler,  input.textureCoordinate).r,
                        textureUV.sample(textureSampler, input.textureCoordinate).rg);
    
    float3 rgb = convertMatrix.matrix * (yuv + convertMatrix.offset);
    //color adjustment
    return float4(rgb_adjust(rgb,convertMatrix.adjustment),1.0);
}

/// @brief yuv420p fragment shader
/// @param stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
/// @param texture表明是纹理数据，IJKFragmentTextureIndexTextureY/U/V 是索引
/// @param buffer表明是缓存数据，IJKFragmentBufferIndexMatrix是索引
fragment float4 yuv420pFragmentShader(RasterizerData input [[stage_in]],
                                      texture2d<float> textureY [[ texture(IJKFragmentTextureIndexTextureY) ]],
                                      texture2d<float> textureU [[ texture(IJKFragmentTextureIndexTextureU) ]],
                                      texture2d<float> textureV [[ texture(IJKFragmentTextureIndexTextureV) ]],
                                      constant IJKConvertMatrix &convertMatrix [[ buffer(IJKFragmentMatrixIndexConvert) ]])
{
    // sampler是采样器
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    
    float3 yuv = float3(textureY.sample(textureSampler, input.textureCoordinate).r,
                        textureU.sample(textureSampler, input.textureCoordinate).r,
                        textureV.sample(textureSampler, input.textureCoordinate).r);
    
    float3 rgb = convertMatrix.matrix * (yuv + convertMatrix.offset);
    //color adjustment
    return float4(rgb_adjust(rgb,convertMatrix.adjustment),1.0);
}

/// @brief uyvy422 fragment shader
/// @param stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
/// @param texture表明是纹理数据，IJKFragmentTextureIndexTextureY 是索引
/// @param buffer表明是缓存数据，IJKFragmentBufferIndexMatrix是索引
fragment float4 uyvy422FragmentShader(RasterizerData input [[stage_in]],
                                      texture2d<float> textureY [[ texture(IJKFragmentTextureIndexTextureY) ]],
                                      constant IJKConvertMatrix &convertMatrix [[ buffer(IJKFragmentMatrixIndexConvert) ]])
{
    // sampler是采样器
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    float3 tc = textureY.sample(textureSampler, input.textureCoordinate).rgb;
    float3 yuv = float3(tc.g, tc.b, tc.r);
    
    float3 rgb = convertMatrix.matrix * (yuv + convertMatrix.offset);
    //color adjustment
    return float4(rgb_adjust(rgb,convertMatrix.adjustment),1.0);
}
#endif
