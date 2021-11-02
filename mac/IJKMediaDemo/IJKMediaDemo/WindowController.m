//
//  WindowController.m
//  IJKMediaMacDemo
//
//  Created by Matt Reach on 2021/11/2.
//  Copyright © 2021 IJK Mac. All rights reserved.
//

#import "WindowController.h"

@interface WindowController ()

@end

@implementation WindowController

- (void)windowDidLoad {
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

- (void)keyDown:(NSEvent *)event
{
    if (self.window.contentViewController) {
        if ([self.window.contentViewController respondsToSelector:@selector(keyDown:)]) {
            [self.window.contentViewController keyDown:event];
            return;
        }
    }
    
    return [super keyDown:event];
}

@end
