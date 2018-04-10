//
//  VSyncListener.h
//  IOSurface compositing
//
//  Created by Markus Stange on 2017-12-21.
//  Copyright © 2017 Markus Stange. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CVDisplayLink.h>
#import <Cocoa/Cocoa.h>

typedef void (^VCallBack)(void);

@interface VSyncListener : NSObject
{
    VCallBack vcallback_;
    CVDisplayLinkRef displayLink_;
}

- (instancetype)initWithCallback:(NSOpenGLContext*) glcontext callback:(void (^)(void))callback;
- (CVReturn)getFrameForTime:(const CVTimeStamp*)outputTime;

@end
