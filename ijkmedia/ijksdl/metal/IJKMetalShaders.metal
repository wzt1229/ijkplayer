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

vertex RasterizerData vertexShader(uint vertexID [[vertex_id]],
             constant IJKVertex *vertices [[buffer(IJKVertexInputIndexVertices)]])
{
    RasterizerData out;
    out.clipSpacePosition = vertices[vertexID].position;
    out.textureCoordinate = vertices[vertexID].textureCoordinate;
    return out;
}

//支持mvp矩阵
vertex RasterizerData mvpShader(uint vertexID [[vertex_id]],
             constant IJKVertex *vertices [[buffer(IJKVertexInputIndexVertices)]],
             constant IJKMVPMatrix &mvp   [[buffer(IJKVertexInputIndexMVP)]])
{
    RasterizerData out;
    out.clipSpacePosition = mvp.modelMatrix * vertices[vertexID].position;
    out.textureCoordinate = vertices[vertexID].textureCoordinate;
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

float4 subtitle(float4 rgba,float2 texCoord,texture2d<float> subTexture,IJKSubtitleArguments subRect)
{
    if (!subRect.on) {
        return rgba;
    }
    
    //翻转画面坐标系，这个会影响字幕在画面上的位置；翻转后从底部往上布局
    texCoord.y = 1 - texCoord.y;
    
    float sx = subRect.x;
    float sy = subRect.y;
    //限定字幕纹理区域
    if (texCoord.x >= sx && texCoord.x <= (sx + subRect.w) && texCoord.y >= sy && texCoord.y <= (sy + subRect.h)) {
        //在该区域内，将坐标缩放到 [0,1]
        texCoord.x = (texCoord.x - sx) / subRect.w;
        texCoord.y = (texCoord.y - sy) / subRect.h;
        //flip the y
        texCoord.y = 1 - texCoord.y;
        constexpr sampler textureSampler (mag_filter::linear,
                                          min_filter::linear);
        // Sample the encoded texture in the argument buffer.
        float4 textureSample = subTexture.sample(textureSampler, texCoord);
        // Add the subtitle and color values together and return the result.
        return float4((1.0 - textureSample.a) * rgba + textureSample);
    }  else {
        return rgba;
    }
}

struct IJKFragmentShaderArguments {
    texture2d<float> textureY [[ id(IJKFragmentTextureIndexTextureY) ]];
    texture2d<float> textureU [[ id(IJKFragmentTextureIndexTextureU) ]];
    texture2d<float> textureV [[ id(IJKFragmentTextureIndexTextureV) ]];
    texture2d<float> subTexture [[ id(IJKFragmentTextureIndexTextureSub) ]];
    IJKFragmentShaderData data [[ id(IJKFragmentDataIndex) ]];
};


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
    IJKConvertMatrix convertMatrix = fragmentShaderArgs.data.convertMatrix;
    rgba = float4(rgb_adjust(rgba.rgb, convertMatrix.adjustment),rgba.a);
    //subtitle
    return subtitle(rgba, input.textureCoordinate, fragmentShaderArgs.subTexture, fragmentShaderArgs.data.subRect);
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
    
    IJKConvertMatrix convertMatrix = fragmentShaderArgs.data.convertMatrix;
    float3 rgb = convertMatrix.matrix * (yuv + convertMatrix.offset);
    //color adjustment
    float4 rgba = float4(rgb_adjust(rgb,convertMatrix.adjustment),1.0);
    //subtitle
    return subtitle(rgba, input.textureCoordinate, fragmentShaderArgs.subTexture, fragmentShaderArgs.data.subRect);
}

/// @brief nv21 fragment shader
/// @param stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
/// @param texture表明是纹理数据，IJKFragmentTextureIndexTextureY/UV 是索引
/// @param buffer表明是缓存数据，IJKFragmentBufferIndexMatrix是索引
fragment float4 nv21FragmentShader(RasterizerData input [[stage_in]],
                                   device IJKFragmentShaderArguments & fragmentShaderArgs [[ buffer(IJKFragmentBufferLocation0) ]])
{
    // sampler是采样器
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    texture2d<float> textureY = fragmentShaderArgs.textureY;
    texture2d<float> textureUV = fragmentShaderArgs.textureU;
    
    float3 yuv = float3(textureY.sample(textureSampler,  input.textureCoordinate).r,
                        textureUV.sample(textureSampler, input.textureCoordinate).gr);
    
    IJKConvertMatrix convertMatrix = fragmentShaderArgs.data.convertMatrix;
    float3 rgb = convertMatrix.matrix * (yuv + convertMatrix.offset);
    //color adjustment
    float4 rgba = float4(rgb_adjust(rgb,convertMatrix.adjustment),1.0);
    //subtitle
    return subtitle(rgba, input.textureCoordinate, fragmentShaderArgs.subTexture, fragmentShaderArgs.data.subRect);
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
    
    IJKConvertMatrix convertMatrix = fragmentShaderArgs.data.convertMatrix;
    float3 rgb = convertMatrix.matrix * (yuv + convertMatrix.offset);
    //color adjustment
    float4 rgba = float4(rgb_adjust(rgb,convertMatrix.adjustment),1.0);
    //subtitle
    return subtitle(rgba, input.textureCoordinate, fragmentShaderArgs.subTexture, fragmentShaderArgs.data.subRect);
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
    
    IJKConvertMatrix convertMatrix = fragmentShaderArgs.data.convertMatrix;
    float3 rgb = convertMatrix.matrix * (yuv + convertMatrix.offset);
    //color adjustment 
    float4 rgba = float4(rgb_adjust(rgb,convertMatrix.adjustment),1.0);
    //subtitle
    return subtitle(rgba, input.textureCoordinate, fragmentShaderArgs.subTexture, fragmentShaderArgs.data.subRect);
}
