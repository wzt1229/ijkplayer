<div align="center">
  <img alt="ijkplayer" src="./primary-wide.png">
  <h1>ijkplayer</h1>
  <img src="https://github.com/debugly/ijkplayer/actions/workflows/apple.yml/badge.svg">
</div>

[![Stargazers repo roster for @debugly/ijkplayer](https://reporoster.com/stars/debugly/ijkplayer)](https://github.com/debugly/ijkplayer/stargazers)

ijk media player based on [ffplay](http://ffmpeg.org)

| Platform    | Archs                                   |
| ----------- | ----------------------------------------|
| iOS 11.0    | arm64、arm64_simulator、x86_64_simulator |
| macOS 10.11 | arm64、x86_64                            | 
| tvOS 12.0   | arm64、arm64_simulator、x86_64_simulator |

## My Build Environment

- macOS Sequoia(15.1)
- Xcode Version 16.1 (15F31d)
- cocoapods 1.16.1

## Latest Changes

- [CHANGELOG.md](CHANGELOG.md)

## Features

- Common
  - using FFmpeg 6.1.2
  - enabled ffmpeg all decoders and demuxers binary size is bigger [FFToolChain/ffconfig/module-full.sh](FFToolChain/ffconfig/module-full.sh)
  - workaround for some buggy online video
- iOS/macOS/tvOS
  - video-output: Metal 2/OpenGL 3.3
  - audio-output: AudioQueue, AudioUnit
  - hardware acceleration: auto choose VideoToolbox by default
  - subtitle:
    - text subtitle(srt/vtt/ass)/image subtitle(dvbsub/dvdsub/pgssub/idx+sub)
    - support intenal and external
    - text subtitle support force style
    - adjust position y and scale
  - 4k/HDR/HDR10/HDR10+/Dolby Vision Compatible
  - support Network or Local Blu-ray Disc/BDMV
  - set audio or subtitle extra delay
  - support dash demuxer

## Donate

- Donate to [debugly/ijkplayer](./Donate.md)
- 捐赠 [debugly/ijkplayer](./Donate.md)

## Installation

- integration via Swift Package Manger:

```
https://github.com/debugly/IJKMediaPlayer-SPM.git
```

- integration via Cocoapods:

```
pod "IJKMediaPlayerKit", :podspec => 'https://github.com/debugly/ijkplayer/releases/download/k0.12.0/IJKMediaPlayerKit.spec.json'
```

## Development

if you need change source code, you can use git add submodule, then use cocoapod integrate ijk into your workspace by development pod like examples.

how to run examples:

```
git clone https://github.com/debugly/ijkplayer.git ijkplayer
cd ijkplayer
git checkout -B latest k0.12.0
git submodule update --init

./FFToolChain/main.sh install -p macos -l 'ass ffmpeg'
./FFToolChain/main.sh install -p ios -l 'ass ffmpeg'
./FFToolChain/main.sh install -p tvos -l 'ass ffmpeg'

pod install --project-directory=./examples/macos
pod install --project-directory=./examples/ios
pod install --project-directory=./examples/tvos

# run iOS demo
open ./examples/ios/IJKMediaDemo.xcworkspace
# run macOS demo
open ./examples/macos/IJKMediaMacDemo.xcworkspace
# run tvOS demo
open ./examples/tvos/IJKMediaTVDemo.xcworkspace
```

if you want build your IJKMediaPlayerKit.framework, you need enter examples/{plat} folder, then exec `./build-framework.sh`

## Support (支持)

- Please do not send e-mail to me. Public technical discussion on github is preferred.
- 请尽量在 github 上公开讨论[技术问题](https://github.com/debugly/ijkplayer/issues)，不要以邮件方式私下询问，恕不一一回复。

## License

```
Copyright (c) 2017 Bilibili
Licensed under LGPLv2.1 or later
Copyright (c) 2022 Sohu
Licensed under LGPLv2.1 or later
```

ijkplayer required features are based on or derives from projects below:

- LGPL
  - [FFmpeg](http://git.videolan.org/?p=ffmpeg.git)
  - [libVLC](http://git.videolan.org/?p=vlc.git)
  - [kxmovie](https://github.com/kolyvan/kxmovie)
  - [soundtouch](http://www.surina.net/soundtouch/sourcecode.html)
- zlib license
  - [SDL](http://www.libsdl.org)
- BSD-style license
  - [libyuv](https://code.google.com/p/libyuv/)
- ISC license
  - [libyuv/source/x86inc.asm](https://code.google.com/p/libyuv/source/browse/trunk/source/x86inc.asm)

android/ijkplayer-exo is based on or derives from projects below:

- Apache License 2.0
  - [ExoPlayer](https://github.com/google/ExoPlayer)

android/example is based on or derives from projects below:

- GPL
  - [android-ndk-profiler](https://github.com/richq/android-ndk-profiler) (not included by default)

ios/IJKMediaDemo is based on or derives from projects below:

- Unknown license
  - [iOS7-BarcodeScanner](https://github.com/jpwiddy/iOS7-BarcodeScanner)

ijkplayer's build scripts are based on or derives from projects below:

- [gas-preprocessor](http://git.libav.org/?p=gas-preprocessor.git)
- [VideoLAN](http://git.videolan.org)
- [yixia/FFmpeg-Android](https://github.com/yixia/FFmpeg-Android)
- [kewlbear/FFmpeg-iOS-build-script](https://github.com/kewlbear/FFmpeg-iOS-build-script) 

## Commercial Use

ijkplayer is licensed under LGPLv2.1 or later, so itself is free for commercial use under LGPLv2.1 or later

But ijkplayer is also based on other different projects under various licenses, which I have no idea whether they are compatible to each other or to your product.

[IANAL](https://en.wikipedia.org/wiki/IANAL), you should always ask your lawyer for these stuffs before use it in your product.

## Icon

Primay icon was made by my friend 小星.




### 在局域网rtsp直播流场景下，播放延迟1~2s的问题
问题已解决，小结一下备忘：
1.播放器IJKFFOptions参数的设置
```
//丢帧阈值
mediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "framedrop", 30);
//视频帧率
mediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "fps", 30);
//环路滤波
mediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_CODEC, "skip_loop_filter", 48);
//设置无packet缓存
mediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "packet-buffering", 0);
mediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "fflags", "nobuffer");
//不限制拉流缓存大小
mediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "infbuf", 1);
//设置最大缓存数量
mediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "max-buffer-size", 1024);
//设置最小解码帧数
mediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "min-frames", 3);
//启动预加载
mediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "start-on-prepared", 1);
//设置探测包数量
mediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "probsize", "4096");
//设置分析流时长
mediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "analyzeduration", "2000000");
```

值得注意的是，ijkPlayer默认使用udp拉流，因为速度比较快。如果需要可靠且减少丢包，可以改为tcp协议：
```mediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "rtsp_transport", "tcp");```

另外，可以这样开启硬解码，如果打开硬解码失败，再自动切换到软解码：
```
mediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec", 0);
mediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec-auto-rotate", 0);
mediaPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec-handle-resolution-change", 0);
```

2.解码器设为零延时
大家应该听过编码器的零延时（zerolatency），但可能没听过解码器零延时。其实解码器内部默认会缓存几帧数据，用于后续关联帧的解码，大概是3-5帧。经过反复测试，发现解码器的缓存帧会带来100多ms延时。也就是说，假如能够去掉缓存帧，就可以减少100多ms的延时。而在avcodec.h文件的AVCodecContext结构体有一个参数（flags）用来设置解码器延时：
```
typedef struct AVCodecContext {
......
int flags;
......
}
```
为了去掉解码器缓存帧，我们可以把flags设置为CODEC_FLAG_LOW_DELAY。在初始化解码器时进行设置：
```
//set decoder as low deday
codec_ctx->flags |= CODEC_FLAG_LOW_DELAY;
```

通过以上1、2点的设置，我已经将延迟控制在200ms左右的范围，我们要求暂时没有那么高，效果是可以接受的。还有中间过程中遇到的其他解决方案，这里也备忘下
3.简书-暴走大牙：ijkplay播放直播流延时控制小结
https://www.jianshu.com/p/d6a5d8756eec
4.ff_ffplay文件，read_thread函数中，ret = av_read_frame(ic, pkt);后添加根据缓存大小，倍速播放的逻辑
```
//延迟优化：根据缓存大小设置倍速播放
            // 计算当前缓存大小，通过 audioq 和 videoq 的 size 来计算缓存大小
            int current_cache_size = is->audioq.size + is->videoq.size;
            if (current_cache_size > CACHE_THRESHOLD*3) {
                av_log(ffp, AV_LOG_INFO, "wzt read_thread trible speed play size=%d\n", current_cache_size);
                set_playback_rate(ffp, Trible_PLAYBACK_RATE);
            } else
            if (current_cache_size > CACHE_THRESHOLD) {
                av_log(ffp, AV_LOG_INFO, "wzt read_thread double speed play size=%d\n", current_cache_size);
                set_playback_rate(ffp, DOUBLE_PLAYBACK_RATE);
            } else {
                av_log(ffp, AV_LOG_INFO, "wzt read_thread normal speed play size%d\n", current_cache_size);
                set_playback_rate(ffp, NORMAL_PLAYBACK_RATE);
            }
```
4.直播内容保存为本地视频
https://www.jianshu.com/p/a346f93ddaff

                        
参考链接：https://blog.csdn.net/u011686167/article/details/85256101
https://www.jianshu.com/p/d6a5d8756eec


