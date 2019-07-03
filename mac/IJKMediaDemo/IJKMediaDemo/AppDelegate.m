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
@property (atomic, retain) id<IJKMediaPlayback> player;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    BOOL match = [IJKFFMoviePlayerController checkIfFFmpegVersionMatch:YES];
    
    NSLog(@"==FFmpegVersionMatch:%d",match);
    
    [IJKFFMoviePlayerController setLogReport:YES];
    [IJKFFMoviePlayerController setLogLevel:k_IJK_LOG_UNKNOWN];
    
    IJKFFOptions *options = [IJKFFOptions optionsByDefault];
    BOOL isVideoToolBox = YES;
    if(isVideoToolBox){
//        [options setPlayerOptionValue:@"fcc-_es2"          forKey:@"overlay-format"];
        [options setPlayerOptionIntValue:1      forKey:@"videotoolbox"];
        //[options setPlayerOptionIntValue:4096    forKey:@"videotoolbox-max-frame-width"];
    }else{
        //     [options setPlayerOptionValue:@"fcc-rv24"          forKey:@"overlay-format"];
        [options setPlayerOptionValue:@"fcc-i420"          forKey:@"overlay-format"];
    }
    
    NSString *urlString = @"http://10.7.36.50/ffmpeg-test/xp5.mp4";
//    urlString = @"http://10.7.36.50/ffmpeg-test/ff-concat-2/1.mp4";
    urlString = @"http://10.7.36.50/ffmpeg-test/ff-concat-2/test.ffcat";
    urlString = @"http://10.7.36.50/ifox/m3u8/9035543-5441294-31.m3u8";
    
    NSURL *url = [NSURL URLWithString:urlString];
    self.player = [[IJKFFMoviePlayerController alloc] initWithContentURL:url withOptions:options];
//    self.player.view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    CGRect rect = self.window.frame;
    rect.origin = CGPointZero;
    self.player.view.frame = rect;
    self.player.scalingMode = IJKMPMovieScalingModeAspectFit;
    self.player.shouldAutoplay = YES;
    self.player.playbackRate = 2.0;
    [self.player prepareToPlay];
    self.window.contentView = self.player.view;
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


@end
