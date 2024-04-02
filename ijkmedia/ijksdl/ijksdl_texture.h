//
//  ijksdl_texture.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/3/26.
//

#ifndef ijksdl_texture_h
#define ijksdl_texture_h

#include "ijksdl_rectangle.h"

typedef struct SDL_TextureOverlay_Opaque SDL_TextureOverlay_Opaque;
typedef struct SDL_TextureOverlay SDL_TextureOverlay;
typedef struct SDL_TextureOverlay {
    SDL_TextureOverlay_Opaque *opaque;
    int w;
    int h;
    SDL_Rectangle dirtyRect;
    int changed;
    void(*replaceRegion)(SDL_TextureOverlay_Opaque *opaque, SDL_Rectangle r, void *pixels);
    void*(*getTexture)(SDL_TextureOverlay_Opaque *opaque);
    void (*clearDirtyRect)(SDL_TextureOverlay *overlay);
} SDL_TextureOverlay;

void SDL_TextureOverlayFreeP(SDL_TextureOverlay **poverlay);

typedef struct SDL_GPU_Opaque SDL_GPU_Opaque;
typedef struct SDL_GPU {
    SDL_GPU_Opaque *opaque;
    SDL_TextureOverlay *(*createTexture)(SDL_GPU_Opaque *opaque, int w, int h);
} SDL_GPU;

void SDL_GPUFreeP(SDL_GPU **pgpu);

#endif /* ijksdl_texture_h */
