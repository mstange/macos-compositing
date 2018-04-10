//
//  OpenGLContextView.m
//  IOSurface compositing
//
//  Created by Markus Stange on 2017-12-21.
//  Copyright © 2017 Markus Stange. All rights reserved.
//

#import "OpenGLContextView.h"
#import <IOSurface/IOSurfaceObjC.h>
#import <QuartzCore/QuartzCore.h>

// Private CALayer API.
@interface CALayer (Private)
- (void)setContentsChanged;
@end

static IOSurfaceRef
CreateTransparentIOSurface(int aWidth, int aHeight)
{
    IOSurfaceRef surf = IOSurfaceCreate((CFDictionaryRef)@{
                                                           IOSurfacePropertyKeyWidth: [NSNumber numberWithInt:aWidth],
                                                           IOSurfacePropertyKeyHeight: [NSNumber numberWithInt:aHeight],
                                                           IOSurfacePropertyKeyBytesPerElement: [NSNumber numberWithInt:4],
                                                           IOSurfacePropertyKeyPixelFormat: [NSNumber numberWithInt:'BGRA'],
                                                           (NSString*)kIOSurfaceIsGlobal: [NSNumber numberWithBool:YES]
                                                           });
    NSLog(@"IOSurface: %@", surf);

    IOReturn rv = IOSurfaceLock(surf, 0, nil);
    if (rv != 0) {
        NSLog(@"locking the IOSurface failed");
        return nil;
    }
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(IOSurfaceGetBaseAddress(surf),
                                             IOSurfaceGetWidth(surf), IOSurfaceGetHeight(surf),
                                             8, IOSurfaceGetBytesPerRow(surf),
                                             rgb, kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst);
    NSLog(@"ctx: %@", ctx);
    CGColorSpaceRelease(rgb);
    CGContextClearRect(ctx, CGRectMake(0, 0, aWidth, aHeight));
    NSGraphicsContext* oldGC = [NSGraphicsContext currentContext];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:ctx flipped:YES]];

    [NSGraphicsContext setCurrentContext:oldGC];
    CGContextRelease(ctx);
    rv = IOSurfaceUnlock(surf, 0, nil);
    if (rv != 0) {
        NSLog(@"unlocking the IOSurface failed");
        return nil;
    }
    return surf;
}

static GLuint
CreateTextureForIOSurface(CGLContextObj cglContext, IOSurfaceRef surf)
{
    GLuint texture;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, texture);
    CGLError rv =
    CGLTexImageIOSurface2D(cglContext, GL_TEXTURE_RECTANGLE_ARB, GL_RGB,
                           IOSurfaceGetWidth(surf), IOSurfaceGetHeight(surf),
                           GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, surf, 0);
    if (rv != 0) {
        NSLog(@"CGLError: %d", rv);
    }
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, 0);
    return texture;
}

static GLuint
CreateFBOForTexture(GLuint texture)
{
    GLuint framebuffer;
    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, texture);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_RECTANGLE_ARB, texture, 0);
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"framebuffer incomplete");
    }
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, 0);
    return framebuffer;
}

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

    useIOSurf_ = NO;

    self.wantsBestResolutionOpenGLSurface = YES;

    compositingThread_ = dispatch_queue_create("org.mozilla.CompositingThread", NULL);
    glContext_ = [[NSOpenGLContext contextForWindow] retain];
    dispatch_sync(compositingThread_, ^{
        [glContext_ makeCurrentContext];
        glDrawer_ = [[OpenGLDrawer alloc] init];
    });
    animator_ = nil;

    if (useIOSurf_) {
        surf_ = CreateTransparentIOSurface(601, 361);
        surftex_ = CreateTextureForIOSurface([glContext_ CGLContextObj], surf_);
        surffbo_ = CreateFBOForTexture(surftex_);
        CALayer* layer = [CALayer layer];
        layer.frame = CGRectMake(0, 0, 601, 361);
        layer.contentsGravity = kCAGravityBottomLeft;
        //layer.opaque = YES;

        self.wantsLayer = YES;
        self.layer = layer;
    } else {
        self.wantsLayer = NO;
    }

    return self;
}

- (void)viewDidMoveToWindow
{
    if (![self window]) {
        return;
    }

    if (useIOSurf_) {
        [CATransaction begin];
        dispatch_sync(compositingThread_, ^{
            [glContext_ update];
            NSLog(@"drawing to view: %@", self);
            [glContext_ makeCurrentContext];
            [glDrawer_ drawToFBO:surffbo_ width:displayWidth_ height:displayHeight_ angle:CurrentAngle()];
            [glContext_ flushBuffer];
        });
        glFlush();
        self.layer.contents = (id)surf_;
        [CATransaction commit];
        [CATransaction flush];
        animator_ = [[VSyncListener alloc] initWithCallback:glContext_ callback:^{
            dispatch_async(compositingThread_, ^{
                [CATransaction begin];
                [glContext_ update];
                [glContext_ makeCurrentContext];
                [glDrawer_ drawToFBO:surffbo_ width:displayWidth_ height:displayHeight_ angle:CurrentAngle()];
                [glContext_ flushBuffer];
                glFlush();
                [self.layer setContentsChanged];
                //self.layer.contents = (id)surf_;
                [CATransaction commit];
                [CATransaction flush];
            });
        }];
    } else {
        [glContext_ setView:self];
        animator_ = [[VSyncListener alloc] initWithCallback:glContext_ callback:^{
            dispatch_async(compositingThread_, ^{
                [glContext_ makeCurrentContext];
                [glDrawer_ drawToFBO:0 width:displayWidth_ height:displayHeight_ angle:CurrentAngle()];
                [glContext_ flushBuffer];
            });
        }];
    }

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
