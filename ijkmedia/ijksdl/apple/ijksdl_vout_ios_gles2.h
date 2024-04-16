/*
 * ijksdl_vout_ios_gles2.h
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

#include "ijksdl/ijksdl_stdinc.h"
#include "ijksdl/ijksdl_vout.h"
#include "../ijksdl_gpu.h"

#import "IJKVideoRenderingProtocol.h"

@protocol IJKSDLSubtitleTextureWrapper <NSObject>

@property(nonatomic) uint32_t texture;
@property(nonatomic) int w;
@property(nonatomic) int h;

@end

id<IJKSDLSubtitleTextureWrapper> IJKSDL_crate_openglTextureWrapper(uint32_t texture, int w, int h);

// Normalized Device Coordinates
static inline CGRect IJKSDL_make_NDC(SDL_Rectangle frame, float scale, CGSize viewport)
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

SDL_Vout *SDL_VoutIos_CreateForGLES2(void);
void SDL_VoutIos_SetGLView(SDL_Vout *vout, UIView<IJKVideoRenderingProtocol>* view);
SDL_GPU *SDL_CreateGPU_WithContext(id context);

