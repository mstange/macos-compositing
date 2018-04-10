//
//  OpenGLDrawer.m
//  IOSurface compositing
//
//  Created by Markus Stange on 2017-12-21.
//  Copyright © 2017 Markus Stange. All rights reserved.
//

#import "OpenGLDrawer.h"
#import <Cocoa/Cocoa.h>

static const char* kVertexShader =
    "#version 120\n"
    "// Input vertex data, different for all executions of this shader.\n"
    "attribute vec2 aPos;\n"
    "uniform float uAngle;\n"
    "uniform vec4 uRect;\n"
    "varying vec2 vPos;\n"
    "varying mat4 vColorMat;\n"
    "void main(){\n"
    "  vPos = aPos;\n"
    "  float lumR = 0.2126;\n"
    "  float lumG = 0.7152;\n"
    "  float lumB = 0.0722;\n"
    "  float oneMinusLumR = 1.0 - lumR;\n"
    "  float oneMinusLumG = 1.0 - lumG;\n"
    "  float oneMinusLumB = 1.0 - lumB;\n"
    "  float oneMinusAmount = 1.0 - uAngle;\n"
    "  float c = cos(uAngle * 0.01745329251);\n"
    "  float s = sin(uAngle * 0.01745329251);\n"
    "  vColorMat = mat4(vec4(lumR + oneMinusLumR * c - lumR * s,\n"
    "                        lumR - lumR * c + 0.143 * s,\n"
    "                        lumR - lumR * c - oneMinusLumR * s,\n"
    "                        0.0),\n"
    "                   vec4(lumG - lumG * c - lumG * s,\n"
    "                        lumG + oneMinusLumG * c + 0.140 * s,\n"
    "                        lumG - lumG * c + lumG * s,\n"
    "                        0.0),\n"
    "                   vec4(lumB - lumB * c + oneMinusLumB * s,\n"
    "                        lumB - lumB * c - 0.283 * s,\n"
    "                        lumB + oneMinusLumB * c + lumB * s,\n"
    "                        0.0),\n"
    "                   vec4(0.0, 0.0, 0.0, 1.0));\n"
    "  gl_Position = vec4(uRect.xy + aPos * uRect.zw, 0.0, 1.0);\n"
    "}\n";

static const char* kFragmentShader =
    "#version 120\n"
    "varying vec2 vPos;\n"
    "varying mat4 vColorMat;\n"
    "uniform sampler2D uSampler;\n"
    "void main()\n"
    "{\n"
    "  gl_FragColor = vColorMat * texture2D(uSampler, vPos);\n"
    "}\n";

@implementation OpenGLDrawer

- (instancetype)init
{
    self = [super init];
    
    // Create and compile our GLSL program from the shaders.
    programID_ = [self compileProgramWithVertexShader:kVertexShader fragmentShader:kFragmentShader];
    
    textureSize_ = NSMakeSize(300, 200);
    
    // Create a texture
    texture_ = [self createTextureWithSize:textureSize_ drawingHandler:^(CGContextRef ctx) {
        NSGraphicsContext* oldGC = [NSGraphicsContext currentContext];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:ctx flipped:YES]];
        
        CGFloat imageSize = MIN(textureSize_.width, textureSize_.height);
        NSRect squareInTheMiddleOfTexture = {
            textureSize_.width / 2 - imageSize / 2,
            textureSize_.height / 2 - imageSize / 2,
            imageSize,
            imageSize
        };
        
        [[NSImage imageNamed:NSImageNameColorPanel] drawInRect:squareInTheMiddleOfTexture
                                                      fromRect:NSZeroRect
                                                     operation:NSCompositingOperationSourceOver
                                                      fraction:1.0];
        [NSGraphicsContext setCurrentContext:oldGC];
    }];
    textureUniform_ = glGetUniformLocation(programID_, "uSampler");
    angleUniform_ = glGetUniformLocation(programID_, "uAngle");
    rectUniform_ = glGetUniformLocation(programID_, "uRect");
    
    // Get a handle for our buffers
    posAttribute_ = glGetAttribLocation(programID_, "aPos");
    
    static const GLfloat g_vertex_buffer_data[] = {
        0.0f,  0.0f,
        1.0f,  0.0f,
        0.0f,  1.0f,
        1.0f,  1.0f,
    };
    
    glGenBuffers(1, &vertexBuffer_);
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer_);
    glBufferData(GL_ARRAY_BUFFER, sizeof(g_vertex_buffer_data), g_vertex_buffer_data, GL_STATIC_DRAW);
    
    return self;
}

- (GLuint)compileProgramWithVertexShader:(const char*)vertexShader fragmentShader:(const char*)fragmentShader
{
    // Create the shaders
    GLuint vertexShaderID = glCreateShader(GL_VERTEX_SHADER);
    GLuint fragmentShaderID = glCreateShader(GL_FRAGMENT_SHADER);
    
    GLint result = GL_FALSE;
    int infoLogLength;
    
    // Compile Vertex Shader
    glShaderSource(vertexShaderID, 1, &vertexShader , NULL);
    glCompileShader(vertexShaderID);
    
    // Check Vertex Shader
    glGetShaderiv(vertexShaderID, GL_COMPILE_STATUS, &result);
    glGetShaderiv(vertexShaderID, GL_INFO_LOG_LENGTH, &infoLogLength);
    if (infoLogLength > 0) {
        NSMutableData* msgData = [NSMutableData dataWithCapacity:infoLogLength+1];
        glGetShaderInfoLog(vertexShaderID, infoLogLength, NULL, [msgData mutableBytes]);
        NSString* msg = [[NSString alloc] initWithData:msgData encoding:NSASCIIStringEncoding];
        NSLog(@"Vertex shader compilation failed: %@\n", msg);
        [msg release];
        [msgData release];
    }
    
    // Compile Fragment Shader
    glShaderSource(fragmentShaderID, 1, &fragmentShader , NULL);
    glCompileShader(fragmentShaderID);
    
    // Check Fragment Shader
    glGetShaderiv(fragmentShaderID, GL_COMPILE_STATUS, &result);
    glGetShaderiv(fragmentShaderID, GL_INFO_LOG_LENGTH, &infoLogLength);
    if (infoLogLength > 0) {
        NSMutableData* msgData = [NSMutableData dataWithCapacity:infoLogLength+1];
        glGetShaderInfoLog(fragmentShaderID, infoLogLength, NULL, [msgData mutableBytes]);
        NSString* msg = [[NSString alloc] initWithData:msgData encoding:NSASCIIStringEncoding];
        NSLog(@"Fragment shader compilation failed: %@\n", msg);
        [msg release];
        [msgData release];
    }
    
    // Link the program
    GLuint programID = glCreateProgram();
    glAttachShader(programID, vertexShaderID);
    glAttachShader(programID, fragmentShaderID);
    glLinkProgram(programID);
    
    // Check the program
    glGetProgramiv(programID, GL_LINK_STATUS, &result);
    glGetProgramiv(programID, GL_INFO_LOG_LENGTH, &infoLogLength);
    if (infoLogLength > 0) {
        NSMutableData* msgData = [NSMutableData dataWithCapacity:infoLogLength+1];
        glGetProgramInfoLog(programID, infoLogLength, NULL, [msgData mutableBytes]);
        NSString* msg = [[NSString alloc] initWithData:msgData encoding:NSASCIIStringEncoding];
        NSLog(@"Program linking failed: %@\n", msg);
        [msg release];
        [msgData release];
    }
    
    glDeleteShader(vertexShaderID);
    glDeleteShader(fragmentShaderID);
    
    return programID;
}

- (GLuint)createTextureWithSize:(NSSize)size drawingHandler:(void (^)(CGContextRef))drawingHandler
{
    int width = size.width;
    int height = size.height;
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef imgCtx = CGBitmapContextCreate(NULL, width, height, 8, width * 4,
                                                rgb, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(rgb);
    drawingHandler(imgCtx);
    CGContextRelease(imgCtx);
    
    GLuint texture = 0;
    glActiveTexture(GL_TEXTURE0);
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_BGRA, GL_UNSIGNED_BYTE, CGBitmapContextGetData(imgCtx));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    return texture;
}

- (void)drawToFBO:(GLuint)fbo width:(int)width height:(int)height angle:(float)angle
{
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    
    glViewport(0, 0, width, height);
    
    NSRect wholeViewport = { -1, -1, 2, 2 };
    
    glClearColor(0.7, 0.8, 1.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    
    glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    glEnable(GL_BLEND);

    glUseProgram(programID_);
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texture_);
    glUniform1i(textureUniform_, 0);
    glUniform1f(angleUniform_, angle);
    glUniform4f(rectUniform_,
                wholeViewport.origin.x, wholeViewport.origin.y,
                textureSize_.width / width * wholeViewport.size.width,
                textureSize_.height / height * wholeViewport.size.height);
    
    glEnableVertexAttribArray(posAttribute_);
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer_);
    glVertexAttribPointer(posAttribute_, // The attribute we want to configure
                          2,             // size
                          GL_FLOAT,      // type
                          GL_FALSE,      // normalized?
                          0,             // stride
                          (void*)0       // array buffer offset
                          );
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4); // 4 indices starting at 0 -> 2 triangles
    
    glDisable(GL_BLEND);
    glDisableVertexAttribArray(posAttribute_);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

- (void)dealloc
{
    glDeleteTextures(1, &texture_);
    glDeleteBuffers(1, &vertexBuffer_);
    
    [super dealloc];
}

@end
