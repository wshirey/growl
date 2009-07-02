/*
 Copyright (c) The Growl Project, 2004-2005
 All rights reserved.


 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:


 1. Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 3. Neither the name of Growl nor the names of its contributors
 may be used to endorse or promote products derived from this software
 without specific prior written permission.


 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

 */

//
//  GrowlSafari.m
//  GrowlSafari
//
//  Created by Kevin Ballard on 10/29/04.
//  Copyright 2004 Kevin Ballard. All rights reserved.
//

#import "GrowlSafari.h"
#import "GSWebBookmark.h"
#import <Growl/Growl.h>
#import <objc/objc-runtime.h>


#define SAFARI_VERSION_4_0  5530

enum {
	GrowlSafariDownloadStageActive = 1,
	GrowlSafariDownloadStageDecompressing = 2,
	GrowlSafariDownloadStageDiskImagePreparing = 4,
	GrowlSafariDownloadStageDiskImageVerifying = 7,
	GrowlSafariDownloadStageDiskImageVerified = 8,
	GrowlSafariDownloadStageDiskImageMounting = 9,
	GrowlSafariDownloadStageDiskImageCleanup = 12,
	GrowlSafariDownloadStageInactive = 13,
	GrowlSafariDownloadStageFinished = 14
};

// How long should we wait (in seconds) before it's a long download?
static double longDownload = 15.0;
static int safariVersion;
static NSMutableDictionary *dates = nil;

// Using method swizzling as outlined here:
// http://www.cocoadev.com/index.pl?MethodSwizzling
// A couple of modifications made to support swizzling class methods

static BOOL PerformSwizzle(Class aClass, SEL orig_sel, SEL alt_sel, BOOL forInstance) {
    // First, make sure the class isn't nil
	if (aClass) {
		Method orig_method = nil, alt_method = nil;

		// Next, look for the methods
		if (forInstance) {
			orig_method = class_getInstanceMethod(aClass, orig_sel);
			alt_method = class_getInstanceMethod(aClass, alt_sel);
		} else {
			orig_method = class_getClassMethod(aClass, orig_sel);
			alt_method = class_getClassMethod(aClass, alt_sel);
		}

		// If both are found, swizzle them
		if (orig_method && alt_method) {
			IMP temp;

			temp = orig_method->method_imp;
			orig_method->method_imp = alt_method->method_imp;
			alt_method->method_imp = temp;

			return YES;
		} else {
			// This bit stolen from SubEthaFari's source
			NSLog(@"GrowlSafari Error: Original (selector %s) %@, Alternate (selector %s) %@",
				  orig_sel,
				  orig_method ? @"was found" : @"not found",
				  alt_sel,
				  alt_method ? @"was found" : @"not found");
		}
	} else {
		NSLog(@"%@", @"GrowlSafari Error: No class to swizzle methods in");
	}

	return NO;
}

static void setDownloadStarted(id dl) {
	if (!dates)
		dates = [[NSMutableDictionary alloc] init];

	[dates setObject:[NSDate date] forKey:[dl identifier]];
}

static NSDate *dateStarted(id dl) {
	if (dates)
		return [dates objectForKey:[dl identifier]];

	return nil;
}

static BOOL isLongDownload(id dl) {
	NSDate *date = dateStarted(dl);
	return (date && -[date timeIntervalSinceNow] > longDownload);
}

static void setDownloadFinished(id dl) {
	[dates removeObjectForKey:[dl identifier]];
}

@implementation GrowlSafari
+ (NSBundle *) bundle {
	return [NSBundle bundleWithIdentifier:@"com.growl.GrowlSafari"];
}

+ (NSString *) bundleVersion {
	return [[[GrowlSafari bundle] infoDictionary] objectForKey:(NSString *)kCFBundleVersionKey];
}

+ (void) initialize {
	NSString *growlPath = [[[GrowlSafari bundle] privateFrameworksPath] stringByAppendingPathComponent:@"Growl.framework"];
	NSBundle *growlBundle = [NSBundle bundleWithPath:growlPath];

	if (growlBundle && [growlBundle load]) {
		// Register ourselves as a Growl delegate
		[GrowlApplicationBridge setGrowlDelegate:self];

		safariVersion = [[[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString *)kCFBundleVersionKey] intValue];
		//  NSLog(@"%d",safariVersion);

		if (safariVersion >= SAFARI_VERSION_4_0) {
			//	NSLog(@"Patching DownloadProgressEntry...");
			Class class = NSClassFromString(@"DownloadProgressEntry");
			PerformSwizzle(class, @selector(setDownloadStage:), @selector(mySetDownloadStage:), YES);
					
			PerformSwizzle(class, @selector(_updateDiskImageStatus:), @selector(myUpdateDiskImageStatus:), YES);
			
			PerformSwizzle(class, @selector(initWithDownload:mayOpenWhenDone:allowOverwrite:),
						   @selector(myInitWithDownload:mayOpenWhenDone:allowOverwrite:),
						   YES);
			
			Class webBookmarkClass = NSClassFromString(@"WebBookmark");
			if (webBookmarkClass)
				[[GSWebBookmark class] poseAsClass:webBookmarkClass];

			NSLog(@"Loaded GrowlSafari %@", [GrowlSafari bundleVersion]);
			NSDictionary *infoDictionary = [GrowlApplicationBridge frameworkInfoDictionary];
			NSLog(@"Using Growl.framework %@ (%@)",
				  [infoDictionary objectForKey:@"CFBundleShortVersionString"],
				  [infoDictionary objectForKey:(NSString *)kCFBundleVersionKey]);
		} else {
			NSLog(@"Safari too old (4.0 required); GrowlSafari disabled.");
		}
	} else {
		NSLog(@"Could not load Growl.framework, GrowlSafari disabled");
	}
	
}

#pragma mark GrowlApplicationBridge delegate methods

+ (NSString *) applicationNameForGrowl {
	return @"GrowlSafari";
}

+ (NSImage *) applicationIconForGrowl {
	return [NSImage imageNamed:@"NSApplicationIcon"];
}

+ (NSDictionary *) registrationDictionaryForGrowl {
	NSBundle *bundle = [GrowlSafari bundle];
	NSArray *array = [[NSArray alloc] initWithObjects:
		NSLocalizedStringFromTableInBundle(@"Short Download Complete", nil, bundle, @""),
		NSLocalizedStringFromTableInBundle(@"Download Complete", nil, bundle, @""),
		NSLocalizedStringFromTableInBundle(@"Disk Image Status", nil, bundle, @""),
		NSLocalizedStringFromTableInBundle(@"Compression Status", nil, bundle, @""),
		NSLocalizedStringFromTableInBundle(@"New feed entry", nil, bundle, @""),
		nil];
	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
		array, GROWL_NOTIFICATIONS_DEFAULT,
		array, GROWL_NOTIFICATIONS_ALL,
		nil];
	[array release];

	return dict;
}

+ (void) growlNotificationWasClicked:(id)clickContext {
	NSURL *url = [[NSURL alloc] initWithString:clickContext];
	[[NSWorkspace sharedWorkspace] openURL:url];
	[url release];
}

+ (void) notifyRSSUpdate:(WebBookmark *)bookmark newEntries:(int)newEntries {
	NSBundle *bundle = [GrowlSafari bundle];
	NSMutableString	*description = [[NSMutableString alloc]
		initWithFormat:newEntries == 1 ? NSLocalizedStringFromTableInBundle(@"%d new entry", nil, bundle, @"") : NSLocalizedStringFromTableInBundle(@"%d new entries", nil, bundle, @""),
		newEntries,
		[bookmark unreadRSSCount]];
	if (newEntries != [bookmark unreadRSSCount])
		[description appendFormat:NSLocalizedStringFromTableInBundle(@" (%d unread)", nil, bundle, @""), [bookmark unreadRSSCount]];

	NSString *title = [bookmark title];
	[GrowlApplicationBridge notifyWithTitle:(title ? title : [bookmark URLString])
								description:description
						   notificationName:NSLocalizedStringFromTableInBundle(@"New feed entry", nil, bundle, @"")
								   iconData:nil
								   priority:0
								   isSticky:NO
							   clickContext:[bookmark URLString]];
	[description release];
}
@end

@implementation NSObject (GrowlSafariPatch)
- (void) mySetDownloadStage:(int)stage {
	//int oldStage = [self downloadStage];
	
	//NSLog(@"mySetDownloadStage:%d -> %d", oldStage, stage);
	[self mySetDownloadStage:stage];
	if (dateStarted(self)) {
		if ( stage == GrowlSafariDownloadStageDecompressing ) {
			NSBundle *bundle = [GrowlSafari bundle];
			NSString *description = [[NSString alloc] initWithFormat:
				NSLocalizedStringFromTableInBundle(@"%@", nil, bundle, @""),
				[[self gsDownloadPath] lastPathComponent]];
			[GrowlApplicationBridge notifyWithTitle:NSLocalizedStringFromTableInBundle(@"Decompressing File", nil, bundle, @"")
										description:description
								   notificationName:NSLocalizedStringFromTableInBundle(@"Compression Status", nil, bundle, @"")
										   iconData:nil
										   priority:0
										   isSticky:NO
									   clickContext:nil];
			[description release];
		} else if ( stage == GrowlSafariDownloadStageDiskImageVerifying ) {
			NSBundle *bundle = [GrowlSafari bundle];
			NSString *description = [[NSString alloc] initWithFormat:
									 NSLocalizedStringFromTableInBundle(@"%@", nil, bundle, @""),
									 [[self gsDownloadPath] lastPathComponent]];
			[GrowlApplicationBridge notifyWithTitle:NSLocalizedStringFromTableInBundle(@"Verifying Disk Image", nil, bundle, @"")
										description:description
								   notificationName:NSLocalizedStringFromTableInBundle(@"Disk Image Status", nil, bundle, @"")
										   iconData:nil
										   priority:0
										   isSticky:NO
									   clickContext:nil];
			[description release];
		} else if ( stage == GrowlSafariDownloadStageFinished ) {
			NSBundle *bundle = [GrowlSafari bundle];
			NSString *notificationName = isLongDownload(self) ? NSLocalizedStringFromTableInBundle(@"Download Complete", nil, bundle, @"") : NSLocalizedStringFromTableInBundle(@"Short Download Complete", nil, bundle, @"");
			setDownloadFinished(self);
			NSString *description = [[NSString alloc] initWithFormat:
				NSLocalizedStringFromTableInBundle(@"%@", nil, bundle, "Message shown when a download is complete, where %@ becomes the filename"),
				[self filename]];
			[GrowlApplicationBridge notifyWithTitle:NSLocalizedStringFromTableInBundle(@"Download Complete", nil, bundle, @"")
										description:description
								   notificationName:notificationName
										   iconData:nil
										   priority:0
										   isSticky:NO
									   clickContext:nil];
			[description release];
		}
	} else if (stage == GrowlSafariDownloadStageActive) {
		setDownloadStarted(self);
	}
}

- (void) myUpdateDiskImageStatus:(NSDictionary *)status {
	int oldStage = [self downloadStage];
	[self myUpdateDiskImageStatus:status];
	//NSLog(@"myUpdateDiskImageStatus:%@ stage=%d -> %d", status, oldStage, [self downloadStage]);

	if (dateStarted(self)
			&& oldStage == GrowlSafariDownloadStageDiskImageVerified
			&& [self downloadStage] == GrowlSafariDownloadStageDiskImageMounting
			&& [[status objectForKey:@"status-stage"] isEqualToString:@"attach"]) {
		NSBundle *bundle = [GrowlSafari bundle];
		NSString *description = [[NSString alloc] initWithFormat:
			NSLocalizedStringFromTableInBundle(@"%@", nil, bundle, @""),
			[[self gsDownloadPath] lastPathComponent]];
		[GrowlApplicationBridge notifyWithTitle:NSLocalizedStringFromTableInBundle(@"Mounting Disk Image", nil, bundle, @"")
									description:description
							   notificationName:NSLocalizedStringFromTableInBundle(@"Disk Image Status", nil, bundle, @"")
									   iconData:nil
									   priority:0
									   isSticky:NO
								   clickContext:nil];
		[description release];
	}
}

// This is to make sure we're done with the pre-saved downloads
- (id) myInitWithDownload:(id)fp8 mayOpenWhenDone:(BOOL)fp12 allowOverwrite:(BOOL)fp16 {
	id retval = [self myInitWithDownload:fp8 mayOpenWhenDone:fp12 allowOverwrite:fp16];
	setDownloadStarted(self);
	return retval;
}

- (NSString*) gsDownloadPath {
	return [self currentPath];
}

@end
