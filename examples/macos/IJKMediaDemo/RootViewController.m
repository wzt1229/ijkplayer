//
//  RootViewController.m
//  IJKMediaMacDemo
//
//  Created by Matt Reach on 2021/11/1.
//  Copyright © 2021 IJK Mac. All rights reserved.
//

#import "RootViewController.h"
#import "MRDragView.h"
#import "MRUtil+SystemPanel.h"
#import <IJKMediaPlayerKit/IJKMediaPlayerKit.h>
#import <Carbon/Carbon.h>
#import "NSFileManager+Sandbox.h"
#import "SHBaseView.h"
#import <Quartz/Quartz.h>
#import "MRGlobalNotification.h"

#ifndef __MRWS__
#define __MRWS__

#ifndef __weakSelf__
#define __weakSelf__  __weak    typeof(self)weakSelf = self;
#endif

#ifndef __strongSelf__
#define __strongSelf__ __strong typeof(weakSelf)self = weakSelf;
#endif

#define __weakObj(obj)   __weak   typeof(obj)weak##obj = obj;
#define __strongObj(obj) __strong typeof(weak##obj)obj = weak##obj;

#endif

@interface RootViewController ()<MRDragViewDelegate,SHBaseViewDelegate>

@property (weak) IBOutlet NSView *ctrlView;
@property (weak) IBOutlet NSLayoutConstraint *ctrlViewBottomCons;
@property (assign) BOOL isCtrlViewAnimating;

@property (strong) IJKFFMoviePlayerController * player;
@property (weak) IBOutlet NSTextField *playedTimeLb;
@property (nonatomic, strong) NSMutableArray *playList;
@property (copy) NSURL *playingUrl;
@property (weak) NSTimer *tickTimer;
@property (weak) IBOutlet NSTextField *urlInput;
@property (weak) IBOutlet NSButton *playCtrlBtn;
@property (weak) IBOutlet NSPopUpButton *subtitlePopUpBtn;
@property (weak) IBOutlet NSPopUpButton *audioPopUpBtn;

@property (weak) NSTrackingArea *trackingArea;

//for cocoa binding begin
@property (assign) float subtitleFontSize;
@property (assign) float subtitleDelay;
@property (assign) float subtitleMargin;

@property (assign) float brightness;
@property (assign) float saturation;
@property (assign) float contrast;

@property (assign) BOOL useVideoToolBox;
@property (assign) int useAsyncVTB;
@property (copy) NSString *fcc;
@property (assign) int snapshot;
//for cocoa binding end

@property (weak) id eventMonitor;

@end

@implementation RootViewController

- (void)dealloc
{
    [NSEvent removeMonitor:self.eventMonitor];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
    
    //for debug
    //[self.view setWantsLayer:YES];
    //self.view.layer.backgroundColor = [[NSColor redColor] CGColor];
    
    [self.ctrlView setWantsLayer:YES];
    //self.ctrlView.layer.backgroundColor = [[NSColor colorWithWhite:0.2 alpha:0.5] CGColor];
    self.ctrlView.layer.cornerRadius = 4;
    self.ctrlView.layer.masksToBounds = YES;

    self.subtitleFontSize = 25;
    self.subtitleMargin = 0.7;
    self.useVideoToolBox = YES;
    self.fcc = @"fcc-_es2";
    self.snapshot = 3;
    [self onReset:nil];
    
    NSArray *bundleNameArr = @[@"5003509-693880-3.m3u8",@"996747-5277368-31.m3u8"];
    
    for (NSString *fileName in bundleNameArr) {
        
        NSString *localM3u8 = [[NSBundle mainBundle] pathForResource:[fileName stringByDeletingPathExtension] ofType:[fileName pathExtension]];
        [self.playList addObject:[NSURL fileURLWithPath:localM3u8]];
    }
    [self.playList addObject:[NSURL URLWithString:@"https://data.vod.itc.cn/?new=/73/15/oFed4wzSTZe8HPqHZ8aF7J.mp4&vid=77972299&plat=14&mkey=XhSpuZUl_JtNVIuSKCB05MuFBiqUP7rB&ch=null&user=api&qd=8001&cv=3.13&uid=F45C89AE5BC3&ca=2&pg=5&pt=1&prod=ifox"]];
    
    if ([self.playList count] > 0) {
        self.urlInput.placeholderString = [[self.playList firstObject] description];
    } else {
        self.urlInput.placeholderString = @"请输入播放地址或者拖入视频播放";
    }
    
    if ([self.view isKindOfClass:[SHBaseView class]]) {
        SHBaseView *baseView = (SHBaseView *)self.view;
        baseView.delegate = self;
        baseView.needTracking = YES;
    }
    
    __weakSelf__
    self.eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent * _Nullable(NSEvent * _Nonnull theEvent) {
        __strongSelf__
        if ([theEvent keyCode] == kVK_ANSI_Period && theEvent.modifierFlags & NSEventModifierFlagCommand){
            [self stopPlay:nil];
        }
        return theEvent;
    }];
    
    OBSERVER_NOTIFICATION(self, _playExplorerMovies:,kPlayExplorerMovieNotificationName_G, nil);
}

- (void)_playExplorerMovies:(NSNotification *)notifi
{
    NSDictionary *info = notifi.userInfo;
    NSArray *movies = info[@"obj"];
    
    if ([movies count] > 0) {
        // 开始播放
        [self appendToPlayList:movies];
    }
}

- (void)baseView:(SHBaseView *)baseView mouseEntered:(NSEvent *)event
{
    [self showCtrlView];
}

- (void)baseView:(SHBaseView *)baseView mouseMoved:(NSEvent *)event
{
    [self showCtrlView];
}

- (void)baseView:(SHBaseView *)baseView mouseExited:(NSEvent *)event
{
    [self hideCtrlView];
}

- (void)switchCtrlView:(BOOL)wantShow
{
    float constant = wantShow ? 0 : - self.ctrlView.bounds.size.height;
    
    if (self.ctrlViewBottomCons.constant == constant) {
        return;
    }
    
    if (self.isCtrlViewAnimating) {
        return;
    }
    self.isCtrlViewAnimating = YES;
    
    __weakSelf__
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        context.duration = 0.35;
        context.allowsImplicitAnimation = YES;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        __strongSelf__
        self.ctrlViewBottomCons.animator.constant = wantShow ? 0 : - self.ctrlView.bounds.size.height;
    } completionHandler:^{
        __strongSelf__
        self.isCtrlViewAnimating = NO;
    }];
}

- (void)showCtrlView
{
    [self switchCtrlView:YES];
}

- (void)hideCtrlView
{
    [self switchCtrlView:NO];
}

- (void)toggleCtrlViewShow
{
    BOOL isShowing = self.ctrlView.frame.origin.y >= 0;
    [self switchCtrlView:!isShowing];
}

- (void)keyDown:(NSEvent *)event
{
    if ([event keyCode] == kVK_LeftArrow && event.modifierFlags & NSEventModifierFlagCommand) {
        [self playPrevious:nil];
    } else if ([event keyCode] == kVK_RightArrow && event.modifierFlags & NSEventModifierFlagCommand) {
        [self playNext:nil];
    } else if ([event keyCode] == kVK_ANSI_B && event.modifierFlags & NSEventModifierFlagCommand) {
        
        [self toggleCtrlViewShow];
        
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
    } else if ([event keyCode] == kVK_ANSI_S && event.modifierFlags & NSEventModifierFlagCommand) {
        [self onCaptureShot:nil];
    } else if ([event keyCode] == kVK_ANSI_Period && event.modifierFlags & NSEventModifierFlagCommand) {
        [self stopPlay:nil];
    } else {
        NSLog(@"0x%X",[event keyCode]);
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
    
//    [options setPlayerOptionValue:@"fcc-bgra"        forKey:@"overlay-format"];
//    [options setPlayerOptionValue:@"fcc-bgr0"        forKey:@"overlay-format"];
//    [options setPlayerOptionValue:@"fcc-argb"        forKey:@"overlay-format"];
//    [options setPlayerOptionValue:@"fcc-0rgb"        forKey:@"overlay-format"];
//    [options setPlayerOptionValue:@"fcc-uyvy"        forKey:@"overlay-format"];
//    [options setPlayerOptionValue:@"fcc-i420"        forKey:@"overlay-format"];
//    [options setPlayerOptionValue:@"fcc-nv12"        forKey:@"overlay-format"];
    
    [options setPlayerOptionValue:self.fcc forKey:@"overlay-format"];
    [options setPlayerOptionIntValue:self.useVideoToolBox forKey:@"videotoolbox"];
    [options setPlayerOptionIntValue:self.useAsyncVTB forKey:@"videotoolbox-async"];
    [options setPlayerOptionIntValue:3840 forKey:@"videotoolbox-max-frame-width"];
    
    [self stopPlay:nil];
    [NSDocumentController.sharedDocumentController noteNewRecentDocumentURL:url];
    self.player = [[IJKFFMoviePlayerController alloc] initWithContentURL:url withOptions:options];
    CGRect rect = self.view.frame;
    rect.origin = CGPointZero;
    self.player.view.frame = rect;
    
    NSView <IJKSDLGLViewProtocol>*playerView = self.player.view;
    playerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.view addSubview:playerView positioned:NSWindowBelow relativeTo:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:IJKMPMediaPlaybackIsPreparedToPlayDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ijkPlayerPreparedToPlay:) name:IJKMPMediaPlaybackIsPreparedToPlayDidChangeNotification object:self.player];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:IJKMPMoviePlayerSelectedStreamDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ijkPlayerPreparedToPlay:) name:IJKMPMoviePlayerSelectedStreamDidChangeNotification object:self.player];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:IJKMPMoviePlayerPlaybackDidFinishNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ijkPlayerDidFinish:) name:IJKMPMoviePlayerPlaybackDidFinishNotification object:self.player];
    
    self.player.scalingMode = IJKMPMovieScalingModeAspectFit;
    self.player.shouldAutoplay = YES;
}

- (void)ijkPlayerDidFinish:(NSNotification *)notifi
{
    if (self.player == notifi.object) {
        int reason = [notifi.userInfo[IJKMPMoviePlayerPlaybackDidFinishReasonUserInfoKey] intValue];
        if (IJKMPMovieFinishReasonPlaybackError == reason) {
            int errCode = [notifi.userInfo[@"error"] intValue];
            NSLog(@"播放出错:%d",errCode);
            [self.player stop];
        } else if (IJKMPMovieFinishReasonPlaybackEnded == reason) {
            NSLog(@"播放结束");
            [self playNext:nil];
        }
    }
}

- (void)ijkPlayerPreparedToPlay:(NSNotification *)notifi
{
    if (self.player.isPreparedToPlay) {
        
        NSDictionary *dic = self.player.monitor.mediaMeta;
        
        [self.subtitlePopUpBtn removeAllItems];
        NSString *currentTitle = @"选择字幕";
        [self.subtitlePopUpBtn addItemWithTitle:currentTitle];
        
        [self.audioPopUpBtn removeAllItems];
        NSString *currentAudio = @"选择音轨";
        [self.audioPopUpBtn addItemWithTitle:currentAudio];
        
        for (NSDictionary *stream in dic[kk_IJKM_KEY_STREAMS]) {
            NSString *type = stream[k_IJKM_KEY_TYPE];
            int streamIdx = [stream[k_IJKM_KEY_STREAM_IDX] intValue];
            if ([type isEqualToString:k_IJKM_VAL_TYPE__SUBTITLE]) {
                NSString *title = stream[k_IJKM_KEY_TITLE];
                if (title.length == 0) {
                    title = stream[k_IJKM_KEY_LANGUAGE];
                }
                if (title.length == 0) {
                    title = @"未知";
                }
                title = [NSString stringWithFormat:@"%@-%d",title,streamIdx];
                if ([dic[k_IJKM_VAL_TYPE__SUBTITLE] intValue] == streamIdx) {
                    currentTitle = title;
                }
                [self.subtitlePopUpBtn addItemWithTitle:title];
            } else if ([type isEqualToString:k_IJKM_VAL_TYPE__AUDIO]) {
                NSString *title = stream[k_IJKM_KEY_TITLE];
                if (title.length == 0) {
                    title = stream[k_IJKM_KEY_LANGUAGE];
                }
                if (title.length == 0) {
                    title = @"未知";
                }
                title = [NSString stringWithFormat:@"%@-%d",title,streamIdx];
                if ([dic[k_IJKM_VAL_TYPE__AUDIO] intValue] == streamIdx) {
                    currentAudio = title;
                }
                [self.audioPopUpBtn addItemWithTitle:title];
            }
        }
        [self.subtitlePopUpBtn selectItemWithTitle:currentTitle];
        [self.audioPopUpBtn selectItemWithTitle:currentAudio];
    }
}

- (void)playURL:(NSURL *)url
{
    [self perpareIJKPlayer:url];
    self.playingUrl = url;
    self.urlInput.stringValue = [url isFileURL] ? [url path] : [url absoluteString];
    self.urlInput.placeholderString = @"";
    NSString *title = [url isFileURL] ? [url path] : [[url resourceSpecifier] lastPathComponent];
    [self.view.window setTitle:title];
    
    [self onReset:nil];
    
    IJKSDLSubtitlePreference p = self.player.view.subtitlePreference;
    p.bottomMargin = self.subtitleMargin;
    self.player.view.subtitlePreference = p;
    
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

- (void)appendToPlayList:(NSArray *)bookmarkArr
{
    NSMutableArray *videos = [NSMutableArray array];
    NSMutableArray *subtitles = [NSMutableArray array];
    
    for (NSDictionary *dic in bookmarkArr) {
        NSURL *url = dic[@"url"];
        
        if ([self existTaskForUrl:url]) {
            continue;
        }
        if ([dic[@"type"] intValue] == 0) {
            [videos addObject:url];
        } else if ([dic[@"type"] intValue] == 1) {
            [subtitles addObject:url];
        } else {
            NSAssert(NO, @"没有处理的文件:%@",url);
        }
    }
    
    //拖进来新的视频时，清理老的视频列表
    if ([videos count] > 0) {
        [self.playList addObjectsFromArray:videos];
        [self playFirstIfNeed];
    }
    
    for (NSURL *url in subtitles) {
        [self.player loadSubtitleFile:[url path]];
    }
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
                NSArray *dicArr = [MRUtil scanFolderWithPath:dir filter:[MRUtil acceptMediaType]];
                if ([dicArr count] > 0) {
                    [bookmarkArr addObjectsFromArray:dicArr];
                }
            } else {
                NSString *pathExtension = [[url pathExtension] lowercaseString];
                if ([[MRUtil acceptMediaType] containsObject:pathExtension]) {
                    NSDictionary *dic = [MRUtil makeBookmarkWithURL:url];
                    [bookmarkArr addObject:dic];
                }
            }
        }
    }
    //拖拽播放时清空原先的列表
    [self.playList removeAllObjects];
    [self appendToPlayList:bookmarkArr];
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
                   NSArray *dicArr = [MRUtil scanFolderWithPath:dir filter:[MRUtil acceptMediaType]];
                    if ([dicArr count] > 0) {
                        return NSDragOperationCopy;
                    }
                } else {
                    NSString *pathExtension = [[url pathExtension] lowercaseString];
                    if ([[MRUtil acceptMediaType] containsObject:pathExtension]) {
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

#pragma mark - 播放控制

- (IBAction)onPlay:(NSButton *)sender
{
    if (self.urlInput.stringValue.length > 0) {
        NSUInteger idx = [self.playList indexOfObject:self.playingUrl];
        if (idx == NSNotFound) {
            idx = -1;
        }
        idx ++;
        NSURL *url = [NSURL URLWithString:self.urlInput.stringValue];
        self.playList[idx] = url;
        [self playURL:url];
    } else {
        [self playNext:nil];
    }
}

- (IBAction)stopPlay:(NSButton *)sender
{
    [self.player.view removeFromSuperview];
    [self.player stop];
    [self.player shutdown];
    self.player = nil;
    self.playingUrl = nil;
    self.urlInput.stringValue = @"";
    [self.view.window setTitle:@""];
    if ([self.playList count] > 0) {
        self.urlInput.placeholderString = [[self.playList firstObject] description];
    } else {
        self.urlInput.placeholderString = @"请输入播放地址或者拖入视频播放";
    }
}

- (IBAction)pauseOrPlay:(NSButton *)sender
{
    if ([self.playCtrlBtn.title isEqualToString:@"Pause"]) {
        [self.playCtrlBtn setTitle:@"Play"];
        [self.player pause];
    } else {
        [self.playCtrlBtn setTitle:@"Pause"];
        [self.player play];
    }
}

- (void)playPrevious:(NSButton *)sender
{
    if ([self.playList count] == 0) {
        return;
    }
    
    NSUInteger idx = [self.playList indexOfObject:self.playingUrl];
    if (idx == NSNotFound) {
        idx = 0;
    } else if (idx <= 0) {
        idx = [self.playList count] - 1;
    } else {
        idx --;
    }
    
    NSURL *url = self.playList[idx];
    [self playURL:url];
}

- (IBAction)playNext:(NSButton *)sender
{
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

- (IBAction)fastRewind:(NSButton *)sender
{
    float cp = self.player.currentPlaybackTime;
    cp -= 50;
    if (cp < 0) {
        cp = 0;
    }
    self.player.currentPlaybackTime = cp;
}

- (IBAction)fastForward:(NSButton *)sender
{
    float cp = self.player.currentPlaybackTime;
    cp += 50;
    if (cp < 0) {
        cp = 0;
    }
    self.player.currentPlaybackTime = cp;
}

#pragma mark 倍速设置

- (IBAction)updateSpeed:(NSButton *)sender
{
    NSInteger tag = sender.tag;
    float speed = tag / 100.0;
    self.player.playbackRate = speed;
}

#pragma mark 字幕设置

- (IBAction)onChangeSubtitleColor:(NSPopUpButton *)sender
{
    NSMenuItem *item = [sender selectedItem];
    int bgrValue = (int)item.tag;
    IJKSDLSubtitlePreference p = self.player.view.subtitlePreference;
    p.color = bgrValue;
    self.player.view.subtitlePreference = p;
    [self.player invalidateSubtitleEffect];
}

- (IBAction)onChangeSubtitleSize:(NSStepper *)sender
{
    IJKSDLSubtitlePreference p = self.player.view.subtitlePreference;
    p.fontSize = sender.intValue;
    self.player.view.subtitlePreference = p;
    [self.player invalidateSubtitleEffect];
}

- (IBAction)onSelectSubtitle:(NSPopUpButton*)sender
{
    NSString *title = sender.selectedItem.title;
    NSArray *items = [title componentsSeparatedByString:@"-"];
    if ([items count] == 2) {
        int idx = [[items lastObject] intValue];
        NSLog(@"SelectSubtitle:%d",idx);
        [self.player exchangeSelectedStream:idx];
    } else {
        [self.player closeCurrentStream:k_IJKM_VAL_TYPE__SUBTITLE];
    }
}

- (IBAction)onChangeSubtitleDelay:(NSStepper *)sender
{
    float delay = sender.floatValue;
    [self.player updateSubtitleExtraDelay:delay];
}

- (IBAction)onChangeSubtitleBottomMargin:(NSSlider *)sender
{
    IJKSDLSubtitlePreference p = self.player.view.subtitlePreference;
    p.bottomMargin = sender.floatValue;
    self.player.view.subtitlePreference = p;
    [self.player invalidateSubtitleEffect];
}

#pragma mark 画面设置

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
        preference.degrees = -90;
    } else if (item.tag == 2) {
        preference.type = IJKSDLRotateZ;
        preference.degrees = -180;
    } else if (item.tag == 3) {
        preference.type = IJKSDLRotateZ;
        preference.degrees = -270;
    } else if (item.tag == 4) {
        preference.type = IJKSDLRotateY;
        preference.degrees = 180;
    } else if (item.tag == 5) {
        preference.type = IJKSDLRotateX;
        preference.degrees = 180;
    }
    
    self.player.view.rotatePreference = preference;
    
    NSLog(@"rotate:%@ %d",@[@"None",@"X",@"Y",@"Z"][preference.type],(int)preference.degrees);
}

- (IBAction)onCaptureShot:(id)sender
{
    CGImageRef img = [self.player.view snapshot:self.snapshot];
    if (img) {
        //,[self.playingUrl lastPathComponent]
        NSString * path = [NSFileManager mr_DirWithType:NSPicturesDirectory WithPathComponents:@[@"ijkPro"]];
        NSString *fileName = [NSString stringWithFormat:@"%ld.jpg",(long)CFAbsoluteTimeGetCurrent()];
        NSString *filePath = [path stringByAppendingPathComponent:fileName];
        NSLog(@"截屏:%@",filePath);
        [MRUtil saveImageToFile:img path:filePath];
    }
}

- (IBAction)onChangeBSC:(NSSlider *)sender
{
    if (sender.tag == 1) {
        self.brightness = sender.floatValue;
    } else if (sender.tag == 2) {
        self.saturation = sender.floatValue;
    } else if (sender.tag == 3) {
        self.contrast = sender.floatValue;
    }
    
    IJKSDLColorConversionPreference colorPreference = self.player.view.colorPreference;
    colorPreference.brightness = self.brightness;//B
    colorPreference.saturation = self.saturation;//S
    colorPreference.contrast = self.contrast;//C
    self.player.view.colorPreference = colorPreference;
}

- (IBAction)onChangeDAR:(NSPopUpButton *)sender
{
    int dar_num = 1;
    int dar_den = 1;
    if ([sender.titleOfSelectedItem isEqual:@"还原"]) {
        dar_num = dar_den = 0;
    }
    else {
        const char* str = sender.titleOfSelectedItem.UTF8String;
        sscanf(str, "%d:%d", &dar_num, &dar_den);
    }
    self.player.view.darPreference = (IJKSDLDARPreference){dar_num,dar_den};
}

- (IBAction)onReset:(NSButton *)sender
{
    if (sender.tag == 1) {
        self.brightness = 1.0;
    } else if (sender.tag == 2) {
        self.saturation = 1.0;
    } else if (sender.tag == 3) {
        self.contrast = 1.0;
    } else {
        self.brightness = 1.0;
        self.saturation = 1.0;
        self.contrast = 1.0;
    }
    
    [self onChangeBSC:nil];
}

#pragma mark 音轨设置

- (IBAction)onSelectAudioTrack:(NSPopUpButton*)sender
{
    NSString *title = sender.selectedItem.title;
    NSArray *items = [title componentsSeparatedByString:@"-"];
    if ([items count] == 2) {
        int idx = [[items lastObject] intValue];
        NSLog(@"SelectAudioTrack:%d",idx);
        [self.player exchangeSelectedStream:idx];
    } else {
        [self.player closeCurrentStream:k_IJKM_VAL_TYPE__AUDIO];
    }
}

#pragma mark 解码设置

- (IBAction)onSelectFCC:(NSPopUpButton*)sender
{
    NSString *title = sender.selectedItem.title;
    NSString *fcc = [@"fcc-" stringByAppendingString:title];
    self.fcc = fcc;
}

@end
