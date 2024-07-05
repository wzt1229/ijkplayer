/*
 * IJKSDLThread.m
 *
 * Copyright (c) 2013-2014 Bilibili
 * Copyright (c) 2013-2014 Zhang Rui <bbcallen@gmail.com>
 *
 * This file is part of ijkPlayer.
 *
 * ijkPlayer is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * ijkPlayer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with ijkPlayer; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#import "IJKSDLThread.h"

@interface IJKSDLThread ()

@property (nonatomic, strong) NSThread *thread;
@property (nonatomic, assign) BOOL shouldStop;

@end

@implementation IJKSDLThread

- (void)dealloc
{
    
}

- (instancetype)initWithName:(NSString *)name
{
    self = [super init];
    if (self) {
        self.name = name;
    }
    return self;
}

- (void)start
{
    if (!_thread) {
        _shouldStop = NO;
        _thread = [[NSThread alloc] initWithTarget:self selector:@selector(main) object:nil];
        if (self.name) {
            [_thread setName:self.name];
        } else {
            [_thread setName:[NSString stringWithFormat:@"%@",NSStringFromClass([self class])]];
        }
        [_thread start];
    }
}

- (void)main
{
    [[NSRunLoop currentRunLoop] addPort:[[NSPort alloc] init] forMode:NSDefaultRunLoopMode];

    while (!self.shouldStop) {
        BOOL r = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }
    
    CFRunLoopStop(CFRunLoopGetCurrent());
}

- (void)stop
{
    self.shouldStop = YES;
    //just let runloop runMode:beforeDate: return
    [self performSelector:@selector(description) onThread:_thread withObject:nil waitUntilDone:YES];
}

- (void)performSelector:(SEL)aSelector
             withTarget:(nullable id)target
             withObject:(nullable id)arg
          waitUntilDone:(BOOL)wait
{
    if (self.shouldStop) {
        return;
    }
    [target performSelector:aSelector
                 onThread:_thread
               withObject:arg
            waitUntilDone:wait];
}

@end
