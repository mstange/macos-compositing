//
//  OpenGLContextView.m
//  IOSurface compositing
//
//  Created by Markus Stange on 2017-12-21.
//  Copyright © 2017 Markus Stange. All rights reserved.
//

#import "OpenGLContextView.h"

@interface NSOpenGLContext(ExtraCreatorFunctions)
+ (instancetype)contextForWindow;
@end

@implementation NSOpenGLContext(ExtraCreatorFunctions)

+ (instancetype)contextForWindow
{
    NSOpenGLPixelFormatAttribute attribs[] = {
        NSOpenGLPFAAllowOfflineRenderers,
        NSOpenGLPFADoubleBuffer,
        (NSOpenGLPixelFormatAttribute)nil
    };
    NSOpenGLPixelFormat* pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attribs];
    NSOpenGLContext* ctx = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:nil];
    [pixelFormat release];
    GLint swapInt = 1;
    [ctx setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];
    GLint opaque = 0;
    [ctx setValues:&opaque forParameter:NSOpenGLCPSurfaceOpacity];
    return [ctx autorelease];
}

@end

@implementation OpenGLContextView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    
    self.wantsBestResolutionOpenGLSurface = YES;

    compositingThread_ = dispatch_queue_create("org.mozilla.CompositingThread", NULL);
    glContext_ = [[NSOpenGLContext contextForWindow] retain];
    dispatch_sync(compositingThread_, ^{
        [glContext_ makeCurrentContext];
        glDrawer_ = [[OpenGLDrawer alloc] init];
    });
    animator_ = nil;
    return self;
}

- (void)viewDidMoveToWindow
{
    if (![self window]) {
        return;
    }

    [glContext_ setView:self];
    animator_ = [[VSyncListener alloc] initWithCallback:^{
        dispatch_async(compositingThread_, ^{
            [glContext_ makeCurrentContext];
            [glDrawer_ drawToFBO:0 width:displayWidth_ height:displayHeight_ angle:CurrentAngle()];
            [glContext_ flushBuffer];
        });
    }];
    NSLog(@"subscribing to NSViewGlobalFrameDidChangeNotification");
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_surfaceNeedsUpdate:)
                                                 name:NSViewGlobalFrameDidChangeNotification
                                               object:self];
    [self reshape];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
    if (newWindow) {
        return;
    }
    
    [animator_ release];
    animator_ = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSViewGlobalFrameDidChangeNotification
                                                  object:self];
}

- (void)_surfaceNeedsUpdate:(NSNotification*)notification
{
    NSLog(@"surfaceNeedsUpdate: %@", notification);
    [self reshape];
}

static float CurrentAngle() { return fmod(CFAbsoluteTimeGetCurrent(), 1.0) * 360; }

- (void)reshape
{
    NSLog(@"reshape");
    NSSize backingSize = [self convertSizeToBacking:self.bounds.size];
    displayWidth_ = (int)backingSize.width;
    displayHeight_ = (int)backingSize.height;
    dispatch_sync(compositingThread_, ^{
        [glContext_ update];
        NSLog(@"drawing to view: %@", self);
        [glContext_ makeCurrentContext];
        [glDrawer_ drawToFBO:0 width:displayWidth_ height:displayHeight_ angle:CurrentAngle()];
        [glContext_ flushBuffer];
    });
}

- (void)dealloc
{
    dispatch_sync(compositingThread_, ^{
        [glContext_ makeCurrentContext];
        [glDrawer_ release];
    });
    dispatch_release(compositingThread_);
    [glContext_ release];
    [super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect {
    NSSize backingSize = [self convertSizeToBacking:self.bounds.size];
    if (displayWidth_ != (int)backingSize.width ||
        displayHeight_ != (int)backingSize.height) {
        NSLog(@"calling reshape from drawRect");
        [self reshape];
    } else {
        dispatch_sync(compositingThread_, ^{
            NSLog(@"drawing to view inside drawRect: %@", self);
            [glContext_ makeCurrentContext];
            [glDrawer_ drawToFBO:0 width:displayWidth_ height:displayHeight_ angle:CurrentAngle()];
            [glContext_ flushBuffer];
        });
    }
//    NSGradient* gradient = [[NSGradient alloc] initWithColors:@[NSColor.whiteColor, NSColor.blackColor]];
//    [gradient drawInRect:self.bounds angle:-45];
//    [gradient release];
}

@end
