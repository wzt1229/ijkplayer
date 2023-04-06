//
//  MRRenderViewAuxProxy.m
//  IJKMediaMacDemo
//
//  Created by Reach Matt on 2023/4/6.
//  Copyright © 2023 IJK Mac. All rights reserved.
//

#import "MRRenderViewAuxProxy.h"
#import <IJKMediaPlayerKit/IJKInternalRenderView.h>

@interface MRRenderViewAuxProxy ()

@property (nonatomic, strong) NSMutableArray *renderViewArr;
@property (nonatomic, strong) NSLock *lock;

@end

@implementation MRRenderViewAuxProxy

@synthesize colorPreference = _colorPreference;

@synthesize darPreference = _darPreference;

@synthesize preventDisplay = _preventDisplay;

@synthesize rotatePreference = _rotatePreference;

@synthesize scalingMode = _scalingMode;

@synthesize subtitlePreference = _subtitlePreference;

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.renderViewArr = [NSMutableArray array];
        self.lock = [[NSLock alloc] init];
    }
    return self;
}

- (void)addRenderView:(NSView<IJKVideoRenderingProtocol> *)view
{
    if (view) {
        [self.lock lock];
        [self.renderViewArr addObject:view];
        [self.lock unlock];
    }
}

- (void)removeRenderView:(NSView<IJKVideoRenderingProtocol> *)view
{
    if (view) {
        [self.lock lock];
        [self.renderViewArr removeObject:view];
        [self.lock unlock];
    }
}

- (BOOL)displayAttach:(IJKOverlayAttach *)attach
{
    [self.lock lock];
    NSArray *renderViewArr = [self.renderViewArr copy];
    [self.lock unlock];
    [renderViewArr makeObjectsPerformSelector:_cmd withObject:attach];
    return YES;
}

- (NSString *)name
{
    return @"render-aux";
}

- (void)setNeedsRefreshCurrentPic
{
    [self.lock lock];
    NSArray *renderViewArr = [self.renderViewArr copy];
    [self.lock unlock];
    [renderViewArr makeObjectsPerformSelector:_cmd];
}

- (CGImageRef)snapshot:(IJKSDLSnapshotType)aType
{
    [self.lock lock];
    NSArray *renderViewArr = [self.renderViewArr copy];
    [self.lock unlock];
    NSView<IJKVideoRenderingProtocol> *view = [renderViewArr firstObject];
    return [view snapshot:aType];
}

- (void)setColorPreference:(IJKSDLColorConversionPreference)colorPreference
{
    _colorPreference = colorPreference;
    
    [self.lock lock];
    NSArray *renderViewArr = [self.renderViewArr copy];
    [self.lock unlock];
    
    NSValue *value = [NSValue valueWithBytes:&colorPreference objCType:@encode(IJKSDLColorConversionPreference)];
    [renderViewArr makeObjectsPerformSelector:_cmd withObject:value];
}

- (void)setDarPreference:(IJKSDLDARPreference)darPreference
{
    _darPreference = darPreference;
    
    [self.lock lock];
    NSArray *renderViewArr = [self.renderViewArr copy];
    [self.lock unlock];
    
    NSValue *value = [NSValue valueWithBytes:&darPreference objCType:@encode(IJKSDLDARPreference)];
    [renderViewArr makeObjectsPerformSelector:_cmd withObject:value];
}

- (void)setPreventDisplay:(BOOL)preventDisplay
{
    _preventDisplay = preventDisplay;
    
    [self.lock lock];
    NSArray *renderViewArr = [self.renderViewArr copy];
    [self.lock unlock];
    
    [renderViewArr makeObjectsPerformSelector:_cmd withObject:@(preventDisplay)];
}

- (void)setRotatePreference:(IJKSDLRotatePreference)rotatePreference
{
    _rotatePreference = rotatePreference;
    
    [self.lock lock];
    NSArray *renderViewArr = [self.renderViewArr copy];
    [self.lock unlock];
    
    NSValue *value = [NSValue valueWithBytes:&rotatePreference objCType:@encode(IJKSDLRotatePreference)];
    [renderViewArr makeObjectsPerformSelector:_cmd withObject:value];
}

- (void)setScalingMode:(IJKMPMovieScalingMode)scalingMode
{
    _scalingMode = scalingMode;
    
    [self.lock lock];
    NSArray *renderViewArr = [self.renderViewArr copy];
    [self.lock unlock];
    [renderViewArr makeObjectsPerformSelector:_cmd withObject:@(scalingMode)];
}

- (void)setSubtitlePreference:(IJKSDLSubtitlePreference)subtitlePreference
{
    _subtitlePreference = subtitlePreference;
    
    [self.lock lock];
    NSArray *renderViewArr = [self.renderViewArr copy];
    [self.lock unlock];
    
    NSValue *value = [NSValue valueWithBytes:&subtitlePreference objCType:@encode(IJKSDLSubtitlePreference)];
    
    [renderViewArr makeObjectsPerformSelector:_cmd withObject:value];
}

@end
