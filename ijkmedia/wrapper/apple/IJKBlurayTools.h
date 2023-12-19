//
//  IJKBlurayTools.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2023/12/19.
//
// probe the folder whether or not bluray video

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IJKBlurayTools : NSObject

+ (BOOL)isBlurayVideo:(NSString *)discRoot keyFile:(NSString * _Nullable)keyFile;

@end

NS_ASSUME_NONNULL_END
