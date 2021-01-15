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

#include "internal.h"

static GLboolean yuv420p_use(IJK_GLES2_Renderer *renderer)
{
    ALOGI("use render yuv420p\n");
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    //使用gl程序，包含了编译好的着色器
    glUseProgram(renderer->program);            IJK_GLES2_checkError_TRACE("glUseProgram");
    //生成 3 个纹理
    if (0 == renderer->plane_textures[0])
        glGenTextures(3, renderer->plane_textures);
    //批量处理纹理
    for (int i = 0; i < 3; ++i) {
        //激活纹理
        glActiveTexture(GL_TEXTURE0 + i);
        //绑定纹理
        glBindTexture(GL_TEXTURE_2D, renderer->plane_textures[i]);
        // 2D纹理 GL_LINEAR 线形过滤，插值计算得出像素颜色；当画面分辨率低，被显示的很大时会产生更真实的输出，避免出现颗粒状像素；
        //GL_TEXTURE_MAG_FILTER 放大时设置纹理过滤为 GL_LINEAR
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        //GL_TEXTURE_MAG_FILTER 缩小时设置纹理过滤为 GL_LINEAR
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        //GL_CLAMP_TO_EDGE:纹理坐标会被约束在0到1之间，超出的部分会重复纹理坐标的边缘，产生一种边缘被拉伸的效果;
        //S方向上的贴图模式, S 就是 x 轴，水平方向
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        //T方向上的贴图模式, T 就是 y 轴，水平方向
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        //绑定纹理到对应的纹理单元
        glUniform1i(renderer->us2_sampler[i], i);
    }

    glUniformMatrix3fv(renderer->um3_color_conversion, 1, GL_FALSE, IJK_GLES2_getColorMatrix_bt709());

    return GL_TRUE;
}

static GLsizei yuv420p_getBufferWidth(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!overlay)
        return 0;

    return overlay->pitches[0] / 1;
}

static GLboolean yuv420p_uploadTexture(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!renderer || !overlay)
        return GL_FALSE;

          int     planes[3]    = { 0, 1, 2 };
    const GLsizei widths[3]    = { overlay->pitches[0], overlay->pitches[1], overlay->pitches[2] };
    const GLsizei heights[3]   = { overlay->h,          overlay->h / 2,      overlay->h / 2 };
    const GLubyte *pixels[3]   = { overlay->pixels[0],  overlay->pixels[1],  overlay->pixels[2] };

    switch (overlay->format) {
        case SDL_FCC_I420:
            break;
        case SDL_FCC_YV12:
            planes[1] = 2;
            planes[2] = 1;
            break;
        default:
            ALOGE("[yuv420p] unexpected format %x\n", overlay->format);
            return GL_FALSE;
    }
    
    for (int i = 0; i < 3; ++i) {
        int plane = planes[i];

        glBindTexture(GL_TEXTURE_2D, renderer->plane_textures[i]);
        //将 纹理图像 附加到 当前绑定的 纹理对象 //参数含义(纹理目标;多级渐远纹理的级别;把纹理储存为何种格式;纹理宽度;纹理高度;遗留，固定0;源图格式;源图数据类型;图像数据)
        glTexImage2D(GL_TEXTURE_2D,
                     0,
                     GL_LUMINANCE,
                     widths[plane],
                     heights[plane],
                     0,
                     GL_LUMINANCE,
                     GL_UNSIGNED_BYTE,
                     pixels[plane]);
    }

    return GL_TRUE;
}

IJK_GLES2_Renderer *IJK_GLES2_Renderer_create_yuv420p()
{
    ALOGI("create render yuv420p\n");
    IJK_GLES2_Renderer *renderer = IJK_GLES2_Renderer_create_base(IJK_GL_getFragmentShader_yuv420p());
    if (!renderer)
        goto fail;

    renderer->us2_sampler[0] = glGetUniformLocation(renderer->program, "us2_SamplerX"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_SamplerX)");
    renderer->us2_sampler[1] = glGetUniformLocation(renderer->program, "us2_SamplerY"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_SamplerY)");
    renderer->us2_sampler[2] = glGetUniformLocation(renderer->program, "us2_SamplerZ"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_SamplerZ)");

    renderer->um3_color_conversion = glGetUniformLocation(renderer->program, "um3_ColorConversion"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(um3_ColorConversionMatrix)");

    renderer->func_use            = yuv420p_use;
    renderer->func_getBufferWidth = yuv420p_getBufferWidth;
    renderer->func_uploadTexture  = yuv420p_uploadTexture;

    return renderer;
fail:
    IJK_GLES2_Renderer_free(renderer);
    return NULL;
}
