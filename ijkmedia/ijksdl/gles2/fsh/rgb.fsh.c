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
    uniform sampler2D us2_SamplerX;

    void main()
    {
        gl_FragColor = vec4(texture2D(us2_SamplerX, vv2_Texcoord).rgb, 1);
    }
);

//macOS use sampler2DRect,need texture dimensions
static const char rect_g_shader[] = IJK_GLES_STRING(
    uniform sampler2DRect us2_SamplerX;
    varying vec2 vv2_Texcoord;
    uniform vec2 textureDimensions;
    void main(){
        vec2 recTexCoord = vv2_Texcoord * textureDimensions;
        gl_FragColor = texture2DRect(us2_SamplerX, recTexCoord);
    }
);

static const char argb_g_shader[] = IJK_GLES_STRING(
    varying vec2 vv2_Texcoord;
    uniform sampler2D us2_SamplerX;

    void main()
    {
        gl_FragColor = vec4(texture2D(us2_SamplerX, vv2_Texcoord).gba, 1);
    }
);

const char *IJK_GLES2_getFragmentShader_rect_rgb()
{
    return rect_g_shader;
}

#else

static const char g_shader[] = IJK_GLES_STRING(
    precision highp float;
    varying highp vec2 vv2_Texcoord;
    uniform lowp sampler2D us2_SamplerX;

    void main()
    {
        gl_FragColor = vec4(texture2D(us2_SamplerX, vv2_Texcoord).rgb, 1);
    }
);

static const char argb_g_shader[] = IJK_GLES_STRING(
    precision highp float;
    varying highp vec2 vv2_Texcoord;
    uniform lowp sampler2D us2_SamplerX;

    void main()
    {
        gl_FragColor = vec4(texture2D(us2_SamplerX, vv2_Texcoord).gba, 1);
    }
);

#endif

const char *IJK_GLES2_getFragmentShader_rgb()
{
    return g_shader;
}

const char *IJK_GLES2_getFragmentShader_argb()
{
    return argb_g_shader;
}
