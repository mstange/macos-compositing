//
//  NSWindowSquare.h
//  IOSurface compositing
//
//  Created by Timothy Nikkel on 2018-04-09.
//  Copyright © 2018 Markus Stange. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NSWindowSquare : NSWindow

- (BOOL)_shouldRoundCornersForSurface;

@end
