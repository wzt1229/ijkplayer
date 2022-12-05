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
} IJKConvertMatrix;

typedef enum IJKFragmentBufferIndex
{
    IJKFragmentInputIndexMatrix     = 0,
} IJKFragmentBufferIndex;

typedef enum IJKFragmentTextureIndex
{
    IJKFragmentTextureIndexTextureY  = 0,
    IJKFragmentTextureIndexTextureU  = 1,
    IJKFragmentTextureIndexTextureV  = 2,
} IJKFragmentTextureIndex;

typedef enum IJKYUVToRGBMatrixType
{
    IJKYUVToRGBBT709Matrix = 0,
    IJKYUVToRGBBT601Matrix = 1,
    IJKUYVYToRGBMatrix = 2,
} IJKYUVToRGBMatrixType;


#endif /* IJKMetalShaderTypes_h */
