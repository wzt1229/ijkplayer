//
//  IJKMetalAttach.m
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/12/5.
//

#import "IJKMetalAttach.h"

@implementation IJKMetalAttach

- (void)dealloc
{
    if (self.currentVideoPic) {
        CVPixelBufferRelease(self.currentVideoPic);
        self.currentVideoPic = NULL;
    }
    
    if (self.currentSubtitle) {
        CVPixelBufferRelease(self.currentSubtitle);
        self.currentSubtitle = NULL;
    }
}

@end
