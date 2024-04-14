/*
 * ijksdl_vout_ios_gles2.c
 *
 * Copyright (c) 2013 Bilibili
 * Copyright (c) 2013 Zhang Rui <bbcallen@gmail.com>
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

#import "ijksdl_vout_ios_gles2.h"

#include <assert.h>
#include "ijksdl/ijksdl_vout.h"
#include "ijksdl/ijksdl_vout_internal.h"
#include "ijksdl_vout_overlay_ffmpeg.h"
#include "ijksdl_vout_overlay_ffmpeg_hw.h"
#include "ijkplayer/ff_subtitle_def.h"

#if TARGET_OS_IOS
#include "../ios/IJKSDLGLView.h"
#else
#include "../mac/IJKSDLGLView.h"
#endif
#import <MetalKit/MetalKit.h>
#import "IJKMetalFBO.h"
#import "IJKMetalSubtitlePipeline.h"

@interface _IJKSDLSubTexture : NSObject<IJKSDLSubtitleTextureProtocol>

@property(nonatomic) GLuint texture;
@property(nonatomic) int w;
@property(nonatomic) int h;

@end

@implementation _IJKSDLSubTexture

- (void)dealloc
{
    if (_texture) {
        glDeleteTextures(1, &_texture);
    }
}

- (GLuint)texture
{
    return _texture;
}

- (instancetype)initWith:(uint32_t)texture w:(int)w h:(int)h
{
    self = [super init];
    if (self) {
        self.w = w;
        self.h = h;
        self.texture = texture;
    }
    return self;
}

@end

@implementation IJKOverlayAttach

- (void)dealloc
{
    if (self.videoPicture) {
        CVPixelBufferRelease(self.videoPicture);
        self.videoPicture = NULL;
    }
    self.subTexture = nil;
    if (self.overlay) {
        SDL_TextureOverlay_Release(&self->_overlay);
    }
}

- (BOOL)generateSubTexture
{
    if (!self.overlay) {
        return NO;
    }
    self.subTexture = (__bridge _IJKSDLSubTexture *)self.overlay->getTexture(self.overlay->opaque);
    return !!self.subTexture;
}

@end

struct SDL_Vout_Opaque {
    void *cvPixelBufferPool;
    int cv_format;
    __strong UIView<IJKVideoRenderingProtocol> *gl_view;
    SDL_TextureOverlay *overlay;
};

static SDL_VoutOverlay *vout_create_overlay_l(int width, int height, int src_format, SDL_Vout *vout)
{
    switch (src_format) {
        case AV_PIX_FMT_VIDEOTOOLBOX:
            return SDL_VoutFFmpeg_HW_CreateOverlay(width, height, vout);
        default:
            return SDL_VoutFFmpeg_CreateOverlay(width, height, src_format, vout);
    }
}

static SDL_VoutOverlay *vout_create_overlay(int width, int height, int src_format, SDL_Vout *vout)
{
    SDL_LockMutex(vout->mutex);
    SDL_VoutOverlay *overlay = vout_create_overlay_l(width, height, src_format, vout);
    SDL_UnlockMutex(vout->mutex);
    return overlay;
}

static void vout_free_l(SDL_Vout *vout)
{
    if (!vout)
        return;
    
    SDL_Vout_Opaque *opaque = vout->opaque;
    if (opaque) {
        opaque->gl_view = nil;
        if (opaque->cvPixelBufferPool) {
            CVPixelBufferPoolRelease(opaque->cvPixelBufferPool);
            opaque->cvPixelBufferPool = NULL;
        }
        if (opaque->overlay) {
            SDL_TextureOverlay_Release(&opaque->overlay);
        }
    }

    SDL_Vout_FreeInternal(vout);
}

static CVPixelBufferRef SDL_Overlay_getCVPixelBufferRef(SDL_VoutOverlay *overlay)
{
    switch (overlay->format) {
        case SDL_FCC__VTB:
            return SDL_VoutFFmpeg_HW_GetCVPixelBufferRef(overlay);
        case SDL_FCC__FFVTB:
            return SDL_VoutFFmpeg_GetCVPixelBufferRef(overlay);
        default:
            return NULL;
    }
}

static int vout_display_overlay_l(SDL_Vout *vout, SDL_VoutOverlay *overlay)
{
    SDL_Vout_Opaque *opaque = vout->opaque;
    UIView<IJKVideoRenderingProtocol>* gl_view = opaque->gl_view;

    if (!gl_view) {
        ALOGE("vout_display_overlay_l: NULL gl_view\n");
        return -1;
    }

    if (!overlay) {
        ALOGE("vout_display_overlay_l: NULL overlay\n");
        return -2;
    }

    if (overlay->w <= 0 || overlay->h <= 0) {
        ALOGE("vout_display_overlay_l: invalid overlay dimensions(%d, %d)\n", overlay->w, overlay->h);
        return -3;
    }

    if (SDL_FCC__VTB != overlay->format && SDL_FCC__FFVTB != overlay->format) {
        ALOGE("vout_display_overlay_l: invalid format:%d\n",overlay->format);
        return -4;
    }
    
    CVPixelBufferRef videoPic = SDL_Overlay_getCVPixelBufferRef(overlay);
    if (videoPic) {
        IJKOverlayAttach *attach = [[IJKOverlayAttach alloc] init];
        attach.w = overlay->w;
        attach.h = overlay->h;
      
        attach.pixelW = (int)CVPixelBufferGetWidth(videoPic);
        attach.pixelH = (int)CVPixelBufferGetHeight(videoPic);
        
        attach.pitches = overlay->pitches;
        attach.sarNum = overlay->sar_num;
        attach.sarDen = overlay->sar_den;
        attach.autoZRotate = overlay->auto_z_rotate_degrees;
        //attach.bufferW = overlay->pitches[0];
        attach.videoPicture = CVPixelBufferRetain(videoPic);
        attach.overlay = SDL_TextureOverlay_Retain(opaque->overlay);
        return [gl_view displayAttach:attach];
    } else {
        ALOGE("vout_display_overlay_l: no video picture.\n");
        return -5;
    }
}

static int vout_display_overlay(SDL_Vout *vout, SDL_VoutOverlay *overlay)
{
    @autoreleasepool {
        SDL_LockMutex(vout->mutex);
        int retval = vout_display_overlay_l(vout, overlay);
        SDL_UnlockMutex(vout->mutex);
        return retval;
    }
}

static void vout_update_subtitle(SDL_Vout *vout, void *overlay)
{
    SDL_Vout_Opaque *opaque = vout->opaque;
    if (!opaque) {
        return;
    }
    if (opaque->overlay) {
        SDL_TextureOverlay_Release(&opaque->overlay);
    }
    opaque->overlay = SDL_TextureOverlay_Retain(overlay);
}

SDL_Vout *SDL_VoutIos_CreateForGLES2(void)
{
    SDL_Vout *vout = SDL_Vout_CreateInternal(sizeof(SDL_Vout_Opaque));
    if (!vout)
        return NULL;

    SDL_Vout_Opaque *opaque = vout->opaque;
    opaque->cv_format = -1;
    vout->create_overlay = vout_create_overlay;
    vout->free_l = vout_free_l;
    vout->display_overlay = vout_display_overlay;
    vout->update_subtitle = vout_update_subtitle;
    return vout;
}

static void SDL_VoutIos_SetGLView_l(SDL_Vout *vout, UIView<IJKVideoRenderingProtocol>* view)
{
    SDL_Vout_Opaque *opaque = vout->opaque;
    if (opaque->gl_view != view) {
        opaque->gl_view = view;
    }
}

void SDL_VoutIos_SetGLView(SDL_Vout *vout, UIView<IJKVideoRenderingProtocol>* view)
{
    SDL_LockMutex(vout->mutex);
    SDL_VoutIos_SetGLView_l(vout, view);
    SDL_UnlockMutex(vout->mutex);
}

typedef struct SDL_GPU_Opaque {
    id<MTLDevice>device;
    id<MTLCommandQueue>commandQueue;
    NSOpenGLContext *glContext;
} SDL_GPU_Opaque;

typedef struct SDL_TextureOverlay_Opaque {
    id<MTLTexture>texture_metal;
    _IJKSDLSubTexture* texture_gl;
    NSOpenGLContext *glContext;
} SDL_TextureOverlay_Opaque;

typedef struct SDL_FBOOverlay_Opaque {
    SDL_TextureOverlay *texture;
    IJKMetalFBO* fbo;
    id<MTLCommandQueue>commandQueue;
    id<MTLRenderCommandEncoder> renderEncoder;
    id<MTLParallelRenderCommandEncoder> parallelRenderEncoder;
    id<MTLCommandBuffer> commandBuffer;
    IJKMetalSubtitlePipeline*subPipeline;

} SDL_FBOOverlay_Opaque;

static void* getTexture(SDL_TextureOverlay_Opaque *opaque);

#pragma mark - Texture Metal

static void replaceMetalRegion(SDL_TextureOverlay_Opaque *opaque, SDL_Rectangle rect, void *pixels)
{
    if (opaque && opaque->texture_metal) {
        
        if (rect.x + rect.w > opaque->texture_metal.width) {
            rect.x = 0;
            rect.w = (int)opaque->texture_metal.width;
        }
        
        if (rect.y + rect.h > opaque->texture_metal.height) {
            rect.y = 0;
            rect.h = (int)opaque->texture_metal.height;
        }
        
        int bpr = rect.stride;
        MTLRegion region = {
            {rect.x, rect.y, 0}, // MTLOrigin
            {rect.w, rect.h, 1} // MTLSize
        };
        
        [opaque->texture_metal replaceRegion:region
                                 mipmapLevel:0
                                   withBytes:pixels
                                 bytesPerRow:bpr];
    }
}

static void clearMetalRegion(SDL_TextureOverlay *overlay)
{
    if (!overlay) {
        return;
    }
    SDL_TextureOverlay_Opaque *opaque = overlay->opaque;
    if (isZeroRectangle(overlay->dirtyRect)) {
        return;
    }
    void *pixels = av_mallocz(overlay->dirtyRect.w * overlay->dirtyRect.h * 4);
    replaceMetalRegion(opaque, overlay->dirtyRect, pixels);
    av_free(pixels);
}

static SDL_TextureOverlay *createMetalTexture(id<MTLDevice>device, int w, int h, SDL_TEXTURE_FMT fmt)
{
    SDL_TextureOverlay *texture = (SDL_TextureOverlay*) calloc(1, sizeof(SDL_TextureOverlay));
    if (!texture)
        return NULL;
    
    SDL_TextureOverlay_Opaque *opaque = (SDL_TextureOverlay_Opaque*) calloc(1, sizeof(SDL_TextureOverlay_Opaque));
    if (!opaque) {
        free(texture);
        return NULL;
    }
    
    MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];

    // Indicate that each pixel has a blue, green, red, and alpha channel, where each channel is
    // an 8-bit unsigned normalized value (i.e. 0 maps to 0.0 and 255 maps to 1.0)
    textureDescriptor.pixelFormat = fmt == SDL_TEXTURE_FMT_A8 ? MTLPixelFormatA8Unorm : MTLPixelFormatBGRA8Unorm;
    
    // Set the pixel dimensions of the texture
    
    textureDescriptor.width  = w;
    textureDescriptor.height = h;
    
    // Create the texture from the device by using the descriptor
    id<MTLTexture> subTexture = [device newTextureWithDescriptor:textureDescriptor];
    
    opaque->texture_metal = subTexture;
    texture->opaque = opaque;
    texture->w = w;
    texture->h = h;
    texture->replaceRegion = replaceMetalRegion;
    texture->getTexture = getTexture;
    texture->clearDirtyRect = clearMetalRegion;
    texture->refCount = 1;
    return texture;
}

#pragma mark - Texture OpenGL

static void replaceOpenGlRegion(SDL_TextureOverlay_Opaque *opaque, SDL_Rectangle r, void *pixels)
{
    if (opaque && opaque->texture_gl) {
        _IJKSDLSubTexture *t = opaque->texture_gl;
        CGLLockContext([opaque->glContext CGLContextObj]);
        [opaque->glContext makeCurrentContext];
        glBindTexture(GL_TEXTURE_RECTANGLE, t.texture);
        IJK_GLES2_checkError("bind texture subtitle");
        
        if (r.x + r.w > t.w) {
            r.x = 0;
            r.w = t.w;
        }
        
        if (r.y + r.h > t.h) {
            r.y = 0;
            r.h = t.h;
        }
        
        glTexSubImage2D(GL_TEXTURE_RECTANGLE, 0, r.x, r.y, (GLsizei)r.w, (GLsizei)r.h, GL_RGBA, GL_UNSIGNED_BYTE, (const GLvoid *)pixels);
        IJK_GLES2_checkError("replaceOpenGlRegion");
        glBindTexture(GL_TEXTURE_RECTANGLE, 0);
        CGLUnlockContext([opaque->glContext CGLContextObj]);
    }
}

static void clearOpenGLRegion(SDL_TextureOverlay *overlay)
{
    if (!overlay) {
        return;
    }
    SDL_TextureOverlay_Opaque *opaque = overlay->opaque;
    if (opaque && opaque->texture_gl) {
        if (isZeroRectangle(overlay->dirtyRect)) {
            return;
        }
        int h = overlay->dirtyRect.h;
        int bpr = overlay->dirtyRect.w * 4;
        void *pixels = av_mallocz(h * bpr);
        //memset(pixels, 100, h*bpr);
        replaceOpenGlRegion(opaque, overlay->dirtyRect, pixels);
        av_free(pixels);
    }
}

static SDL_TextureOverlay *createOpenGLTexture(NSOpenGLContext *context, int w, int h, SDL_TEXTURE_FMT fmt)
{
    SDL_TextureOverlay *overlay = (SDL_TextureOverlay*) calloc(1, sizeof(SDL_TextureOverlay));
    if (!overlay)
        return NULL;
    
    SDL_TextureOverlay_Opaque *opaque = (SDL_TextureOverlay_Opaque*) calloc(1, sizeof(SDL_TextureOverlay_Opaque));
    if (!opaque) {
        free(overlay);
        return NULL;
    }

    CGLLockContext([context CGLContextObj]);
    [context makeCurrentContext];
    uint32_t texture;
    // Create a texture object that you apply to the model.
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_RECTANGLE, texture);
    glTexImage2D(GL_TEXTURE_RECTANGLE, 0, GL_RGBA, w, h, 0, GL_BGRA, GL_UNSIGNED_BYTE, NULL);
    
    glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
   
    glBindTexture(GL_TEXTURE_RECTANGLE, 0);
    CGLUnlockContext([context CGLContextObj]);
    opaque->glContext = context;
    opaque->texture_gl = [[_IJKSDLSubTexture alloc] initWith:texture w:w h:h];;
    overlay->opaque = opaque;
    overlay->w = w;
    overlay->h = h;
    overlay->replaceRegion = replaceOpenGlRegion;
    overlay->getTexture = getTexture;
    overlay->clearDirtyRect = clearOpenGLRegion;
    overlay->refCount = 1;
    return overlay;
}

#pragma mark - Texture

SDL_TextureOverlay * SDL_TextureOverlay_Retain(SDL_TextureOverlay *t)
{
    if (t) {
        __atomic_add_fetch(&t->refCount, 1, __ATOMIC_RELEASE);
    }
    return t;
}

void SDL_TextureOverlay_Release(SDL_TextureOverlay **tp)
{
    if (tp) {
        if (*tp) {
            if (__atomic_add_fetch(&(*tp)->refCount, -1, __ATOMIC_RELEASE) == 0) {
                (*tp)->opaque->texture_gl = NULL;
                (*tp)->opaque->glContext = NULL;
                (*tp)->opaque->texture_metal = NULL;
                free((*tp)->opaque);
                free(*tp);
            }
        }
        *tp = NULL;
    }
}

static void* getTexture(SDL_TextureOverlay_Opaque *opaque)
{
    if (opaque) {
        if (opaque->texture_gl) {
            return (__bridge void *)opaque->texture_gl;
        } else if (opaque->texture_metal) {
            return (__bridge void *)opaque->texture_metal;
        }
    }
    return NULL;
}

static SDL_TextureOverlay *createTexture(SDL_GPU_Opaque *opaque, int w, int h, SDL_TEXTURE_FMT fmt)
{
    if (opaque->device) {
        return createMetalTexture(opaque->device, w, h, fmt);
    } else {
        return createOpenGLTexture(opaque->glContext, w, h, fmt);
    }
}

#pragma mark - FBO Metal

static SDL_FBOOverlay *createMetalFBO(id<MTLDevice> device, int w, int h)
{
    SDL_FBOOverlay *overlay = (SDL_FBOOverlay*) calloc(1, sizeof(SDL_FBOOverlay));
    if (!overlay)
        return NULL;
    
    SDL_FBOOverlay_Opaque *opaque = (SDL_FBOOverlay_Opaque*) calloc(1, sizeof(SDL_FBOOverlay_Opaque));
    if (!opaque) {
        free(overlay);
        return NULL;
    }
    
    CGSize size = CGSizeMake(w, h);
    if (opaque->fbo) {
        if (![opaque->fbo canReuse:size]) {
            opaque->fbo = nil;
        }
    }
    if (!opaque->fbo) {
        opaque->fbo = [[IJKMetalFBO alloc] init:device size:size];
    }
    opaque->commandQueue = [device newCommandQueue];
    overlay->opaque = opaque;
    return overlay;
}

#pragma mark - FBO OpenGl

static SDL_FBOOverlay *createOpenGLFBO(NSOpenGLContext *glContext, int w, int h)
{
    return NULL;
}

static void beginOpenGLDraw(SDL_GPU_Opaque *opaque, SDL_FBOOverlay *overlay, int ass)
{
}

static void openglDraw(NSOpenGLContext *glContext, SDL_FBOOverlay *foverlay, SDL_TextureOverlay *toverlay)
{
    if (!glContext || !foverlay || !toverlay) {
        return;
    }
}

static void endOpenGLDraw(SDL_GPU_Opaque *opaque, SDL_FBOOverlay *overlay)
{
    if (!opaque || !overlay) {
        return;
    }
}

#pragma mark - FBO

static CGRect subRect(SDL_Rectangle frame, float scale, CGSize viewport)
{
//    scale = 1.0;
    float swidth  = frame.w * scale;
    float sheight = frame.h * scale;
    
    float width  = viewport.width;
    float height = viewport.height;
    
    //转化到 [-1,1] 的区间
    float sx = frame.x - (scale - 1.0) * frame.w * 0.5;
    float sy = frame.y - (scale - 1.0) * frame.h * 0.5;
    
    float x = sx / width * 2.0 - 1.0;
    float y = 1.0 * (height - sy - sheight) / height * 2.0 - 1.0;
    
    float maxY = (height - sheight) / height;
    if (y < -1) {
        y = -1;
    } else if (y > maxY) {
        y = maxY;
    }
    
    if (width != 0 && height != 0) {
        return (CGRect){
            x,
            y,
            2.0 * (swidth / width),
            2.0 * (sheight / height)
        };
    }
    return CGRectZero;
}

static void beginMetalDraw(SDL_GPU_Opaque *opaque, SDL_FBOOverlay *overlay, int ass)
{
    if (ass) {
        
    } else {
        if (!overlay->opaque->subPipeline) {
            IJKMetalSubtitlePipeline *subPipeline = [[IJKMetalSubtitlePipeline alloc] initWithDevice:opaque->device colorPixelFormat:MTLPixelFormatBGRA8Unorm];
            if ([subPipeline createRenderPipelineIfNeed]) {
                overlay->opaque->subPipeline = subPipeline;
            }
        }
        
        if (overlay->opaque->subPipeline) {
            id<MTLCommandBuffer>commandBuffer = [overlay->opaque->commandQueue commandBuffer];
            overlay->opaque->renderEncoder = [overlay->opaque->fbo createRenderEncoder:commandBuffer];
            overlay->opaque->commandBuffer = commandBuffer;
            
            [overlay->opaque->subPipeline lock];
            // Set the region of the drawable to draw into.
            CGSize viewport = [overlay->opaque->fbo size];
            [overlay->opaque->renderEncoder setViewport:(MTLViewport){0.0, 0.0, viewport.width, viewport.height, -1.0, 1.0}];
        } else {
            return;
        }
    }
}

static void metalDraw(SDL_FBOOverlay *foverlay, SDL_TextureOverlay *toverlay)
{
    if (!foverlay || !toverlay || !foverlay->opaque) {
        return;
    }
   
    CGSize viewport = [foverlay->opaque->fbo size];
    CGRect rect = subRect(toverlay->frame, toverlay->scale, viewport);
    [foverlay->opaque->subPipeline updateSubtitleVertexIfNeed:rect];
    id<MTLTexture>texture = (__bridge id<MTLTexture>)toverlay->getTexture(toverlay->opaque);
    [foverlay->opaque->subPipeline uploadTextureWithEncoder:foverlay->opaque->renderEncoder texture:texture];
}

static void endMetalDraw(SDL_GPU_Opaque *opaque, SDL_FBOOverlay *overlay)
{
    if (!opaque || !overlay) {
        return;
    }
    [overlay->opaque->renderEncoder endEncoding];
    [overlay->opaque->renderEncoder popDebugGroup];
    [overlay->opaque->parallelRenderEncoder endEncoding];
    [overlay->opaque->commandBuffer commit];
    [overlay->opaque->commandBuffer waitUntilCompleted];

    overlay->opaque->renderEncoder = nil;
    overlay->opaque->parallelRenderEncoder = nil;
    overlay->opaque->commandBuffer = nil;
    [overlay->opaque->subPipeline unlock];
}

static void beginDraw_FBO(SDL_GPU_Opaque *opaque, SDL_FBOOverlay *overlay, int ass)
{
    if (!opaque || !overlay) {
        return;
    }
    if (opaque->device) {
        beginMetalDraw(opaque, overlay, ass);
    } else if (opaque->glContext) {
        beginOpenGLDraw(opaque, overlay, ass);
    }
}

static void drawTexture_FBO(SDL_GPU_Opaque *gpu, SDL_FBOOverlay *foverlay, SDL_TextureOverlay *toverlay)
{
    if (!gpu || !foverlay || !toverlay) {
        return;
    }
    if (gpu->glContext) {
        openglDraw(gpu->glContext, foverlay, toverlay);
    } else if (gpu->device){
        metalDraw(foverlay, toverlay);
    }
}

static void endDraw_FBO(SDL_GPU_Opaque *opaque, SDL_FBOOverlay *overlay)
{
    if (!opaque || !overlay) {
        return;
    }
    if (opaque->device) {
        endMetalDraw(opaque, overlay);
    } else if (opaque->glContext) {
        endOpenGLDraw(opaque, overlay);
    } else {
        return;
    }
}

static void clear_FBO(SDL_FBOOverlay *overlay)
{
    
}

static SDL_TextureOverlay * getTexture_FBO(SDL_FBOOverlay *foverlay)
{
    if (foverlay->opaque->texture) {
        return SDL_TextureOverlay_Retain(foverlay->opaque->texture);
    }
    
    SDL_TextureOverlay *texture = (SDL_TextureOverlay*) calloc(1, sizeof(SDL_TextureOverlay));
    if (!texture)
        return NULL;
    
    SDL_TextureOverlay_Opaque *opaque = (SDL_TextureOverlay_Opaque*) calloc(1, sizeof(SDL_TextureOverlay_Opaque));
    if (!opaque) {
        free(texture);
        return NULL;
    }
    
    id<MTLTexture> subTexture = [foverlay->opaque->fbo texture];
    CGSize size = [foverlay->opaque->fbo size];
    
    opaque->texture_metal = subTexture;
    texture->opaque = opaque;
    texture->w = (int)size.width;
    texture->h = (int)size.height;
    texture->replaceRegion = replaceMetalRegion;
    texture->getTexture = getTexture;
    texture->clearDirtyRect = clearMetalRegion;
    texture->refCount = 1;
    foverlay->opaque->texture = texture;
    return texture;
}

void SDL_FBOOverlayFreeP(SDL_FBOOverlay **poverlay)
{
    if (poverlay) {
        if (*poverlay) {
            if ((*poverlay)->opaque) {
                SDL_TextureOverlay_Release(&(*poverlay)->opaque->texture);
                (*poverlay)->opaque->fbo = nil;
                (*poverlay)->opaque->commandQueue = nil;
                (*poverlay)->opaque->renderEncoder = nil;
                (*poverlay)->opaque->commandBuffer = nil;
                (*poverlay)->opaque->subPipeline = nil;
                free((*poverlay)->opaque);
            }
            free(*poverlay);
        }
        *poverlay = NULL;
    }
}

static SDL_FBOOverlay *createFBO(SDL_GPU_Opaque *opaque, int w, int h)
{
    SDL_FBOOverlay *overlay;
    if (opaque->device) {
        overlay = createMetalFBO(opaque->device, w, h);
    } else {
        overlay = createOpenGLFBO(opaque->glContext, w, h);
    }
    
    if (overlay) {
        overlay->w = w;
        overlay->h = h;
        overlay->beginDraw = beginDraw_FBO;
        overlay->drawTexture = drawTexture_FBO;
        overlay->endDraw = endDraw_FBO;
        overlay->clear = clear_FBO;
        overlay->getTexture = getTexture_FBO;
    }
    return overlay;
}

#pragma mark - GPU

SDL_GPU *SDL_CreateGPU_WithContext(id context)
{
    SDL_GPU *gl = (SDL_GPU*) calloc(1, sizeof(SDL_GPU));
    if (!gl)
        return NULL;
    int opaque_size = sizeof(SDL_GPU_Opaque);
    gl->opaque = calloc(1, opaque_size);
    if (!gl->opaque) {
        free(gl);
        return NULL;
    }
    bzero((void *)gl->opaque, opaque_size);
    SDL_GPU_Opaque *opaque = gl->opaque;
    if ([context isKindOfClass:[NSOpenGLContext class]]) {
        opaque->glContext = context;
    } else {
        opaque->device = context;
        opaque->commandQueue = [context newCommandQueue];
    }
    gl->createTexture = createTexture;
    gl->createFBO = createFBO;
    return gl;
}

void SDL_GPUFreeP(SDL_GPU **pgpu)
{
    if (pgpu) {
        (*pgpu)->opaque->glContext = NULL;
        (*pgpu)->opaque->device = NULL;
        (*pgpu)->opaque->commandQueue = NULL;
        free((*pgpu)->opaque);
        free(*pgpu);
        *pgpu = NULL;
    }
}

#pragma mark - save image for debug ass

static CGContextRef _CreateCGBitmapContext(size_t w, size_t h, size_t bpc, size_t bpp, size_t bpr, uint32_t bmi)
{
    assert(bpp != 24);
    /*
     AV_PIX_FMT_RGB24 bpp is 24! not supported!
     Crash:
     2020-06-06 00:08:20.245208+0800 FFmpegTutorial[23649:2335631] [Unknown process name] CGBitmapContextCreate: unsupported parameter combination: set CGBITMAP_CONTEXT_LOG_ERRORS environmental variable to see the details
     2020-06-06 00:08:20.245417+0800 FFmpegTutorial[23649:2335631] [Unknown process name] CGBitmapContextCreateImage: invalid context 0x0. If you want to see the backtrace, please set CG_CONTEXT_SHOW_BACKTRACE environmental variable.
     */
    //Update: Since 10.8, CGColorSpaceCreateDeviceRGB is equivalent to sRGB, and is closer to option 2)
    //CGColorSpaceCreateWithName(kCGColorSpaceSRGB)
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmapContext = CGBitmapContextCreate(
        NULL,
        w,
        h,
        bpc,
        bpr,
        colorSpace,
        bmi
    );
    
    CGColorSpaceRelease(colorSpace);
    return bitmapContext;
}

static NSError * mr_mkdirP(NSString *aDir)
{
    BOOL isDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:aDir isDirectory:&isDirectory]) {
        if (isDirectory) {
            return nil;
        } else {
            //remove the file
            [[NSFileManager defaultManager] removeItemAtPath:aDir error:NULL];
        }
    }
    //aDir is not exist
    NSError *err = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:aDir withIntermediateDirectories:YES attributes:nil error:&err];
    return err;
}

static NSString * mr_DirWithType(NSSearchPathDirectory directory,NSArray<NSString *>*pathArr)
{
    NSString *directoryDir = [NSSearchPathForDirectoriesInDomains(directory, NSUserDomainMask, YES) firstObject];
    NSString *aDir = directoryDir;
    for (NSString *dir in pathArr) {
        aDir = [aDir stringByAppendingPathComponent:dir];
    }
    if (mr_mkdirP(aDir)) {
        return nil;
    }
    return aDir;
}

static BOOL saveImageToFile(CGImageRef img,NSString *imgPath)
{
    CFStringRef imageUTType = NULL;
    NSString *fileType = [[imgPath pathExtension] lowercaseString];
    if ([fileType isEqualToString:@"jpg"] || [fileType isEqualToString:@"jpeg"]) {
        imageUTType = kUTTypeJPEG;
    } else if ([fileType isEqualToString:@"png"]) {
        imageUTType = kUTTypePNG;
    } else if ([fileType isEqualToString:@"tiff"]) {
        imageUTType = kUTTypeTIFF;
    } else if ([fileType isEqualToString:@"bmp"]) {
        imageUTType = kUTTypeBMP;
    } else if ([fileType isEqualToString:@"gif"]) {
        imageUTType = kUTTypeGIF;
    } else if ([fileType isEqualToString:@"pdf"]) {
        imageUTType = kUTTypePDF;
    }
    
    if (imageUTType == NULL) {
        imageUTType = kUTTypePNG;
    }

    CFStringRef key = kCGImageDestinationLossyCompressionQuality;
    CFStringRef value = CFSTR("0.5");
    const void * keys[] = {key};
    const void * values[] = {value};
    CFDictionaryRef opts = CFDictionaryCreate(CFAllocatorGetDefault(), keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    NSURL *fileUrl = [NSURL fileURLWithPath:imgPath];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef) fileUrl, imageUTType, 1, opts);
    CFRelease(opts);
    
    if (destination) {
        CGImageDestinationAddImage(destination, img, NULL);
        CGImageDestinationFinalize(destination);
        CFRelease(destination);
        return YES;
    } else {
        return NO;
    }
}

void SaveIMGToFile(uint8_t *data,int width,int height,IMG_FORMAT format, char *tag, int pts)
{
    const GLint bytesPerRow = width * 4;
    
    uint32_t bmi;
    if (format == IMG_FORMAT_RGBA) {
        bmi = kCGBitmapByteOrderDefault | kCGImageAlphaNoneSkipLast;
    } else {
        bmi = kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;
    }
    CGContextRef ctx = _CreateCGBitmapContext(width, height, 8, 32, bytesPerRow, bmi);
    if (ctx) {
        void * bitmapData = CGBitmapContextGetData(ctx);
        if (bitmapData) {
            memcpy(bitmapData, data, bytesPerRow * height);
            CGImageRef img = CGBitmapContextCreateImage(ctx);
            if (img) {
                NSString *dir = mr_DirWithType(NSPicturesDirectory, @[@"ijkplayer"]);
                if (!tag) {
                    tag = "";
                }
                if (pts == -1) {
                    pts = (int)CFAbsoluteTimeGetCurrent();
                }
                NSString *fileName = [NSString stringWithFormat:@"%s-%d.png",tag,pts];
                NSString *filePath = [dir stringByAppendingPathComponent:fileName];
                NSLog(@"save img:%@",filePath);
                saveImageToFile(img, filePath);
                CFRelease(img);
            }
        }
        CGContextRelease(ctx);
    }
}

