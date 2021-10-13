#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "IJKMediaPlayback.h"
#import "IJKFFOptions.h"
#import "IJKFFMonitor.h"
#import "IJKFFMoviePlayerController.h"
#import "IJKMediaModule.h"
#import "IJKMediaPlayer.h"
#import "IJKNotificationManager.h"
#import "IJKKVOController.h"
#import "IJKSDLGLViewProtocol.h"
#import "IJKMediaPlayerKit.h"

FOUNDATION_EXPORT double IJKMediaPlayerKitVersionNumber;
FOUNDATION_EXPORT const unsigned char IJKMediaPlayerKitVersionString[];

