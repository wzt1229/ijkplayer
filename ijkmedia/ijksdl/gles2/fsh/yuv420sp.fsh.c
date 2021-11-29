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

#include "ijksdl/gles2/internal.h"

#if TARGET_OS_OSX

static const char g_shader[] = IJK_GLES_STRING(
    varying vec2 vv2_Texcoord;
    uniform mat3 um3_ColorConversion;
    uniform sampler2D us2_Sampler0;
    uniform sampler2D us2_Sampler1;

    void main()
    {
        vec3 yuv;
        vec3 rgb;

        yuv.x  = (texture2D(us2_Sampler0,  vv2_Texcoord).r  - (16.0 / 255.0));
        yuv.yz = (texture2D(us2_Sampler1,  vv2_Texcoord).rg - vec2(0.5, 0.5));
        rgb = um3_ColorConversion * yuv;
        gl_FragColor = vec4(rgb, 1);
    }
);

//macOS use sampler2DRect,need texture dimensions
static const char g_shader_rect_2[] = IJK_GLES_STRING(
    varying vec2 vv2_Texcoord;
    uniform mat3 um3_ColorConversion;
    uniform vec3 um3_rgbAdjustment;
    uniform sampler2DRect us2_Sampler0;
    uniform sampler2DRect us2_Sampler1;
    uniform vec2 textureDimension0;
    uniform vec2 textureDimension1;
    uniform int isSubtitle;
    
                                                      
    void main()
    {
        if (isSubtitle == 1) {
            vec2 recTexCoord0 = vv2_Texcoord * textureDimension0;
            gl_FragColor = texture2DRect(us2_Sampler0, recTexCoord0);
        } else {
            vec3 yuv;
            vec3 rgb;
            
            vec2 recTexCoord0 = vv2_Texcoord * textureDimension0;
            vec2 recTexCoord1 = vv2_Texcoord * textureDimension1;
            //yuv.x = (texture2DRect(us2_Sampler0, recTexCoord).r  - (16.0 / 255.0));
            //videotoolbox decoded video range pixel already! kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            yuv.x = texture2DRect(us2_Sampler0, recTexCoord0).r;
            yuv.yz = (texture2DRect(us2_Sampler1, recTexCoord1).ra - vec2(0.5, 0.5));
            
            rgb = um3_ColorConversion * yuv;
            
            //C 是对比度值，B 是亮度值，S 是饱和度
            float B = um3_rgbAdjustment.x;
            float S = um3_rgbAdjustment.y;
            float C = um3_rgbAdjustment.z;

            rgb = (rgb - 0.5) * C + 0.5;
            rgb = rgb + (0.75 * B - 0.5) / 2.5 - 0.1;
            vec3 intensity = vec3(dot(rgb, vec3(0.299, 0.587, 0.114)));
            rgb = intensity + S * (rgb - intensity);

            gl_FragColor = vec4(rgb, 1.0);
        }
    }
);

//for yuv420p
static const char g_shader_rect_3[] = IJK_GLES_STRING(
    varying vec2 vv2_Texcoord;
    uniform mat3 um3_ColorConversion;
    uniform vec3 um3_rgbAdjustment;
                                                     
    uniform sampler2DRect us2_Sampler0;
    uniform sampler2DRect us2_Sampler1;
    uniform sampler2DRect us2_Sampler2;
                                                     
    uniform vec2 textureDimension0;
    uniform vec2 textureDimension1;
    uniform vec2 textureDimension2;
                                                     
    uniform int isSubtitle;
                                                    

    void main()
    {
        if (isSubtitle == 1) {
            vec2 recTexCoord0 = vv2_Texcoord * textureDimension0;
            gl_FragColor = texture2DRect(us2_Sampler0, recTexCoord0);
        } else {
            vec3 yuv;
            vec3 rgb;
            
            vec2 recTexCoord0 = vv2_Texcoord * textureDimension0;
            vec2 recTexCoord1 = vv2_Texcoord * textureDimension1;
            vec2 recTexCoord2 = vv2_Texcoord * textureDimension2;

            yuv.x = (texture2DRect(us2_Sampler0, recTexCoord0).r - (16.0 / 255.0));
            yuv.y = (texture2DRect(us2_Sampler1, recTexCoord1).r - 0.5);
            yuv.z = (texture2DRect(us2_Sampler2, recTexCoord2).r - 0.5);
            
            rgb = um3_ColorConversion * yuv;
            
            //C 是对比度值，B 是亮度值，S 是饱和度
            float B = um3_rgbAdjustment.x;
            float S = um3_rgbAdjustment.y;
            float C = um3_rgbAdjustment.z;

            rgb = (rgb - 0.5) * C + 0.5;
            rgb = rgb + (0.75 * B - 0.5) / 2.5 - 0.1;
            vec3 intensity = vec3(dot(rgb, vec3(0.299, 0.587, 0.114)));
            rgb = intensity + S * (rgb - intensity);

            gl_FragColor = vec4(rgb, 1.0);
        }
    }
);

const char *IJK_GL_getFragmentShader_yuv420sp()
{
    return g_shader;
}

const char *IJK_GL_getFragmentShader_yuv420sp_rect(int samples)
{
    if (samples == 2) {
        return g_shader_rect_2;
    } else if (samples == 3) {
        return g_shader_rect_3;
    } else {
        assert(0);
        return "";
    }
}

#else

static const char g_shader[] = IJK_GLES_STRING(
    precision highp float;
    varying   highp vec2 vv2_Texcoord;
    uniform         mat3 um3_ColorConversion;
    uniform   lowp  sampler2D us2_SamplerX;
    uniform   lowp  sampler2D us2_SamplerY;

    void main()
    {
        mediump vec3 yuv;
        lowp    vec3 rgb;

        yuv.x  = (texture2D(us2_SamplerX,  vv2_Texcoord).r  - (16.0 / 255.0));
        yuv.yz = (texture2D(us2_SamplerY,  vv2_Texcoord).rg - vec2(0.5, 0.5));
        rgb = um3_ColorConversion * yuv;
        gl_FragColor = vec4(rgb, 1);
    }
);

const char *IJK_GL_getFragmentShader_yuv420sp()
{
    return g_shader;
}

#endif
