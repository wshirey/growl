//  GrowlTunes.c
//  GrowlTunesPlugin
//
//  Created by rudy on 11/27/05.
//  Copyright 2005 The Growl Project. All rights reserved.


/**\
|**|	includes
\**/

#include "iTunesVisualAPI.h"
#include "Growl/Growl.h"

/**\
|**|	typedef's, struct's, enum's, etc.
\**/

#define kTVisualPluginName              "\pGrowlTunes"
#define	kTVisualPluginCreator           'GRWL'

#define	kTVisualPluginMajorVersion		1
#define	kTVisualPluginMinorVersion		0
#define	kTVisualPluginReleaseStage		finalStage
#define	kTVisualPluginNonFinalRelease	0


#define ITUNES_TRACK_CHANGED	CFSTR("Changed Tracks")
#define ITUNES_PAUSED			CFSTR("Paused")
#define ITUNES_STOPPED			CFSTR("Stopped")
#define ITUNES_PLAYING			CFSTR("Started Playing")

typedef Boolean (*GrowlSetDelegateProcPtr) (struct Growl_Delegate *newDelegate);
static GrowlSetDelegateProcPtr GrowlTunes_SetDelegate;

typedef void (*GrowlPostNotificationProcPtr)(const struct Growl_Notification *notification);
static GrowlPostNotificationProcPtr GrowlTunes_PostNotification;

typedef Boolean (*GrowlIsInstalledProcPtr)(void);
static GrowlIsInstalledProcPtr GrowlTunes_GrowlIsInstalled;


typedef struct VisualPluginData {
	void 				*appCookie;
	ITAppProcPtr		appProc;

	ITFileSpec			pluginFileSpec;

	CGrafPtr			destPort;
	Rect				destRect;
	OptionBits			destOptions;
	UInt32				destBitDepth;

	RenderVisualData	renderData;
	UInt32				renderTimeStampID;

	ITTrackInfo			trackInfo;
	ITStreamInfo		streamInfo;

	Boolean				playing;
	Boolean				padding[3];

//	Plugin-specific data
	UInt8				minLevel[kVisualMaxDataChannels];		// 0-128
	UInt8				maxLevel[kVisualMaxDataChannels];		// 0-128

	UInt8				min,max;

	GWorldPtr			offscreen;
} VisualPluginData;

typedef struct Growl_Notification Growl_Notification;
static struct Growl_Delegate delegate;
extern CFArrayCallBacks notificationCallbacks;

/**\
|**|	exported function prototypes
\**/

extern OSStatus iTunesPluginMainMachO(OSType message, PluginMessageInfo *messageInfo, void *refCon);
extern void CFLog(int priority, CFStringRef format, ...);

static OSStatus VisualPluginHandler(OSType message, VisualPluginMessageInfo *messageInfo, void *refCon)
{
	OSStatus         err = noErr;
	VisualPluginData *visualPluginData;

	visualPluginData = (VisualPluginData *)refCon;

	err = noErr;

	switch (message) {
		/*
			Sent when the visual plugin is registered.  The plugin should do minimal
			memory allocations here.  The resource fork of the plugin is still available.
		*/
		case kVisualPluginInitMessage:
			visualPluginData = (VisualPluginData *)calloc(1, sizeof(VisualPluginData));
			if (!visualPluginData) {
				err = memFullErr;
				break;
			}

			visualPluginData->appCookie	= messageInfo->u.initMessage.appCookie;
			visualPluginData->appProc	= messageInfo->u.initMessage.appProc;

			/* Remember the file spec of our plugin file. We need this so we can open our resource fork during */
			/* the configuration message */

			err = PlayerGetPluginITFileSpec(visualPluginData->appCookie, visualPluginData->appProc, &visualPluginData->pluginFileSpec);

			messageInfo->u.initMessage.refCon = (void *)visualPluginData;
			break;

		/*
			Sent when the visual plugin is unloaded
		*/
		case kVisualPluginCleanupMessage:
			if (visualPluginData)
				free(visualPluginData);
			break;

		/*
			Sent when the visual plugin is enabled.  iTunes currently enables all
			loaded visual plugins.  The plugin should not do anything here.
		*/
		case kVisualPluginEnableMessage:
		case kVisualPluginDisableMessage:
			break;

		/*
			Sent if the plugin requests idle messages.  Do this by setting the kVisualWantsIdleMessages
			option in the RegisterVisualMessage.options field.
		*/
		case kVisualPluginIdleMessage:
			break;

		/*
			Sent if the plugin requests the ability for the user to configure it.  Do this by setting
			the kVisualWantsConfigure option in the RegisterVisualMessage.options field.
		*/
		case kVisualPluginConfigureMessage:
			break;
		/*
			Sent when iTunes is going to show the visual plugin in a port.  At
			this point,the plugin should allocate any large buffers it needs.
		*/
		case kVisualPluginShowWindowMessage:
			break;

		/*
			Sent when iTunes is no longer displayed.
		*/
		case kVisualPluginHideWindowMessage:
			break;

		/*
			Sent when iTunes needs to change the port or rectangle of the currently
			displayed visual.
		*/
		case kVisualPluginSetWindowMessage:
			break;

		/*
			Sent for the visual plugin to render a frame.
		*/
		case kVisualPluginRenderMessage:
			break;
		/*
			Sent in response to an update event.  The visual plugin should update
			into its remembered port.  This will only be sent if the plugin has been
			previously given a ShowWindow message.
		*/
		case kVisualPluginUpdateMessage:
			break;
		/*
			Sent when the player starts.
		*/
		case kVisualPluginPlayMessage: {
			CFStringRef title;
			CFStringRef album;
			CFStringRef artist;
			CFStringRef desc;
			CFStringRef	totalTime;
			//CFStringRef	rating;

			//printf("size %ld\n", sizeof(visualPluginData->trackInfo));
			if (messageInfo->u.playMessage.trackInfo)
				visualPluginData->trackInfo = *messageInfo->u.playMessage.trackInfoUnicode;
			else
				memset(&visualPluginData->trackInfo, 0, sizeof(visualPluginData->trackInfo));

			if (messageInfo->u.playMessage.streamInfo)
				visualPluginData->streamInfo = *messageInfo->u.playMessage.streamInfoUnicode;
			else
				memset(&visualPluginData->streamInfo, 0, sizeof(visualPluginData->streamInfo));

			if (visualPluginData->trackInfo.validFields & kITTINameFieldMask)
				title = CFStringCreateWithCharactersNoCopy(kCFAllocatorDefault, &visualPluginData->trackInfo.name[1], visualPluginData->trackInfo.name[0], kCFAllocatorNull);
			else
				title = CFSTR("");
			if (visualPluginData->trackInfo.validFields & kITTIArtistFieldMask)
				artist = CFStringCreateWithCharactersNoCopy(kCFAllocatorDefault, &visualPluginData->trackInfo.artist[1], visualPluginData->trackInfo.artist[0], kCFAllocatorNull);
			else
				artist = CFSTR("");
			if (visualPluginData->trackInfo.validFields & kITTIAlbumFieldMask)
				album = CFStringCreateWithCharactersNoCopy(kCFAllocatorDefault, &visualPluginData->trackInfo.album[1], visualPluginData->trackInfo.album[0], kCFAllocatorNull);
			else
				album = CFSTR("");
			if (visualPluginData->trackInfo.validFields & kITTITotalTimeFieldMask) {
				int minutes = visualPluginData->trackInfo.totalTimeInMS / 1000 / 60;
				int seconds = visualPluginData->trackInfo.totalTimeInMS / 1000 - minutes * 60;
				totalTime = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%d:%d"), minutes, seconds);
			} else {
				totalTime = CFSTR("");
			}
			/*if (visualPluginData->trackInfo.userRating == 0)
				rating = CFSTR("·····");
			if (visualPluginData->trackInfo.userRating == 1)
				rating = CFSTR("✯····");
			if (visualPluginData->trackInfo.userRating == 2)
				rating = CFSTR("✯✯···");
			if (visualPluginData->trackInfo.userRating == 3)
				rating = CFSTR("✯✯✯··");
			if (visualPluginData->trackInfo.userRating == 4)
				rating = CFSTR("✯✯✯✯·");
			if (visualPluginData->trackInfo.userRating == 5)
				rating = CFSTR("✯✯✯✯✯");*/
			desc = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@\n%@\n%@"), totalTime, artist, album);

			CFLog(1, CFSTR("%s\n"), __FUNCTION__);
			CFLog(1, CFSTR("title: %@\n"), title);
			CFLog(1, CFSTR("time: %@\n"), time);
			CFLog(1, CFSTR("artist: %@\n"), artist);
			CFLog(1, CFSTR("album: %@\n"), album);
			CFLog(1, CFSTR("desc: %@\n"), desc);

			Handle coverArt = NULL;
			OSType format;
			CFDataRef coverArtDataRef = NULL;
			err = PlayerGetCurrentTrackCoverArt(visualPluginData->appCookie, visualPluginData->appProc, &coverArt, &format);
			//CFLog(1, CFSTR("%d %p\n"), err, coverArt);
			if ((err == noErr) && coverArt) {
				//get our data ready for the notificiation.
				coverArtDataRef = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, (const UInt8 *)*coverArt, GetHandleSize(coverArt), kCFAllocatorNull);
			} else {
				char *string = (char *)&format;
				CFLog(1, CFSTR("%d: %c%c%c%c"), err, string[0], string[1], string[2], string[3]);
			}
			//insert growl notification here. bong.
			Growl_Notification notification;

			InitGrowlNotification(&notification);

			//notification.size          = sizeof(struct Growl_Notification);
			notification.name          = ITUNES_PLAYING;
			notification.title         = title;
			notification.description   = desc;
			//notification.priority      = priority;
			if (coverArtDataRef)
				notification.iconData  = coverArtDataRef;
			//notification.reserved      = 0;
			//notification.isSticky      = isSticky;
			//notification.clickContext  = NULL;
			//notification.clickCallback = NULL;
			//notification.enabledByDefault      = isDefault;
			notification.identifier    = CFSTR("GrowlTunes");

			GrowlTunes_PostNotification(&notification);

			if (title)
				CFRelease(title);
			if (artist)
				CFRelease(artist);
			if (album)
				CFRelease(album);
			if (desc)
				CFRelease(desc);
			if (coverArtDataRef)
				CFRelease(coverArtDataRef);
			if (coverArt)
				DisposeHandle(coverArt);
			visualPluginData->playing = true;
			break;
		}

		/*
			Sent when the player changes the current track information.  This
			is used when the information about a track changes,or when the CD
			moves onto the next track.  The visual plugin should update any displayed
			information about the currently playing song.
		*/
		case kVisualPluginChangeTrackMessage:
			if (messageInfo->u.changeTrackMessage.trackInfo)
				visualPluginData->trackInfo = *messageInfo->u.changeTrackMessage.trackInfoUnicode;
			else
				memset(&visualPluginData->trackInfo, 0, sizeof(visualPluginData->trackInfo));

			if (messageInfo->u.changeTrackMessage.streamInfo)
				visualPluginData->streamInfo = *messageInfo->u.changeTrackMessage.streamInfoUnicode;
			else
				memset(&visualPluginData->streamInfo, 0, sizeof(visualPluginData->streamInfo));
			break;

		/*
			Sent when the player stops.
		*/
		case kVisualPluginStopMessage:
			break;

		/*
			Sent when the player changes position.
		*/
		case kVisualPluginSetPositionMessage:
			break;

		/*
			Sent when the player pauses.  iTunes does not currently use pause or unpause.
			A pause in iTunes is handled by stopping and remembering the position.
		*/
		case kVisualPluginPauseMessage:
			break;

		/*
			Sent when the player unpauses.  iTunes does not currently use pause or unpause.
			A pause in iTunes is handled by stopping and remembering the position.
		*/
		case kVisualPluginUnpauseMessage:
			break;

		/*
			Sent to the plugin in response to a MacOS event.  The plugin should return noErr
			for any event it handles completely,or an error (unimpErr) if iTunes should handle it.
		*/
		case kVisualPluginEventMessage:
			err = unimpErr;
			break;

		default:
			err = unimpErr;
			break;
	}
	return err;
}

/*
	RegisterVisualPlugin
*/
static OSStatus RegisterVisualPlugin(PluginMessageInfo *messageInfo)
{
	printf("%s\n", __FUNCTION__);

	OSStatus			err = noErr;
	PlayerMessageInfo	playerMessageInfo;
	Str255				pluginName = kTVisualPluginName;

	memset(&playerMessageInfo.u.registerVisualPluginMessage, 0, sizeof(playerMessageInfo.u.registerVisualPluginMessage));

	memcpy(playerMessageInfo.u.registerVisualPluginMessage.name, pluginName, pluginName[0] + 1);

	SetNumVersion(&playerMessageInfo.u.registerVisualPluginMessage.pluginVersion, kTVisualPluginMajorVersion, kTVisualPluginMinorVersion, kTVisualPluginReleaseStage, kTVisualPluginNonFinalRelease);

	playerMessageInfo.u.registerVisualPluginMessage.options        = kPluginWantsToBeLeftOpen;
	playerMessageInfo.u.registerVisualPluginMessage.handler        = (VisualPluginProcPtr)VisualPluginHandler;
	playerMessageInfo.u.registerVisualPluginMessage.registerRefCon = NULL;
	playerMessageInfo.u.registerVisualPluginMessage.creator        = kTVisualPluginCreator;

	err = PlayerRegisterVisualPlugin(messageInfo->u.initMessage.appCookie,messageInfo->u.initMessage.appProc,&playerMessageInfo);

	return err;
}

/**\
|**|	main entrypoint
\**/

OSStatus iTunesPluginMainMachO(OSType message, PluginMessageInfo *messageInfo, void *refCon)
{
#pragma unused(refCon)
	OSStatus		err = noErr;
	printf("%s\n", __FUNCTION__);
	switch (message) {
		case kPluginInitMessage:
			err = RegisterVisualPlugin(messageInfo);
			//register with growl and setup our delegate
			CFBundleRef growlMailBundle = CFBundleGetBundleWithIdentifier(CFSTR("com.growl.growltunes"));
			CFURLRef privateFrameworksURL = CFBundleCopyPrivateFrameworksURL(growlMailBundle);
			CFURLRef growlBundleURL = CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, privateFrameworksURL, CFSTR("Growl.framework"), true);
			CFRelease(privateFrameworksURL);
			CFBundleRef growlBundle = CFBundleCreate(kCFAllocatorDefault, growlBundleURL);
			CFRelease(growlBundleURL);
			if (growlBundle) {
				if (CFBundleLoadExecutable(growlBundle)) {
					//manually load these buggers since just weak linking the framework doesn't cut it.
					GrowlTunes_SetDelegate = CFBundleGetFunctionPointerForName(growlBundle, CFSTR("Growl_SetDelegate"));
					GrowlTunes_PostNotification = CFBundleGetFunctionPointerForName(growlBundle, CFSTR("Growl_PostNotification"));
					GrowlTunes_GrowlIsInstalled = CFBundleGetFunctionPointerForName(growlBundle, CFSTR("Growl_IsInstalled"));

					if (GrowlTunes_SetDelegate && GrowlTunes_PostNotification && GrowlTunes_GrowlIsInstalled) {

						InitGrowlDelegate(&delegate);

						CFMutableArrayRef allNotifications = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
						CFArrayAppendValue(allNotifications, ITUNES_PLAYING);
						CFArrayAppendValue(allNotifications, ITUNES_TRACK_CHANGED);

						CFMutableArrayRef defaultNotifications = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
						CFArrayAppendValue(defaultNotifications, ITUNES_PLAYING);
						CFArrayAppendValue(defaultNotifications, ITUNES_TRACK_CHANGED);

						CFTypeRef keys[] = { GROWL_APP_NAME, GROWL_NOTIFICATIONS_ALL, GROWL_NOTIFICATIONS_DEFAULT };
						CFTypeRef values[] = {CFSTR("GrowlTunes"), allNotifications, defaultNotifications };
						delegate.registrationDictionary = CFDictionaryCreate(
														 kCFAllocatorDefault, keys, values, 3,
														 &kCFTypeDictionaryKeyCallBacks,
														 &kCFTypeDictionaryValueCallBacks);
						CFLog(1, CFSTR("%@\n"), delegate.registrationDictionary);
						if (GrowlTunes_SetDelegate(&delegate))
							CFLog(1, CFSTR("registered"));
						else
							CFLog(1, CFSTR("not registered"));

						if (!GrowlTunes_GrowlIsInstalled()) {
							//notify the user that growl isn't installed and as such that there won't be any notifications for this session of iTunes.
						}

						//lets nuke the menu item :)
						//MenuBarHandle iTunesMenuBar = GetMenuBar();

						//MenuRef rootMenu = AcquireRootMenu ();
						//CFLog(1, CFSTR("%@"), rootMenu);
						//DisposeMenuBar(iTunesMenuBar);
						if (growlBundle)
							CFRelease(growlBundle);
					} else {
						err = unimpErr;
					}
				}

			}
			break;

		case kPluginCleanupMessage:
			err = noErr;
			if (delegate.registrationDictionary)
				CFRelease(delegate.registrationDictionary);

			break;

		default:
			err = unimpErr;
			break;
	}

	return err;
}
