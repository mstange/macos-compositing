//
//  WindowDelegate.m
//  iosurface-compositing
//
//  Created by Markus Stange on 2017-12-21.
//  Copyright © 2017 Markus Stange. All rights reserved.
//

#import "WindowDelegate.h"

@implementation WindowDelegate

- (void)windowWillClose:(NSNotification*)notification
{
    [NSApp terminate:self];
}

@end
