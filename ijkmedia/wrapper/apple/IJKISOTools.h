//
//  IJKISOTools.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2023/12/19.
//
// probe the folder whether or not bluray video

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IJKISOTools : NSObject


/// Detect if it is DVD
/// - Parameter discRoot: iso path
+ (BOOL)isDVDVideo:(NSString *)discRoot;


/// Detect if it is BD
/// - Parameters:
///   - discRoot: iso path
///   - keyFile: keyfile is optional
+ (BOOL)isBlurayVideo:(NSString *)discRoot keyFile:(NSString * _Nullable)keyFile;

@end

NS_ASSUME_NONNULL_END
