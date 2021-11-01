/*
 * IJKSDLGLView.h
 *
 * Copyright (c) 2013 Bilibili
 * Copyright (c) 2013 Zhang Rui <bbcallen@gmail.com>
 *
 * based on https://github.com/kolyvan/kxmovie
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

#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
typedef NSOpenGLView GLView;
typedef NSImage UIImage;
#else
#import <UIKit/UIKit.h>
typedef UIView GLView;
#endif
#import <CoreVideo/CVPixelBuffer.h>
#import "IJKSDLGLViewProtocol.h"
#include "ijksdl/ijksdl_vout.h"

@interface IJKSDLGLView : GLView <IJKSDLGLViewProtocol>

@property(nonatomic) IJKMPMovieScalingMode scalingMode;

- (id)initWithFrame:(CGRect)frame;
- (void)display:(SDL_VoutOverlay *)overlay subtitle:(CVPixelBufferRef)subtitle;
// subtitle preference
@property(nonatomic) IJKSDLSubtitlePreference subtitlePreference;

#if !TARGET_OS_OSX
- (UIImage*)snapshot;
- (void)setShouldLockWhileBeingMovedToWindow:(BOOL)shouldLockWhiteBeingMovedToWindow __attribute__((deprecated("unused")));
#endif

@end
