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
    GLint opaque = 1;
    [ctx setValues:&opaque forParameter:NSOpenGLCPSurfaceOpacity];
    return [ctx autorelease];
}

@end

@implementation OpenGLContextView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];

    compositingThread_ = dispatch_queue_create("org.mozilla.CompositingThread", NULL);
    glContext_ = [[NSOpenGLContext contextForWindow] retain];
    
    return self;
}

- (void)dealloc
{
    dispatch_release(compositingThread_);
    [glContext_ release];
    [super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[[NSGradient alloc] initWithColors:@[NSColor.whiteColor, NSColor.blackColor]] drawInRect:self.bounds angle:-45];
}

@end
