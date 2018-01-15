//
//  VSyncListener.m
//  IOSurface compositing
//
//  Created by Markus Stange on 2017-12-21.
//  Copyright © 2017 Markus Stange. All rights reserved.
//

#import "VSyncListener.h"

@implementation VSyncListener

- (instancetype)initWithCallback:(void (^)(void))callback
{
    self = [super init];
    return self;
}

@end
