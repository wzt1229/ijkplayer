//
//  ijksdl_texture.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/3/26.
//

#ifndef ijksdl_texture_h
#define ijksdl_texture_h

#include "ijksdl_rectangle.h"

typedef struct SDL_GPU_Opaque SDL_GPU_Opaque;
typedef struct SDL_TextureOverlay_Opaque SDL_TextureOverlay_Opaque;
typedef struct SDL_TextureOverlay SDL_TextureOverlay;
typedef struct SDL_TextureOverlay {
    SDL_TextureOverlay_Opaque *opaque;
    int w;
    int h;
    SDL_Rectangle frame;
    float scale;
    SDL_Rectangle dirtyRect;
    int changed;
    int refCount;
    void (*replaceRegion)(SDL_TextureOverlay_Opaque *opaque, SDL_Rectangle r, void *pixels);
    void*(*getTexture)(SDL_TextureOverlay_Opaque *opaque);
    void (*clearDirtyRect)(SDL_TextureOverlay *overlay);
} SDL_TextureOverlay;

SDL_TextureOverlay * SDL_TextureOverlay_Retain(SDL_TextureOverlay *t);
void SDL_TextureOverlay_Release(SDL_TextureOverlay **tp);

typedef struct SDL_FBOOverlay_Opaque SDL_FBOOverlay_Opaque;
typedef struct SDL_FBOOverlay SDL_FBOOverlay;
typedef struct SDL_FBOOverlay {
    SDL_FBOOverlay_Opaque *opaque;
    int w;
    int h;
    void (*clear)(SDL_FBOOverlay *overlay);
    void (*beginDraw)(SDL_GPU_Opaque *opaque, SDL_FBOOverlay *overlay, int ass);
    void (*drawTexture)(SDL_GPU_Opaque *gpu, SDL_FBOOverlay *foverlay, SDL_TextureOverlay *toverlay);
    void (*endDraw)(SDL_GPU_Opaque *opaque, SDL_FBOOverlay *overlay);
    SDL_TextureOverlay *(*getTexture)(SDL_FBOOverlay *overlay);
} SDL_FBOOverlay;

void SDL_FBOOverlayFreeP(SDL_FBOOverlay **poverlay);

typedef enum : int {
    SDL_TEXTURE_FMT_BRGA,
    SDL_TEXTURE_FMT_A8
} SDL_TEXTURE_FMT;

typedef struct SDL_GPU {
    SDL_GPU_Opaque *opaque;
    SDL_TextureOverlay *(*createTexture)(SDL_GPU_Opaque *opaque, int w, int h, SDL_TEXTURE_FMT fmt);
    SDL_FBOOverlay *(*createFBO)(SDL_GPU_Opaque *opaque, int w, int h);
} SDL_GPU;

void SDL_GPUFreeP(SDL_GPU **pgpu);

typedef enum : int {
    IMG_FORMAT_RGBA,
    IMG_FORMAT_BGRA,
} IMG_FORMAT;

void SaveIMGToFile(uint8_t *data,int width,int height,IMG_FORMAT format, char *tag, int pts);


#endif /* ijksdl_texture_h */
