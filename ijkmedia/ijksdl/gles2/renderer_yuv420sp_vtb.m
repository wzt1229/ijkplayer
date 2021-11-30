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
#if TARGET_OS_OSX
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl3.h>
#else
#if __OBJC__
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/EAGL.h>
#endif
#endif

#import <CoreVideo/CoreVideo.h>
#include "ijksdl_vout_overlay_videotoolbox.h"
#include "ijksdl_vout_overlay_ffmpeg.h"
#include "renderer_pixfmt.h"

#define NV12_RENDER_FAST_UPLOAD 2
#define NV12_RENDER_IO_SURFACE  4

#if TARGET_OS_OSX
//osx use NV12_RENDER_FAST_UPLOAD failed: -6683
#define NV12_RENDER_TYPE NV12_RENDER_IO_SURFACE
#else
#define NV12_RENDER_TYPE NV12_RENDER_FAST_UPLOAD
#endif

#if TARGET_OS_OSX
#define GL_TEXTURE_TARGET GL_TEXTURE_RECTANGLE
#else
#define GL_TEXTURE_TARGET GL_TEXTURE_2D
#endif

typedef struct _Frame_Size
{
    int w;
    int h;
}Frame_Size;

typedef struct IJK_GLES2_Renderer_Opaque
{
    OpenGLTextureCacheRef cv_texture_cache;
    OpenGLTextureRef      nv12_texture[3];
    CFTypeRef             color_attachments;
    GLint                 textureDimension[3];
    GLint                 isSubtitle;
    GLint                 isFullRange;
    Frame_Size            frameSize[3];
    OpenGLTextureRef      subCVGLTexture;
    Frame_Size            subTextureSize;
    int samples;
} IJK_GLES2_Renderer_Opaque;

static GLboolean yuv420sp_vtb_use(IJK_GLES2_Renderer *renderer)
{
    ALOGI("use render yuv420sp_vtb\n");
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glEnable(GL_TEXTURE_TARGET);
    glUseProgram(renderer->program);            IJK_GLES2_checkError_TRACE("glUseProgram");

#if NV12_RENDER_TYPE == NV12_RENDER_IO_SURFACE
    IJK_GLES2_Renderer_Opaque * opaque = renderer->opaque;
    assert(opaque->samples);
    
    if (0 == renderer->plane_textures[0])
        glGenTextures(opaque->samples, renderer->plane_textures);
#endif
    
    return GL_TRUE;
}

static GLsizei yuv420sp_vtb_getBufferWidth(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!overlay)
        return 0;

    return overlay->pitches[0] / 1;
}

#if NV12_RENDER_TYPE == NV12_RENDER_FAST_UPLOAD
static GLvoid yuv420sp_vtb_clean_textures(IJK_GLES2_Renderer *renderer)
{
    if (!renderer || !renderer->opaque)
        return;

    IJK_GLES2_Renderer_Opaque *opaque = renderer->opaque;

    for (int i = 0; i < 2; ++i) {
        if (opaque->nv12_texture[i]) {
            CFRelease(opaque->nv12_texture[i]);
            opaque->nv12_texture[i] = nil;
        }
    }
    
    // Periodic texture cache flush every frame
    if (opaque->cv_texture_cache)
        OpenGLTextureCacheFlush(opaque->cv_texture_cache, 0);
}

static GLboolean upload_texture_use_Cache(IJK_GLES2_Renderer_Opaque *opaque, CVPixelBufferRef pixel_buffer, IJK_GLES2_Renderer *renderer)
{
    if (!opaque->cv_texture_cache) {
        ALOGE("nil textureCache\n");
        return GL_FALSE;
    }
    
    yuv420sp_vtb_clean_textures(renderer);
    
    GLenum gl_target = GL_TEXTURE_TARGET;
    const int planes = (int)CVPixelBufferGetPlaneCount(pixel_buffer);
    for (int i = 0; i < planes; i++) {
        //设置采样器位置，保证了每个uniform采样器对应着正确的纹理单元
        glUniform1i(renderer->us2_sampler[i], i);
        glActiveTexture(GL_TEXTURE0 + i);
#if TARGET_OS_OSX
        CVReturn err = CVOpenGLTextureCacheCreateTextureFromImage(kCFAllocatorDefault, opaque->cv_texture_cache, pixel_buffer, NULL, &opaque->nv12_texture[i]);
#else
        
        GLsizei frame_width  = (GLsizei)CVPixelBufferGetWidthOfPlane(pixel_buffer, i);
        GLsizei frame_height = (GLsizei)CVPixelBufferGetHeightOfPlane(pixel_buffer, i);

        int format = i == 0 ? OpenGL_RED_EXT : OpenGL_RG_EXT;
        
        CVReturn err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                     opaque->cv_texture_cache,
                                                     pixel_buffer,
                                                     NULL,
                                                     gl_target,
                                                     format,
                                                     frame_width,
                                                     frame_height,
                                                     format,
                                                     GL_UNSIGNED_BYTE,
                                                     i,
                                                     &opaque->nv12_texture[i]);
        
#endif
        if (err != kCVReturnSuccess) {
            ALOGE("Error at CVOpenGLTextureCacheCreateTextureFromImage %d\n", err);
            return GL_FALSE;
        }

        glBindTexture(OpenGLTextureGetTarget(opaque->nv12_texture[i]), OpenGLTextureGetName(opaque->nv12_texture[i]));
        
        glTexParameteri(gl_target, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(gl_target, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameterf(gl_target, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(gl_target, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
    return GL_TRUE;
}
#endif

#if NV12_RENDER_TYPE == NV12_RENDER_IO_SURFACE
static GLboolean upload_texture_use_IOSurface(CVPixelBufferRef pixel_buffer,IJK_GLES2_Renderer *renderer)
{
    IOSurfaceRef surface  = CVPixelBufferGetIOSurface(pixel_buffer);
    
    if (!surface) {
        printf("CVPixelBuffer has no IOSurface\n");
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
    
    for (int i = 0; i < f->planes; i++) {
        GLfloat w = (GLfloat)IOSurfaceGetWidthOfPlane(surface, i);
        GLfloat h = (GLfloat)IOSurfaceGetHeightOfPlane(surface, i);
        Frame_Size size = renderer->opaque->frameSize[i];
        if (size.w != w || size.h != h) {
            glUniform2f(renderer->opaque->textureDimension[i], w, h);
            size.w = w;
            size.h = h;
            renderer->opaque->frameSize[i] = size;
        }
        //设置采样器位置，保证了每个uniform采样器对应着正确的纹理单元
        glUniform1i(renderer->us2_sampler[i], i);
        glActiveTexture(GL_TEXTURE0 + i);
        glBindTexture(gl_target, renderer->plane_textures[i]);
        struct vt_gl_plane_format plane_format = f->gl[i];
        CGLError err = CGLTexImageIOSurface2D(CGLGetCurrentContext(),
                                              gl_target,
                                              plane_format.gl_internal_format,
                                              w,
                                              h,
                                              plane_format.gl_format,
                                              plane_format.gl_type,
                                              surface,
                                              i);

        if (err != kCGLNoError) {
            ALOGE("error creating IOSurface texture for plane %d: %s\n",
                   0, CGLErrorString(err));
            return GL_FALSE;
        } else {
            glTexParameteri(gl_target, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(gl_target, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameterf(gl_target, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameterf(gl_target, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        }
    }
    return GL_TRUE;
}
#endif

static GLboolean upload_420sp_vtp_Texture(IJK_GLES2_Renderer *renderer, CVPixelBufferRef pixel_buffer)
{
    int pixel_fmt = CVPixelBufferGetPixelFormatType(pixel_buffer);
    
    assert(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange == pixel_fmt ||
           kCVPixelFormatType_420YpCbCr8BiPlanarFullRange == pixel_fmt ||
           kCVPixelFormatType_420YpCbCr8Planar == pixel_fmt ||
           kCVPixelFormatType_420YpCbCr8PlanarFullRange == pixel_fmt ||
           kCVPixelFormatType_32BGRA == pixel_fmt);
    
    IJK_GLES2_Renderer_Opaque *opaque = renderer->opaque;
    
    if (!opaque->color_attachments) {
        CFTypeRef color_attachments = CVBufferGetAttachment(pixel_buffer, kCVImageBufferYCbCrMatrixKey, NULL);
        if (color_attachments == nil ||
            CFStringCompare(color_attachments, kCVImageBufferYCbCrMatrix_ITU_R_709_2, 0) == kCFCompareEqualTo) {
            color_attachments = kCVImageBufferYCbCrMatrix_ITU_R_709_2;
            glUniformMatrix3fv(renderer->um3_color_conversion, 1, GL_FALSE, IJK_GLES2_getColorMatrix_bt709());
        } else if (CFStringCompare(color_attachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == kCFCompareEqualTo) {
            glUniformMatrix3fv(renderer->um3_color_conversion, 1, GL_FALSE, IJK_GLES2_getColorMatrix_bt601());
        } else {
            glUniformMatrix3fv(renderer->um3_color_conversion, 1, GL_FALSE, IJK_GLES2_getColorMatrix_bt709());
        }

        opaque->color_attachments = CFRetain(color_attachments);
        
        //full color range
        if (kCVPixelFormatType_420YpCbCr8BiPlanarFullRange == pixel_fmt ||
            kCVPixelFormatType_420YpCbCr8PlanarFullRange == pixel_fmt) {
            glUniform1i(renderer->opaque->isFullRange, GL_TRUE);
        }
    }

#if NV12_RENDER_TYPE == NV12_RENDER_FAST_UPLOAD
    upload_texture_use_Cache(opaque, pixel_buffer, renderer);
#else
    upload_texture_use_IOSurface(pixel_buffer, renderer);
#endif
    return GL_TRUE;
}

static CVPixelBufferRef yuv420sp_getCVPixelBufferRef(SDL_VoutOverlay *overlay)
{
    switch (overlay->format) {
        case SDL_FCC__VTB:
            return SDL_VoutOverlayVideoToolBox_GetCVPixelBufferRef(overlay);
        case SDL_FCC__FFVTB:
#if USE_FF_VTB
            return SDL_VoutFFmpeg_GetCVPixelBufferRef(overlay);
#endif
        default:
            return NULL;
    }
}

static GLboolean yuv420sp_vtb_uploadTexture(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!renderer || !renderer->opaque || !overlay)
        return GL_FALSE;
    
    CVPixelBufferRef pixel_buffer = yuv420sp_getCVPixelBufferRef(overlay);
    if (!pixel_buffer) {
        ALOGE("nil pixelBuffer in overlay\n");
        return GL_FALSE;
    }
    return upload_420sp_vtp_Texture(renderer, pixel_buffer);
}

void * yuv420sp_vtb_getImage(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!renderer || !renderer->opaque || !overlay)
        return NULL;
    return yuv420sp_getCVPixelBufferRef(overlay);
}

static GLvoid yuv420sp_vtb_destroy(IJK_GLES2_Renderer *renderer)
{
    if (!renderer || !renderer->opaque)
        return;
    
    IJK_GLES2_Renderer_Opaque *opaque = renderer->opaque;
#if NV12_RENDER_TYPE == NV12_RENDER_FAST_UPLOAD
    yuv420sp_vtb_clean_textures(renderer);
    if (opaque->cv_texture_cache) {
        CFRelease(opaque->cv_texture_cache);
        opaque->cv_texture_cache = nil;
    }
#endif
    if (opaque->color_attachments != nil) {
        CFRelease(opaque->color_attachments);
        opaque->color_attachments = nil;
    }
    free(renderer->opaque);
    renderer->opaque = nil;
}

#if NV12_RENDER_TYPE == NV12_RENDER_FAST_UPLOAD
static GLboolean create_gltexture(IJK_GLES2_Renderer *renderer)
{
    OpenGLTextureCacheRef ref;
#if TARGET_OS_OSX
    CGLContextObj cglContext = CGLGetCurrentContext();
    CGLPixelFormatObj cglPixelFormat = CGLGetPixelFormat(CGLGetCurrentContext());
    CVReturn err = CVOpenGLTextureCacheCreate(kCFAllocatorDefault, NULL, cglContext, cglPixelFormat, NULL, &ref);
#else
    EAGLContext *context = [EAGLContext currentContext];
    CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, context, NULL, &ref);
#endif
    if (err || ref == nil) {
        ALOGE("Error at CVOpenGLESTextureCacheCreate %d\n", err);
        return GL_FALSE;;
    }
    
    renderer->opaque->cv_texture_cache = ref;
    return GL_TRUE;
}
#endif


#if TARGET_OS_OSX

static GLvoid yuv420sp_useSubtitle(IJK_GLES2_Renderer *renderer,GLboolean subtitle)
{
    glUniform1i(renderer->opaque->isSubtitle, (GLint)subtitle);
}

/**
 On macOS, create an OpenGL texture and retrieve an OpenGL texture name using the following steps, and as annotated in the code listings below:
 */
OpenGLTextureRef createGLTexture(IJK_GLES2_Renderer_Opaque* opaque, CVPixelBufferRef pixelBuff)
{
    assert(opaque->cv_texture_cache);
    
    if (opaque->cv_texture_cache) {
        OpenGLTextureCacheFlush(opaque->cv_texture_cache, 0);
    }

    CVOpenGLTextureRef texture = NULL;
    // 2. Create a CVPixelBuffer-backed OpenGL texture image from the texture cache.
    CVReturn cvret = CVOpenGLTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                opaque->cv_texture_cache,
                                                       pixelBuff,
                                                       nil,
                                                       &texture);
    
    assert(cvret == kCVReturnSuccess);
    return texture;
}

#else // if!(TARGET_IOS || TARGET_TVOS)

/**
 On iOS, create an OpenGL ES texture from the CoreVideo pixel buffer using the following steps, and as annotated in the code listings below:
 */
OpenGLTextureRef createGLTexture(IJK_GLES2_Renderer_Opaque* opaque, CVPixelBufferRef pixelBuff)
{
    assert(opaque->cv_texture_cache);
    
    if (opaque->cv_texture_cache) {
        OpenGLTextureCacheFlush(opaque->cv_texture_cache, 0);
    }
    
    GLsizei width  = (GLsizei)CVPixelBufferGetWidth(pixelBuff);
    GLsizei height = (GLsizei)CVPixelBufferGetHeight(pixelBuff);
    
#if TARGET_OS_SIMULATOR
    GLint target = GL_BGRA;
#elif TARGET_OS_IOS
    GLint target = GL_RGBA;
#endif
    OpenGLTextureRef texture = NULL;
    // 2. Create a CVPixelBuffer-backed OpenGL ES texture image from the texture cache.
    CVReturn cvret = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                  opaque->cv_texture_cache,
                                                         pixelBuff,
                                                         NULL,
                                                         GL_TEXTURE_2D,
                                                         target,
                                                         width,
                                                         height,
                                                         GL_BGRA,
                                                         GL_UNSIGNED_BYTE,
                                                         0,
                                                         &texture);
    
    assert(cvret == kCVReturnSuccess);
    
    return texture;
}

#endif // !(TARGET_IOS || TARGET_TVOS)

#if TARGET_OS_OSX
static GLboolean yuv420sp_uploadSubtitle(IJK_GLES2_Renderer *renderer,void *subtitle, IJK_Subtile_Size* size)
{
    CVPixelBufferRef cvPixelRef = (CVPixelBufferRef)subtitle;
    if (cvPixelRef) {
        CVPixelBufferRetain(cvPixelRef);
        
        int width = (int)CVPixelBufferGetWidth(cvPixelRef);
        int height = (int)CVPixelBufferGetHeight(cvPixelRef);
        
        IJK_GLES2_Renderer_Opaque *opaque = renderer->opaque;
        
        opaque->subTextureSize.w = width;
        opaque->subTextureSize.h = height;
        
        if (opaque->subCVGLTexture) {
            CFRelease(opaque->subCVGLTexture);
            opaque->subCVGLTexture = 0;
        }
        
        upload_texture_use_IOSurface(cvPixelRef, renderer);
        size->w = width / 2.0;
        size->h = height / 2.0;
        CVPixelBufferRelease(cvPixelRef);
    }
    return GL_TRUE;
}
#endif

IJK_GLES2_Renderer *IJK_GL_Renderer_create_yuv420sp_vtb(SDL_VoutOverlay *overlay,int samples)
{
#if TARGET_OS_OSX
    assert(overlay->format == SDL_FCC__VTB || overlay->format == SDL_FCC__FFVTB);
    
    IJK_GLES2_Renderer *renderer = IJK_GLES2_Renderer_create_base(IJK_GL_getFragmentShader_yuv420sp_rect(samples));
#else
    IJK_GLES2_Renderer *renderer = IJK_GLES2_Renderer_create_base(IJK_GL_getFragmentShader_yuv420sp());
#endif
    
    if (!renderer)
        goto fail;
    
    for (int i = 0; i < samples; i++) {
        char name[20] = "us2_Sampler";
        name[strlen(name)] = (char)i + '0';
        renderer->us2_sampler[i] = glGetUniformLocation(renderer->program, name); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_Sampler)");
    }

    if (samples > 1) {
        renderer->um3_color_conversion = glGetUniformLocation(renderer->program, "um3_ColorConversion"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(um3_ColorConversionMatrix)");
    }
    
    renderer->um3_rgb_adjustment = glGetUniformLocation(renderer->program, "um3_rgbAdjustment"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(um3_rgb_adjustmentVector)");
    
    renderer->func_use            = yuv420sp_vtb_use;
    renderer->func_getBufferWidth = yuv420sp_vtb_getBufferWidth;
    renderer->func_uploadTexture  = yuv420sp_vtb_uploadTexture;
    renderer->func_getImage       = yuv420sp_vtb_getImage;
    renderer->func_destroy        = yuv420sp_vtb_destroy;
#if TARGET_OS_OSX
    renderer->func_useSubtitle    = yuv420sp_useSubtitle;
    renderer->func_uploadSubtitle = yuv420sp_uploadSubtitle;
#endif
    renderer->opaque = calloc(1, sizeof(IJK_GLES2_Renderer_Opaque));
    if (!renderer->opaque)
        goto fail;
    bzero(renderer->opaque, sizeof(IJK_GLES2_Renderer_Opaque));
    renderer->opaque->samples = samples;
    renderer->opaque->isSubtitle  = -1;
    renderer->opaque->isFullRange = -1;
    
#if NV12_RENDER_TYPE == NV12_RENDER_FAST_UPLOAD
    if (!create_gltexture(renderer)) {
        goto fail;
    }
#endif
    
#if TARGET_OS_OSX
    if (overlay->format == SDL_FCC__VTB || overlay->format == SDL_FCC__FFVTB) {
        
        for (int i = 0; i < samples; i++) {
            char name[20] = "textureDimension";
            name[strlen(name)] = (char)i + '0';
            GLint textureDimension = glGetUniformLocation(renderer->program, name);
            assert(textureDimension >= 0);
            renderer->opaque->textureDimension[i] = textureDimension;
        }
    }

    if (samples > 1) {
        GLint isFullRange = glGetUniformLocation(renderer->program, "isFullRange");
        assert(isFullRange >= 0);
        renderer->opaque->isFullRange = isFullRange;
    }
    
    GLint isSubtitle = glGetUniformLocation(renderer->program, "isSubtitle");
    assert(isSubtitle >= 0);
    renderer->opaque->isSubtitle = isSubtitle;
#endif
    
    return renderer;
fail:
    IJK_GLES2_Renderer_free(renderer);
    return NULL;
}
