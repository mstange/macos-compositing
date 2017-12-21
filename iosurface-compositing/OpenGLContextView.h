//
//  OpenGLContextView.h
//  IOSurface compositing
//
//  Created by Markus Stange on 2017-12-21.
//  Copyright © 2017 Markus Stange. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface OpenGLContextView : NSView
{
    dispatch_queue_t compositingThread_;
    NSOpenGLContext* glContext_;
}
@end
