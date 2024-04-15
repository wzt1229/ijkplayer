//
//  ijksdl_gpu_metal.m
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/4/14.
//

#import "ijksdl_gpu_metal.h"
#import <MetalKit/MetalKit.h>
#import "IJKMetalFBO.h"
#import "IJKMetalSubtitlePipeline.h"
#import "ijksdl_gpu.h"
#include <libavutil/mem.h>

typedef struct SDL_GPU_Opaque_Metal {
    id<MTLDevice>device;
    id<MTLCommandQueue>commandQueue;
} SDL_GPU_Opaque_Metal;

typedef struct SDL_TextureOverlay_Opaque_Metal {
    id<MTLTexture>texture;
} SDL_TextureOverlay_Opaque_Metal;

typedef struct SDL_FBOOverlay_Opaque_Metal {
    SDL_TextureOverlay *texture;
    IJKMetalFBO* fbo;
    id<MTLCommandQueue>commandQueue;
    id<MTLRenderCommandEncoder> renderEncoder;
    id<MTLParallelRenderCommandEncoder> parallelRenderEncoder;
    id<MTLCommandBuffer> commandBuffer;
    IJKMetalSubtitlePipeline*subPipeline;
} SDL_FBOOverlay_Opaque_Metal;

static void* getTexture(SDL_TextureOverlay *overlay);

#pragma mark - Texture Metal

static void replaceRegion(SDL_TextureOverlay *overlay, SDL_Rectangle rect, void *pixels)
{
    if (overlay && overlay->opaque) {
        SDL_TextureOverlay_Opaque_Metal *op = overlay->opaque;
        if (op->texture) {
            if (rect.x + rect.w > op->texture.width) {
                rect.x = 0;
                rect.w = (int)op->texture.width;
            }
            
            if (rect.y + rect.h > op->texture.height) {
                rect.y = 0;
                rect.h = (int)op->texture.height;
            }
            
            int bpr = rect.stride;
            MTLRegion region = {
                {rect.x, rect.y, 0}, // MTLOrigin
                {rect.w, rect.h, 1} // MTLSize
            };
            
            [op->texture replaceRegion:region
                           mipmapLevel:0
                             withBytes:pixels
                           bytesPerRow:bpr];
        }
    }
}

static void clearMetalRegion(SDL_TextureOverlay *overlay)
{
    if (!overlay) {
        return;
    }
    
    if (isZeroRectangle(overlay->dirtyRect)) {
        return;
    }
    void *pixels = av_mallocz(overlay->dirtyRect.stride * overlay->dirtyRect.h);
    replaceRegion(overlay, overlay->dirtyRect, pixels);
    av_free(pixels);
}

static void dealloc_texture(SDL_TextureOverlay *overlay)
{
    if (overlay) {
        SDL_TextureOverlay_Opaque_Metal *opaque = overlay->opaque;
        if (opaque) {
            opaque->texture = NULL;
            free(opaque);
        }
        overlay->opaque = NULL;
    }
}

static SDL_TextureOverlay *createMetalTexture(id<MTLDevice>device, int w, int h, SDL_TEXTURE_FMT fmt)
{
    SDL_TextureOverlay *texture = (SDL_TextureOverlay*) calloc(1, sizeof(SDL_TextureOverlay));
    if (!texture)
        return NULL;
    
    SDL_TextureOverlay_Opaque_Metal *opaque = (SDL_TextureOverlay_Opaque_Metal*) calloc(1, sizeof(SDL_TextureOverlay_Opaque_Metal));
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
    
    opaque->texture = subTexture;
    texture->opaque = opaque;
    texture->w = w;
    texture->h = h;
    texture->replaceRegion = replaceRegion;
    texture->getTexture = getTexture;
    texture->clearDirtyRect = clearMetalRegion;
    texture->dealloc = dealloc_texture;
    texture->refCount = 1;
    return texture;
}

#pragma mark - Texture

static void* getTexture(SDL_TextureOverlay *overlay)
{
    if (overlay && overlay->opaque) {
        SDL_TextureOverlay_Opaque_Metal *opaque = overlay->opaque;
        return (__bridge void *)opaque->texture;
    }
    return NULL;
}

static SDL_TextureOverlay *createTexture(SDL_GPU *gpu, int w, int h, SDL_TEXTURE_FMT fmt)
{
    if (!gpu && ! gpu->opaque) {
        return NULL;
    }
    
    SDL_GPU_Opaque_Metal *gop = gpu->opaque;
    return createMetalTexture(gop->device, w, h, fmt);
}

#pragma mark - FBO Metal

static SDL_FBOOverlay *createMetalFBO(id<MTLDevice> device, int w, int h)
{
    if (!device) {
        return NULL;
    }
    
    SDL_FBOOverlay *overlay = (SDL_FBOOverlay*) calloc(1, sizeof(SDL_FBOOverlay));
    if (!overlay)
        return NULL;
    
    SDL_FBOOverlay_Opaque_Metal *opaque = (SDL_FBOOverlay_Opaque_Metal*) calloc(1, sizeof(SDL_FBOOverlay_Opaque_Metal));
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
    overlay->opaque = (void *)opaque;
    return overlay;
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

static void beginMetalDraw_fbo(SDL_GPU *gpu, SDL_FBOOverlay *overlay, int ass)
{
    if (!gpu || !gpu->opaque || !overlay || !overlay->opaque) {
        return;
    }
    
    SDL_FBOOverlay_Opaque_Metal *fop = overlay->opaque;
    SDL_GPU_Opaque_Metal *gop = gpu->opaque;
    if (ass) {
        
    } else {
        if (!fop->subPipeline) {
            IJKMetalSubtitlePipeline *subPipeline = [[IJKMetalSubtitlePipeline alloc] initWithDevice:gop->device outFormat:IJKMetalSubtitleOutFormatDIRECT];
            if ([subPipeline createRenderPipelineIfNeed]) {
                fop->subPipeline = subPipeline;
            }
        }
        
        if (fop->subPipeline) {
            id<MTLCommandBuffer>commandBuffer = [fop->commandQueue commandBuffer];
            fop->renderEncoder = [fop->fbo createRenderEncoder:commandBuffer];
            fop->commandBuffer = commandBuffer;
            
            [fop->subPipeline lock];
            // Set the region of the drawable to draw into.
            CGSize viewport = [fop->fbo size];
            [fop->renderEncoder setViewport:(MTLViewport){0.0, 0.0, viewport.width, viewport.height, -1.0, 1.0}];
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
    SDL_FBOOverlay_Opaque_Metal *fop = foverlay->opaque;
    CGSize viewport = [fop->fbo size];
    CGRect rect = subRect(toverlay->frame, toverlay->scale, viewport);
    [fop->subPipeline updateSubtitleVertexIfNeed:rect];
    id<MTLTexture>texture = (__bridge id<MTLTexture>)toverlay->getTexture(toverlay);
    [fop->subPipeline uploadTextureWithEncoder:fop->renderEncoder texture:texture];
}

static void drawTexture_fbo(SDL_GPU *gpu, SDL_FBOOverlay *foverlay, SDL_TextureOverlay *toverlay)
{
    if (!foverlay || !toverlay) {
        return;
    }
    metalDraw(foverlay, toverlay);
}

static void endDraw_fbo(SDL_GPU *gpu, SDL_FBOOverlay *overlay)
{
    if (!overlay || !overlay->opaque) {
        return;
    }
    
    SDL_FBOOverlay_Opaque_Metal *fop = overlay->opaque;
    
    [fop->renderEncoder endEncoding];
    [fop->renderEncoder popDebugGroup];
    [fop->parallelRenderEncoder endEncoding];
    [fop->commandBuffer commit];
    [fop->commandBuffer waitUntilCompleted];

    fop->renderEncoder = nil;
    fop->parallelRenderEncoder = nil;
    fop->commandBuffer = nil;
    [fop->subPipeline unlock];
}

static void clear_fbo(SDL_FBOOverlay *overlay)
{
    
}

static void dealloc_fbo(SDL_FBOOverlay *overlay)
{
    if (!overlay || !overlay->opaque) {
        return;
    }
    
    SDL_FBOOverlay_Opaque_Metal *fop = overlay->opaque;
    
    SDL_TextureOverlay_Release(&fop->texture);
    fop->fbo = nil;
    fop->commandQueue = nil;
    fop->renderEncoder = nil;
    fop->commandBuffer = nil;
    fop->subPipeline = nil;
    free(fop);
}

static SDL_TextureOverlay * getTexture_fbo(SDL_FBOOverlay *foverlay)
{
    if (!foverlay || !foverlay->opaque) {
        return NULL;
    }
    
    SDL_FBOOverlay_Opaque_Metal *fop = foverlay->opaque;
    if (fop->texture) {
        return SDL_TextureOverlay_Retain(fop->texture);
    }
    
    SDL_TextureOverlay *texture = (SDL_TextureOverlay*) calloc(1, sizeof(SDL_TextureOverlay));
    if (!texture)
        return NULL;
    
    SDL_TextureOverlay_Opaque_Metal *opaque = (SDL_TextureOverlay_Opaque_Metal*) calloc(1, sizeof(SDL_TextureOverlay_Opaque_Metal));
    if (!opaque) {
        free(texture);
        return NULL;
    }
    
    id<MTLTexture> subTexture = [fop->fbo texture];
    CGSize size = [fop->fbo size];
    
    opaque->texture = subTexture;
    texture->opaque = opaque;
    texture->w = (int)size.width;
    texture->h = (int)size.height;
    texture->replaceRegion = replaceRegion;
    texture->getTexture = getTexture;
    texture->clearDirtyRect = clearMetalRegion;
    texture->refCount = 1;
    texture->dealloc = dealloc_texture;
    fop->texture = texture;
    return texture;
}

static SDL_FBOOverlay *createFBO(SDL_GPU *gpu, int w, int h)
{
    if (!gpu || !gpu->opaque) {
        return NULL;
    }
    
    SDL_GPU_Opaque_Metal *gop = gpu->opaque;
    SDL_FBOOverlay *overlay = createMetalFBO(gop->device, w, h);
    
    if (overlay) {
        overlay->w = w;
        overlay->h = h;
        overlay->beginDraw = beginMetalDraw_fbo;
        overlay->drawTexture = drawTexture_fbo;
        overlay->endDraw = endDraw_fbo;
        overlay->clear = clear_fbo;
        overlay->getTexture = getTexture_fbo;
        overlay->dealloc = dealloc_fbo;
    }
    return overlay;
}

#pragma mark - GPU

static void dealloc_gpu(SDL_GPU *gpu)
{
    if (!gpu || !gpu->opaque) {
        return;
    }
    
    SDL_GPU_Opaque_Metal *gop = gpu->opaque;
    gop->device = NULL;
    gop->commandQueue = NULL;
    free(gop);
}

SDL_GPU *SDL_CreateGPU_WithMTLDevice(id<MTLDevice>device)
{
    if (!device) {
        return NULL;
    }
    SDL_GPU *gl = (SDL_GPU*) calloc(1, sizeof(SDL_GPU));
    if (!gl)
        return NULL;
    
    SDL_GPU_Opaque_Metal *opaque = av_mallocz(sizeof(SDL_GPU_Opaque_Metal));
    if (!opaque) {
        free(gl);
        return NULL;
    }
    opaque->device = device;
    gl->opaque = opaque;
    gl->createTexture = createTexture;
    gl->createFBO = createFBO;
    gl->dealloc = dealloc_gpu;
    
    return gl;
}
