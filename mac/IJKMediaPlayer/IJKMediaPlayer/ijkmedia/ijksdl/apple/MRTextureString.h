//
// File:		MRTextureString.h 
//				(Originally Apple's GLString.h)
//
// Abstract:	Uses Quartz to draw a string into a CVPixelBufferRef
//
// Version:
//          2.0 - use CVPixelBufferRef instead of glTexImage2D; use ARC
//          1.1 - Minor enhancements and bug fixes.
//          1.0 - Original release.
//				

#import <Foundation/Foundation.h>

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#else
#import <UIKit/UIKit.h>
#define NSColor UIColor
#define NSSize CGSize
#define NSEdgeInsets UIEdgeInsets
#define NSEdgeInsetsMake UIEdgeInsetsMake
#define NSEdgeInsetsEqual UIEdgeInsetsEqualToEdgeInsets
#endif


@interface MRTextureString : NSObject

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
//text size + edgeInsets
@property (nonatomic, assign) CGSize size;
// set top,right,bottom,left margin
@property (nonatomic, assign) NSEdgeInsets edgeInsets;
@property (nonatomic, assign) BOOL antialias;

- (void)setString:(NSAttributedString *)attributedString; // set string after initial creation
- (void)setString:(NSString *)aString withAttributes:(NSDictionary *)attribs; // set string after initial creation
- (CVPixelBufferRef)cvPixelBuffer;

@end

