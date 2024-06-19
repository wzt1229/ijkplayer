# ijkplayer

| Platform    | Archs                                  | Build Status                                                                                                                                                            |
| ----------- | -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| iOS 11.0    | arm64、arm64_simulator、x86_64_simulator | [![Build Status](https://github.com/debugly/ijkplayer/actions/workflows/apple.yml/badge.svg)](https://github.com/debugly/ijkplayer/actions/workflows/apple.yml) |
| macOS 10.11 | arm64、x86_64                           | [![Build Status](https://github.com/debugly/ijkplayer/actions/workflows/apple.yml/badge.svg)](https://github.com/debugly/ijkplayer/actions/workflows/apple.yml) |
| tvOS 12.0   | arm64、arm64_simulator、x86_64_simulator | [![Build Status](https://github.com/debugly/ijkplayer/actions/workflows/apple.yml/badge.svg)](https://github.com/debugly/ijkplayer/actions/workflows/apple.yml) |

Video player based on [ffplay](http://ffmpeg.org)

### My Build Environment

- macOS Sonoma(14.3)
- Xcode Version 15.4 (15F31d)
- cocoapods 1.15.2

### Latest Changes

- [CHANGELOG.md](CHANGELOG.md)

### Features

- Common
  - remove rarely used ffmpeg components to reduce binary size [config/module-lite.sh](config/module-lite.sh)
  - workaround for some buggy online video.
- iOS/macOS/tvOS
  - api: [MediaPlayer.framework-like](IJKMediaPlayerKit/IJKMediaPlayback.h)
  - video-output: Metal 2/OpenGL ES 2.0/OpenGL 3.3
  - audio-output: AudioQueue, AudioUnit
  - hw-decoder: auto use VideoToolbox accel by default
  - subtitle: use libass render text to bitmap then use OpenGL/Metal generate texture

### ON-PLAN

- upgrade FFmpeg to 6.x
- exchange video resolution gapless

### Installation

install use cocoapod:

```
pod "IJKMediaPlayerKit", :podspec => 'https://github.com/debugly/ijkplayer/releases/download/k0.11.2/IJKMediaPlayerKit.spec.json'
```

### Development

if you need change source code, you can use git add submodule, then use cocoapod integrate ijk into your workspace by development pod.

```
git clone https://github.com/debugly/ijkplayer.git ijkplayer
cd ijkplayer
git checkout -B latest k0.11.2

./shell/install-pre-any.sh all
pod install --project-directory=./examples/macos
pod install --project-directory=./examples/ios
pod install --project-directory=./examples/tvos

# run iOS demo
open ./examples/macos/IJKMediaDemo.xcworkspace
# run macOS demo
open ./examples/macos/IJKMediaMacDemo.xcworkspace
# run tvOS demo
open ./examples/macos/IJKMediaTVDemo.xcworkspace
```

if you want build your IJKMediaPlayerKit.framework, you need enter examples/{plat} folder, then exec `./build-framework.sh`

### Support (支持)

- Please do not send e-mail to me. Public technical discussion on github is preferred.
- 请尽量在 github 上公开讨论[技术问题](https://github.com/debugly/ijkplayer/issues)，不要以邮件方式私下询问，恕不一一回复。

### License

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

### Commercial Use

ijkplayer is licensed under LGPLv2.1 or later, so itself is free for commercial use under LGPLv2.1 or later

But ijkplayer is also based on other different projects under various licenses, which I have no idea whether they are compatible to each other or to your product.

[IANAL](https://en.wikipedia.org/wiki/IANAL), you should always ask your lawyer for these stuffs before use it in your product.