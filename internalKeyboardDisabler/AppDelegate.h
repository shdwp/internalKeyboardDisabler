//
//  AppDelegate.h
//  internalKeyboardDisabler
//
//  Created by shdwprince on 10/22/15.
//  Copyright © 2015 shdwprince. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "libusb.h"
#import "pwd.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTableViewDelegate>
@property IBOutlet NSMutableArray *usbDevices;
@property NSDictionary *trackedDevice;

@end

