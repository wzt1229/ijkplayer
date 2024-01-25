//
//  AppDelegate.m
//  IJKMediaDemo
//
//  Created by Matt Reach on 2019/6/25.
//  Copyright © 2019 IJK Mac. All rights reserved.
//

#import "AppDelegate.h"
#import "WindowController.h"
#import "MRRootViewController.h"
#import "MRAutoTestViewController.h"
#import "MRStatisticalViewController.h"
#import <IJKMediaPlayerKit/IJKMediaPlayerKit.h>
#import "MRGlobalNotification.h"
#import "MRUtil+SystemPanel.h"
#import "MRActionKit.h"
#import "MRTextInfoViewController.h"
#import <IOKit/pwr_mgt/IOPMLib.h>

@interface AppDelegate ()

@property (strong) NSWindowController *windowCtrl;
@property (strong) NSArray *waitHandleArr;

@end

@implementation AppDelegate

- (void)prepareActionProcessor
{
    MRActionProcessor *processor = [[MRActionProcessor alloc] initWithScheme:@"ijkplayer"];
    
    __weakSelf__
    [processor registerHandler:^(MRActionItem *item) {
        __strongSelf__
        NSDictionary *params = [item queryMap];
        NSString *link = params[@"links"];
        if (link) {
            link = [link stringByRemovingPercentEncoding];
        }
        NSArray *links = [link componentsSeparatedByString:@"|"];
        NSMutableDictionary *dic = [NSMutableDictionary new];
        [dic setObject:links forKey:@"links"];
        POST_NOTIFICATION(kPlayNetMovieNotificationName_G, self, dic);
        [NSApp activateIgnoringOtherApps:YES];
    } forPath:@"/play"];
    
    [MRUtil initUserDefaults];
    [MRActionManager registerProcessor:processor];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    int a = 0x11223344;
    char *c = (char *)&a;
    printf("%02X,%02X,%02X,%02X\n",c[0],c[1],c[2],c[3]);
    int *b = (int *)c;
    printf("%d:%d\n",a,*b);
    if (*c == 0x44) {
        printf("little endian\n");
    } else {
        printf("big endian\n");
    }
    
    [self prepareActionProcessor];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
#if DEBUG
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints"];
#endif
    // Insert code here to initialize your application
    NSWindowStyleMask mask = NSWindowStyleMaskBorderless | NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView;
    
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600) styleMask:mask backing:NSBackingStoreBuffered defer:YES];
    
    window.contentViewController = [[MRRootViewController alloc] init];
//    window.contentViewController = [[MRAutoTestViewController alloc] init];
//    window.contentViewController = [[MRStatisticalViewController alloc] init];
    if (window.contentViewController.title) {
        window.title = window.contentViewController.title;
    }
    window.movableByWindowBackground = YES;
    
    self.windowCtrl = [[WindowController alloc] init];
    self.windowCtrl.window = window;
    [window center];
    [self.windowCtrl showWindow:nil];
    BOOL match = [IJKFFMoviePlayerController checkIfFFmpegVersionMatch:YES];
    NSLog(@"==FFmpegVersionMatch:%d",match);

    if ([self.waitHandleArr count] > 0) {
        [self application:NSApp openURLs:self.waitHandleArr];
        self.waitHandleArr = nil;
    }
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

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

- (void)playOpenedURL:(NSArray<NSURL *> * _Nonnull)urls
{
    if ([urls count] == 0) {
        return;
    }
    
    NSMutableArray *bookmarkArr = [NSMutableArray array];
    for (NSURL *url in urls) {
        NSDictionary *dic = [MRUtil makeBookmarkWithURL:url];
        if (dic) {
            [bookmarkArr addObject:dic];
        }
    }
    if ([bookmarkArr count] > 0) {
        NSMutableDictionary *dic = [NSMutableDictionary new];
        [dic setObject:bookmarkArr forKey:@"obj"];
        POST_NOTIFICATION(kPlayExplorerMovieNotificationName_G, self, dic);
    }
}

- (void)openDocument:(id)sender
{
    NSArray<NSDictionary *> * bookmarkArr = [MRUtil showSystemChooseVideoPanelAutoScan];
    if ([bookmarkArr count] > 0) {
        NSMutableDictionary *dic = [NSMutableDictionary new];
        [dic setObject:bookmarkArr forKey:@"obj"];
        POST_NOTIFICATION(kPlayExplorerMovieNotificationName_G, self, dic);
    }
}

- (IBAction)showPreferencesPanel:(id)sender
{
    NSStoryboard *sb = [NSStoryboard storyboardWithName:@"Setting" bundle:nil];
    [self.windowCtrl.window.contentViewController presentViewControllerAsModalWindow:[sb instantiateInitialController]];
}

- (IBAction)showSupportedDecoder:(id)sender
{
    NSString *text = [[IJKFFMoviePlayerController supportedDecoders] description];
    MRTextInfoViewController *vc = [[MRTextInfoViewController alloc] initWithText:text];
    vc.title = @"Supported Decoder";
    [self.windowCtrl.window.contentViewController presentViewControllerAsModalWindow:vc];
}

- (BOOL)application:(NSApplication *)sender openFile:(nonnull NSString *)filename
{
    [self application:sender openFiles:@[filename]];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames
{
    NSMutableArray *urlArr = [NSMutableArray array];
    for (NSString *file in filenames) {
        [urlArr addObject:[NSURL fileURLWithPath:file]];
    }
    
    [self application:sender openURLs:urlArr];
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urlArr
{
    if ([urlArr count] > 0) {
        if (!self.windowCtrl) {
            self.waitHandleArr = urlArr;
        } else {
            if ([urlArr count] == 1) {
                NSURL *url = [urlArr firstObject];
                NSError *err = nil;
                if ([MRActionManager handleActionWithURL:[url absoluteString] error:&err]) {
                    return;
                }
            }
            
            [self playOpenedURL:urlArr];
            [NSApp activateIgnoringOtherApps:YES];
        }
    }
}

static IOPMAssertionID g_displaySleepAssertionID;

- (void)enableComputerSleep:(BOOL)enable
{
    if (!g_displaySleepAssertionID && !enable)
    {
        NSLog(@"enableComputerSleep:NO");
        IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep, kIOPMAssertionLevelOn,
                                    (__bridge CFStringRef)[[NSBundle mainBundle] bundleIdentifier],&g_displaySleepAssertionID);
    }
    else if (g_displaySleepAssertionID && enable)
    {
        NSLog(@"enableComputerSleep:YES");
        IOPMAssertionRelease(g_displaySleepAssertionID);
        g_displaySleepAssertionID = 0;
    }
}

@end
