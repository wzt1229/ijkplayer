//
//  IJKMetalPixelTypes.h
//  FFmpegTutorial-macOS
//
//  Created by qianlongxu on 2022/11/23.
//  Copyright © 2022 Matt Reach's Awesome FFmpeg Tutotial. All rights reserved.
//

#ifndef IJKMetalPixelTypes_h
#define IJKMetalPixelTypes_h

typedef struct mp_format {
    uint32_t cvpixfmt;
    int planes;
    MTLPixelFormat formats[3];
}mp_format;

static struct mp_format mp_formats[] = {
    {
        .cvpixfmt = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        .planes = 2,
        .formats = {MTLPixelFormatR8Unorm,MTLPixelFormatRG8Unorm}
    },
    {
        .cvpixfmt = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        .planes = 2,
        .formats = {MTLPixelFormatR8Unorm,MTLPixelFormatRG8Unorm}
    },
    {
        .cvpixfmt = kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange,
        .planes = 2,
        .formats = {MTLPixelFormatR16Unorm,MTLPixelFormatRG16Unorm}
    },
    {
        .cvpixfmt = kCVPixelFormatType_444YpCbCr10BiPlanarFullRange,
        .planes = 2,
        .formats = {MTLPixelFormatR16Unorm,MTLPixelFormatRG16Unorm}
    },
    {
        .cvpixfmt = kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange,
        .planes = 2,
        .formats = {MTLPixelFormatR16Unorm,MTLPixelFormatRG16Unorm}
    },
    {
        .cvpixfmt = kCVPixelFormatType_422YpCbCr10BiPlanarFullRange,
        .planes = 2,
        .formats = {MTLPixelFormatR16Unorm,MTLPixelFormatRG16Unorm}
    },
    {
        .cvpixfmt = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        .planes = 2,
        .formats = {MTLPixelFormatR16Unorm,MTLPixelFormatRG16Unorm}
    },
    {
        .cvpixfmt = kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
        .planes = 2,
        .formats = {MTLPixelFormatR16Unorm,MTLPixelFormatRG16Unorm}
    },
#if TARGET_OS_OSX
    {
        .cvpixfmt = kCVPixelFormatType_422YpCbCr8,
        .planes = 1,
        .formats = {MTLPixelFormatBGRG422}
    },
    {
        .cvpixfmt = kCVPixelFormatType_422YpCbCr8_yuvs,
        .planes = 1,
        .formats = {MTLPixelFormatGBGR422}
    },
    {
        .cvpixfmt = kCVPixelFormatType_422YpCbCr8FullRange,
        .planes = 1,
        .formats = {MTLPixelFormatGBGR422}
    },
#endif
    {
        .cvpixfmt = kCVPixelFormatType_420YpCbCr8Planar,
        .planes = 3,
        .formats = {MTLPixelFormatR8Unorm,MTLPixelFormatR8Unorm,MTLPixelFormatR8Unorm}
    },
    {
        .cvpixfmt = kCVPixelFormatType_420YpCbCr8PlanarFullRange,
        .planes = 3,
        .formats = {MTLPixelFormatR8Unorm,MTLPixelFormatR8Unorm,MTLPixelFormatR8Unorm}
    },
    {
        .cvpixfmt = kCVPixelFormatType_32BGRA,
        .planes = 1,
        .formats = {MTLPixelFormatBGRA8Unorm}
    },
    {
        .cvpixfmt = kCVPixelFormatType_32ARGB,
        .planes = 1,
        .formats = {MTLPixelFormatBGRA8Unorm}
    },
};

#define MP_ARRAY_SIZE(s) (sizeof(s) / sizeof((s)[0]))

static inline mp_format *mp_get_metal_format(uint32_t cvpixfmt)
{
    for (int i = 0; i < MP_ARRAY_SIZE(mp_formats); i++) {
        if (mp_formats[i].cvpixfmt == cvpixfmt)
            return &mp_formats[i];
    }
    return NULL;
}


#endif /* IJKMetalPixelTypes_h */
