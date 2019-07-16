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
@property (weak) IBOutlet NSTextField *playedTimeLb;
@property (weak) IBOutlet NSView *playbackView;

@end

@implementation AppDelegate

- (IBAction)pauseOrPlay:(NSButton *)sender {
    if ([sender.title isEqualToString:@"Pause"]) {
        [sender setTitle:@"Play"];
        [self.player pause];
    } else {
        [sender setTitle:@"Pause"];
        [self.player play];
    }
}

- (IBAction)fastRewind:(NSButton *)sender {
    float cp = self.player.currentPlaybackTime;
    cp -= 50;
    if (cp < 0) {
        cp = 0;
    }
    self.player.currentPlaybackTime = cp;
}


- (IBAction)fastForward:(NSButton *)sender {
    float cp = self.player.currentPlaybackTime;
    cp += 50;
    if (cp < 0) {
        cp = 0;
    }
    self.player.currentPlaybackTime = cp;
}

- (IBAction)updateSpeed:(NSButton *)sender {
    NSInteger tag = sender.tag;
    float speed = tag / 100.0;
    self.player.playbackRate = speed;
}


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    BOOL match = [IJKFFMoviePlayerController checkIfFFmpegVersionMatch:YES];
    
    NSLog(@"==FFmpegVersionMatch:%d",match);
    
    [IJKFFMoviePlayerController setLogReport:YES];
    [IJKFFMoviePlayerController setLogLevel:k_IJK_LOG_UNKNOWN];
    
    IJKFFOptions *options = [IJKFFOptions optionsByDefault];
    //视频帧处理不过来的时候丢弃一些帧达到同步的效果
    [options setPlayerOptionIntValue:5 forKey:@"framedrop"];
    
    BOOL isVideoToolBox = YES;
    if(isVideoToolBox){
//        [options setPlayerOptionValue:@"fcc-_es2"          forKey:@"overlay-format"];
        [options setPlayerOptionIntValue:1      forKey:@"videotoolbox"];
        //[options setPlayerOptionIntValue:4096    forKey:@"videotoolbox-max-frame-width"];
    }else{
        //     [options setPlayerOptionValue:@"fcc-rv24"          forKey:@"overlay-format"];
        [options setPlayerOptionValue:@"fcc-i420"          forKey:@"overlay-format"];
    }
    
    NSString *urlString = @"ijkhttphook:http://10.7.36.50/ffmpeg-test/xp5.mp4";
//    urlString = @"http://10.7.36.50/ffmpeg-test/ff-concat-2/1.mp4";
//    urlString = @"http://10.7.36.50/ffmpeg-test/ff-concat-2/test.ffcat";
    urlString = @"http://10.7.36.50/ifox/m3u8/9035543-5441294-31.m3u8";
//    urlString = @"http://10.7.36.50/ifox/m3u8/9513306-5546836-21.m3u8";
    urlString = @"http://10.7.36.50/ifox/m3u8/9513306-5546836-31.m3u8";
    
//    urlString = @"http://10.7.36.50/ffmpeg-test/Roof.of.the.World.E04.4K.WEB-DL.H265.mp4";
    
    NSURL *url = [NSURL URLWithString:urlString];
    
//    NSString *localM3u8 = [[NSBundle mainBundle] pathForResource:@"996747-5277368-31" ofType:@"m3u8"];
//    url = [NSURL fileURLWithPath:localM3u8];
    self.player = [[IJKFFMoviePlayerController alloc] initWithContentURL:url withOptions:options];
//    self.player.view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    CGRect rect = self.window.frame;
    rect.origin = CGPointZero;
    self.player.view.frame = rect;
    self.player.scalingMode = IJKMPMovieScalingModeAspectFit;
    self.player.shouldAutoplay = YES;
    
    [self.player prepareToPlay];
    [self.playbackView addSubview:self.player.view];
    self.player.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.playbackView setWantsLayer:YES];
    self.playbackView.layer.backgroundColor = [[NSColor redColor] CGColor];
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer * _Nonnull timer) {
        NSTimeInterval interval = self.player.currentPlaybackTime;
        self.playedTimeLb.stringValue = [NSString stringWithFormat:@"%02d:%02d",
                                         (int)interval/60,(int)interval%60];
    }];

}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


@end
