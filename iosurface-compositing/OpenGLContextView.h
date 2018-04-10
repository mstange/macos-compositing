//
//  OpenGLContextView.h
//  IOSurface compositing
//
//  Created by Markus Stange on 2017-12-21.
//  Copyright © 2017 Markus Stange. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "OpenGLDrawer.h"
#import "VSyncListener.h"

@interface OpenGLContextView : NSView
{
    dispatch_queue_t compositingThread_;
    NSOpenGLContext* glContext_;
    OpenGLDrawer* glDrawer_;
    VSyncListener* animator_;
    int displayWidth_;
    int displayHeight_;

    IOSurfaceRef surf_;
    GLuint surftex_;
    GLuint surffbo_;

    BOOL useIOSurf;
}

- (instancetype)initWithFrame:(NSRect)frameRect;

@end
