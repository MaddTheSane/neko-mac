#import "NekoPermissions.h"
#import "NekoGlance.h"
#import "NekoPlace.h"
#import "NekoPlayer.h"
#import "NekoPluginVerbs.h"
#import "NekoListener.h"
#import "NekoDesktop.h"
#import "NekoWakeWord.h"
#import "NekoAsk.h"
#import "NekoController.h"
#import "NekoFolderAccess.h"
#import <AVFoundation/AVFoundation.h>

@implementation NekoPermission

- (id)initWithIdentifier:(NSString *)key
{
	self = [super init];
	if(self != nil)
		identifier = [key copy];
	return self;
}

@synthesize identifier;

- (NSString *)name
{
	if([identifier isEqualToString:@"microphone"])
		return NSLocalizedString(@"Microphone", @"Microphone");
	if([identifier isEqualToString:@"speech"])
		return NSLocalizedString(@"Speech recognition", @"Speech recognition");
	if([identifier isEqualToString:@"accessibility"])
		return NSLocalizedString(@"Accessibility", @"Accessibility");
	if([identifier isEqualToString:@"screen"])
		return NSLocalizedString(@"Screen recording", @"Screen recording");
	if([identifier isEqualToString:@"folders"])
		return NSLocalizedString(@"Your folders", @"Your folders");
	if([identifier isEqualToString:@"location"])
		return NSLocalizedString(@"Where you are", @"Where you are");
	if([identifier isEqualToString:@"players"])
		return NSLocalizedString(@"Music and Spotify", @"Music and Spotify");
	return identifier;
}

- (NSString *)explanation
{
	if([identifier isEqualToString:@"microphone"])
		return NSLocalizedString(@"Without it the cat cannot hear a question. Asked the first time you use the keystroke, never before.", @"Without it the cat cannot hear a question. Asked the first time you use the keystroke, never before.");
	if([identifier isEqualToString:@"speech"])
		return NSLocalizedString(@"Turns what you said into words. On this Mac it stays on this Mac.", @"Turns what you said into words. On this Mac it stays on this Mac.");
	if([identifier isEqualToString:@"accessibility"])
		return NSLocalizedString(@"Only for reading the text you are working on, which is a switch of its own on the Suggestions tab. Nothing else uses it.", @"Only for reading the text you are working on, which is a switch of its own on the Suggestions tab. Nothing else uses it.");
	if([identifier isEqualToString:@"screen"])
		return NSLocalizedString(@"Window titles, and nothing else. Neko never asks for this one: it is used if you granted it for some other reason, and simply left out if not.", @"Window titles, and nothing else. Neko never asks for this one: it is used if you granted it for some other reason, and simply left out if not.");
	if([identifier isEqualToString:@"folders"])
		return NSLocalizedString(@"Handed over one folder at a time, in a panel, so the cat can copy or move a file. Nothing is read until you do.", @"Handed over one folder at a time, in a panel, so the cat can copy or move a file. Nothing is read until you do.");
	if([identifier isEqualToString:@"players"])
		return NSLocalizedString(@"So that “alza il volume”, “metti in pausa” and “prossima canzone” reach Music and Spotify themselves. Those two applications and no others, with a fixed list of commands Neko sends. macOS asks once for each of them.", @"So that “alza il volume”, “metti in pausa” and “prossima canzone” reach Music and Spotify themselves. Those two applications and no others, with a fixed list of commands Neko sends. macOS asks once for each of them.");
	if([identifier isEqualToString:@"location"]) {
		NSString *town = [[NekoPlace sharedPlace] town];
		NSString *region = [[NekoPlace sharedPlace] region];
		/* Pressing a button and seeing nothing change is the same as a button
		   that does nothing, so when there is an answer the row shows it. */
		if([town length] > 0)
			return [NSString stringWithFormat:
				NSLocalizedString(@"It knows it is in %@%@ — the name of the town and of the region, and nothing finer. No coordinates are kept, and it asks macOS again no oftener than once a day.", @"It knows it is in %@%@ --- the name of the town and of the region, and nothing finer. No coordinates are kept, and it asks macOS again no oftener than once a day."),
				town, [region length] > 0
					? [NSString stringWithFormat:@", %@", region] : @""];
		return NSLocalizedString(@"So that “what is the weather” and “what is happening here” need no city named. It keeps the name of the town and of the region, never the coordinates, and asks macOS for a position no oftener than once a day.", @"So that \"what is the weather\" and \"what is happening here\" need no city named. It keeps the name of the town and of the region, never the coordinates, and asks macOS for a position no oftener than once a day.");
	}
	return @"";
}

#pragma mark What the system says

- (NekoPermissionState)permissionState
{
	if([identifier isEqualToString:@"microphone"]) {
		if(@available(macOS 10.14, *)) {
			switch([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]) {
				case AVAuthorizationStatusAuthorized: return NekoPermissionGranted;
				case AVAuthorizationStatusDenied:
				case AVAuthorizationStatusRestricted: return NekoPermissionDenied;
				default: return NekoPermissionUnknown;
			}
		}
		return NekoPermissionGranted;      /* older systems did not ask */
	}
	if([identifier isEqualToString:@"speech"]) {
		if(![NekoListener isAvailable])
			return NekoPermissionUnavailable;
		switch([NekoListener authorizationStatus]) {
			case 3: return NekoPermissionGranted;
			case 1:
			case 2: return NekoPermissionDenied;
			default: return NekoPermissionUnknown;
		}
	}
	if([identifier isEqualToString:@"accessibility"])
		return [NekoDesktop accessibilityGranted] ? NekoPermissionGranted
		                                          : NekoPermissionUnknown;
	if([identifier isEqualToString:@"screen"])
		return CGPreflightScreenCaptureAccess() ? NekoPermissionGranted
		                                        : NekoPermissionUnknown;
	if([identifier isEqualToString:@"folders"])
		return [[[NekoFolderAccess sharedAccess] allowedKeys] count] > 0
			? NekoPermissionGranted : NekoPermissionUnknown;
	if([identifier isEqualToString:@"players"]) {
		/* Read from the consent database, which costs nothing and asks nobody
		   anything: a tab that prompted for permission by being looked at would be
		   worse than no tab. Granted when either of the two says yes; refused only
		   when every one that is here says no. */
		NekoPlayerConsent music = [NekoPlayer consentFor:@"music"];
		NekoPlayerConsent spotify = [NekoPlayer consentFor:@"spotify"];
		if(music == NekoPlayerConsentImpossible
		   && spotify == NekoPlayerConsentImpossible)
			return NekoPermissionUnavailable;
		if(music == NekoPlayerConsentGiven || spotify == NekoPlayerConsentGiven)
			return NekoPermissionGranted;
		if((music == NekoPlayerConsentRefused
		    || music == NekoPlayerConsentImpossible)
		   && (spotify == NekoPlayerConsentRefused
		       || spotify == NekoPlayerConsentImpossible))
			return NekoPermissionDenied;
		return NekoPermissionUnknown;
	}
	if([identifier isEqualToString:@"location"]) {
		if(![NekoPlace isAvailable])
			return NekoPermissionUnavailable;
		/* A town in hand outranks a status that has not settled: a freshly made
		   CLLocationManager answers "not determined" until the system gets round
		   to telling it otherwise, which is after this row was drawn. Knowing
		   where the Mac is means it was allowed. */
		if([[[NekoPlace sharedPlace] town] length] > 0)
			return NekoPermissionGranted;
		switch([NekoPlace authorizationStatus]) {
			case 3:  return NekoPermissionGranted;
			case 1:
			case 2:  return NekoPermissionDenied;
			default: return NekoPermissionUnknown;
		}
	}
	return NekoPermissionUnknown;
}

- (BOOL)isNeeded
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL asking = [[NekoAsk sharedAsk] isEnabled];
	if([identifier isEqualToString:@"microphone"] || [identifier isEqualToString:@"speech"])
		return asking;
	/* Wanted by looking at the screen, which is no longer a switch somebody
	   leaves on: it is a stretch of time they ask for. So the row is wanted while
	   one is running and while the permission is already granted — and, once it
	   has been granted, it stays wanted so that somebody can see and revoke it
	   rather than having it disappear from the list the moment the look ends. */
	if([identifier isEqualToString:@"accessibility"])
		return [[NekoGlance sharedGlance] isLooking]
		    || [NekoDesktop accessibilityGranted];
	if([identifier isEqualToString:@"folders"])
		return asking && [defaults boolForKey:@"NekoActionsEnabled"];
	/* Wanted only by looking things up, and not even needed for that: without it
	   the cat asks which town instead of knowing. */
	if([identifier isEqualToString:@"location"])
		return NO;
	/* Only if something actually listens for one of those phrases: a plugin the
	   person switched on. Nothing here is wanted by the app on its own. */
	if([identifier isEqualToString:@"players"])
		return [NekoPluginVerbs anythingCommandsAPlayer];
	return NO;                    /* screen recording is never needed, only used */
}

#pragma mark Asking

- (BOOL)canRequest
{
	NekoPermissionState state = [self permissionState];
	if(state == NekoPermissionGranted || state == NekoPermissionUnavailable)
		return NO;
	/* Once macOS has a no on file for one of these, only System Settings can
	   change it: asking again does nothing at all, silently, which is worse than
	   saying so. */
	if(state == NekoPermissionDenied)
		return NO;
	return YES;
}

- (void)request
{
	if([identifier isEqualToString:@"microphone"]) {
		if(@available(macOS 10.14, *))
			[AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio
			                         completionHandler:^(BOOL granted) { }];
		return;
	}
	if([identifier isEqualToString:@"speech"]) {
		[NekoListener requestAuthorization:^(BOOL granted) { }];
		return;
	}
	if([identifier isEqualToString:@"accessibility"]) {
		/* macOS shows the alert for this one exactly once in an app's life.
		   After that the call returns no and puts nothing on screen, which is
		   what "the Ask button does nothing" was: so if the answer is still no a
		   moment later, the pane where it can be changed is opened instead. */
		[NekoDesktop requestAccessibility];
		[self performSelector:@selector(settingsIfStillRefused) withObject:nil afterDelay:1.2];
		return;
	}
	if([identifier isEqualToString:@"screen"]) {
		/* The one permission the app is not supposed to want. Asked for only if
		   somebody presses the button here on purpose. */
		CGRequestScreenCaptureAccess();
		return;
	}
	if([identifier isEqualToString:@"players"]) {
		/* There is no API that asks. The prompt belongs to the first Apple event
		   that needs one, so the smallest harmless question is sent to whichever
		   of the two is here, and macOS does the asking. */
		if([NekoPlayer isInstalled:@"music"])
			[NekoPlayer askToControl:@"music"];
		if([NekoPlayer isInstalled:@"spotify"])
			[NekoPlayer askToControl:@"spotify"];
		/* macOS asks once. After a no it answers no without showing anything,
		   which is what "the Ask button does nothing" was twice before — so if the
		   answer is still no a moment later, the pane where it can be changed is
		   opened instead. */
		[self performSelector:@selector(settingsIfStillRefused)
		           withObject:nil afterDelay:1.2];
		return;
	}
	if([identifier isEqualToString:@"location"]) {
		/* Pressed by hand, so it looks again whatever it already knows: the
		   once-a-day rule is there to stop the app pestering the system, not to
		   stop somebody asking. Before this, pressing the button with a town
		   already in hand returned in six milliseconds having done nothing at
		   all — which is exactly what "the button does nothing" was. */
		[[NekoPlace sharedPlace] lookAgain:^(NSString *town, NSString *region) { }];
		return;
	}
	if([identifier isEqualToString:@"folders"]) {
		/* Which folder is a question, and the preferences ask it with a menu:
		   see -permissionPressed: in the controller. Reaching here means nobody
		   asked, so the Desktop is the sensible default. */
		[NSApp activateIgnoringOtherApps:YES];
		NSString *why = nil;
		[[NekoFolderAccess sharedAccess] requestAccessToFolderKey:@"desktop" saying:&why];
		/* A row in a settings window that refuses in silence is the same complaint
		   twice over, so it says what happened where it happened. */
		if([why length] > 0) {
			NSAlert *said = [[NSAlert alloc] init];
			[said setMessageText:NSLocalizedString(@"That folder was not the one I asked for.", @"That folder was not the one I asked for.")];
			[said setInformativeText:why];
			NSWindow *host = [[NSApp keyWindow] attachedSheet] == nil
				? [NSApp keyWindow] : nil;
			if(host != nil)
				[said beginSheetModalForWindow:host completionHandler:nil];
			else
				[said runModal];
		}
		return;
	}
}

- (void)settingsIfStillRefused
{
	if([self permissionState] != NekoPermissionGranted)
		[self openSettings];
}

- (void)openSettings
{
	NSString *pane = nil;
	if([identifier isEqualToString:@"microphone"])
		pane = @"Privacy_Microphone";
	else if([identifier isEqualToString:@"speech"])
		pane = @"Privacy_SpeechRecognition";
	else if([identifier isEqualToString:@"accessibility"])
		pane = @"Privacy_Accessibility";
	else if([identifier isEqualToString:@"screen"])
		pane = @"Privacy_ScreenCapture";
	else if([identifier isEqualToString:@"folders"])
		pane = @"Privacy_AllFiles";
	else if([identifier isEqualToString:@"location"])
		pane = @"Privacy_LocationServices";
	else if([identifier isEqualToString:@"players"])
		pane = @"Privacy_Automation";
	if(pane == nil)
		return;
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:
		[@"x-apple.systempreferences:com.apple.preference.security?" stringByAppendingString:pane]]];
}

@end


@implementation NekoPermissions

+ (NSArray<NekoPermission*> *)all
{
	NSMutableArray *all = [NSMutableArray array];
	static NSArray *const e = @[@"microphone", @"speech",
								@"accessibility", @"location", @"players",
								@"folders", @"screen"];
	for (NSString *key in e) {
		[all addObject:[[NekoPermission alloc] initWithIdentifier:key]];
	}
	return all;
}

+ (NSArray<NekoPermission*> *)missing
{
	NSMutableArray *missing = [NSMutableArray array];
	for(NekoPermission *permission in [self all])
		if([permission isNeeded] && [permission permissionState] != NekoPermissionGranted)
			[missing addObject:permission];
	return missing;
}

@end
