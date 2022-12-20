//
//  IJKMetalShaderTypes.h
//  FFmpegTutorial-macOS
//
//  Created by qianlongxu on 2022/11/23.
//  Copyright © 2022 Matt Reach's Awesome FFmpeg Tutotial. All rights reserved.
//

#ifndef IJKMetalShaderTypes_h
#define IJKMetalShaderTypes_h

#include <simd/simd.h>

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs
// match Metal API buffer set calls.
typedef enum IJKVertexInputIndex
{
    IJKVertexInputIndexVertices  = 0,
    IJKVertexInputIndexMVP       = 1,
} IJKVertexInputIndex;

//  This structure defines the layout of vertices sent to the vertex
//  shader. This header is shared between the .metal shader and C code, to guarantee that
//  the layout of the vertex array in the C code matches the layout that the .metal
//  vertex shader expects.
typedef struct
{
    vector_float4 position;
    vector_float2 textureCoordinate;
} IJKVertex;

typedef struct
{
    matrix_float4x4 modelMatrix;
} IJKMVPMatrix;

typedef struct {
    matrix_float3x3 matrix;
    vector_float3 offset;
    vector_float4 adjustment;
} IJKConvertMatrix;

typedef struct IJKSubtitleArguments
{
    int on;
    float x;
    float y;
    float w;
    float h;
}IJKSubtitleArguments;

typedef struct IJKFragmentShaderData {
    IJKConvertMatrix convertMatrix;
    IJKSubtitleArguments subRect;
}IJKFragmentShaderData;

typedef enum IJKFragmentBufferArguments
{
    IJKFragmentTextureIndexTextureY,
    IJKFragmentTextureIndexTextureU,
    IJKFragmentTextureIndexTextureV,
    IJKFragmentTextureIndexTextureSub,
    IJKFragmentDataIndex,
    IJKFragmentSubtitleRect
} IJKFragmentBufferArguments;

typedef enum IJKFragmentBufferLocation
{
    IJKFragmentBufferLocation0,
} IJKFragmentBufferLocation;

typedef enum IJKYUVToRGBMatrixType
{
    IJKYUVToRGBNoneMatrix,
    IJKYUVToRGBBT709FullRangeMatrix,
    IJKYUVToRGBBT709VideoRangeMatrix,
    IJKYUVToRGBBT601FullRangeMatrix,
    IJKYUVToRGBBT601VideoRangeMatrix,
    IJKUYVYToRGBFullRangeMatrix,
    IJKUYVYToRGBVideoRangeMatrix,
} IJKYUVToRGBMatrixType;

#endif /* IJKMetalShaderTypes_h */
