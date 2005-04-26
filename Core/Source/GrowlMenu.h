//
//  GrowlMenu.h
//
//

#import <Foundation/Foundation.h>
//#import "SystemUIPlugin.h"

@class GrowlPreferences, NSStatusItem;

@interface GrowlMenu : NSObject {
	GrowlPreferences	*preferences;
	NSStatusItem		*statusItem;

	NSImage				*clawImage;
	NSImage				*clawHighlightImage;
	NSImage				*squelchImage;
	NSImage				*squelchHighlightImage;
}

- (IBAction) openGrowl:(id)sender;
- (IBAction) defaultDisplay:(id)sender;
- (IBAction) stopGrowl:(id)sender;
- (IBAction) startGrowl:(id)sender;
- (NSMenu *) buildMenu;
- (BOOL) validateMenuItem:(NSMenuItem *)item;

@end
