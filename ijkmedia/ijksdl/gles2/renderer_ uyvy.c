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
//#import <OpenGLES/ES3/gl.h>
#endif
#endif
#include "ijksdl_vout_overlay_videotoolbox.h"
#include "renderer_pixfmt.h"

//https://stackoverflow.com/questions/11361583/gl-texture-rectangle-arb/11363905
//https://stackoverflow.com/questions/38361376/convert-iosurface-backed-texture-to-gl-texture-2d
//https://allmybrain.com/2011/12/08/rendering-to-a-texture-with-ios-5-texture-cache-api/comment-page-1/
//https://cpp.hotexamples.com/examples/-/-/CGLTexImageIOSurface2D/cpp-cglteximageiosurface2d-function-examples.html
//https://stackoverflow.com/questions/24933453/best-path-from-avplayeritemvideooutput-to-opengl-texture
//https://github.com/flutter/engine/commit/aafa6611039699d000b0b852a54f37b1e502a2f0

//GL_TEXTURE_2D vs GL_TEXTURE_RECTANGLE
//https://stackoverflow.com/questions/13933503/core-video-pixel-buffers-as-gl-texture-2d

#define UYVY_RENDER_NORMAL      1
#define UYVY_RENDER_FAST_UPLOAD 2
#define UYVY_RENDER_IO_SURFACE  4

#warning UYVY_RENDER_NORMAL not right
#define UYVY_RENDER_TYPE UYVY_RENDER_IO_SURFACE

#if TARGET_OS_OSX
    #define GL_TEXTURE_TARGET GL_TEXTURE_RECTANGLE_EXT
#else
    #define GL_TEXTURE_TARGET GL_TEXTURE_2D
#endif

typedef struct IJK_GLES2_Renderer_Opaque
{
    OpenGLTextureCacheRef cv_texture_cache;
    OpenGLTextureRef      rgb_texture;
    CFTypeRef             color_attachments;
    GLint                 textureDimensionIndex;
} IJK_GL_Renderer_Opaque;

static GLboolean uyvy_use(IJK_GLES2_Renderer *renderer)
{
    ALOGI("use render uyvy\n");
    glPixelStorei(GL_UNPACK_ALIGNMENT, GL_TRUE);
    glEnable(GL_TEXTURE_TARGET);
    glUseProgram(renderer->program);            IJK_GLES2_checkError_TRACE("glUseProgram");

#if UYVY_RENDER_TYPE == UYVY_RENDER_NORMAL || UYVY_RENDER_TYPE == UYVY_RENDER_IO_SURFACE
    if (0 == renderer->plane_textures[0])
        glGenTextures(1, renderer->plane_textures);
#endif
    
    for (int i = 0; i < 1; ++i) {
        glUniform1i(renderer->us2_sampler[i], i);
    }
    
    return GL_TRUE;
}

#if UYVY_RENDER_TYPE == UYVY_RENDER_FAST_UPLOAD
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

static GLsizei uyvy_getBufferWidth(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
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

#if UYVY_RENDER_TYPE == UYVY_RENDER_IO_SURFACE
static GLboolean upload_uyvy_texture_use_IOSurface(CVPixelBufferRef pixel_buffer,IJK_GLES2_Renderer *renderer)
{
    IOSurfaceRef surface = CVPixelBufferGetIOSurface(pixel_buffer);
    
    if (!surface) {
        ALOGE("CVPixelBuffer has no IOSurface\n");
        return GL_FALSE;
    }

    uint32_t cvpixfmt = CVPixelBufferGetPixelFormatType(pixel_buffer);
    struct vt_format *f = vt_get_gl_format(cvpixfmt);
    if (!f) {
        ALOGE("CVPixelBuffer has unsupported format type\n");
        return GL_FALSE;
    }

    const bool planar = CVPixelBufferIsPlanar(pixel_buffer);
    const int planes  = (int)CVPixelBufferGetPlaneCount(pixel_buffer);
    assert(planar && planes == f->planes || f->planes == 1);
    
    GLenum gl_target = GL_TEXTURE_TARGET;
    glBindTexture(gl_target, renderer->plane_textures[0]);
#if TARGET_OS_OSX
    GLsizei w = (GLsizei)IOSurfaceGetWidth(surface);
    GLsizei h = (GLsizei)IOSurfaceGetHeight(surface);
#else
    GLsizei w = (GLsizei)CVPixelBufferGetWidth(pixel_buffer);
    GLsizei h = (GLsizei)CVPixelBufferGetHeight(pixel_buffer);
#endif
    glUniform2f(renderer->opaque->textureDimensionIndex, w, h);

#if TARGET_OS_OSX
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
    }
#else
    int err = 0;
#warning TODO iOS
    
#endif
    {
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
    
    int pft = CVPixelBufferGetPixelFormatType(pixel_buffer);
    assert(kCVPixelFormatType_422YpCbCr8 == pft);
    
    CFTypeRef color_attachments = CVBufferGetAttachment(pixel_buffer, kCVImageBufferYCbCrMatrixKey, NULL);
    
    if (CFStringCompare(color_attachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == kCFCompareEqualTo) {
        glUniformMatrix3fv(renderer->um3_color_conversion, 1, GL_FALSE, IJK_GLES2_getColorMatrix_bt601());
    } else /* kCVImageBufferYCbCrMatrix_ITU_R_709_2 */ {
        glUniformMatrix3fv(renderer->um3_color_conversion, 1, GL_FALSE, IJK_GLES2_getColorMatrix_bt709());
    }
    glActiveTexture(GL_TEXTURE0);
    
#if UYVY_RENDER_TYPE == UYVY_RENDER_FAST_UPLOAD
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
#elif UYVY_RENDER_TYPE == UYVY_RENDER_IO_SURFACE
    return upload_uyvy_texture_use_IOSurface(pixel_buffer, renderer);
#else
    GLsizei w = (GLsizei)CVPixelBufferGetHeight(pixel_buffer);
    GLsizei h = (GLsizei)CVPixelBufferGetWidth(pixel_buffer);
    
    glUniform2f(renderer->opaque->textureDimensionIndex, w, h);
    
    CVPixelBufferLockBaseAddress(pixel_buffer, 0);
    const GLubyte *pixel = CVPixelBufferGetBaseAddress(pixel_buffer);
    
    glBindTexture(GL_TEXTURE_TARGET, renderer->plane_textures[0]);
    GLsizei length = 2 * w * h;
//    glTextureRangeAPPLE(GL_TEXTURE_TARGET, length, pixel);
//    glTexParameteri(GL_TEXTURE_TARGET, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_SHARED_APPLE);
//    glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
    
    glTexParameteri(GL_TEXTURE_TARGET, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_TARGET, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_TARGET, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_TARGET, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
//    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
//    glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);

    //Using BGRA extension to pull in video frame data directly
    glTexImage2D(GL_TEXTURE_TARGET, 0, GL_RGBA8, w, h, 0, GL_YCBCR_422_APPLE, GL_UNSIGNED_SHORT_8_8_REV_APPLE, pixel);
    CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
    
    return GL_TRUE;
#endif
}

static GLboolean uyvy_uploadTexture(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!renderer || !overlay)
        return GL_FALSE;
    
    switch (overlay->format) {
        case SDL_FCC__VTB:
            return upload_vtp_Texture(renderer, overlay);
        case SDL_FCC_RGB565:
#if TARGET_OS_OSX
        case SDL_FCC_BGR565:
        case SDL_FCC_BGR24:
#endif
        case SDL_FCC_RGB24:
        case SDL_FCC_RGB0:
        case SDL_FCC_RGBA:
        case SDL_FCC_BGRA:
        case SDL_FCC_BGR0:
        case SDL_FCC_ARGB:
        case SDL_FCC_0RGB:
        {
            int bpp = 1;
            GLenum src_format = 0;
            int src_type = GL_UNSIGNED_BYTE;
            if (overlay->format == SDL_FCC_RGB565){
                bpp = 2;
                src_format = GL_RGB;
                src_type = GL_UNSIGNED_SHORT_5_6_5;
            }
#if TARGET_OS_OSX
            else if (overlay->format == SDL_FCC_BGR565){
                bpp = 2;
                src_format = GL_BGR;
                src_type = GL_UNSIGNED_SHORT_5_6_5;
            } else if (overlay->format == SDL_FCC_BGR24) {
                bpp = 3;
                src_format = GL_BGR;
            }
#endif
            else if (overlay->format == SDL_FCC_RGB24) {
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
                glActiveTexture(GL_TEXTURE0);
                glBindTexture(GL_TEXTURE_TARGET, renderer->plane_textures[i]);
                glTexImage2D(GL_TEXTURE_TARGET,
                             0,
                             GL_RGBA,
                             widths[i],
                             heights[i],
                             0,
                             src_format,
                             src_type,
                             pixels[i]);
                
                glTexParameteri(GL_TEXTURE_TARGET, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
                glTexParameteri(GL_TEXTURE_TARGET, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
                glTexParameterf(GL_TEXTURE_TARGET, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
                glTexParameterf(GL_TEXTURE_TARGET, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            }
            
            return GL_TRUE;
        }
            break;
        default:
            ALOGE("[bgra32] unexpected format %x\n", overlay->format);
            return GL_FALSE;
    }
}

IJK_GLES2_Renderer *IJK_GL_Renderer_create_uyvy(void)
{
    const char *fsh = IJK_GLES2_getFragmentShader_rect_rgb();
    ALOGI("create render 2vuy.\n");
    IJK_GLES2_Renderer *renderer = IJK_GLES2_Renderer_create_base(fsh);
    if (!renderer)
        goto fail;
    
    renderer->us2_sampler[0] = glGetUniformLocation(renderer->program, "us2_SamplerX"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_SamplerX)");
    
    renderer->func_use            = uyvy_use;
    renderer->func_getBufferWidth = uyvy_getBufferWidth;
    renderer->func_uploadTexture  = uyvy_uploadTexture;
    
    renderer->opaque = calloc(1, sizeof(IJK_GL_Renderer_Opaque));
    if (!renderer->opaque)
        goto fail;
#if UYVY_RENDER_TYPE == UYVY_RENDER_FAST_UPLOAD
    CGLContextObj context = CGLGetCurrentContext();
    printf("CGLContextObj2:%p",context);
    CGLPixelFormatObj cglPixelFormat = CGLGetPixelFormat(CGLGetCurrentContext());
    
    CVReturn err = CVOpenGLTextureCacheCreate(kCFAllocatorDefault, NULL, context, cglPixelFormat, NULL, &renderer->opaque->cv_texture_cache);
    if (err || renderer->opaque->cv_texture_cache == nil) {
        ALOGE("Error at CVOpenGLESTextureCacheCreate %d\n", err);
        goto fail;
    }
#endif
    
#if UYVY_RENDER_TYPE != UYVY_RENDER_NORMAL
    
#endif
    
    GLint textureDimensionIndex = glGetUniformLocation(renderer->program, "textureDimensions");

    assert(textureDimensionIndex >= 0);
    
    renderer->opaque->textureDimensionIndex = textureDimensionIndex;
    
    renderer->opaque->color_attachments = CFRetain(kCVImageBufferYCbCrMatrix_ITU_R_709_2);
    
    return renderer;
fail:
    IJK_GLES2_Renderer_free(renderer);
    return NULL;
}

