/*
 * IJKSDLGLViewProtocol.h
 *
 * Copyright (c) 2017 Bilibili
 * Copyright (c) 2017 raymond <raymondzheng1412@gmail.com>
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

#ifndef IJKSDLGLViewProtocol_h
#define IJKSDLGLViewProtocol_h
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#import <CoreGraphics/CGImage.h>
typedef NSFont UIFont;
typedef NSColor UIColor;
#else
#import <UIKit/UIKit.h>
#endif

typedef NS_ENUM(NSInteger, IJKMPMovieScalingMode) {
    IJKMPMovieScalingModeAspectFit,  // Uniform scale until one dimension fits
    IJKMPMovieScalingModeAspectFill, // Uniform scale until the movie fills the visible bounds. One dimension may have clipped contents
    IJKMPMovieScalingModeFill        // Non-uniform scale. Both render dimensions will exactly match the visible bounds
};

typedef struct IJKOverlay IJKOverlay;
struct IJKOverlay {
    int w;
    int h;
    UInt32 format;
    int planes;
    UInt16 *pitches;
    UInt8 **pixels;
    int sar_num;
    int sar_den;
    CVPixelBufferRef pixel_buffer;
};

typedef struct _IJKSDLSubtitlePreference IJKSDLSubtitlePreference;
struct _IJKSDLSubtitlePreference {
    int fontSize;
    int32_t color;
    float bottomMargin;//[0.0,1.0]
};

typedef enum _IJKSDLRotateType {
    IJKSDLRotateNone,
    IJKSDLRotateX,
    IJKSDLRotateY,
    IJKSDLRotateZ
} IJKSDLRotateType;


typedef struct _IJKSDLRotatePreference IJKSDLRotatePreference;
struct _IJKSDLRotatePreference {
    IJKSDLRotateType type;
    float degrees;
};

typedef struct _IJKSDLColorConversionPreference IJKSDLColorConversionPreference;
struct _IJKSDLColorConversionPreference {
    float brightness;
    float saturation;
    float contrast;
};

typedef struct _IJKSDLDARPreference IJKSDLDARPreference;
struct _IJKSDLDARPreference {
    int num; //width
    int den; //height
};

@protocol IJKSDLGLViewProtocol <NSObject>

@property(nonatomic) IJKMPMovieScalingMode scalingMode;
@property(nonatomic, readonly) CGFloat  fps;
@property(nonatomic) CGFloat  scaleFactor;
@property(nonatomic) BOOL  isThirdGLView;
// subtitle preference
@property(nonatomic) IJKSDLSubtitlePreference subtitlePreference;
// rotate preference
@property(nonatomic) IJKSDLRotatePreference rotatePreference;
// color conversion perference
@property(nonatomic) IJKSDLColorConversionPreference colorPreference;
//user defined display aspect ratio
@property(nonatomic) IJKSDLDARPreference darPreference;
@property(atomic)    BOOL darWillChange;

- (void)onDARChange:(int)dar_num den:(int)dar_den;

#if !TARGET_OS_OSX
- (void)display_pixels:(IJKOverlay *)overlay;
- (UIImage *)snapshot;
#else
- (CGImageRef)snapshot;
- (CGImageRef)snapshot2;
#endif

@optional;
- (void)display_pixels:(IJKOverlay *)overlay;

@end

#endif /* IJKSDLGLViewProtocol_h */
