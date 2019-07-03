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
#import <CoreVideo/CoreVideo.h>
#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <OpenGL/GL.h>
#import <OpenGL/gl.h>
#else
#if __OBJC__
#import <OpenGLES/EAGL.h>
#endif
#endif
#include "ijksdl_vout_overlay_videotoolbox.h"

static GLboolean rgb_use(IJK_GLES2_Renderer *renderer)
{
    ALOGI("use render rgb\n");
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    
    glUseProgram(renderer->program);            IJK_GLES2_checkError_TRACE("glUseProgram");
    
    if (0 == renderer->plane_textures[0])
        glGenTextures(1, renderer->plane_textures);
    
    for (int i = 0; i < 1; ++i) {
        glActiveTexture(GL_TEXTURE0 + i);
        glBindTexture(GL_TEXTURE_2D, renderer->plane_textures[i]);
        
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        glUniform1i(renderer->us2_sampler[i], i);
    }
    
    return GL_TRUE;
}

static GLsizei rgb565_getBufferWidth(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!overlay)
        return 0;
    
    return overlay->pitches[0] / 2;
}

static GLboolean rgb565_uploadTexture(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!renderer || !overlay)
        return GL_FALSE;
    
    int     planes[1]    = { 0 };
    const GLsizei widths[1]    = { overlay->pitches[0] / 2 };
    const GLsizei heights[3]   = { overlay->h };
    const GLubyte *pixels[3]   = { overlay->pixels[0] };
    
    switch (overlay->format) {
        case SDL_FCC_RV16:
            break;
        default:
            ALOGE("[rgb565] unexpected format %x\n", overlay->format);
            return GL_FALSE;
    }

    for (int i = 0; i < 1; ++i) {
        int plane = planes[i];

        glBindTexture(GL_TEXTURE_2D, renderer->plane_textures[i]);

        glTexImage2D(GL_TEXTURE_2D,
                     0,
                     GL_RGB,
                     widths[plane],
                     heights[plane],
                     0,
                     GL_RGB,
                     GL_UNSIGNED_SHORT_5_6_5,
                     pixels[plane]);
    }

    return GL_TRUE;
}

IJK_GLES2_Renderer *IJK_GLES2_Renderer_create_rgb565()
{
    ALOGI("create render rgb565\n");
    IJK_GLES2_Renderer *renderer = IJK_GLES2_Renderer_create_base(IJK_GLES2_getFragmentShader_rgb());
    if (!renderer)
        goto fail;
    
    renderer->us2_sampler[0] = glGetUniformLocation(renderer->program, "us2_SamplerX"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_SamplerX)");
    
    renderer->func_use            = rgb_use;
    renderer->func_getBufferWidth = rgb565_getBufferWidth;
    renderer->func_uploadTexture  = rgb565_uploadTexture;
    
    return renderer;
fail:
    IJK_GLES2_Renderer_free(renderer);
    return NULL;
}



static GLsizei rgb888_getBufferWidth(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!overlay)
        return 0;
    
    return overlay->pitches[0] / 3;
}

static GLboolean rgb888_uploadTexture(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!renderer || !overlay)
        return GL_FALSE;
    
    int     planes[1]    = { 0 };
    const GLsizei widths[1]    = { overlay->pitches[0] / 3 };
    const GLsizei heights[3]   = { overlay->h };
    const GLubyte *pixels[3]   = { overlay->pixels[0] };
    
    switch (overlay->format) {
        case SDL_FCC_RV24:
            break;
        default:
            ALOGE("[rgb888] unexpected format %x\n", overlay->format);
            return GL_FALSE;
    }
    
    for (int i = 0; i < 1; ++i) {
        int plane = planes[i];
        
        glBindTexture(GL_TEXTURE_2D, renderer->plane_textures[i]);
        
        glTexImage2D(GL_TEXTURE_2D,
                     0,
                     GL_RGB,
                     widths[plane],
                     heights[plane],
                     0,
                     GL_RGB,
                     GL_UNSIGNED_BYTE,
                     pixels[plane]);
    }
    
    return GL_TRUE;
}

IJK_GLES2_Renderer *IJK_GLES2_Renderer_create_rgb888()
{
    ALOGI("create render rgb888\n");
    IJK_GLES2_Renderer *renderer = IJK_GLES2_Renderer_create_base(IJK_GLES2_getFragmentShader_rgb());
    if (!renderer)
        goto fail;
    
    renderer->us2_sampler[0] = glGetUniformLocation(renderer->program, "us2_SamplerX"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_SamplerX)");
    
    renderer->func_use            = rgb_use;
    renderer->func_getBufferWidth = rgb888_getBufferWidth;
    renderer->func_uploadTexture  = rgb888_uploadTexture;
    
    return renderer;
fail:
    IJK_GLES2_Renderer_free(renderer);
    return NULL;
}



static GLsizei rgbx8888_getBufferWidth(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!overlay)
        return 0;
    
    return overlay->pitches[0] / 4;
}

static GLboolean rgbx8888_uploadTexture(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!renderer || !overlay)
        return GL_FALSE;
    
    int     planes[1]    = { 0 };
    const GLsizei widths[1]    = { overlay->pitches[0] / 4 };
    const GLsizei heights[3]   = { overlay->h };
    const GLubyte *pixels[3]   = { overlay->pixels[0] };
    
    switch (overlay->format) {
        case SDL_FCC_RV32:
            break;
        default:
            ALOGE("[rgbx8888] unexpected format %x\n", overlay->format);
            return GL_FALSE;
    }
    
    for (int i = 0; i < 1; ++i) {
        int plane = planes[i];
        
        glBindTexture(GL_TEXTURE_2D, renderer->plane_textures[i]);
        
        glTexImage2D(GL_TEXTURE_2D,
                     0,
                     GL_RGBA,
                     widths[plane],
                     heights[plane],
                     0,
                     GL_RGBA,
                     GL_UNSIGNED_BYTE,
                     pixels[plane]);
    }
    
    return GL_TRUE;
}

IJK_GLES2_Renderer *IJK_GLES2_Renderer_create_rgbx8888()
{
    ALOGI("create render rgbx8888\n");
    IJK_GLES2_Renderer *renderer = IJK_GLES2_Renderer_create_base(IJK_GLES2_getFragmentShader_rgb());
    if (!renderer)
        goto fail;
    
    renderer->us2_sampler[0] = glGetUniformLocation(renderer->program, "us2_SamplerX"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_SamplerX)");
    
    renderer->func_use            = rgb_use;
    renderer->func_getBufferWidth = rgbx8888_getBufferWidth;
    renderer->func_uploadTexture  = rgbx8888_uploadTexture;
    
    return renderer;
fail:
    IJK_GLES2_Renderer_free(renderer);
    return NULL;
}


static GLsizei bgra32_getBufferWidth(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!overlay)
        return 0;
    
    return overlay->pitches[0];
}

static GLboolean bgra32_uploadTexture(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!renderer || !overlay)
        return GL_FALSE;
    
    if (!overlay->is_private)
        return GL_FALSE;
    
    switch (overlay->format) {
        case SDL_FCC__VTB:
            break;
        default:
            ALOGE("[bgra32] unexpected format %x\n", overlay->format);
            return GL_FALSE;
    }
    
    CVPixelBufferRef pixel_buffer = SDL_VoutOverlayVideoToolBox_GetCVPixelBufferRef(overlay);
    if (!pixel_buffer) {
        ALOGE("nil pixelBuffer in overlay\n");
        return GL_FALSE;
    }
    
    CFTypeRef color_attachments = CVBufferGetAttachment(pixel_buffer, kCVImageBufferYCbCrMatrixKey, NULL);
    
    if (CFStringCompare(color_attachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == kCFCompareEqualTo) {
        glUniformMatrix3fv(renderer->um3_color_conversion, 1, GL_FALSE, IJK_GLES2_getColorMatrix_bt601());
    } else /* kCVImageBufferYCbCrMatrix_ITU_R_709_2 */ {
        glUniformMatrix3fv(renderer->um3_color_conversion, 1, GL_FALSE, IJK_GLES2_getColorMatrix_bt709());
    }
    
    CVPixelBufferLockBaseAddress(pixel_buffer, 0);
    int bufferHeight = (int) CVPixelBufferGetHeight(pixel_buffer);
    int bufferWidth = (int) CVPixelBufferGetWidth(pixel_buffer);
    
    const GLubyte *pixel   = CVPixelBufferGetBaseAddress(pixel_buffer);
    glBindTexture(GL_TEXTURE_2D, renderer->plane_textures[0]);
    //Using BGRA extension to pull in video frame data directly
    glTexImage2D(GL_TEXTURE_2D,
                 0,
                 GL_RGBA,
                 bufferWidth,
                 bufferHeight,
                 0,
                 GL_BGRA,
                 GL_UNSIGNED_BYTE,
                 pixel);
    CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
    return GL_TRUE;
}

IJK_GLES2_Renderer *IJK_GLES2_Renderer_create_bgra32()
{
    ALOGI("create render bgra32\n");
    IJK_GLES2_Renderer *renderer = IJK_GLES2_Renderer_create_base(IJK_GLES2_getFragmentShader_rgb());
    if (!renderer)
        goto fail;
    
    renderer->us2_sampler[0] = glGetUniformLocation(renderer->program, "us2_SamplerX"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_SamplerX)");
    
    renderer->func_use            = rgb_use;
    renderer->func_getBufferWidth = bgra32_getBufferWidth;
    renderer->func_uploadTexture  = bgra32_uploadTexture;
    
    return renderer;
fail:
    IJK_GLES2_Renderer_free(renderer);
    return NULL;
}
