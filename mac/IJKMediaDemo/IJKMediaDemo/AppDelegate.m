//
//  AppDelegate.m
//  IJKMediaDemo
//
//  Created by Matt Reach on 2019/6/25.
//  Copyright © 2019 IJK Mac. All rights reserved.
//

#import "AppDelegate.h"
#import <IJKMediaMacFramework/IJKMediaMacFramework.h>

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    BOOL match = [IJKFFMoviePlayerController checkIfFFmpegVersionMatch:YES];
    NSLog(@"==FFmpegVersionMatch:%d",match);
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


@end
