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
#import <OpenGL/gl3.h>
#else
#if __OBJC__
#import <OpenGLES/EAGL.h>
#endif
#endif
#include "ijksdl_vout_overlay_videotoolbox.h"
#include "renderer_pixfmt.h"

//https://stackoverflow.com/questions/11361583/gl-texture-rectangle-arb/11363905
//https://stackoverflow.com/questions/38361376/convert-iosurface-backed-texture-to-gl-texture-2d

#define RGB_RENDER_NORMAL      1
#define RGB_RENDER_FAST_UPLOAD 2
#define RGB_RENDER_IO_SURFACE  4

#define RGB_RENDER_TYPE RGB_RENDER_IO_SURFACE

#if RGB_RENDER_TYPE != RGB_RENDER_NORMAL
#define GL_TEXTURE_TARGET GL_TEXTURE_RECTANGLE
#else
#define GL_TEXTURE_TARGET GL_TEXTURE_2D
#endif

typedef struct IJK_GLES2_Renderer_Opaque
{
    CVOpenGLTextureCacheRef cv_texture_cache;
    CVOpenGLTextureRef      rgb_texture;
    CFTypeRef               color_attachments;
    GLint                   textureDimensionIndex;
} IJK_GL_Renderer_Opaque;

static GLboolean rgb_use(IJK_GLES2_Renderer *renderer)
{
    ALOGI("use render rgb\n");
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glEnable(GL_TEXTURE_TARGET);
    glUseProgram(renderer->program);            IJK_GLES2_checkError_TRACE("glUseProgram");

#if RGB_RENDER_TYPE == RGB_RENDER_NORMAL || RGB_RENDER_TYPE == RGB_RENDER_IO_SURFACE
    if (0 == renderer->plane_textures[0])
        glGenTextures(1, renderer->plane_textures);
#endif
    
    for (int i = 0; i < 1; ++i) {
        glUniform1i(renderer->us2_sampler[i], i);
    }
    
    return GL_TRUE;
}

#if RGB_RENDER_TYPE == RGB_RENDER_FAST_UPLOAD
static GLvoid yuv420sp_vtb_clean_textures(IJK_GLES2_Renderer *renderer)
{
    if (!renderer || !renderer->opaque)
        return;

    IJK_GL_Renderer_Opaque *opaque = renderer->opaque;

    if (opaque->rgb_texture) {
        CFRelease(opaque->rgb_texture);
        opaque->rgb_texture = nil;
    }

    // Periodic texture cache flush every frame
    if (opaque->cv_texture_cache)
        CVOpenGLTextureCacheFlush(opaque->cv_texture_cache, 0);
}
#endif

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

#if RGB_RENDER_TYPE == RGB_RENDER_IO_SURFACE
static GLboolean upload_rgb_texture_use_IOSurface(CVPixelBufferRef pixel_buffer,IJK_GLES2_Renderer *renderer)
{
    IOSurfaceRef surface = CVPixelBufferGetIOSurface(pixel_buffer);
    
    if (!surface) {
        ALOGE("CVPixelBuffer has no IOSurface\n");
        return GL_FALSE;
    }
    GLsizei w = (GLsizei)IOSurfaceGetWidth(surface);
    GLsizei h = (GLsizei)IOSurfaceGetHeight(surface);

    uint32_t cvpixfmt = CVPixelBufferGetPixelFormatType(pixel_buffer);
    struct vt_format *f = vt_get_gl_format(cvpixfmt);
    if (!f) {
        ALOGE("CVPixelBuffer has unsupported format type\n");
        return GL_FALSE;
    }

    const bool planar = CVPixelBufferIsPlanar(pixel_buffer);
    const int planes  = (int)CVPixelBufferGetPlaneCount(pixel_buffer);
    assert(planar && planes == f->planes || f->planes == 1);

    GLenum gl_target = GL_TEXTURE_RECTANGLE;
    glUniform2f(renderer->opaque->textureDimensionIndex, w, h);
    glBindTexture(gl_target, renderer->plane_textures[0]);
    CGLError err = CGLTexImageIOSurface2D(
        CGLGetCurrentContext(), gl_target,
        f->gl[0].gl_internal_format,
        w,
        h,
        f->gl[0].gl_format, f->gl[0].gl_type, surface, 0);
    
    if (err != kCGLNoError) {
        ALOGE("error creating IOSurface texture for plane %d: %s\n",
               0, CGLErrorString(err));
        return GL_FALSE;
    } else {
        glTexParameteri(gl_target, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(gl_target, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameterf(gl_target, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(gl_target, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        return GL_TRUE;
    }
}
#endif

static GLboolean upload_vtp_Texture(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    CVPixelBufferRef pixel_buffer = SDL_VoutOverlayVideoToolBox_GetCVPixelBufferRef(overlay);
    
    if (!pixel_buffer) {
        ALOGE("nil pixelBuffer in overlay\n");
        return GL_FALSE;
    }
    
    assert(kCVPixelFormatType_32BGRA == CVPixelBufferGetPixelFormatType(pixel_buffer));
    
    CFTypeRef color_attachments = CVBufferGetAttachment(pixel_buffer, kCVImageBufferYCbCrMatrixKey, NULL);
    
    if (CFStringCompare(color_attachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == kCFCompareEqualTo) {
        glUniformMatrix3fv(renderer->um3_color_conversion, 1, GL_FALSE, IJK_GLES2_getColorMatrix_bt601());
    } else /* kCVImageBufferYCbCrMatrix_ITU_R_709_2 */ {
        glUniformMatrix3fv(renderer->um3_color_conversion, 1, GL_FALSE, IJK_GLES2_getColorMatrix_bt709());
    }
    glActiveTexture(GL_TEXTURE0);
    
#if RGB_RENDER_TYPE == RGB_RENDER_FAST_UPLOAD
    IJK_GL_Renderer_Opaque *opaque = renderer->opaque;
    yuv420sp_vtb_clean_textures(renderer);
    int bufferHeight = (int) CVPixelBufferGetHeight(pixel_buffer);
    int bufferWidth  = (int) CVPixelBufferGetWidth(pixel_buffer);
    
    glUniform2f(opaque->textureDimensionIndex, bufferWidth, bufferHeight);

    CVReturn err = CVOpenGLTextureCacheCreateTextureFromImage(kCFAllocatorDefault, opaque->cv_texture_cache, pixel_buffer, NULL, &opaque->rgb_texture);

    if (kCVReturnSuccess != err) {
        ALOGE("CreateTextureFromImage:%d",err);
        return GL_FALSE;
    }
    
    glBindTexture(CVOpenGLTextureGetTarget(opaque->rgb_texture), CVOpenGLTextureGetName(opaque->rgb_texture));
    
    glTexParameteri(GL_TEXTURE_TARGET, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_TARGET, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_TARGET, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_TARGET, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    return GL_TRUE;
#elif RGB_RENDER_TYPE == RGB_RENDER_IO_SURFACE
    return upload_rgb_texture_use_IOSurface(pixel_buffer, renderer);
#else
    int bufferHeight = (int) CVPixelBufferGetHeight(pixel_buffer);
    int bufferWidth  = (int) CVPixelBufferGetWidth(pixel_buffer);

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
    
    CVPixelBufferLockBaseAddress(pixel_buffer, 0);
    const GLubyte *pixel = CVPixelBufferGetBaseAddress(pixel_buffer);
    //Using BGRA extension to pull in video frame data directly
    glTexImage2D(GL_TEXTURE_TARGET,
                 0,
                 GL_RGBA,
                 bufferWidth,
                 bufferHeight,
                 0,
                 src_format,
                 src_type,
                 pixel);
    CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
    
    glTexParameteri(GL_TEXTURE_TARGET, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_TARGET, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_TARGET, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_TARGET, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    return GL_TRUE;
#endif
}

static GLboolean bgrx_uploadTexture(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!renderer || !overlay)
        return GL_FALSE;
    
    switch (overlay->format) {
        case SDL_FCC__VTB:
            return upload_vtp_Texture(renderer, overlay);
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
#if RGB_RENDER_TYPE == RGB_RENDER_FAST_UPLOAD
    CGLContextObj context = CGLGetCurrentContext();
    printf("CGLContextObj2:%p",context);
    CGLPixelFormatObj cglPixelFormat = CGLGetPixelFormat(CGLGetCurrentContext());
    
    CVReturn err = CVOpenGLTextureCacheCreate(kCFAllocatorDefault, NULL, context, cglPixelFormat, NULL, &renderer->opaque->cv_texture_cache);
    if (err || renderer->opaque->cv_texture_cache == nil) {
        ALOGE("Error at CVOpenGLESTextureCacheCreate %d\n", err);
        goto fail;
    }
#endif
    
#if RGB_RENDER_TYPE != RGB_RENDER_NORMAL
    GLint textureDimensionIndex = glGetUniformLocation(renderer->program, "textureDimensions");

    assert(textureDimensionIndex >= 0);
    
    renderer->opaque->textureDimensionIndex = textureDimensionIndex;
#endif
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
#if RGB_RENDER_TYPE != RGB_RENDER_NORMAL
    return IJK_GL_Renderer_create_xgbx(IJK_GLES2_getFragmentShader_rect_rgb());
#else
    return IJK_GL_Renderer_create_xgbx(IJK_GLES2_getFragmentShader_rgb());
#endif
}
