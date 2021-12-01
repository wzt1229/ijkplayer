//
//  MRUtil.h
//  FFmpegTutorial-macOS
//
//  Created by qianlongxu on 2020/12/2.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CGImage.h>

NS_ASSUME_NONNULL_BEGIN

@interface MRUtil : NSObject

+ (NSArray <NSString *>*)videoType;
+ (NSArray <NSString *>*)subtitleType;
+ (NSArray <NSString *>*)acceptMediaType;

+ (NSDictionary *)makeBookmarkWithURL:(NSURL *)url;
+ (NSArray <NSDictionary *>*)scanFolderWithPath:(NSString *)dir filter:(NSArray<NSString *>*)types;
+ (BOOL)saveImageToFile:(CGImageRef)img path:(NSString *)imgPath;

@end

NS_ASSUME_NONNULL_END
