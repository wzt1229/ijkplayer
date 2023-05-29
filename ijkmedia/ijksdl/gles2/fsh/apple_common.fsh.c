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

//only macOS use sampler2DRect,need texture dimensions

//for 420sp
static const char apple_nv12_shader[] = IJK_GLES_STRING(
    varying vec2 vv2_Texcoord;
    uniform mat3 um3_ColorConversion;
    uniform vec3 um3_rgbAdjustment;
    
    uniform sampler2DRect us2_Sampler0;
    uniform sampler2DRect us2_Sampler1;
#if TARGET_OS_OSX
    uniform vec2 textureDimension0;
    uniform vec2 textureDimension1;
#endif
    uniform int isSubtitle;
    uniform int isFullRange;
                                         
    void main()
    {
        if (isSubtitle == 1) {
#if TARGET_OS_OSX
            vec2 recTexCoord0 = vv2_Texcoord * textureDimension0;
            fragColor = texture2DRect(us2_Sampler0, recTexCoord0);
#else
            fragColor = texture2DRect(us2_Sampler0, vv2_Texcoord);
#endif
        } else {
#if TARGET_OS_OSX
            vec3 yuv;
            vec2 recTexCoord0 = vv2_Texcoord * textureDimension0;
            vec2 recTexCoord1 = vv2_Texcoord * textureDimension1;
            
            yuv.x = texture2DRect(us2_Sampler0, recTexCoord0).r;
            yuv.yz = texture2DRect(us2_Sampler1, recTexCoord1).rg;
#else
            mediump vec3 yuv;
            yuv.x = texture2DRect(us2_Sampler0, vv2_Texcoord).r;
            yuv.yz = texture2DRect(us2_Sampler1, vv2_Texcoord).rg;
#endif
            vec3 offset;
            if (isFullRange == 1) {
                offset = vec3(0.0, -0.5, -0.5);
            } else {
                offset = vec3(- (16.0 / 255.0), -0.5, -0.5);
            }
            yuv += offset;
            vec3 rgb = um3_ColorConversion * yuv;
            rgb = rgb_adjust(rgb,um3_rgbAdjustment);
            fragColor = vec4(rgb, 1.0);
        }
    }
);

//for bgrx texture
static const char g_shader_rect_bgrx_1[] = IJK_GLES_STRING(
    varying vec2 vv2_Texcoord;
    uniform vec3 um3_rgbAdjustment;
    
    uniform sampler2DRect us2_Sampler0;
    uniform vec2 textureDimension0;
    
    uniform int isSubtitle;
                                         
    void main()
    {
        if (isSubtitle == 1) {
            vec2 recTexCoord0 = vv2_Texcoord * textureDimension0;
            fragColor = texture2DRect(us2_Sampler0, recTexCoord0);
        } else {
            vec2 recTexCoord0 = vv2_Texcoord * textureDimension0;
            vec3 rgb = texture2DRect(us2_Sampler0, recTexCoord0).rgb;
            rgb = rgb_adjust(rgb,um3_rgbAdjustment);

            fragColor = vec4(rgb, 1.0);
        }
    }
);

//for rgbx texture
static const char g_shader_rect_rgbx_1[] = IJK_GLES_STRING(
    varying vec2 vv2_Texcoord;
    uniform vec3 um3_rgbAdjustment;
    
    uniform sampler2DRect us2_Sampler0;
    uniform vec2 textureDimension0;
    
    uniform int isSubtitle;
                                            
    void main()
    {
        if (isSubtitle == 1) {
            vec2 recTexCoord0 = vv2_Texcoord * textureDimension0;
            fragColor = texture2DRect(us2_Sampler0, recTexCoord0);
        } else {
            vec2 recTexCoord0 = vv2_Texcoord * textureDimension0;
            vec3 rgb = texture2DRect(us2_Sampler0, recTexCoord0).rgb;
            rgb = rgb_adjust(rgb,um3_rgbAdjustment);

            fragColor = vec4(rgb, 1.0);
        }
    }
);

//for xrgb texture
static const char g_shader_rect_xrgb_1[] = IJK_GLES_STRING(
    varying vec2 vv2_Texcoord;
    uniform vec3 um3_rgbAdjustment;
    
    uniform sampler2DRect us2_Sampler0;
    uniform vec2 textureDimension0;
    
    uniform int isSubtitle;
                                                 
    void main()
    {
        if (isSubtitle == 1) {
            vec2 recTexCoord0 = vv2_Texcoord * textureDimension0;
            fragColor = texture2DRect(us2_Sampler0, recTexCoord0);
        } else {
            vec2 recTexCoord0 = vv2_Texcoord * textureDimension0;
            //bgra -> argb
            //argb -> bgra
            vec3 rgb = texture2DRect(us2_Sampler0, recTexCoord0).gra;
            rgb = rgb_adjust(rgb,um3_rgbAdjustment);

            fragColor = vec4(rgb, 1.0);
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
#if TARGET_OS_OSX
    uniform vec2 textureDimension0;
    uniform vec2 textureDimension1;
    uniform vec2 textureDimension2;
#endif
    uniform int isSubtitle;
    uniform int isFullRange;
                                                      
    void main()
    {
        if (isSubtitle == 1) {
#if TARGET_OS_OSX
            vec2 recTexCoord0 = vv2_Texcoord * textureDimension0;
            fragColor = texture2DRect(us2_Sampler0, recTexCoord0);
#else
            fragColor = texture2DRect(us2_Sampler0, vv2_Texcoord);
#endif
        } else {
#if TARGET_OS_OSX
            vec3 yuv;
            vec2 recTexCoord0 = vv2_Texcoord * textureDimension0;
            vec2 recTexCoord1 = vv2_Texcoord * textureDimension1;
            vec2 recTexCoord2 = vv2_Texcoord * textureDimension2;

            yuv.x = texture2DRect(us2_Sampler0, recTexCoord0).r;
            yuv.y = texture2DRect(us2_Sampler1, recTexCoord1).r;
            yuv.z = texture2DRect(us2_Sampler2, recTexCoord2).r;
#else
            mediump vec3 yuv;
            yuv.x = texture2DRect(us2_Sampler0, vv2_Texcoord).r;
            yuv.y = texture2DRect(us2_Sampler1, vv2_Texcoord).r;
            yuv.z = texture2DRect(us2_Sampler2, vv2_Texcoord).r;
#endif
            vec3 offset;
            if (isFullRange == 1) {
                offset = vec3(0.0, -0.5, -0.5);
            } else {
                offset = vec3(- (16.0 / 255.0), -0.5, -0.5);
            }
            yuv += offset;
            vec3 rgb = um3_ColorConversion * yuv;
            rgb = rgb_adjust(rgb,um3_rgbAdjustment);
            fragColor = vec4(rgb, 1.0);
        }
    }
);

//for uyvy texture
static const char g_shader_rect_uyvy_1[] = IJK_GLES_STRING(
    varying vec2 vv2_Texcoord;
    uniform vec3 um3_rgbAdjustment;
    uniform mat3 um3_ColorConversion;
    uniform sampler2DRect us2_Sampler0;
    uniform vec2 textureDimension0;
    
    uniform int isSubtitle;
    uniform int isFullRange;
          
    void main()
    {
        if (isSubtitle == 1) {
            vec2 recTexCoord0 = vv2_Texcoord * textureDimension0;
            fragColor = texture2DRect(us2_Sampler0, recTexCoord0);
        } else {
            vec2 recTexCoord0 = vv2_Texcoord * textureDimension0;
            vec3 yuv = texture2DRect(us2_Sampler0, recTexCoord0).gbr;
            vec3 offset;
            if (isFullRange == 1) {
                offset = vec3(0.0, -0.5, -0.5);
            } else {
                offset = vec3(- (16.0 / 255.0), -0.5, -0.5);
            }
            yuv += offset;
            vec3 rgb = um3_ColorConversion * yuv;
            rgb = rgb_adjust(rgb,um3_rgbAdjustment);
            fragColor = vec4(rgb, 1.0);
        }
    }
);

void ijk_get_apple_common_fragment_shader(IJK_SHADER_TYPE type,char *out,int ver)
{
    *out = '\0';
    sprintf(out, "#version %d\n",ver);
#if TARGET_OS_IOS
    strcat(out, "#define texture2DRect texture2D\n");
    strcat(out, "#define sampler2DRect sampler2D\n");
    strcat(out, "#define fragColor gl_FragColor\n");
    strcat(out,"precision highp float;\n");
    strcat(out,"precision lowp sampler2D;\n");
#else
    if (ver >= 330) {
        strcat(out, "#define varying in\n");
        strcat(out, "#define texture2DRect texture\n");
        strcat(out, "out vec4 fragColor;\n");
    } else {
        strcat(out, "#define fragColor gl_FragColor\n");
    }
#endif
    strcat(out, "\n");
    strcat(out, IJK_GLES_STRING(
                vec3 rgb_adjust(vec3 rgb,vec3 rgbAdjustment) {
                    //C 是对比度值，B 是亮度值，S 是饱和度
                    float B = rgbAdjustment.x;
                    float S = rgbAdjustment.y;
                    float C = rgbAdjustment.z;

                    rgb = (rgb - 0.5) * C + 0.5;
                    rgb = rgb + (0.75 * B - 0.5) / 2.5 - 0.1;
                    vec3 intensity = vec3(dot(rgb, vec3(0.299, 0.587, 0.114)));
                    return intensity + S * (rgb - intensity);
                }
                                ));
    strcat(out, "\n");
    
    const char * buffer;
    //for rgbx
    switch (type) {
        case BGRX_SHADER:
        {
            buffer = g_shader_rect_bgrx_1;
        }
            break;
        case XRGB_SHADER:
        {
            buffer = g_shader_rect_xrgb_1;
        }
            break;
        case YUV_2P_SHADER:
        {
            buffer = apple_nv12_shader;
        }
            break;
        case YUV_3P_SHADER:
        {
            buffer = g_shader_rect_3;
        }
            break;
        case UYVY_SHADER:
        case YUYV_SHADER:
        {
            if (ver >= 330) {
                buffer = g_shader_rect_uyvy_1;
            } else {
                buffer = g_shader_rect_rgbx_1;
            }
        }
            break;
        case NONE_SHADER:
        {
            assert(0);
            buffer = "";
        }
            break;
    }
    
    strcat(out, buffer);
}
