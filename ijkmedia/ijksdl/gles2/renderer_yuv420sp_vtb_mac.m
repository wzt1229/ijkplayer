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
#import <OpenGLES/EAGL.h>
#endif /* TARGET_OS_OSX */
#import <Foundation/Foundation.h>

#include "ijksdl_vout_overlay_videotoolbox.h"

typedef struct IJK_GLES2_Renderer_Opaque
{
    CVOpenGLTextureCacheRef cv_texture_cache;
    CVOpenGLTextureRef      cv_texture[2];
    CFTypeRef               color_attachments;
} IJK_GLES2_Renderer_Opaque;

static GLboolean yuv420sp_vtb_use(IJK_GLES2_Renderer *renderer)
{
    ALOGI("use render yuv420sp_vtb\n");
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    glUseProgram(renderer->program);            IJK_GLES2_checkError_TRACE("glUseProgram");

    for (int i = 0; i < 2; ++i) {
        glUniform1i(renderer->us2_sampler[i], i);
    }

    glUniformMatrix3fv(renderer->um3_color_conversion, 1, GL_FALSE, IJK_GLES2_getColorMatrix_bt709());
    
    return GL_TRUE;
}

static GLvoid yuv420sp_vtb_clean_textures(IJK_GLES2_Renderer *renderer)
{
    if (!renderer || !renderer->opaque)
        return;

    IJK_GLES2_Renderer_Opaque *opaque = renderer->opaque;

    for (int i = 0; i < 2; ++i) {
        if (opaque->cv_texture[i]) {
            CFRelease(opaque->cv_texture[i]);
            opaque->cv_texture[i] = nil;
        }
    }

    // Periodic texture cache flush every frame
    if (opaque->cv_texture_cache)
        CVOpenGLTextureCacheFlush(opaque->cv_texture_cache, 0);
}

static GLsizei yuv420sp_vtb_getBufferWidth(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!overlay)
        return 0;

    return overlay->pitches[0] / 1;
}

static GLboolean yuv420sp_vtb_uploadTexture(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!renderer || !renderer->opaque || !overlay)
        return GL_FALSE;

    if (!overlay->is_private)
        return GL_FALSE;

    switch (overlay->format) {
        case SDL_FCC__VTB:
            break;
        default:
            ALOGE("[yuv420sp_vtb] unexpected format %x\n", overlay->format);
            return GL_FALSE;
    }

    IJK_GLES2_Renderer_Opaque *opaque = renderer->opaque;
    if (!opaque->cv_texture_cache) {
        ALOGE("nil textureCache\n");
        return GL_FALSE;
    }

    CVPixelBufferRef pixel_buffer = SDL_VoutOverlayVideoToolBox_GetCVPixelBufferRef(overlay);
    if (!pixel_buffer) {
        ALOGE("nil pixelBuffer in overlay\n");
        return GL_FALSE;
    }

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

    yuv420sp_vtb_clean_textures(renderer);
//https://stackoverflow.com/questions/27149380/how-to-list-all-opengl-es-compatible-pixelbuffer-formats/27152363#27152363
//    @autoreleasepool {
//        printf("Core Video Supported Pixel Format Types:\n");
//        
//        CFArrayRef pixelFormatDescriptionsArray = CVPixelFormatDescriptionArrayCreateWithAllPixelFormatTypes(kCFAllocatorDefault);
//        for (CFIndex i = 0; i < CFArrayGetCount(pixelFormatDescriptionsArray); i++) {
//            CFNumberRef pixelFormatFourCC = (CFNumberRef)CFArrayGetValueAtIndex(pixelFormatDescriptionsArray, i);
//            
//            if (pixelFormatFourCC != NULL) {
//                UInt32 value;
//                
//                CFNumberGetValue(pixelFormatFourCC, kCFNumberSInt32Type, &value);
//                
//                NSString * pixelFormat;
//                if (value <= 0x28) {
//                    pixelFormat = [NSString stringWithFormat:@"Core Video Pixel Format Type 0x%02x", (unsigned int)value];
//                } else {
//                    pixelFormat = [NSString stringWithFormat:@"Core Video Pixel Format Type (FourCC) %c%c%c%c", (char)(value >> 24), (char)(value >> 16), (char)(value >> 8), (char)value];
//                }
//                
//                CFDictionaryRef desc =  CVPixelFormatDescriptionCreateWithPixelFormatType(kCFAllocatorDefault, (OSType)value);
//                CFBooleanRef OpenGLCompatibility = (CFBooleanRef)CFDictionaryGetValue(desc, kCVPixelFormatOpenGLCompatibility);
//                printf("%s: Compatible with OpenGL: %s\n", pixelFormat.UTF8String, (OpenGLCompatibility != nil && CFBooleanGetValue(OpenGLCompatibility)) ? "YES" : "NO");
//            }
//        }
//        
//        printf("End Core Video Supported Pixel Format Types.\n");
//    }
    
    glActiveTexture(GL_TEXTURE0);
    int32_t r = kCVReturnSuccess;
    if(kCVReturnSuccess != (r = CVOpenGLTextureCacheCreateTextureFromImage(NULL,
                                                 opaque->cv_texture_cache,
                                                 pixel_buffer,
                                                 NULL,&opaque->cv_texture[0]))){
        return GL_FALSE;
    }
    glBindTexture(CVOpenGLTextureGetTarget(opaque->cv_texture[0]), CVOpenGLTextureGetName(opaque->cv_texture[0]));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);


    glActiveTexture(GL_TEXTURE1);
    if(kCVReturnSuccess != CVOpenGLTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                 opaque->cv_texture_cache,
                                                 pixel_buffer,
                                                 NULL,
                                                                      &opaque->cv_texture[1])){
        return GL_FALSE;
    }
    glBindTexture(CVOpenGLTextureGetTarget(opaque->cv_texture[1]), CVOpenGLTextureGetName(opaque->cv_texture[1]));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);


    return GL_TRUE;
}

static GLvoid yuv420sp_vtb_destroy(IJK_GLES2_Renderer *renderer)
{
    if (!renderer || !renderer->opaque)
        return;

    yuv420sp_vtb_clean_textures(renderer);

    IJK_GLES2_Renderer_Opaque *opaque = renderer->opaque;
    if (opaque->cv_texture_cache) {
        CFRelease(opaque->cv_texture_cache);
        opaque->cv_texture_cache = nil;
    }

    if (opaque->color_attachments != nil) {
        CFRelease(opaque->color_attachments);
        opaque->color_attachments = nil;
    }
    free(renderer->opaque);
    renderer->opaque = nil;
}

IJK_GLES2_Renderer *IJK_GLES2_Renderer_create_yuv420sp_vtb(SDL_VoutOverlay *overlay)
{
    CVReturn err = 0;

    if (!overlay) {
        ALOGW("invalid overlay, fall back to yuv420sp renderer\n");
        return IJK_GLES2_Renderer_create_yuv420sp();
    }

    if (!overlay) {
        ALOGW("non-private overlay, fall back to yuv420sp renderer\n");
        return IJK_GLES2_Renderer_create_yuv420sp();
    }
//    EAGLContext *context = [EAGLContext currentContext];
//    if (!context) {
//        ALOGW("nil EAGLContext, fall back to yuv420sp renderer\n");
//        return IJK_GLES2_Renderer_create_yuv420sp();
//    }

    if (!CGLGetCurrentContext()) {
        ALOGW("nil EAGLContext, fall back to yuv420sp renderer\n");
        return IJK_GLES2_Renderer_create_yuv420sp();
    }
    ALOGI("create render yuv420sp_vtb\n");
    IJK_GLES2_Renderer *renderer = IJK_GLES2_Renderer_create_base(IJK_GLES2_getFragmentShader_yuv420sp());
    if (!renderer)
        goto fail;

    renderer->us2_sampler[0] = glGetUniformLocation(renderer->program, "us2_SamplerX"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_SamplerX)");
    renderer->us2_sampler[1] = glGetUniformLocation(renderer->program, "us2_SamplerY"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_SamplerY)");

    renderer->um3_color_conversion = glGetUniformLocation(renderer->program, "um3_ColorConversion"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(um3_ColorConversionMatrix)");

    renderer->func_use            = yuv420sp_vtb_use;
    renderer->func_getBufferWidth = yuv420sp_vtb_getBufferWidth;
    renderer->func_uploadTexture  = yuv420sp_vtb_uploadTexture;
    renderer->func_destroy        = yuv420sp_vtb_destroy;

    renderer->opaque = calloc(1, sizeof(IJK_GLES2_Renderer_Opaque));
    if (!renderer->opaque)
        goto fail;
    CGLPixelFormatObj cglPixelFormat = CGLGetPixelFormat(CGLGetCurrentContext());
    err = CVOpenGLTextureCacheCreate(kCFAllocatorDefault, NULL, CGLGetCurrentContext(), cglPixelFormat, NULL, &renderer->opaque->cv_texture_cache);
    
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
