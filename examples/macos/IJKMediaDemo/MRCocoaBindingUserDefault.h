//
//  MRCocoaBindingUserDefault.h
//  IJKMediaMacDemo
//
//  Created by Reach Matt on 2024/1/25.
//  Copyright © 2024 IJK Mac. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MRCocoaBindingUserDefault : NSObject

+ (void)initUserDefaults;
+ (BOOL)boolForKey:(NSString *)key;
+ (NSString *)stringForKey:(NSString *)key;
+ (MRCocoaBindingUserDefault *)sharedDefault;
//block BOOL means after invoke wheather stop ovserve and remove the observer
- (void)onChange:(void(^)(id,BOOL*))observer forKey:(NSString *)keyPath;

@end

@interface MRCocoaBindingUserDefault (util)

+ (NSString *)log_level;
+ (BOOL)copy_hw_frame;
+ (BOOL)hw;
+ (float)subtitle_font_ratio;
+ (float)subtitle_bottom_margin;
+ (NSString *)overlay_format;
+ (BOOL)accurate_seek;
+ (BOOL)use_opengl;
+ (int)snapshot_type;

@end

NS_ASSUME_NONNULL_END
