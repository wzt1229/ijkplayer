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
    uniform sampler2D us2_SamplerX;
    uniform sampler2D us2_SamplerY;

    void main()
    {
        vec3 yuv;
        vec3 rgb;

        yuv.x  = (texture2D(us2_SamplerX,  vv2_Texcoord).r  - (16.0 / 255.0));
        yuv.yz = (texture2D(us2_SamplerY,  vv2_Texcoord).rg - vec2(0.5, 0.5));
        rgb = um3_ColorConversion * yuv;
        gl_FragColor = vec4(rgb, 1);
    }
);

//macOS use sampler2DRect,need texture dimensions
static const char g_shader_rect[] = IJK_GLES_STRING(
    varying vec2 vv2_Texcoord;
    uniform mat3 um3_ColorConversion;
    //wtf? can't use 'um3_PreColorConversion'
    uniform vec3 um3_Pre_ColorConversion;
    uniform sampler2DRect us2_SamplerX;
    uniform sampler2DRect us2_SamplerY;
    uniform vec2 textureDimensionX;
    uniform vec2 textureDimensionY;
    uniform int isSubtitle;
                                                    
//    vec3 applyHue(vec3 aColor, float aHue)
//    {
//        //Range(-360, 360)
//        float angle = radians(aHue);
//        vec3 k = vec3(0.57735, 0.57735, 0.57735);
//        float cosAngle = cos(angle);
//        //Rodrigues' rotation formula
//        return aColor * cosAngle + cross(k, aColor) * sin(angle) + k * dot(k, aColor) * (1.0 - cosAngle);
//    }
                                                    
                                                    
    void main()
    {
        if (isSubtitle == 1) {
            vec2 recTexCoordX = vv2_Texcoord * textureDimensionX;
            gl_FragColor = texture2DRect(us2_SamplerX, recTexCoordX);
        } else {
            vec3 yuv;
            vec3 rgb;
            
            vec2 recTexCoordX = vv2_Texcoord * textureDimensionX;
            vec2 recTexCoordY = vv2_Texcoord * textureDimensionY;
            //yuv.x = (texture2DRect(us2_SamplerX, recTexCoord).r  - (16.0 / 255.0));
            //videotoolbox decoded video range pixel already! kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            yuv.x = texture2DRect(us2_SamplerX, recTexCoordX).r;
            yuv.yz = (texture2DRect(us2_SamplerY, recTexCoordY).ra - vec2(0.5, 0.5));
            
            //C 是对比度值，B 是亮度值，S 是饱和度
            float B = um3_Pre_ColorConversion.x;
            float S = um3_Pre_ColorConversion.y;
            float C = um3_Pre_ColorConversion.z;

            rgb = um3_ColorConversion * yuv;

//            rgb = applyHue(rgb, 0.0);
            rgb = (rgb - 0.5) * C + 0.5;
            rgb = rgb + B;
            vec3 intensity = vec3(dot(rgb, vec3(0.299, 0.587, 0.114)));
            rgb = intensity + S * (rgb - intensity);

            vec4 result = vec4(rgb, 1.0);
            gl_FragColor = result;
        }
    }
);

const char *IJK_GL_getFragmentShader_yuv420sp()
{
    return g_shader;
}

const char *IJK_GL_getFragmentShader_yuv420sp_rect()
{
    return g_shader_rect;
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
