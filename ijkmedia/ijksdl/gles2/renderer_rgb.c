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

typedef struct IJK_GLES2_Renderer_Opaque
{
    CVOpenGLTextureCacheRef cv_texture_cache;
    CVOpenGLTextureRef      cv_texture[1];

    CFTypeRef                 color_attachments;
} IJK_GL_Renderer_Opaque;

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

static GLvoid yuv420sp_vtb_clean_textures(IJK_GLES2_Renderer *renderer)
{
    if (!renderer || !renderer->opaque)
        return;

    IJK_GL_Renderer_Opaque *opaque = renderer->opaque;

    for (int i = 0; i < 1; ++i) {
        if (opaque->cv_texture[i]) {
            CFRelease(opaque->cv_texture[i]);
            opaque->cv_texture[i] = nil;
        }
    }

    // Periodic texture cache flush every frame
    if (opaque->cv_texture_cache)
        CVOpenGLTextureCacheFlush(opaque->cv_texture_cache, 0);
}

static GLsizei bgrx_getBufferWidth(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!overlay)
        return 0;
    
    if (overlay->format == SDL_FCC__VTB) {
        return overlay->pitches[0];
    } else if (overlay->format == SDL_FCC_RGB565 || overlay->format == SDL_FCC_BGR565) {
        return overlay->pitches[0] / 2;
    } else if (overlay->format == SDL_FCC_BGR24 || overlay->format == SDL_FCC_RGB24) {
        return overlay->pitches[0] / 3;
    } else if (overlay->format == SDL_FCC_RGB0 || overlay->format == SDL_FCC_RGBA || overlay->format == SDL_FCC_BGRA || overlay->format == SDL_FCC_BGR0 || overlay->format == SDL_FCC_ARGB || overlay->format == SDL_FCC_0RGB) {
        return overlay->pitches[0] / 4;
    } else {
        assert(0);
    }
    return 0;
}

static GLboolean bgrx_uploadTexture(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!renderer || !overlay)
        return GL_FALSE;
    
    switch (overlay->format) {
        case SDL_FCC__VTB:
        {
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
            yuv420sp_vtb_clean_textures(renderer);

            IJK_GL_Renderer_Opaque *opaque = renderer->opaque;
            
            CVPixelBufferLockBaseAddress(pixel_buffer, 0);
            int bufferHeight = (int) CVPixelBufferGetHeight(pixel_buffer);
            int bufferWidth = (int) CVPixelBufferGetWidth(pixel_buffer);

            const GLubyte *pixel = CVPixelBufferGetBaseAddress(pixel_buffer);
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, CVOpenGLTextureGetName(opaque->cv_texture[0]));
            
            GLenum src_format = 0;
            int src_type = GL_UNSIGNED_BYTE;
            int pixel_format = CVPixelBufferGetPixelFormatType(pixel_buffer);
            if (pixel_format == kCVPixelFormatType_32BGRA) {
                src_format = GL_BGRA;
            } else if (pixel_format == kCVPixelFormatType_24RGB) {
                src_format = GL_RGB;
            } else if (pixel_format == kCVPixelFormatType_32ARGB) {
                //使用的是 argb 的 fsh 
                src_format = GL_RGBA;
            }
            
            //Using BGRA extension to pull in video frame data directly
            glTexImage2D(GL_TEXTURE_2D,
                         0,
                         GL_RGBA,
                         bufferWidth,
                         bufferHeight,
                         0,
                         src_format,
                         src_type,
                         pixel);
            
//            CVReturn err = CVOpenGLTextureCacheCreateTextureFromImage(kCFAllocatorDefault, opaque->cv_texture_cache, pixel_buffer, NULL, &opaque->cv_texture[0]);

//            if (kCVReturnSuccess != err) {
//                printf("CreateTextureFromImage:%d",err);
//            }
            
            CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
            
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            
            return GL_TRUE;
        }
            break;
        case SDL_FCC_RGB565:
        case SDL_FCC_BGR565:
        case SDL_FCC_BGR24:
        case SDL_FCC_RGB24:
        case SDL_FCC_RGB0:
        case SDL_FCC_RGBA:
        case SDL_FCC_BGRA:
        case SDL_FCC_BGR0:
        case SDL_FCC_ARGB:
        case SDL_FCC_0RGB:
        {
            int planes[1] = { 0 };
            int bpp = 1;
            GLenum src_format = 0;
            int src_type = GL_UNSIGNED_BYTE;
            if (overlay->format == SDL_FCC_RGB565){
                bpp = 2;
                src_format = GL_RGB;
                src_type = GL_UNSIGNED_SHORT_5_6_5;
            } else if (overlay->format == SDL_FCC_BGR565){
                bpp = 2;
                src_format = GL_BGR;
                src_type = GL_UNSIGNED_SHORT_5_6_5;
            } else if (overlay->format == SDL_FCC_BGR24) {
                bpp = 3;
                src_format = GL_BGR;
            } else if (overlay->format == SDL_FCC_RGB24) {
                bpp = 3;
                src_format = GL_RGB;
            } else if (overlay->format == SDL_FCC_RGB0 || overlay->format == SDL_FCC_RGBA) {
                bpp = 4;
                src_format = GL_RGBA;
            } else if (overlay->format == SDL_FCC_BGRA || overlay->format == SDL_FCC_BGR0) {
                bpp = 4;
                src_format = GL_BGRA;
            } else if (overlay->format == SDL_FCC_ARGB || overlay->format == SDL_FCC_0RGB) {
                //使用的是 argb 的 fsh
                bpp = 4;
                src_format = GL_RGBA;
            }
            const GLsizei widths[1] = { overlay->pitches[0] / bpp };
            const GLsizei heights[3] = { overlay->h };
            const GLubyte *pixels[3] = { overlay->pixels[0] };
            
            for (int i = 0; i < 1; ++i) {
                int plane = planes[i];
                
                glBindTexture(GL_TEXTURE_2D, renderer->plane_textures[i]);
                
                glTexImage2D(GL_TEXTURE_2D,
                             0,
                             GL_RGBA,
                             widths[plane],
                             heights[plane],
                             0,
                             src_format,
                             src_type,
                             pixels[plane]);
            }
            
            return GL_TRUE;
        }
            break;
        default:
            ALOGE("[bgra32] unexpected format %x\n", overlay->format);
            return GL_FALSE;
    }
}

static IJK_GLES2_Renderer *IJK_GL_Renderer_create_xgbx(const char *fsh)
{
    ALOGI("create render rgbx\n");
    IJK_GLES2_Renderer *renderer = IJK_GLES2_Renderer_create_base(fsh);
    if (!renderer)
        goto fail;
    
    renderer->us2_sampler[0] = glGetUniformLocation(renderer->program, "us2_SamplerX"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_SamplerX)");
    
    renderer->func_use            = rgb_use;
    renderer->func_getBufferWidth = bgrx_getBufferWidth;
    renderer->func_uploadTexture  = bgrx_uploadTexture;
    
    renderer->opaque = calloc(1, sizeof(IJK_GL_Renderer_Opaque));
    if (!renderer->opaque)
        goto fail;
    CGLPixelFormatObj cglPixelFormat = CGLGetPixelFormat(CGLGetCurrentContext());
    CGLContextObj context = CGLGetCurrentContext();
    CVReturn err = CVOpenGLTextureCacheCreate(kCFAllocatorDefault, NULL, context, cglPixelFormat, NULL, &renderer->opaque->cv_texture_cache);
    if (err || renderer->opaque->cv_texture_cache == nil) {
        ALOGE("Error at CVOpenGLESTextureCacheCreate %d\n", err);
        goto fail;
    }

    renderer->opaque->color_attachments = CFRetain(kCVImageBufferYCbCrMatrix_ITU_R_709_2);
    
    return renderer;
fail:
    IJK_GLES2_Renderer_free(renderer);
    return NULL;
}

IJK_GLES2_Renderer *IJK_GL_Renderer_create_xrgb()
{
    return IJK_GL_Renderer_create_xgbx(IJK_GLES2_getFragmentShader_argb());
}

IJK_GLES2_Renderer *IJK_GL_Renderer_create_rgbx()
{
    return IJK_GL_Renderer_create_xgbx(IJK_GLES2_getFragmentShader_rgb());
}
