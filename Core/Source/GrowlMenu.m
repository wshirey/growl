//
//  GrowlMenu.m
//
//
//  Created by rudy on Sun Apr 17 2005.
//  Copyright (c) 2005 The Growl Project. All rights reserved.
//

#import "GrowlMenu.h"
#import "GrowlPreferencesController.h"
#import "GrowlPreferencePane.h"
#import "GrowlPathUtilities.h"
#import "GrowlNotificationDatabase.h"
#import "GrowlHistoryNotification.h"
#import "GrowlApplicationController.h"
#include <unistd.h>

#define kStartGrowl                  NSLocalizedString(@"Resume Growl", @"")
#define kStartGrowlTooltip           NSLocalizedString(@"Resume Growl visual notifications", @"")
#define kStopGrowl                   NSLocalizedString(@"Pause Growl", @"")
#define kStopGrowlTooltip            NSLocalizedString(@"Pause Growl visual notifications", @"")
#define kShowRollup                  NSLocalizedString(@"Show Rollup", @"")
#define kShowRollupTooltip           NSLocalizedString(@"Show the History Rollup", @"")
#define kHideRollup                  NSLocalizedString(@"Hide Rollup", @"")
#define kHideRollupTooltip           NSLocalizedString(@"Hide the History Rollup", @"")
#define kOpenGrowlPreferences        NSLocalizedString(@"Open Growl Preferences...", @"")
#define kOpenGrowlPreferencesTooltip NSLocalizedString(@"Open the Growl preference pane", @"")
#define kNoRecentNotifications       NSLocalizedString(@"No Recent Notifications", @"")
#define kOpenGrowlLogTooltip         NSLocalizedString(@"Application: %@\nTitle: %@\nDescription: %@\nClick to open the log", @"")
#define kGrowlHistoryLogDisabled     NSLocalizedString(@"Growl History Disabled", @"")
#define kGrowlQuit                   NSLocalizedString(@"Quit", @"")
#define kQuitGrowlMenuTooltip        NSLocalizedString(@"Quit Growl entirely", @"")

#define kStartStopMenuTag           1
#define kShowHideRollupTag          2
#define kHistoryItemTag             6
#define kMenuItemsBeforeHistory     6

@implementation GrowlMenu

@synthesize settingsWindow;
@synthesize statusItem;


#pragma mark -

- (id) init {
    
    if ((self = [super init])) {
        preferences = [GrowlPreferencesController sharedController];
        
        NSMenu *m = [self createMenu];
        
        self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
        
        
        [self setImage:[NSNumber numberWithBool:![preferences squelchMode]]];
        
        [statusItem setMenu:m]; // retains m
        [statusItem setToolTip:@"Growl"];
        [statusItem setHighlightMode:YES];
        
        [self setGrowlMenuEnabled:YES];
        
        //NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        /*[nc addObserver:self
         selector:@selector(reloadPrefs:)
         name:GrowlPreferencesChanged
         object:nil];*/
        
        GrowlNotificationDatabase *db = [GrowlNotificationDatabase sharedInstance];
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(growlDatabaseDidUpdate:) 
                                                     name:@"GrowlDatabaseUpdated"
                                                   object:db];
        
        [preferences addObserver:self forKeyPath:@"squelchMode" options:NSKeyValueObservingOptionNew context:&self];
    }
    return self;
}

- (void) dealloc {
//	[[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
//	[statusItem            release];

    [preferences removeObserver:self forKeyPath:@"squelchMode"];
	[super dealloc];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if([keyPath isEqualToString:@"squelchMode"])
    {
        NSMenuItem *menuItem = [[[statusItem menu] itemArray] objectAtIndex:0U];
        BOOL squelch = [preferences squelchMode] ? NO : YES;        
        if (!squelch) {
            [menuItem setTitle:kStopGrowl];
            [menuItem setToolTip:kStopGrowlTooltip];
        } else {
            [menuItem setTitle:kStartGrowl];
            [menuItem setToolTip:kStartGrowlTooltip];
        }
        [self setImage:[NSNumber numberWithBool:squelch]];
    }
}
#pragma mark -
#pragma mark Growl History
#pragma mark -

-(void)growlDatabaseDidUpdate:(NSNotification*)notification
{
   NSArray *noteArray = [[GrowlNotificationDatabase sharedInstance] mostRecentNotifications:5];
   NSArray *menuItems = [[statusItem menu] itemArray];
   
   unsigned int menuIndex = kMenuItemsBeforeHistory;
   if([noteArray count] > 0)
   {
      for(id note in noteArray)
      {
         NSString *tooltip = [NSString stringWithFormat:kOpenGrowlLogTooltip, [note ApplicationName], [note Title], [note Description]];
         //Do we presently have a menu item for this note? if so, change it, if not, add a new one
         if(menuIndex < [menuItems count])
         {
            [[menuItems objectAtIndex:menuIndex] setTitle:[note Title]];
            [[menuItems objectAtIndex:menuIndex] setToolTip:tooltip];
            [[statusItem menu] itemChanged:[menuItems objectAtIndex:menuIndex]];
         }else {
            NSMenuItem *tempMenuItem = (NSMenuItem *)[[statusItem menu] addItemWithTitle:[note Title] action:@selector(openGrowlLog:) keyEquivalent:@""];
            [tempMenuItem setTarget:self];
            [tempMenuItem setToolTip:tooltip];
            [[statusItem menu] itemChanged:tempMenuItem];
         }
         menuIndex++;
      }
      //Did we get back less than are on the menu? remove any extra listings
      if ([noteArray count] < [[[statusItem menu] itemArray] count] - kMenuItemsBeforeHistory) {
         NSInteger toRemove = 0;
         for(toRemove = [[[statusItem menu] itemArray] count] - [noteArray count] - kMenuItemsBeforeHistory ; toRemove > 0; toRemove--)
         {
            [[statusItem menu] removeItemAtIndex:menuIndex];
         }
      }
   }else {
      if ([preferences isGrowlHistoryLogEnabled])
         [[menuItems objectAtIndex:menuIndex] setTitle:kNoRecentNotifications];
      else
         [[menuItems objectAtIndex:menuIndex] setTitle:kGrowlHistoryLogDisabled];
      [[menuItems objectAtIndex:menuIndex] setToolTip:@""];
      [[menuItems objectAtIndex:menuIndex] setTarget:self];
      
      //Make sure there arent extra items at the moment since we don't seem to have any
      NSInteger toRemove = 0;
      for(toRemove = [menuItems count]; toRemove > kMenuItemsBeforeHistory + 1; toRemove--)
      {
         [[statusItem menu] removeItemAtIndex:toRemove - 1];
      }
   }

}

#pragma mark -
#pragma mark IBActions
#pragma mark -

- (IBAction) openGrowlPreferences:(id)sender {
   [[GrowlApplicationController sharedInstance] showPreferences];
}

- (IBAction) startStopGrowl:(id)sender {
    BOOL squelch = [preferences squelchMode] ? NO : YES;
    [preferences setSquelchMode:squelch];
}

- (IBAction)openGrowlLog:(id)sender
{
    [preferences setSelectedPreferenceTab:4];
    [self openGrowlPreferences:nil];
}

- (IBAction)toggleRollup:(id)sender
{
   [preferences setRollupShown:![preferences isRollupShown]];
}

#pragma mark -

- (void) setGrowlMenuEnabled:(BOOL)state {
	/*NSString *growlMenuPath = [[NSBundle mainBundle] bundlePath];
	[preferences setStartAtLogin:growlMenuPath enabled:state];*/
    
	[self setImage:[NSNumber numberWithBool:![preferences squelchMode]]];
}

- (void) setImage:(NSNumber*)state {
	
	NSImage *normalImage = nil;
	NSImage *pressedImage = nil;
	switch([state unsignedIntegerValue])
	{
		case kGrowlNotRunningState:
			normalImage = [NSImage imageNamed:@"squelch.png"];
			pressedImage = [NSImage imageNamed:@"growlmenu.png"];
			break;
		case kGrowlRunningState:
		default:
			normalImage = [NSImage imageNamed:@"growlmenu.png"];
			pressedImage = [NSImage imageNamed:@"growlmenu-alt.png"];
			break;
	}
	[statusItem setImage:normalImage];
	[statusItem setAlternateImage:pressedImage];
}

- (NSMenu *) createMenu {
	NSZone *menuZone = [NSMenu menuZone];
	NSMenu *m = [[NSMenu allocWithZone:menuZone] init];

	NSMenuItem *tempMenuItem;

	tempMenuItem = (NSMenuItem *)[m addItemWithTitle:kStartGrowl action:@selector(startStopGrowl:) keyEquivalent:@""];
	[tempMenuItem setTarget:self];
	[tempMenuItem setTag:kStartStopMenuTag];

	if (![preferences squelchMode]) {
		[tempMenuItem setTitle:kStopGrowl];
		[tempMenuItem setToolTip:kStopGrowlTooltip];
	} else {
		[tempMenuItem setToolTip:kStartGrowlTooltip];
	}
   
   tempMenuItem = (NSMenuItem *)[m addItemWithTitle:kShowRollup action:@selector(toggleRollup:) keyEquivalent:@""];
   [tempMenuItem setTarget:self];
   [tempMenuItem setTag:kShowHideRollupTag];
   if([preferences isRollupShown]){
      [tempMenuItem setTitle:kHideRollup];
      [tempMenuItem setToolTip:kHideRollupTooltip];
   }else{
      [tempMenuItem setToolTip:kShowRollupTooltip];
   }

	[m addItem:[NSMenuItem separatorItem]];

	tempMenuItem = (NSMenuItem *)[m addItemWithTitle:kOpenGrowlPreferences action:@selector(openGrowlPreferences:) keyEquivalent:@""];
	[tempMenuItem setTarget:self];
	[tempMenuItem setToolTip:kOpenGrowlPreferencesTooltip];
   
	tempMenuItem = (NSMenuItem *)[m addItemWithTitle:kGrowlQuit action:@selector(terminate:) keyEquivalent:@""];
	[tempMenuItem setTarget:NSApp];
	[tempMenuItem setToolTip:kQuitGrowlMenuTooltip];
    
	[m addItem:[NSMenuItem separatorItem]];
   /*TODO: need to check against prefferences whether we are logging or not*/
   NSArray *noteArray = [[GrowlNotificationDatabase sharedInstance] mostRecentNotifications:5];
   if([noteArray count] > 0)
   {
      for(id note in noteArray)
      {
         tempMenuItem = (NSMenuItem *)[m addItemWithTitle:[note Title] 
                                                   action:@selector(openGrowlLog:)
                                            keyEquivalent:@""];
         [tempMenuItem setTarget:self];
         [tempMenuItem setToolTip:[NSString stringWithFormat:kOpenGrowlLogTooltip, [note ApplicationName], [note Title], [note Description]]];
         [tempMenuItem setTag:kHistoryItemTag];
      }
   }else {
      NSString *tempString;
      if ([preferences isGrowlHistoryLogEnabled])
         tempString = kNoRecentNotifications;
      else
         tempString = kGrowlHistoryLogDisabled;
      tempMenuItem = (NSMenuItem *)[m addItemWithTitle:tempString 
                                                action:@selector(openGrowlLog:)
                                         keyEquivalent:@""];
      [tempMenuItem setTarget:self];
      [tempMenuItem setEnabled:NO];
      [tempMenuItem setTag:kHistoryItemTag];
   }
    

	return [m autorelease];
}

- (BOOL) validateMenuItem:(NSMenuItem *)item {
	BOOL isGrowlRunning = ![preferences squelchMode];
	//we do this because growl might have died or been launched, and NSWorkspace doesn't post 
	//notifications to its notificationCenter for LSUIElement apps for NSWorkspaceDidLaunchApplicationNotification or NSWorkspaceDidTerminateApplicationNotification
	[self setImage:[NSNumber numberWithBool:isGrowlRunning]];
	
	switch ([item tag]) {
		case kStartStopMenuTag:
			if (isGrowlRunning) {
				[item setTitle:kStopGrowl];
				[item setToolTip:kStopGrowlTooltip];
			} else {
				[item setTitle:kStartGrowl];
				[item setToolTip:kStartGrowlTooltip];
			}
			break;
      case kShowHideRollupTag:
         if ([preferences isRollupShown]) {
				[item setTitle:kHideRollup];
				[item setToolTip:kHideRollupTooltip];
			} else {
				[item setTitle:kShowRollup];
				[item setToolTip:kShowRollupTooltip];
			}

         break;
      case kHistoryItemTag:
         return ![[item title] isEqualToString:kNoRecentNotifications] && ![[item title] isEqualToString:kGrowlHistoryLogDisabled];
         break;
	}
	return YES;
}

@end