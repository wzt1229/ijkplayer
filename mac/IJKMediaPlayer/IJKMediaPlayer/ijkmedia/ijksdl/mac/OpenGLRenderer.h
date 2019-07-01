 /*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 The OpenGLRenderer class creates and draws objects.
  Most of the code is OS independent.
 */
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#include "ijksdl/ijksdl_vout.h"

@interface OpenGLRenderer : NSObject

- (void) resizeWithWidth:(GLuint)width AndHeight:(GLuint)height;
- (void) render;
- (void) setImage:(SDL_VoutOverlay*)overlay;

@end
