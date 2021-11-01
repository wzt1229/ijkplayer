//
//  AppDelegate.m
//  IJKMediaDemo
//
//  Created by Matt Reach on 2019/6/25.
//  Copyright © 2019 IJK Mac. All rights reserved.
//

#import "AppDelegate.h"
#import "RootViewController.h"
#import <IJKMediaPlayerKit/IJKMediaPlayerKit.h>

@interface AppDelegate ()

@property (strong) NSWindowController *windowCtrl;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    
    NSWindowStyleMask mask = NSWindowStyleMaskBorderless | NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600) styleMask:mask backing:NSBackingStoreBuffered defer:YES];
    window.contentViewController = [[RootViewController alloc] init];
    window.movableByWindowBackground = YES;
    
    self.windowCtrl = [[NSWindowController alloc] init];
    self.windowCtrl.window = window;
    [window center];
    [self.windowCtrl showWindow:nil];
    BOOL match = [IJKFFMoviePlayerController checkIfFFmpegVersionMatch:YES];
    
    NSLog(@"==FFmpegVersionMatch:%d",match);
    
    [IJKFFMoviePlayerController setLogReport:YES];
    [IJKFFMoviePlayerController setLogLevel:k_IJK_LOG_INFO];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    if ([self.windowCtrl.window isMiniaturized]) {
        [self.windowCtrl.window deminiaturize:sender];
    } else {
        [self.windowCtrl.window makeKeyAndOrderFront:sender];
    }
    [NSApp activateIgnoringOtherApps:YES];
    return YES;
}

@end
