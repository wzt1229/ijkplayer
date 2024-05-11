//
//  ijksdl_gpu_metal.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/4/14.
//

#import <Foundation/Foundation.h>

@protocol MTLDevice;
typedef struct SDL_GPU SDL_GPU;

SDL_GPU *SDL_CreateGPU_WithMTLDevice(id<MTLDevice>device);
