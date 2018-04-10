//
//  VSyncListener.m
//  IOSurface compositing
//
//  Created by Markus Stange on 2017-12-21.
//  Copyright © 2017 Markus Stange. All rights reserved.
//

#import "VSyncListener.h"

static CVReturn MyDisplayLinkCallback(CVDisplayLinkRef displayLink, const CVTimeStamp* now, const CVTimeStamp* outputTime, CVOptionFlags flagsIn, CVOptionFlags* flagsOut, void* displayLinkContext)

{
    CVReturn result = [(VSyncListener*)displayLinkContext getFrameForTime:outputTime];
    return result;
}

@implementation VSyncListener

- (instancetype)initWithCallback:(NSOpenGLContext*) glcontext callback:(void (^)(void))callback
{
    self = [super init];

    vcallback = Block_copy(callback);

    CVDisplayLinkCreateWithActiveCGDisplays(&displayLink);
    CVDisplayLinkSetOutputCallback(displayLink, &MyDisplayLinkCallback, self);

    CGLContextObj cglContext = [glcontext CGLContextObj];
    CGLPixelFormatObj cglPixelFormat = [[glcontext pixelFormat] CGLPixelFormatObj];
    CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(displayLink, cglContext, cglPixelFormat);

    CVDisplayLinkStart(displayLink);

    return self;
}

- (CVReturn)getFrameForTime:(const CVTimeStamp*)outputTime
{
    vcallback();
    return kCVReturnSuccess;
}

@end
