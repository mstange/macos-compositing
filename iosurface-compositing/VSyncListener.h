//
//  VSyncListener.h
//  IOSurface compositing
//
//  Created by Markus Stange on 2017-12-21.
//  Copyright © 2017 Markus Stange. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface VSyncListener : NSObject

- (instancetype)initWithCallback:(void (^)(void))callback;

@end
