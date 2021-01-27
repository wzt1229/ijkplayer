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
#include "renderer_pixfmt.h"
#import "MRTextureString.h"

#define NV12_RENDER_NORMAL      1
#define NV12_RENDER_FAST_UPLOAD 2
#define NV12_RENDER_IO_SURFACE  4

#if TARGET_OS_OSX
#warning use NV12_RENDER_FAST_UPLOAD -6683
#define NV12_RENDER_TYPE NV12_RENDER_IO_SURFACE
#else
#define NV12_RENDER_TYPE NV12_RENDER_FAST_UPLOAD
#endif

#if (NV12_RENDER_TYPE != NV12_RENDER_NORMAL) && TARGET_OS_OSX
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
    OpenGLTextureRef      nv12_texture[2];
    CFTypeRef             color_attachments;
    GLint                 textureDimension[2];
    GLint                 isSubtitle;
    Frame_Size            frameSize[2];
    MRTextureString       *textureString;
} IJK_GLES2_Renderer_Opaque;

static GLboolean yuv420sp_vtb_use(IJK_GLES2_Renderer *renderer)
{
    ALOGI("use render yuv420sp_vtb\n");
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glEnable(GL_TEXTURE_TARGET);
    glUseProgram(renderer->program);            IJK_GLES2_checkError_TRACE("glUseProgram");

#if NV12_RENDER_TYPE == NV12_RENDER_NORMAL || NV12_RENDER_TYPE == NV12_RENDER_IO_SURFACE
    if (0 == renderer->plane_textures[0])
        glGenTextures(2, renderer->plane_textures);
#endif
    
    //设置纹理和采样器的对应关系
    for (int i = 0; i < 2; ++i) {
        glUniform1i(renderer->us2_sampler[i], i);
    }

    glUniformMatrix3fv(renderer->um3_color_conversion, 1, GL_FALSE, IJK_GLES2_getColorMatrix_bt709());
    
    return GL_TRUE;
}

static GLsizei yuv420sp_vtb_getBufferWidth(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!overlay)
        return 0;

    return overlay->pitches[0] / 1;
}

#if NV12_RENDER_TYPE == NV12_RENDER_NORMAL
static void upload_texture_normal(IJK_GLES2_Renderer *renderer, const GLubyte *pixels[2], const GLsizei widths[2], const GLsizei heights[2]) {
    
    assert(NULL != *pixels);
    
    GLenum gl_target = GL_TEXTURE_TARGET;
    for (int i = 0; i < 2; i++) {
        GLenum format = i == 0 ? OpenGL_RED_EXT : OpenGL_RG_EXT;
        glActiveTexture(GL_TEXTURE0 + i);
        glBindTexture(gl_target, renderer->plane_textures[i]);
        glTexImage2D(gl_target,
                     0,
                     format,
                     widths[i],
                     heights[i],
                     0,
                     format,
                     GL_UNSIGNED_BYTE,
                     pixels[i]);
        glTexParameteri(gl_target, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(gl_target, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameterf(gl_target, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(gl_target, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
}
#endif

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
    
    for (int i = 0; i < planes; i++) {
        GLfloat w = (GLfloat)IOSurfaceGetWidthOfPlane(surface, i);
        GLfloat h = (GLfloat)IOSurfaceGetHeightOfPlane(surface, i);
        Frame_Size size = renderer->opaque->frameSize[i];
        if (size.w != w || size.h != h) {
            glUniform2f(renderer->opaque->textureDimension[i], w, h);
            size.w = w;
            size.h = h;
            renderer->opaque->frameSize[i] = size;
        }
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

static GLboolean upload_420sp_vtp_Texture(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    CVPixelBufferRef pixel_buffer = SDL_VoutOverlayVideoToolBox_GetCVPixelBufferRef(overlay);
    if (!pixel_buffer) {
        ALOGE("nil pixelBuffer in overlay\n");
        return GL_FALSE;
    }
    
    assert(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange == CVPixelBufferGetPixelFormatType(pixel_buffer) || kCVPixelFormatType_420YpCbCr8BiPlanarFullRange == CVPixelBufferGetPixelFormatType(pixel_buffer));
    
    IJK_GLES2_Renderer_Opaque *opaque = renderer->opaque;
    
    CFTypeRef color_attachments = CVBufferGetAttachment(pixel_buffer, kCVImageBufferYCbCrMatrixKey, NULL);
    if (color_attachments != opaque->color_attachments) {
        if (color_attachments == nil) {
            glUniformMatrix3fv(renderer->um3_color_conversion, 1, GL_FALSE, IJK_GLES2_getColorMatrix_bt709());
        } else if (opaque->color_attachments != nil &&
                   CFStringCompare(color_attachments, opaque->color_attachments, 0) == kCFCompareEqualTo) {
            // remain prvious color attachment
        } else if (CFStringCompare(color_attachments, kCVImageBufferYCbCrMatrix_ITU_R_709_2, 0) == kCFCompareEqualTo) {
            glUniformMatrix3fv(renderer->um3_color_conversion, 1, GL_FALSE, IJK_GLES2_getColorMatrix_bt709());
        } else if (CFStringCompare(color_attachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == kCFCompareEqualTo) {
            glUniformMatrix3fv(renderer->um3_color_conversion, 1, GL_FALSE, IJK_GLES2_getColorMatrix_bt601());
        } else {
            glUniformMatrix3fv(renderer->um3_color_conversion, 1, GL_FALSE, IJK_GLES2_getColorMatrix_bt709());
        }

        if (opaque->color_attachments != nil) {
            CFRelease(opaque->color_attachments);
            opaque->color_attachments = nil;
        }
        if (color_attachments != nil) {
            opaque->color_attachments = CFRetain(color_attachments);
        }
    }

#if NV12_RENDER_TYPE == NV12_RENDER_FAST_UPLOAD
    upload_texture_use_Cache(opaque, pixel_buffer, renderer);
#elif NV12_RENDER_TYPE == NV12_RENDER_NORMAL
    
    const GLsizei widths[2]    = { overlay->pitches[0], overlay->pitches[1] };
    const GLsizei heights[2]   = { overlay->h,          overlay->h/2.0 };
    
    CVPixelBufferLockBaseAddress(pixel_buffer, 0);
    GLubyte * y = CVPixelBufferGetBaseAddressOfPlane(pixel_buffer, 0);
    GLubyte * uv = CVPixelBufferGetBaseAddressOfPlane(pixel_buffer, 1);
    upload_texture_normal(renderer, (const GLubyte *[2]){y, uv},widths,heights);
    CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
#else
    upload_texture_use_IOSurface(pixel_buffer, renderer);
#endif
    return GL_TRUE;
}

static GLboolean yuv420sp_vtb_uploadTexture(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!renderer || !renderer->opaque || !overlay)
        return GL_FALSE;

    switch (overlay->format) {
        case SDL_FCC__VTB:
            return upload_420sp_vtp_Texture(renderer, overlay);
        default:
            ALOGE("[yuv420sp_vtb] unexpected format %x\n", overlay->format);
            return GL_FALSE;
    }
    return GL_TRUE;
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

static GLvoid yuv420sp_useSubtitle(IJK_GLES2_Renderer *renderer,GLboolean subtitle)
{
    glUniform1i(renderer->opaque->isSubtitle, (GLint)subtitle);
}

static GLboolean yuv420sp_uploadSubtitle(IJK_GLES2_Renderer *renderer,char * subtitle)
{
    NSMutableDictionary * stanStringAttrib = [NSMutableDictionary dictionary];
    NSFont * font = [NSFont fontWithName:@"Helvetica" size:54.0];
    [stanStringAttrib setObject:font forKey:NSFontAttributeName];
    [stanStringAttrib setObject:[NSColor colorWithWhite:1 alpha:1] forKey:NSForegroundColorAttributeName];
    
    NSString *aStr = [[NSString alloc] initWithUTF8String:subtitle];
    
    if (renderer->opaque->textureString) {
        [renderer->opaque->textureString setString:aStr withAttributes:stanStringAttrib];
    } else {
        MRTextureString *textureString = [[MRTextureString alloc] initWithString:aStr withAttributes:stanStringAttrib withBoxColor:[NSColor colorWithRed:0.5f green:0.5f blue:0.5f alpha:0.5f] withBorderColor:nil];
        renderer->opaque->textureString = textureString;
    }
    
    CVPixelBufferRef cvPixelRef = [renderer->opaque->textureString cvPixelBuffer];
#warning TODO draw
    CVPixelBufferRelease(cvPixelRef);
    return GL_TRUE;
}

IJK_GLES2_Renderer *IJK_GL_Renderer_create_yuv420sp_vtb(SDL_VoutOverlay *overlay)
{
    ALOGI("create render yuv420sp_vtb\n");
#if (NV12_RENDER_TYPE != NV12_RENDER_NORMAL) && TARGET_OS_OSX
    
    assert(overlay->format == SDL_FCC__VTB);
    
    IJK_GLES2_Renderer *renderer = IJK_GLES2_Renderer_create_base(IJK_GL_getFragmentShader_yuv420sp_rect());
#else
    IJK_GLES2_Renderer *renderer = IJK_GLES2_Renderer_create_base(IJK_GL_getFragmentShader_yuv420sp());
#endif
    
    if (!renderer)
        goto fail;

    renderer->us2_sampler[0] = glGetUniformLocation(renderer->program, "us2_SamplerX"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_SamplerX)");
    renderer->us2_sampler[1] = glGetUniformLocation(renderer->program, "us2_SamplerY"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_SamplerY)");

    renderer->um3_color_conversion = glGetUniformLocation(renderer->program, "um3_ColorConversion"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(um3_ColorConversionMatrix)");

    renderer->func_use            = yuv420sp_vtb_use;
    renderer->func_getBufferWidth = yuv420sp_vtb_getBufferWidth;
    renderer->func_uploadTexture  = yuv420sp_vtb_uploadTexture;
    renderer->func_destroy        = yuv420sp_vtb_destroy;
    renderer->func_useSubtitle    = yuv420sp_useSubtitle;
    renderer->func_uploadSubtitle = yuv420sp_uploadSubtitle;
    
    renderer->opaque = calloc(1, sizeof(IJK_GLES2_Renderer_Opaque));
    if (!renderer->opaque)
        goto fail;
    
#if NV12_RENDER_TYPE == NV12_RENDER_FAST_UPLOAD
    if (!create_gltexture(renderer)) {
        goto fail;
    }
#endif
    
#if (NV12_RENDER_TYPE != NV12_RENDER_NORMAL) && TARGET_OS_OSX
    if (overlay->format == SDL_FCC__VTB) {
        GLint textureDimensionX = glGetUniformLocation(renderer->program, "textureDimensionX");
        assert(textureDimensionX >= 0);
        renderer->opaque->textureDimension[0] = textureDimensionX;
        
        GLint textureDimensionY = glGetUniformLocation(renderer->program, "textureDimensionY");
        assert(textureDimensionY >= 0);
        renderer->opaque->textureDimension[1] = textureDimensionY;
    }
#endif
    
    GLint isSubtitle = glGetUniformLocation(renderer->program, "isSubtitle");
    assert(isSubtitle >= 0);
    renderer->opaque->isSubtitle = isSubtitle;
    
    renderer->opaque->color_attachments = CFRetain(kCVImageBufferYCbCrMatrix_ITU_R_709_2);
    return renderer;
fail:
    IJK_GLES2_Renderer_free(renderer);
    return NULL;
}
