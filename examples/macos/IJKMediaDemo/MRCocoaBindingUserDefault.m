//
//  MRCocoaBindingUserDefault.m
//  IJKMediaMacDemo
//
//  Created by Reach Matt on 2024/1/25.
//  Copyright © 2024 IJK Mac. All rights reserved.
//
//https://itecnote.com/tecnote/ios-nsuserdefaultsdidchangenotification-whats-the-name-of-the-key-that-changed/

//https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaBindings/Concepts/NSUserDefaultsController.html

#import "MRCocoaBindingUserDefault.h"
#import <AppKit/NSUserDefaultsController.h>
#import <AppKit/NSColor.h>

@interface MRCocoaBindingUserDefault()

@property (nonatomic, strong) NSMutableDictionary *observers;

@end

@implementation MRCocoaBindingUserDefault

+ (MRCocoaBindingUserDefault *)sharedDefault
{
    static MRCocoaBindingUserDefault *obj = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        obj = [[MRCocoaBindingUserDefault alloc] init];
    });
    return obj;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.observers = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (NSDictionary *)initValues 
{
    NSColor *text_color = [NSColor whiteColor];
    NSData *text_color_data = [NSKeyedArchiver archivedDataWithRootObject:text_color];
    
    NSColor *subtitle_bg_color = [NSColor clearColor];
    NSData *subtitle_bg_color_data = [NSKeyedArchiver archivedDataWithRootObject:subtitle_bg_color];
    
    NSColor *subtitle_stroke_color = [NSColor blackColor];
    NSData *subtitle_stroke_color_data = [NSKeyedArchiver archivedDataWithRootObject:subtitle_stroke_color];
    
    NSDictionary *initValues = @{
        @"volume" : @(0.4),
        
        @"log_level":@"info",
        @"color_adjust_brightness" : @(1.0),
        @"color_adjust_saturation" : @(1.0),
        @"color_adjust_contrast" : @(1.0),
        @"use_opengl" : @(0),
        @"picture_fill_mode" : @(0),
        @"picture_wh_ratio" : @(0),
        @"picture_ratate_mode" : @(0),
        @"picture_flip_mode" : @(0),
        
        @"use_hw" : @(1),
        @"copy_hw_frame" : @(0),
        @"de_interlace" : @(0),
        @"open_hdr" : @(1),
        @"overlay_format" : @"fcc-_es2",
        
        @"subtitle_font_name" : @"STSongti-SC-Regular",
        @"subtitle_font_size" : @(50),
        @"subtitle_bottom_margin":@(0.5),
        @"subtitle_stroke_size" : @(5),
        @"subtitle_text_color" : text_color_data,
        @"subtitle_bg_color" : subtitle_bg_color_data,
        @"subtitle_stroke_color" : subtitle_stroke_color_data,

        @"snapshot_type" : @(3),
        @"accurate_seek" : @(1),
        @"seek_step" : @(15),
        @"open_gzip" : @(1),
        @"use_dns_cache" : @(1),
        @"dns_cache_period" : @(600),
    };
    return initValues;
}

+ (void)initUserDefaults
{
    NSDictionary * initValues = [self initValues];
    [[NSUserDefaultsController sharedUserDefaultsController] setInitialValues:initValues];
    [[[NSUserDefaultsController sharedUserDefaultsController] defaults] registerDefaults:initValues];
}

+ (void)resetAll
{
    NSDictionary * initValues = [self initValues];
    [[[NSUserDefaultsController sharedUserDefaultsController] defaults] setPersistentDomain:initValues forName:[[NSBundle mainBundle] bundleIdentifier]];
    
    //清理掉现有的值
//    [[[NSUserDefaultsController sharedUserDefaultsController] defaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
}

+ (NSString *)resolveKey:(NSString *)key
{
    if (!key) {
        return nil;
    }
    if (![key hasPrefix:@"values."]) {
        key = [@"values." stringByAppendingString:key];
    }
    return key;
}

+ (id)anyForKey:(NSString *)key
{
    key = [self resolveKey:key];
    return [[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath:key];
}

+ (void)setValue:(id)value forKey:(NSString *)key
{
    key = [self resolveKey:key];
    [[NSUserDefaultsController sharedUserDefaultsController] setValue:value forKeyPath:key];
}

+ (void)resetValueForKey:(NSString *)key
{
    key = [self resolveKey:key];
    id initValue = [[[NSUserDefaultsController sharedUserDefaultsController] initialValues] objectForKey:key];
    [self setValue:initValue forKey:key];
}

+ (BOOL)boolForKey:(NSString *)key
{
    return [[self anyForKey:key] boolValue];
}

+ (float)floatForKey:(NSString *)key
{
    return [[self anyForKey:key] floatValue];
}

+ (NSString *)stringForKey:(NSString *)key
{
    return [[self anyForKey:key] description];
}

+ (int)intForKey:(NSString *)key
{
    return [[self anyForKey:key] intValue];
}

- (void)onChange:(void(^)(id,BOOL*))observer forKey:(NSString *)key
{
    [self onChange:observer forKey:key init:NO];
}

- (void)onChange:(void(^)(id,BOOL*))observer forKey:(NSString *)key init:(BOOL)init
{
    if (!observer) {
        return;
    }
    BOOL remove = NO;
    if (init) {
        id value = [[self class] anyForKey:key];
        observer(value, &remove);
    }
    
    if (!remove) {
        NSMutableArray *array = [self.observers objectForKey:key];
        if (!array) {
            array = [NSMutableArray array];
            [self.observers setObject:array forKey:key];
            NSUserDefaults *defaults = [[NSUserDefaultsController sharedUserDefaultsController] defaults];
            [defaults addObserver:self
                       forKeyPath:key
                          options:NSKeyValueObservingOptionNew
                          context:NULL];
        }
        [array addObject:[observer copy]];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                 ofObject:(id)object
                   change:(NSDictionary *)change
                  context:(void *)context
{
    NSArray *array = [self.observers objectForKey:keyPath];
    id value = change[NSKeyValueChangeNewKey];
    NSMutableArray *removeArr = nil;
    for (int i = 0; i< array.count; i++) {
        void(^block)(id,BOOL*) = array[i];
        BOOL remove = NO;
        if ([value isKindOfClass:[NSData class]]) {
            value = [NSKeyedUnarchiver unarchiveObjectWithData:value];
        }
        block(value, &remove);
        if (remove) {
            if (removeArr == nil) {
                removeArr = [NSMutableArray array];
            }
            [removeArr addObject:@(i)];
        }
    }
    if ([removeArr count] > 0) {
        NSMutableArray *result = [NSMutableArray arrayWithArray:array];
        NSEnumerator *enumerator = [removeArr reverseObjectEnumerator];
        id obj = nil;
        while (obj = [enumerator nextObject]) {
            [result removeObjectAtIndex:[obj intValue]];
        }
        [self.observers setObject:result forKey:keyPath];
    }
}

@end

@implementation MRCocoaBindingUserDefault (util)

+ (NSString *)log_level
{
    return [self stringForKey:@"log_level"];
}

+ (float)color_adjust_brightness
{
    return [self floatForKey:@"color_adjust_brightness"];
}

+ (float)color_adjust_saturation
{
    return [self floatForKey:@"color_adjust_saturation"];
}

+ (float)color_adjust_contrast
{
    return [self floatForKey:@"color_adjust_contrast"];
}

+ (int)picture_fill_mode
{
    return [self intForKey:@"picture_fill_mode"];
}

+ (int)picture_wh_ratio
{
    return [self intForKey:@"picture_wh_ratio"];
}

+ (int)picture_ratate_mode
{
    return [self intForKey:@"picture_ratate_mode"];
}

+ (int)picture_flip_mode
{
    return [self intForKey:@"picture_flip_mode"];
}

+ (BOOL)copy_hw_frame
{
    return [self boolForKey:@"copy_hw_frame"];
}

+ (BOOL)use_hw
{
    return [self boolForKey:@"use_hw"];
}

+ (NSString *)subtitle_font_name
{
    return [self stringForKey:@"subtitle_font_name"];
}

+ (void)setSubtitle_font_name:(NSString *)font_name
{
    return [self setValue:font_name forKey:@"subtitle_font_name"];
}

+ (float)subtitle_font_size
{
    return [self floatForKey:@"subtitle_font_size"];
}

+ (void)setSubtitle_font_size:(float)font_size
{
    return [self setValue:@(font_size) forKey:@"subtitle_font_size"];
}

+ (float)subtitle_bottom_margin
{
    return [self floatForKey:@"subtitle_bottom_margin"];
}

+ (float)subtitle_stroke_size
{
    return [self floatForKey:@"subtitle_stroke_size"];
}

+ (NSColor *)subtitle_text_color
{
    NSData *data = [self anyForKey:@"subtitle_text_color"];
    if (data) {
        return [NSKeyedUnarchiver unarchiveObjectWithData:data];
    }
    return nil;
}

+ (NSColor *)subtitle_bg_color
{
    NSData *data = [self anyForKey:@"subtitle_bg_color"];
    if (data) {
        return [NSKeyedUnarchiver unarchiveObjectWithData:data];
    }
    return nil;
}

+ (NSColor *)subtitle_stroke_color
{
    NSData *data = [self anyForKey:@"subtitle_stroke_color"];
    if (data) {
        return [NSKeyedUnarchiver unarchiveObjectWithData:data];
    }
    return nil;
}

+ (float)volume
{
    return [self floatForKey:@"volume"];
}

+ (void)setVolume:(float)aVolume
{
    [self setValue:@(aVolume) forKey:@"volume"];
}

+ (NSString *)overlay_format
{
    return [self stringForKey:@"overlay_format"];
}

+ (BOOL)use_opengl
{
    return [self boolForKey:@"use_opengl"];
}

+ (int)snapshot_type
{
    return [self intForKey:@"snapshot_type"];
}

+ (BOOL)accurate_seek
{
    return [self boolForKey:@"accurate_seek"];
}

+ (int)seek_step
{
    return [self intForKey:@"seek_step"];
}

+ (int)open_gzip
{
    return [self intForKey:@"open_gzip"];
}

+ (int)use_dns_cache
{
    return [self intForKey:@"use_dns_cache"];
}

+ (int)dns_cache_period
{
    return [self intForKey:@"dns_cache_period"];
}

@end
