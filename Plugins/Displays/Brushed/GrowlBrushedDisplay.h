//
//  GrowlBrushedDisplay.h
//  Display Plugins
//
//  Created by Ingmar Stein on 12/01/2004.
//  Copyright 2004-2005 The Growl Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GrowlDisplayPlugin.h"

@class NSPreferencePane;

@interface GrowlBrushedDisplay : GrowlDisplayPlugin {
}

- (void) displayNotification:(GrowlApplicationNotification *)notification;
- (void) brushedGone:(NSNotification *)note;

@end
