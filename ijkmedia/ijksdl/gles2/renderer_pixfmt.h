/*
 * Copyright (c) 2016 Bilibili
 * copyright (c) 2016 Zhang Rui <bbcallen@gmail.com>
 *
 * This file is part of ijkPlayer.
 *
 * ijkPlayer is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * ijkPlayer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with ijkPlayer; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#ifndef IJKSDL__renderer_pixfmt__INTERNAL__H
#define IJKSDL__renderer_pixfmt__INTERNAL__H

enum mp_imgfmt {
    IMGFMT_NONE = 0,

    // Offset to make confusing with ffmpeg formats harder
    IMGFMT_START = 1000,

    // Planar YUV formats
    IMGFMT_444P,                // 1x1
    IMGFMT_420P,                // 2x2

    // Gray
    IMGFMT_Y8,
    IMGFMT_Y16,

    // Packed YUV formats (components are byte-accessed)
    IMGFMT_UYVY,                // U  Y0 V  Y1

    // Y plane + packed plane for chroma
    IMGFMT_NV12,

    // Like IMGFMT_NV12, but with 10 bits per component (and 6 bits of padding)
    IMGFMT_P010,

    // Like IMGFMT_NV12, but for 4:4:4
    IMGFMT_NV24,

    // RGB/BGR Formats

    // Byte accessed (low address to high address)
    IMGFMT_ARGB,
    IMGFMT_BGRA,
    IMGFMT_ABGR,
    IMGFMT_RGBA,
    IMGFMT_BGR24,               // 3 bytes per pixel
    IMGFMT_RGB24,

    // Like e.g. IMGFMT_ARGB, but has a padding byte instead of alpha
    IMGFMT_0RGB,
    IMGFMT_BGR0,
    IMGFMT_0BGR,
    IMGFMT_RGB0,

    IMGFMT_RGB0_START = IMGFMT_0RGB,
    IMGFMT_RGB0_END = IMGFMT_RGB0,

    // Like IMGFMT_RGBA, but 2 bytes per component.
    IMGFMT_RGBA64,

    // Accessed with bit-shifts after endian-swapping the uint16_t pixel
    IMGFMT_RGB565,              // 5r 6g 5b (MSB to LSB)

    // Hardware accelerated formats. Plane data points to special data
    // structures, instead of pixel data.
    IMGFMT_VDPAU,           // VdpVideoSurface
    IMGFMT_VDPAU_OUTPUT,    // VdpOutputSurface
    IMGFMT_VAAPI,
    // plane 0: ID3D11Texture2D
    // plane 1: slice index casted to pointer
    IMGFMT_D3D11,
    IMGFMT_DXVA2,           // IDirect3DSurface9 (NV12/P010/P016)
    IMGFMT_MMAL,            // MMAL_BUFFER_HEADER_T
    IMGFMT_VIDEOTOOLBOX,    // CVPixelBufferRef
    IMGFMT_MEDIACODEC,      // AVMediaCodecBuffer
    IMGFMT_DRMPRIME,        // AVDRMFrameDescriptor
    IMGFMT_CUDA,            // CUDA Buffer

    // Generic pass-through of AV_PIX_FMT_*. Used for formats which don't have
    // a corresponding IMGFMT_ value.
    IMGFMT_AVPIXFMT_START,
    IMGFMT_AVPIXFMT_END = IMGFMT_AVPIXFMT_START + 500,

    IMGFMT_END
};

#define MP_MAX_PLANES 4
#define MP_ARRAY_SIZE(s) (sizeof(s) / sizeof((s)[0]))

struct vt_gl_plane_format {
    GLenum gl_format;
    GLenum gl_type;
    GLenum gl_internal_format;
};

struct vt_format {
    uint32_t cvpixfmt;
    int imgfmt;
    int planes;
    struct vt_gl_plane_format gl[MP_MAX_PLANES];
    char swizzle[5];
};

static struct vt_format vt_formats[] = {
    {
        .cvpixfmt = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        .imgfmt = IMGFMT_NV12,
        .planes = 2,
        .gl = {
            { GL_RED, GL_UNSIGNED_BYTE, GL_RED },
            { GL_RG,  GL_UNSIGNED_BYTE, GL_RG } ,
        }
    },
    {
        .cvpixfmt = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        .imgfmt = IMGFMT_NV12,
        .planes = 2,
        .gl = {
            { GL_RED, GL_UNSIGNED_BYTE, GL_RED },
            { GL_RG,  GL_UNSIGNED_BYTE, GL_RG } ,
        }
    },

    {
        .cvpixfmt = kCVPixelFormatType_422YpCbCr8,
        .imgfmt = IMGFMT_UYVY,
        .planes = 1,
        .gl = {
            { GL_RGB_422_APPLE, GL_UNSIGNED_SHORT_8_8_APPLE, GL_RGB }
        },
        .swizzle = "gbra",
    },
    {
        .cvpixfmt = kCVPixelFormatType_420YpCbCr8Planar,
        .imgfmt = IMGFMT_420P,
        .planes = 3,
        .gl = {
            { GL_RED, GL_UNSIGNED_BYTE, GL_RED },
            { GL_RED, GL_UNSIGNED_BYTE, GL_RED },
            { GL_RED, GL_UNSIGNED_BYTE, GL_RED },
        }
    },
    {
        .cvpixfmt = kCVPixelFormatType_32BGRA,
        .imgfmt = IMGFMT_BGR0,
        .planes = 1,
        .gl = {
            { GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, GL_RGBA }
        }
    },
};

static struct vt_format *vt_get_gl_format(uint32_t cvpixfmt)
{
    for (int i = 0; i < MP_ARRAY_SIZE(vt_formats); i++) {
        if (vt_formats[i].cvpixfmt == cvpixfmt)
            return &vt_formats[i];
    }
    return NULL;
}

#endif
