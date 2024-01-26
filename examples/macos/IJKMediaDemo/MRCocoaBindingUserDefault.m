//
//  MRCocoaBindingUserDefault.m
//  IJKMediaMacDemo
//
//  Created by Reach Matt on 2024/1/25.
//  Copyright © 2024 IJK Mac. All rights reserved.
//
//https://itecnote.com/tecnote/ios-nsuserdefaultsdidchangenotification-whats-the-name-of-the-key-that-changed/

#import "MRCocoaBindingUserDefault.h"
#import <AppKit/NSUserDefaultsController.h>

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

+ (void)initUserDefaults
{
    [[NSUserDefaultsController sharedUserDefaultsController] setInitialValues:@{
        @"values.log_level":@"info",
        @"values.subtitle_font_ratio":@(1.5),
        @"values.subtitle_bottom_margin":@(1.5),
        @"values.hw":@(1),
        @"values.copy_hw_frame":@(1),
        @"values.overlay_format":@"fcc-_es2",
        @"values.accurate_seek":@(1),
        @"values.use_opengl":@(0),
        @"values.snapshot_type":@(0),
    }];
//    [self initUserDefault:@"values.log_level" defaultValue:@"info"];
//    
//    [self initUserDefault:@"values.subtitle_font_ratio" defaultValue:@(1.5)];
//    [self initUserDefault:@"values.subtitle_bottom_margin" defaultValue:@(1.5)];
//    
//    [self initUserDefault:@"values.hw" defaultValue:@(1)];
//    [self initUserDefault:@"values.copy_hw_frame" defaultValue:@(1)];
//    [self initUserDefault:@"values.overlay_format" defaultValue:@"fcc-_es2"];
//    [self initUserDefault:@"values.accurate_seek" defaultValue:@(1)];
//    [self initUserDefault:@"values.use_opengl" defaultValue:@(0)];
//    
//    [self initUserDefault:@"values.snapshot_type" defaultValue:@(0)];
}

+ (id)anyForKey:(NSString *)key
{
    if (!key) {
        return nil;
    }
    if (![key hasPrefix:@"values."]) {
        key = [@"values." stringByAppendingString:key];
    }
    return [[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath:key];
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
        BOOL remove;
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
        while (obj = [enumerator nextObject]) { //通过枚举器，取数组里面的每一个元素
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

+ (BOOL)copy_hw_frame
{
    return [self boolForKey:@"copy_hw_frame"];
}

+ (BOOL)hw
{
    return [self boolForKey:@"hw"];
}

+ (float)subtitle_font_ratio
{
    return [self floatForKey:@"subtitle_font_ratio"];
}

+ (float)subtitle_bottom_margin
{
    return [self floatForKey:@"subtitle_bottom_margin"];
}

+ (NSString *)overlay_format
{
    return [self stringForKey:@"overlay_format"];
}

+ (BOOL)accurate_seek
{
    return [self boolForKey:@"accurate_seek"];
}

+ (BOOL)use_opengl
{
    return [self boolForKey:@"use_opengl"];
}

+ (int)snapshot_type
{
    return [self intForKey:@"snapshot_type"];
}

@end
