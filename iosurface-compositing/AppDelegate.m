//
//  AppDelegate.m
//  iosurface-compositing
//
//  Created by Markus Stange on 2017-12-21.
//  Copyright © 2017 Markus Stange. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate ()

@property IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.window.titlebarAppearsTransparent = YES;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
}

@end
