//
//  OpenGLDrawer.h
//  IOSurface compositing
//
//  Created by Markus Stange on 2017-12-21.
//  Copyright © 2017 Markus Stange. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <OpenGL/gl.h>

@interface OpenGLDrawer : NSObject
{
    GLuint programID_;
    GLuint texture_;
    GLuint textureUniform_;
    GLuint angleUniform_;
    GLuint rectUniform_;
    GLuint posAttribute_;
    GLuint vertexBuffer_;
    
    NSSize textureSize_;
}

- (instancetype)init;
- (void)drawToFBO:(GLuint)fbo width:(int)width height:(int)height angle:(float)angle;

@end
