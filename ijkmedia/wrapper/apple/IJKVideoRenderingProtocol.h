/*
 * IJKVideoRenderingProtocol.h
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

#ifndef IJKVideoRenderingProtocol_h
#define IJKVideoRenderingProtocol_h
#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#import <CoreGraphics/CGImage.h>
typedef NSFont UIFont;
typedef NSColor UIColor;
typedef NSImage UIImage;
typedef NSView UIView;
#else
#import <UIKit/UIKit.h>
#endif
#import "ff_subtitle_def.h"

typedef NS_ENUM(NSInteger, IJKMPMovieScalingMode) {
    IJKMPMovieScalingModeAspectFit,  // Uniform scale until one dimension fits
    IJKMPMovieScalingModeAspectFill, // Uniform scale until the movie fills the visible bounds. One dimension may have clipped contents
    IJKMPMovieScalingModeFill        // Non-uniform scale. Both render dimensions will exactly match the visible bounds
};

typedef struct SDL_TextureOverlay SDL_TextureOverlay;
@interface IJKOverlayAttach : NSObject

//video frame normal size not alignmetn,maybe not equal to currentVideoPic's size.
@property(nonatomic) int w;
@property(nonatomic) int h;
//cvpixebuffer pixel memory size;
@property(nonatomic) int pixelW;
@property(nonatomic) int pixelH;

@property(nonatomic) int planes;
@property(nonatomic) UInt16 *pitches;
@property(nonatomic) UInt8 **pixels;
@property(nonatomic) int sarNum;
@property(nonatomic) int sarDen;
//degrees
@property(nonatomic) int autoZRotate;
@property(nonatomic) CVPixelBufferRef videoPicture;
@property(nonatomic) NSArray *videoTextures;

@property(nonatomic) SDL_TextureOverlay *overlay;
@property(nonatomic) id subTexture;

@end

static inline uint32_t color2int(UIColor *color) {
#if TARGET_OS_OSX
    if (@available(macOS 10.13, *)) {
        if (color.type != NSColorSpaceModelRGB) {
            
        }
    }
    if (![color.colorSpaceName isEqualToString:NSDeviceRGBColorSpace] && ![color.colorSpaceName isEqualToString:NSCalibratedRGBColorSpace]) {
        color = [color colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    }
#endif
    CGFloat r,g,b,a;
    [color getRed:&r green:&g blue:&b alpha:&a];
    
    r *= 255;
    g *= 255;
    b *= 255;
    a *= 255;
    return (uint32_t)a + ((uint32_t)b << 8) + ((uint32_t)g << 16) + ((uint32_t)r << 24);
}

static inline UIColor * int2color(uint32_t abgr) {
    CGFloat r,g,b,a;
    a = ((float)(abgr & 0xFF)) / 255.0;
    b = ((float)((abgr & 0xFF00) >> 8)) / 255.0;
    g = (float)(((abgr & 0xFF0000) >> 16)) / 255.0;
    r = ((float)((abgr & 0xFF000000) >> 24)) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

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
    float ratio; //ratio is width / height;
};

typedef enum : NSUInteger {
    IJKSDLSnapshot_Origin, //keep original video size,without subtitle and video effect
    IJKSDLSnapshot_Screen, //current glview's picture as you see
    IJKSDLSnapshot_Effect_Origin,//keep original video size,with subtitle,without video effect
    IJKSDLSnapshot_Effect_Subtitle_Origin //keep original video size,with subtitle and video effect
} IJKSDLSnapshotType;

@protocol IJKVideoRenderingProtocol <NSObject>

@property(nonatomic) IJKMPMovieScalingMode scalingMode;
#if TARGET_OS_IOS
@property(nonatomic) CGFloat scaleFactor;
#endif
/*
 if you update these preference blow, when player paused,
 you can call -[setNeedsRefreshCurrentPic] method let current picture refresh right now.
 */
// rotate preference
@property(nonatomic) IJKSDLRotatePreference rotatePreference;
// color conversion preference
@property(nonatomic) IJKSDLColorConversionPreference colorPreference;
// user defined display aspect ratio
@property(nonatomic) IJKSDLDARPreference darPreference;
// not render picture and subtitle,but holder overlay content.
@property(atomic) BOOL preventDisplay;
// hdr video show 'Gray mask' animation
@property(nonatomic) BOOL showHdrAnimation;
// refresh current video picture and subtitle (when player paused change video pic preference, you can invoke this method)
- (void)setNeedsRefreshCurrentPic;

// display the overlay.
- (BOOL)displayAttach:(IJKOverlayAttach *)attach;

#if !TARGET_OS_OSX
- (UIImage *)snapshot;
#else
- (CGImageRef)snapshot:(IJKSDLSnapshotType)aType;
#endif
- (NSString *)name;
- (id)context;

@optional;
- (void)setBackgroundColor:(uint8_t)r g:(uint8_t)g b:(uint8_t)b;

@end

#endif /* IJKVideoRenderingProtocol_h */
