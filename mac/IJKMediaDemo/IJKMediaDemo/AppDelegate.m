//
//  AppDelegate.m
//  IJKMediaDemo
//
//  Created by Matt Reach on 2019/6/25.
//  Copyright © 2019 IJK Mac. All rights reserved.
//

#import "AppDelegate.h"
#import "MRDragView.h"
#import "MRUtil.h"
#import <IJKMediaPlayerKit/IJKMediaPlayerKit.h>

@interface AppDelegate ()<MRDragViewDelegate>

@property (weak) IBOutlet NSWindow *window;
@property (strong) IJKFFMoviePlayerController * player;
@property (weak) IBOutlet NSTextField *playedTimeLb;
@property (weak) IBOutlet MRDragView *playbackView;
@property (nonatomic, strong) NSMutableArray *playList;
@property (copy) NSURL *playingUrl;
@property (weak) NSTimer *tickTimer;
@property (weak) IBOutlet NSTextField *urlInput;

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

- (IBAction)onPlay:(NSButton *)sender {
    if (self.urlInput.stringValue.length > 0) {
        NSUInteger idx = [self.playList indexOfObject:self.playingUrl];
        if (idx == NSNotFound) {
            idx = -1;
        }
        idx ++;
        NSURL *url = [NSURL URLWithString:self.urlInput.stringValue];
        self.playList[idx] = url;
        [self playURL:url];
    }
}

- (IBAction)playNext:(NSButton *)sender {
    if ([self.playList count] == 0) {
        return;
    }
    
    NSUInteger idx = [self.playList indexOfObject:self.playingUrl];
    if (idx == NSNotFound) {
        idx = 0;
    } else if (idx >= [self.playList count] - 1) {
        idx = 0;
    } else {
        idx ++;
    }
    
    NSURL *url = self.playList[idx];
    [self playURL:url];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    BOOL match = [IJKFFMoviePlayerController checkIfFFmpegVersionMatch:YES];
    
    NSLog(@"==FFmpegVersionMatch:%d",match);
    
    [IJKFFMoviePlayerController setLogReport:YES];
    [IJKFFMoviePlayerController setLogLevel:k_IJK_LOG_INFO];
    
//    [self.playList addObject:[NSURL URLWithString:@"http://localhost/ffmpeg-test/Roof.of.the.World.E04.4K.WEB-DL.H265.mp4"]];
//    [self.playList addObject:[NSURL URLWithString:@"http://localhost/ffmpeg-test/Captain.Marvel.2019.2160p.WEB-DL.DD%2B5.1.HDR.HEVC-MOMA.mkv"]];
//    [self.playList addObject:[NSURL URLWithString:@"http://localhost/ffmpeg-test/11.mp4"]];
//    [self.playList addObject:[NSURL URLWithString:@"ijkhttphook:http://localhost/ffmpeg-test/xp5.mp4"]];
//    [self.playList addObject:[NSURL URLWithString:@"http://localhost/ffmpeg-test/xp5.mp4"]];
    [self.playList addObject:[NSURL URLWithString:@"https://data.vod.itc.cn/?new=/73/15/oFed4wzSTZe8HPqHZ8aF7J.mp4&vid=77972299&plat=14&mkey=XhSpuZUl_JtNVIuSKCB05MuFBiqUP7rB&ch=null&user=api&qd=8001&cv=3.13&uid=F45C89AE5BC3&ca=2&pg=5&pt=1&prod=ifox"]];
    NSString *localM3u8 = [[NSBundle mainBundle] pathForResource:@"996747-5277368-31" ofType:@"m3u8"];
    [self.playList addObject:[NSURL fileURLWithPath:localM3u8]];
}

- (NSMutableArray *)playList
{
    if (!_playList) {
        _playList = [NSMutableArray array];
    }
    return _playList;
}

- (void)playURL:(NSURL *)url
{
    self.playingUrl = url;
    self.urlInput.stringValue = [url absoluteString];
    NSString *title = [[url resourceSpecifier] lastPathComponent];
    [self.window setTitle:title];
    IJKFFOptions *options = [IJKFFOptions optionsByDefault];
    //视频帧处理不过来的时候丢弃一些帧达到同步的效果
//    [options setPlayerOptionIntValue:2 forKey:@"framedrop"];
    [options setPlayerOptionIntValue:16      forKey:@"video-pictq-size"];
//    [options setPlayerOptionIntValue:50000      forKey:@"min-frames"];
//    [options setPlayerOptionIntValue:50*1024*1024      forKey:@"max-buffer-size"];
    [options setPlayerOptionIntValue:30     forKey:@"max-fps"];
    [options setPlayerOptionIntValue:1      forKey:@"packet-buffering"];
    [options setPlayerOptionIntValue:0      forKey:@"videotoolbox-async"];
    
    BOOL isVideoToolBox = YES;
    if (isVideoToolBox) {
//        [options setPlayerOptionValue:@"fcc-vtb-RGB24"         forKey:@"overlay-format"];
//        [options setPlayerOptionValue:@"fcc-vtb-ARGB"          forKey:@"overlay-format"];
//        [options setPlayerOptionValue:@"fcc-vtb-BGRA"          forKey:@"overlay-format"];
//        [options setPlayerOptionValue:@"fcc-vtb-UYVY"          forKey:@"overlay-format"];
        
        //default is NV12 for videotoolbox
//        [options setPlayerOptionValue:@"fcc-vtb-NV12"          forKey:@"overlay-format"];
        
        [options setPlayerOptionIntValue:1      forKey:@"videotoolbox"];
        [options setPlayerOptionIntValue:3840    forKey:@"videotoolbox-max-frame-width"];
    } else {
#warning bgr565 not support
//        [options setPlayerOptionValue:@"fcc-bgr565"      forKey:@"overlay-format"];
//        [options setPlayerOptionValue:@"fcc-rgb565"      forKey:@"overlay-format"];
//        [options setPlayerOptionValue:@"fcc-rgb24"       forKey:@"overlay-format"];
//        [options setPlayerOptionValue:@"fcc-bgr24"       forKey:@"overlay-format"];
//        [options setPlayerOptionValue:@"fcc-rgba"        forKey:@"overlay-format"];
//        [options setPlayerOptionValue:@"fcc-rgb0"        forKey:@"overlay-format"];
//        [options setPlayerOptionValue:@"fcc-bgra"        forKey:@"overlay-format"];
//        [options setPlayerOptionValue:@"fcc-bgr0"        forKey:@"overlay-format"];
//        [options setPlayerOptionValue:@"fcc-argb"        forKey:@"overlay-format"];
//        [options setPlayerOptionValue:@"fcc-0rgb"        forKey:@"overlay-format"];
//        [options setPlayerOptionValue:@"fcc-i420"        forKey:@"overlay-format"];
        [options setPlayerOptionValue:@"fcc-nv12"        forKey:@"overlay-format"];
    }
    
    if (self.player) {
        [self.player.view removeFromSuperview];
        [self.player stop];
    }
    
    self.player = [[IJKFFMoviePlayerController alloc] initWithContentURL:self.playingUrl withOptions:options];
//    self.player.view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    CGRect rect = self.window.frame;
    rect.origin = CGPointZero;
    self.player.view.frame = rect;
    self.player.scalingMode = IJKMPMovieScalingModeAspectFit;
    self.player.shouldAutoplay = YES;
    
    [self.player prepareToPlay];
    
    NSView <IJKSDLGLViewProtocol>*playerView = self.player.view;
#warning TODO IJKContentModeScaleAspectFit
//    [playerView setContentMode:IJKContentModeScaleAspectFit];
    playerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.playbackView addSubview:playerView];
    [self.playbackView setWantsLayer:YES];
    self.playbackView.layer.backgroundColor = [[NSColor redColor] CGColor];
    
    if (!self.tickTimer) {
        self.tickTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(onTick:) userInfo:nil repeats:YES];
    }
}

- (void)onTick:(NSTimer *)sender
{
    if (self.player) {
        NSTimeInterval interval = self.player.currentPlaybackTime;
        self.playedTimeLb.stringValue = [NSString stringWithFormat:@"%02d:%02d",
                                         (int)interval/60,(int)interval%60];
    } else {
        self.playedTimeLb.stringValue = @"--:--";
        [sender invalidate];
    }
}

- (void)playFirstIfNeed
{
    if (!self.playingUrl) {
        NSURL *url = [self.playList firstObject];
        if (url) {
            [self playURL:url];
        }
    }
}

- (NSURL *)existTaskForUrl:(NSURL *)url
{
    NSURL *t = nil;
    for (NSURL *item in [self.playList copy]) {
        if ([[item absoluteString] isEqualToString:[url absoluteString]]) {
            t = item;
            break;
        }
    }
    return t;
}

- (void)handleDragFileList:(nonnull NSArray<NSURL *> *)fileUrls
{
    NSMutableArray *bookmarkArr = [NSMutableArray array];
    for (NSURL *url in fileUrls) {
        //先判断是不是文件夹
        BOOL isDirectory = NO;
        BOOL isExist = [[NSFileManager defaultManager] fileExistsAtPath:[url path] isDirectory:&isDirectory];
        if (isExist) {
            if (isDirectory) {
                ///扫描文件夹
                NSString *dir = [url path];
                NSArray *dicArr = [MRUtil scanFolderWithPath:dir filter:[MRUtil videoType]];
                if ([dicArr count] > 0) {
                    [bookmarkArr addObjectsFromArray:dicArr];
                }
            } else {
                NSString *pathExtension = [[url pathExtension] lowercaseString];
                if ([[MRUtil videoType] containsObject:pathExtension]) {
                    //视频
                    NSDictionary *dic = [MRUtil makeBookmarkWithURL:url];
                    [bookmarkArr addObject:dic];
                }
            }
        }
    }
    
    if ([bookmarkArr count] > 0) {
        
        [self.playList removeAllObjects];
        for (NSDictionary *dic in bookmarkArr) {
            NSURL *url = dic[@"url"];
            
            if ([self existTaskForUrl:url]) {
                continue;
            }
            
            [self.playList addObject:url];
        }
        
        [self playFirstIfNeed];
    }
}

- (NSDragOperation)acceptDragOperation:(NSArray<NSURL *> *)list
{
    for (NSURL *url in list) {
        if (url) {
            //先判断是不是文件夹
            BOOL isDirectory = NO;
            BOOL isExist = [[NSFileManager defaultManager] fileExistsAtPath:[url path] isDirectory:&isDirectory];
            if (isExist) {
                if (isDirectory) {
                   ///扫描文件夹
                   NSString *dir = [url path];
                   NSArray *dicArr = [MRUtil scanFolderWithPath:dir filter:[MRUtil videoType]];
                    if ([dicArr count] > 0) {
                        return NSDragOperationCopy;
                    }
                } else {
                    NSString *pathExtension = [[url pathExtension] lowercaseString];
                    if ([[MRUtil videoType] containsObject:pathExtension]) {
                        return NSDragOperationCopy;
                    }
                }
            }
        }
    }
    return NSDragOperationNone;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    if ([self.window isMiniaturized]) {
        [self.window deminiaturize:sender];
    } else {
        [self.window makeKeyAndOrderFront:sender];
    }
    [NSApp activateIgnoringOtherApps:YES];
    return YES;
}
@end
