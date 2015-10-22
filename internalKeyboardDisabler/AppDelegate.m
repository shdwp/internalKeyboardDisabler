//
//  AppDelegate.m
//  internalKeyboardDisabler
//
//  Created by shdwprince on 10/22/15.
//  Copyright © 2015 shdwprince. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate ()
@property (weak) IBOutlet NSTableView *tableView;
@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSArrayController *arrayController;

@property NSStatusItem *statusItem;

@property BOOL *runUIUpdates;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    //[self checkPrivilegedUser];

    // intit
    libusb_context *context;
    libusb_init(&context);
    self.runUIUpdates = malloc(sizeof(BOOL));
    *self.runUIUpdates = YES;

    // persistence
    self.trackedDevice = [NSKeyedUnarchiver unarchiveObjectWithFile:[self persistenceFile]];

    // status icon
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [NSImage imageNamed:@"statusicon"];
    self.statusItem.button.alternateImage = [NSImage imageNamed:@"statusicon_alt"];

    [self updateMenuForDisconnectedDevice];

    // threading
    [[NSOperationQueue new] addOperationWithBlock:^{
        while (true) { @autoreleasepool {
            if (*self.runUIUpdates) {
                self.usbDevices = [self readUsbDevices].mutableCopy;
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [self.arrayController rearrangeObjects];
                }];
                [self focusOnTrackedDevice];
            }

            [NSThread sleepForTimeInterval:1.0];
        }}
    }];

    [[NSOperationQueue new] addOperationWithBlock:^{
        BOOL connected = NO;
        while (true) {@autoreleasepool {
            BOOL check = [self libusbContext:context
                  checkForDeviceWithVendorID:[(NSNumber *) self.trackedDevice[@"vendor_id"] unsignedIntValue]
                                   productID:[(NSNumber *) self.trackedDevice[@"product_id"] unsignedIntValue]];

            if (check && !connected) {
                connected = YES;
                [self trackedDeviceConnected];
            } else if (!check && connected) {
                connected = NO;
                [self trackedDeviceDisconnected];
            }

            [NSThread sleepForTimeInterval:1.0];
        }}
    }];

}

- (void) applicationWillTerminate:(NSNotification *)notification {
    [self enableInternalKeyboard:YES];
}

- (void) applicationWillHide:(NSNotification *)notification {
    *self.runUIUpdates = NO;
}

- (void) applicationWillUnhide:(NSNotification *)notification {
    *self.runUIUpdates = YES;
}

#pragma mark - persistence

- (NSString *) persistenceFile {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *basePath =  [paths.firstObject stringByAppendingString:@"/Application Support/internalKeyboardDisabler/"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:basePath isDirectory:0]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:basePath
                                  withIntermediateDirectories:NO
                                                   attributes:nil
                                                        error:nil];
    }

    return [basePath stringByAppendingString:@"database.db"];
}

- (void) save {
    [NSKeyedArchiver archiveRootObject:self.trackedDevice toFile:[self persistenceFile]];
}

#pragma mark - tableview

- (void) tableViewSelectionDidChange:(NSNotification *)notification {
    NSTableView *table = (NSTableView *) notification.object;
    if (table.numberOfSelectedRows > 0) {
        NSDictionary *deviceDict = self.usbDevices[[(NSTableView *) notification.object selectedRow]];

        if (deviceDict) {
            self.trackedDevice = deviceDict.copy;
            [self save];
        }
    }
}

- (void) focusOnTrackedDevice {
    __block NSUInteger row = -1;

    [self.usbDevices enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj[@"description"] isEqualToString:self.trackedDevice[@"description"]])
            row = idx;
    }];

    if (row == -1) {
        [self.tableView deselectAll:nil];
    } else {
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    }
}

#pragma mark - actions

// called in background thread
- (void) trackedDeviceConnected {
    [self enableInternalKeyboard:NO];
    [self updateMenuForConnectedDevice];
}

// called in background thread
- (void) trackedDeviceDisconnected {
    [self enableInternalKeyboard:YES];
    [self updateMenuForDisconnectedDevice];
}

- (void) checkPrivilegedUser {
    register uid_t uid = getuid();
    if (uid != 0) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Error: ";
        alert.informativeText = @"application is not intended to run as non-privileged user.";
        [alert addButtonWithTitle:@"Close"];
        [alert runModal];
        [self quitAction];
    }
}

#pragma mark - status icon

- (void) forceEnableInternalKeyboard {
    [self enableInternalKeyboard:YES];
    [self updateMenuForDisconnectedDevice];
}

- (void) forceDisableInternalKeyboard {
    [self enableInternalKeyboard:NO];
    [self updateMenuForConnectedDevice];
}

- (void) updateMenuForConnectedDevice {
    NSMenu *statusItemMenu = [NSMenu new];
    [statusItemMenu addItemWithTitle:@"Show settings" action:@selector(toggleHiddenAction) keyEquivalent:@""];
    [statusItemMenu addItemWithTitle:@"Enable internal keyboard" action:@selector(forceEnableInternalKeyboard) keyEquivalent:@"F"];
    [statusItemMenu addItemWithTitle:@"Quit" action:@selector(quitAction) keyEquivalent:@"Q"];
    self.statusItem.menu = statusItemMenu;
}

- (void) updateMenuForDisconnectedDevice {
    NSMenu *statusItemMenu = [NSMenu new];
    [statusItemMenu addItemWithTitle:@"Show settings" action:@selector(toggleHiddenAction) keyEquivalent:@""];
    [statusItemMenu addItemWithTitle:@"Disable internal keyboard" action:@selector(forceDisableInternalKeyboard) keyEquivalent:@"F"];
    [statusItemMenu addItemWithTitle:@"Quit" action:@selector(quitAction) keyEquivalent:@"Q"];
    self.statusItem.menu = statusItemMenu;
}

- (void) toggleHiddenAction {
    self.window.isVisible = !self.window.isVisible;
}

- (void) quitAction {
    [self enableInternalKeyboard:YES];
    exit(0);
}

#pragma mark - usb

- (BOOL) libusbContext:(libusb_context *) ctx
 checkForDeviceWithVendorID:(u_int16_t) vendor_id
                  productID:(u_int16_t) product_id {
    libusb_device **devices;
    ssize_t count = libusb_get_device_list(ctx, &devices);

    BOOL result = NO;
    for (int i = 0; i < count; i++) {
        struct libusb_device_descriptor d;
        libusb_get_device_descriptor(devices[i], &d);

        if (d.idVendor == vendor_id && d.idProduct == product_id) {
            result = YES;
            break;
        }
    }

    libusb_free_device_list(devices, 0);
    return result;
}

- (NSArray *) readUsbDevices {
    NSPipe *pipe = [NSPipe pipe];
    NSFileHandle *file = pipe.fileHandleForReading;

    NSTask *task = [NSTask new];
    task.launchPath = @"/usr/sbin/system_profiler";
    task.arguments = @[@"SPUSBDataType", ];
    task.standardOutput = pipe;
    [task launch];

    NSString *output = [[NSString alloc] initWithData:[file readDataToEndOfFile]
                                             encoding:NSUTF8StringEncoding];
    [file closeFile];

    NSMutableArray *result = [NSMutableArray new];

    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    [lines enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL *stop) {
        if ([obj hasPrefix:@"        "] && ![[NSCharacterSet whitespaceCharacterSet] characterIsMember:[obj characterAtIndex:8]]) {
            NSString *productIdString = lines[idx+2];
            NSString *vendorIdString = lines[idx+3];

            NSScanner *scan = [NSScanner scannerWithString:productIdString];
            unsigned int product_id, vendor_id;
            [scan scanString:@"Product ID: " intoString:nil];
            [scan scanHexInt:&product_id];

            scan = [NSScanner scannerWithString:vendorIdString];
            [scan scanString:@"Vendor ID: " intoString:nil];
            [scan scanHexInt:&vendor_id];

            NSString *name = [obj substringWithRange:NSMakeRange(8, obj.length - 8 -1)];
            [result addObject:@{@"name": name,
                                @"product_id": [NSNumber numberWithUnsignedInt:product_id],
                                @"vendor_id": [NSNumber numberWithUnsignedInt:vendor_id],
                                @"description": [NSString stringWithFormat:@"%@ (%d:%d)", name, vendor_id, product_id], }];
        }
    }];

    return result;
}

#pragma mark kext

- (NSString *) kextExecutableForState:(BOOL) state {
    return [NSString stringWithFormat:@"/sbin/kext%@", state ? @"load" : @"unload"];
}

- (void) enableInternalKeyboard:(BOOL) enable {
    system([NSString stringWithFormat:@"%@ %@",
            [self kextExecutableForState:enable],
            @"/System/Library/Extensions/AppleUSBTopCase.kext/Contents/PlugIns/AppleUSBTCKeyboard.kext"].UTF8String);
}

@end
