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
    NSDictionary* dict = @{
       IOSurfacePropertyKeyWidth: [NSNumber numberWithInt:aWidth],
       IOSurfacePropertyKeyHeight: [NSNumber numberWithInt:aHeight],
       IOSurfacePropertyKeyBytesPerElement: [NSNumber numberWithInt:4],
       IOSurfacePropertyKeyPixelFormat: [NSNumber numberWithInt:'BGRA'],
       (NSString*)kIOSurfaceIsGlobal: [NSNumber numberWithBool:YES]
    };
    IOSurfaceRef surf = IOSurfaceCreate((CFDictionaryRef)dict);
    NSLog(@"IOSurface: %@", surf);

    return surf;
}

static GLuint
CreateTextureForIOSurface(CGLContextObj cglContext, IOSurfaceRef surf)
{
    GLuint texture;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, texture);
    CGLError rv =
    CGLTexImageIOSurface2D(cglContext, GL_TEXTURE_RECTANGLE_ARB, GL_RGBA,
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
    GLint opaque = [[[NSProcessInfo processInfo] arguments] containsObject:@"--use-opaque-glcontext"] ? 1 : 0;
    NSLog(@"opaque: %d", opaque);
    [ctx setValues:&opaque forParameter:NSOpenGLCPSurfaceOpacity];
    return [ctx autorelease];
}

@end

@implementation OpenGLContextView

- (void)commonInit
{
    useIOSurf_ = [[[NSProcessInfo processInfo] arguments] containsObject:@"--use-iosurface"];
    surf_ = NULL;
    surftex_ = 0;
    surffbo_ = 0;
    needsUpdate_ = NO;
    
    self.wantsBestResolutionOpenGLSurface = YES;
    
    compositingThread_ = dispatch_queue_create("org.mozilla.CompositingThread", DISPATCH_QUEUE_SERIAL);
    glContext_ = [[NSOpenGLContext contextForWindow] retain];
    dispatch_sync(compositingThread_, ^{
        [glContext_ makeCurrentContext];
        glDrawer_ = [[OpenGLDrawer alloc] init];
    });
    animator_ = nil;
    
    if (useIOSurf_) {
        CALayer* layer = [CALayer layer];
        layer.contentsGravity = kCAGravityTopLeft;
        layer.contentsScale = 2;
        if ([[[NSProcessInfo processInfo] arguments] containsObject:@"--use-opaque-calayer"]) {
            [layer setContentsOpaque:YES];
        }
        
        self.wantsLayer = YES;
        self.layer = layer;
    } else {
        self.wantsLayer = NO;
    }
    
    
    if ([[[NSProcessInfo processInfo] arguments] containsObject:@"--close-after-20-seconds"]) {
        [self performSelector:@selector(terminate) withObject:nil afterDelay:20.0];
    }
}

- (void)terminate
{
    [NSApp terminate:self];
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    [self commonInit];
    return self;
}

// This is called when specifying this class as the window's contentView class.
- (instancetype)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];
    [self commonInit];
    return self;
}

- (BOOL)isOpaque
{
    return YES;
}

- (void)viewDidMoveToWindow
{
    if (![self window]) {
        return;
    }

    animator_ = [[VSyncListener alloc] initWithCallback:glContext_ callback:^{
        dispatch_async(compositingThread_, ^{
            [self compositeOnThisThread];
        });
    }];

    if (useIOSurf_) {
        if ([[[NSProcessInfo processInfo] arguments] containsObject:@"--use-layer-for-content-view"]) {
            // Make the window's contentView layer-backed. This gives our layer anti-aliased rounded corners.
            NSView* contentView = [[self window] contentView];
            contentView.wantsLayer = YES;
        }
    } else {
        [glContext_ setView:self];
    }
    needsUpdate_ = YES;

    NSLog(@"subscribing to NSViewFrameDidChangeNotification");
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_surfaceNeedsUpdate:)
                                                 name:NSViewFrameDidChangeNotification
                                               object:self];
    [self handleSizeChange];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
    if (newWindow) {
        return;
    }
    
    [animator_ release];
    animator_ = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSViewFrameDidChangeNotification
                                                  object:self];
}

- (void)_surfaceNeedsUpdate:(NSNotification*)notification
{
    NSLog(@"surfaceNeedsUpdate: %@", notification);
    [self handleSizeChange];
}

static float CurrentAngle() { return fmod(CFAbsoluteTimeGetCurrent(), 1.0) * 360; }

- (void)handleSizeChange
{
    NSLog(@"handleSizeChange");
    layerBounds_ = self.bounds;
    NSSize backingSize = [self convertSizeToBacking:self.bounds.size];
    displayWidth_ = (int)backingSize.width;
    displayHeight_ = (int)backingSize.height;
    
    needsUpdate_ = YES;
    
    dispatch_sync(compositingThread_, ^{
        [self compositeOnThisThreadAfterChange];
    });
}

- (void)compositeOnThisThread
{
    if (useIOSurf_) {
        if (!surffbo_) {
            return;
        }
        [CATransaction begin];
        [glContext_ makeCurrentContext];
        [glDrawer_ drawToFBO:surffbo_ width:displayWidth_ height:displayHeight_ angle:CurrentAngle()];
        glFlush();
        [self.layer setContentsChanged];
        [CATransaction commit];
        [CATransaction flush];
    } else {
        [glContext_ makeCurrentContext];
        [glDrawer_ drawToFBO:0 width:displayWidth_ height:displayHeight_ angle:CurrentAngle()];
        [glContext_ flushBuffer];
    }
}

- (void)compositeOnThisThreadAfterChange
{
    if (useIOSurf_) {
        [glContext_ makeCurrentContext];
        if (surffbo_) {
            glDeleteFramebuffers(1, &surffbo_);
            surffbo_ = 0;
        }
        if (surftex_) {
            glDeleteTextures(1, &surftex_);
            surftex_ = 1;
        }
        if (surf_) {
            CFRelease(surf_);
            surf_ = NULL;
        }
        surf_ = CreateTransparentIOSurface(displayWidth_, displayHeight_);
        surftex_ = CreateTextureForIOSurface([glContext_ CGLContextObj], surf_);
        surffbo_ = CreateFBOForTexture(surftex_);
        [CATransaction begin];
        [CATransaction setValue:[NSNumber numberWithBool:YES] forKey:kCATransactionDisableActions];
        NSLog(@"current thread: %@", [NSThread currentThread]);
        [glDrawer_ drawToFBO:surffbo_ width:displayWidth_ height:displayHeight_ angle:CurrentAngle()];
        glFlush();
        self.layer.contents = (id)surf_;
        if ([[[NSProcessInfo processInfo] arguments] containsObject:@"--use-opaque-calayer"]) {
            [self.layer setContentsOpaque:YES];
        }
        [CATransaction commit];
        [CATransaction flush];
        // NSLog(@"[self.layer.superlayer NS_view]: %@", (id)[self.layer.superlayer.superlayer NS_view] == [[self superview] superview] ? @"YES" : @"NO");
    } else {
        [glContext_ update];
        [glContext_ makeCurrentContext];
        [glDrawer_ drawToFBO:0 width:displayWidth_ height:displayHeight_ angle:CurrentAngle()];
        [glContext_ flushBuffer];
    }
    needsUpdate_ = NO;
}

- (BOOL)isFlipped
{
    return YES;
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
        NSLog(@"calling handleSizeChange from drawRect");
        [self handleSizeChange];
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
