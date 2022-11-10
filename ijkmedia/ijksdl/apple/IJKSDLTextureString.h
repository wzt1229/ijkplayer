/*
 * IJKSDLTextureString.h
 *
 * Copyright (c) 2013-2014 Bilibili
 * Copyright (c) 2013-2014 Zhang Rui <bbcallen@gmail.com>
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

#import <Foundation/Foundation.h>

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#else
#import <UIKit/UIKit.h>
#define NSColor UIColor
#define NSSize CGSize
#define NSFont UIFont
#define NSEdgeInsets UIEdgeInsets
#define NSEdgeInsetsMake UIEdgeInsetsMake
#define NSEdgeInsetsEqual UIEdgeInsetsEqualToEdgeInsets
#endif


@interface IJKSDLTextureString : NSObject

// designated initializer
- (id)initWithAttributedString:(NSAttributedString *)attributedString withBoxColor:(NSColor *)color withBorderColor:(NSColor *)color;

- (id)initWithString:(NSString *)aString withAttributes:(NSDictionary *)attribs withBoxColor:(NSColor *)color withBorderColor:(NSColor *)color;

// basic methods that pick up defaults
- (id)initWithString:(NSString *)aString withAttributes:(NSDictionary *)attribs;
- (id)initWithAttributedString:(NSAttributedString *)attributedString;

// these will force the texture to be regenerated at the next draw

//the string attributes NSForegroundColorAttribute
@property (nonatomic, strong) NSColor *textColor;
//background box color
@property (nonatomic, strong) NSColor *boxColor;
//border color,default is nil
@property (nonatomic, strong) NSColor *borderColor;
// set top,right,bottom,left margin
@property (nonatomic, assign) NSEdgeInsets edgeInsets;
@property(nonatomic, assign) float cRadius; // Corner radius, if 0 just a rectangle. Defaults to 3.0f

@property (nonatomic, assign) BOOL antialias;

- (void)setAttributedString:(NSAttributedString *)attributedString; // set string after initial creation
- (void)setString:(NSString *)aString withAttributes:(NSDictionary *)attribs; // set string after initial creation
- (CVPixelBufferRef)createPixelBuffer;

@end

