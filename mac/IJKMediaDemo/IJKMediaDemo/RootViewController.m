//
//  RootViewController.m
//  IJKMediaMacDemo
//
//  Created by Matt Reach on 2021/11/1.
//  Copyright © 2021 IJK Mac. All rights reserved.
//

#import "RootViewController.h"
#import "MRDragView.h"
#import "MRUtil.h"
#import <IJKMediaPlayerKit/IJKMediaPlayerKit.h>
#import <Carbon/Carbon.h>

@interface RootViewController ()<MRDragViewDelegate>

@property (weak) IBOutlet NSView *contentView;
@property (strong) IJKFFMoviePlayerController * player;
@property (weak) IBOutlet NSTextField *playedTimeLb;
@property (nonatomic, strong) NSMutableArray *playList;
@property (copy) NSURL *playingUrl;
@property (weak) NSTimer *tickTimer;
@property (weak) IBOutlet NSTextField *urlInput;

@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
    
    //for debug
    //[self.view setWantsLayer:YES];
    //self.view.layer.backgroundColor = [[NSColor redColor] CGColor];
    
    [self.contentView setWantsLayer:YES];
    self.contentView.layer.backgroundColor = [[NSColor colorWithWhite:0.2 alpha:0.5] CGColor];
    self.contentView.layer.cornerRadius = 4;
    self.contentView.layer.masksToBounds = YES;
    
    [self.playList addObject:[NSURL URLWithString:@"https://data.vod.itc.cn/?new=/73/15/oFed4wzSTZe8HPqHZ8aF7J.mp4&vid=77972299&plat=14&mkey=XhSpuZUl_JtNVIuSKCB05MuFBiqUP7rB&ch=null&user=api&qd=8001&cv=3.13&uid=F45C89AE5BC3&ca=2&pg=5&pt=1&prod=ifox"]];
    NSString *localM3u8 = [[NSBundle mainBundle] pathForResource:@"996747-5277368-31" ofType:@"m3u8"];
    [self.playList addObject:[NSURL fileURLWithPath:localM3u8]];
}

- (void)keyDown:(NSEvent *)event
{
    if ([event keyCode] == kVK_RightArrow && event.modifierFlags & NSEventModifierFlagCommand) {
        [self playNext:nil];
    } else if ([event keyCode] == kVK_ANSI_B && event.modifierFlags & NSEventModifierFlagCommand) {
        self.contentView.hidden = !self.contentView.isHidden;
    } else if ([event keyCode] == kVK_ANSI_R && event.modifierFlags & NSEventModifierFlagCommand) {
        
        IJKSDLRotatePreference preference = self.player.view.rotatePreference;
        
        if (preference.type == IJKSDLRotateNone) {
            preference.type = IJKSDLRotateZ;
        }
        
        if (event.modifierFlags & NSEventModifierFlagOption) {
            
            preference.type --;
            
            if (preference.type <= IJKSDLRotateNone) {
                preference.type = IJKSDLRotateZ;
            }
        }
        
        if (event.modifierFlags & NSEventModifierFlagShift) {
            preference.degrees --;
        } else {
            preference.degrees ++;
        }
        
        if (preference.degrees >= 360) {
            preference.degrees = 0;
        }
        self.player.view.rotatePreference = preference;
        
        NSLog(@"rotate:%@ %d",@[@"X",@"Y",@"Z"][preference.type-1],(int)preference.degrees);
    } else if ([event keyCode] == kVK_RightArrow) {
        [self fastForward:nil];
    } else if ([event keyCode] == kVK_LeftArrow) {
        [self fastRewind:nil];
    } else if ([event keyCode] == kVK_DownArrow) {
        float volume = self.player.playbackVolume;
        volume -= 0.1;
        if (volume < 0) {
            volume = .0f;
        }
        self.player.playbackVolume = volume;
        NSLog(@"volume:%0.1f",volume);
    } else if ([event keyCode] == kVK_UpArrow) {
        float volume = self.player.playbackVolume;
        volume += 0.1;
        if (volume > 1) {
            volume = 1.0f;
        }
        self.player.playbackVolume = volume;
        NSLog(@"volume:%0.1f",volume);
    } else if ([event keyCode] == kVK_Space) {
        [self pauseOrPlay:nil];
    }
}

- (NSMutableArray *)playList
{
    if (!_playList) {
        _playList = [NSMutableArray array];
    }
    return _playList;
}

- (void)perpareIJKPlayer:(NSURL *)url
{
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
    
    [self.player.view removeFromSuperview];
    [self.player stop];
    
    self.player = [[IJKFFMoviePlayerController alloc] initWithContentURL:url withOptions:options];
    CGRect rect = self.view.frame;
    rect.origin = CGPointZero;
    self.player.view.frame = rect;
    
    NSView <IJKSDLGLViewProtocol>*playerView = self.player.view;
    playerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.view addSubview:playerView positioned:NSWindowBelow relativeTo:nil];
    
    self.player.scalingMode = IJKMPMovieScalingModeAspectFit;
    self.player.shouldAutoplay = YES;
}

- (void)playURL:(NSURL *)url
{
    self.urlInput.stringValue = [url absoluteString];
    NSString *title = [[url resourceSpecifier] lastPathComponent];
    [self.view.window setTitle:title];
    
    [self perpareIJKPlayer:url];
    self.playingUrl = url;
    
    if (!self.tickTimer) {
        self.tickTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(onTick:) userInfo:nil repeats:YES];
    }
    
    [self.player prepareToPlay];
}

- (void)onTick:(NSTimer *)sender
{
    if (self.player) {
        
        long interval = (long)self.player.currentPlaybackTime;
        long duration = self.player.monitor.duration / 1000;
        self.playedTimeLb.stringValue = [NSString stringWithFormat:@"%02d:%02d/%02d:%02d",
                                         (int)(interval/60),(int)(interval%60),(int)(duration/60),(int)(duration%60)];
    } else {
        self.playedTimeLb.stringValue = @"--:--/--:--";
        [sender invalidate];
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
                //扫描文件夹
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
                   //扫描文件夹
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

- (void)playFirstIfNeed
{
    if (!self.playingUrl) {
        NSURL *url = [self.playList firstObject];
        if (url) {
            [self playURL:url];
        }
    }
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

- (IBAction)pauseOrPlay:(NSButton *)sender {
    if ([sender.title isEqualToString:@"Pause"]) {
        [sender setTitle:@"Play"];
        [self.player pause];
    } else {
        [sender setTitle:@"Pause"];
        [self.player play];
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

- (IBAction)onChangeSubtitleColor:(NSPopUpButton *)sender
{
    NSMenuItem *item = [sender selectedItem];
    NSInteger bgrValue = item.tag;
    NSColor *c = [NSColor colorWithRed:((float)(bgrValue & 0xFF))/255.0 green:((float)((bgrValue & 0xFF00) >> 8))/255.0 blue:(float)(((bgrValue & 0xFF0000) >> 16))/255.0 alpha:1.0];
    IJKSDLSubtitlePreference p = self.player.view.subtitlePreference;
    p.subtitleColor = c;
    p.subtitleFont = [NSFont boldSystemFontOfSize:60];
    self.player.view.subtitlePreference = p;
    [self.player invalidateSubtitleEffect];
}

- (IBAction)onChangeSubtitleSize:(NSButton *)sender
{
    IJKSDLSubtitlePreference p = self.player.view.subtitlePreference;
    NSFont *font = p.subtitleFont;
    
    CGFloat fontSize = 45;
    if (font) {
        fontSize = font.pointSize;
    }
    if (sender.tag == 1) {
        //增大
        fontSize += 5;
    } else {
        //减小
        fontSize -= 5;
    }
    
    p.subtitleFont = [NSFont boldSystemFontOfSize:fontSize];
    self.player.view.subtitlePreference = p;
    
    [self.player invalidateSubtitleEffect];
}

- (IBAction)onChangeScaleMode:(NSPopUpButton *)sender
{
    NSMenuItem *item = [sender selectedItem];
    if (item.tag == 1) {
        //scale to fill
        [self.player setScalingMode:IJKMPMovieScalingModeFill];
    } else if (item.tag == 2) {
        //aspect fill
        [self.player setScalingMode:IJKMPMovieScalingModeAspectFill];
    } else if (item.tag == 3) {
        //aspect fit
        [self.player setScalingMode:IJKMPMovieScalingModeAspectFit];
    }
}

- (IBAction)onRotate:(NSPopUpButton *)sender
{
    NSMenuItem *item = [sender selectedItem];
    
    IJKSDLRotatePreference preference = self.player.view.rotatePreference;
    
    if (item.tag == 0) {
        preference.type = IJKSDLRotateNone;
        preference.degrees = 0;
    } else if (item.tag == 1) {
        preference.type = IJKSDLRotateZ;
        preference.degrees = 90;
    } else if (item.tag == 2) {
        preference.type = IJKSDLRotateZ;
        preference.degrees = 180;
    } else if (item.tag == 3) {
        preference.type = IJKSDLRotateZ;
        preference.degrees = 270;
    } else if (item.tag == 4) {
        preference.type = IJKSDLRotateY;
        preference.degrees = 180;
    } else if (item.tag == 5) {
        preference.type = IJKSDLRotateX;
        preference.degrees = 180;
    }
    
    self.player.view.rotatePreference = preference;
    
    NSLog(@"rotate:%@ %d",@[@"X",@"Y",@"Z"][preference.type-1],(int)preference.degrees);
}

@end
