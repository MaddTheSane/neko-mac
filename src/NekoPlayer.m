#import "NekoPlayer.h"

NSString * const NekoPlayerPlay       = @"play";
NSString * const NekoPlayerPause      = @"pause";
NSString * const NekoPlayerPlayPause  = @"playpause";
NSString * const NekoPlayerNext       = @"next";
NSString * const NekoPlayerPrevious   = @"previous";
NSString * const NekoPlayerVolumeUp   = @"volumeup";
NSString * const NekoPlayerVolumeDown = @"volumedown";
NSString * const NekoPlayerPlayNamed  = @"playnamed";

/* Ten points a step. Measured against the two applications rather than chosen:
   both take a volume of 0 to 100, and a step of ten is four presses from half to
   full, which is what somebody saying "alza il volume" twice expects. */
static const int NekoVolumeStep = 10;

NSString * const NekoPlayerConsentDidChangeNotification = @"NekoPlayerConsentDidChange";

/* What the last attempt found out, per application. Nothing here is a guess about
   what macOS would say; it is what macOS did say, the last time somebody asked it
   something. */
static NSString *NekoConsentKeyFor(NSString *player)
{
	return [NSString stringWithFormat:@"NekoPlayerConsent.%@",
		[player lowercaseString]];
}

@implementation NekoPlayer

+ (NSArray *)players
{
	return [NSArray arrayWithObjects:@"music", @"spotify", nil];
}

+ (NSArray *)commands
{
	return [NSArray arrayWithObjects:
		NekoPlayerPlay, NekoPlayerPause, NekoPlayerPlayPause,
		NekoPlayerNext, NekoPlayerPrevious,
		NekoPlayerVolumeUp, NekoPlayerVolumeDown, NekoPlayerPlayNamed, nil];
}

+ (BOOL)knows:(NSString *)player
{
	return [[self players] containsObject:[player lowercaseString]];
}

+ (BOOL)knowsCommand:(NSString *)command
{
	return [[self commands] containsObject:[command lowercaseString]];
}

+ (NSString *)bundleIdentifierFor:(NSString *)player
{
	if([[player lowercaseString] isEqualToString:@"music"])
		return @"com.apple.Music";
	if([[player lowercaseString] isEqualToString:@"spotify"])
		return @"com.spotify.client";
	return nil;
}

/* The name AppleScript knows it by, which is not the name on the icon in every
   language and is not the bundle identifier either. */
+ (NSString *)scriptingNameFor:(NSString *)player
{
	return [[player lowercaseString] isEqualToString:@"music"] ? @"Music" : @"Spotify";
}

+ (NSString *)displayNameFor:(NSString *)player
{
	NSString *identifier = [self bundleIdentifierFor:player];
	NSURL *where = identifier != nil
		? [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:identifier]
		: nil;
	if(where == nil)
		return [self scriptingNameFor:player];
	NSString *name = [[NSFileManager defaultManager] displayNameAtPath:[where path]];
	return [name stringByDeletingPathExtension];
}

+ (BOOL)isInstalled:(NSString *)player
{
	NSString *identifier = [self bundleIdentifierFor:player];
	return identifier != nil
		&& [[NSWorkspace sharedWorkspace]
			URLForApplicationWithBundleIdentifier:identifier] != nil;
}

#pragma mark The scripts, which live here and nowhere else

/* One place, so that everything a plugin can cause is on one screen. The only
   thing that ever comes from outside is the argument of playnamed, and it is
   escaped for AppleScript before it goes anywhere near this. */
+ (NSString *)scriptFor:(NSString *)command
                     on:(NSString *)player
                   with:(NSString *)argument
{
	NSString *app = [self scriptingNameFor:player];
	BOOL music = [[player lowercaseString] isEqualToString:@"music"];

	if([command isEqualToString:NekoPlayerPlay])
		return [NSString stringWithFormat:@"tell application \"%@\" to play", app];
	if([command isEqualToString:NekoPlayerPause])
		return [NSString stringWithFormat:@"tell application \"%@\" to pause", app];
	if([command isEqualToString:NekoPlayerPlayPause])
		return [NSString stringWithFormat:@"tell application \"%@\" to playpause", app];
	if([command isEqualToString:NekoPlayerNext])
		return [NSString stringWithFormat:@"tell application \"%@\" to next track", app];
	if([command isEqualToString:NekoPlayerPrevious])
		return [NSString stringWithFormat:@"tell application \"%@\" to previous track", app];
	/* Written out rather than clamped in an expression: AppleScript has no min
	   and no max, which the first draft of this file assumed it did — and the
	   volume verbs answered "Musica would not do it" until a test asked what the
	   volume was before and after. */
	if([command isEqualToString:NekoPlayerVolumeUp])
		return [NSString stringWithFormat:
			@"tell application \"%@\"\n"
			 "  set v to (sound volume) + %d\n"
			 "  if v > 100 then set v to 100\n"
			 "  set sound volume to v\n"
			 "end tell", app, NekoVolumeStep];
	if([command isEqualToString:NekoPlayerVolumeDown])
		return [NSString stringWithFormat:
			@"tell application \"%@\"\n"
			 "  set v to (sound volume) - %d\n"
			 "  if v < 0 then set v to 0\n"
			 "  set sound volume to v\n"
			 "end tell", app, NekoVolumeStep];

	if([command isEqualToString:NekoPlayerPlayNamed]) {
		if(!music)
			return nil;      /* Spotify's dictionary cannot search; see perform: */
		/* Your own library, which is the only thing Music's dictionary can look
		   in: the streaming catalogue is not scriptable, and this does not pretend
		   otherwise. Artist first, then title, so "metti Battisti" finds the
		   artist rather than a song with his name in the title. */
		return [NSString stringWithFormat:
			@"tell application \"Music\"\n"
			 "  set found to (every track of library playlist 1 whose artist contains \"%@\")\n"
			 "  if (count of found) is 0 then\n"
			 "    set found to (every track of library playlist 1 whose name contains \"%@\")\n"
			 "  end if\n"
			 "  if (count of found) is 0 then return \"none\"\n"
			 "  play (item 1 of found)\n"
			 "  return \"playing\"\n"
			 "end tell", argument, argument];
	}
	return nil;
}

/* AppleScript string literals take a backslash and a double quote the way C does,
   and nothing else needs escaping inside one. A newline would end the literal, so
   it goes too. */
+ (NSString *)escaped:(NSString *)text
{
	NSMutableString *safe = [NSMutableString stringWithString:text ?: @""];
	[safe replaceOccurrencesOfString:@"\\" withString:@"\\\\"
	                        options:0 range:NSMakeRange(0, [safe length])];
	[safe replaceOccurrencesOfString:@"\"" withString:@"\\\""
	                        options:0 range:NSMakeRange(0, [safe length])];
	[safe replaceOccurrencesOfString:@"\n" withString:@" "
	                        options:0 range:NSMakeRange(0, [safe length])];
	[safe replaceOccurrencesOfString:@"\r" withString:@" "
	                        options:0 range:NSMakeRange(0, [safe length])];
	return safe;
}

#pragma mark Doing it

+ (BOOL)perform:(NSString *)command
             on:(NSString *)player
           with:(NSString *)argument
         saying:(NSString **)problem
{
	if(![self knows:player] || ![self knowsCommand:command])
		return NO;

	if(![self isInstalled:player]) {
		if(problem != NULL)
			*problem = [NSString stringWithFormat:
				NSLocalizedString(@"%@ is not on this Mac.", @"%@ is not on this Mac."),
				[self displayNameFor:player]];
		return NO;
	}

	if([command isEqualToString:NekoPlayerPlayNamed]
	   && ![[player lowercaseString] isEqualToString:@"music"]) {
		if(problem != NULL)
			*problem = [NSString stringWithFormat:
				NSLocalizedString(@"%@ does not let anything else search it; only its own window can.", @"%@ does not let anything else search it; only its own window can."),
				[self displayNameFor:player]];
		return NO;
	}

	NSString *source = [self scriptFor:command on:player
	                              with:[self escaped:argument]];
	if(source == nil)
		return NO;

	NSDictionary *trouble = nil;
	NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
	NSAppleEventDescriptor *answer = [script executeAndReturnError:&trouble];

	if(answer == nil) {
		NSInteger code = [[trouble objectForKey:NSAppleScriptErrorNumber] integerValue];
		if(code == -1743)
			[self remember:NekoPlayerConsentRefused for:player];
		if(problem != NULL) {
			/* -1743 is macOS saying the person has not allowed this, and it is the
			   only failure here they can do something about. */
			*problem = (code == -1743)
				? [NSString stringWithFormat:
					NSLocalizedString(@"macOS will not let me control %@ until you allow it in Privacy & Security, under Automation.", @"macOS will not let me control %@ until you allow it in Privacy & Security, under Automation."),
					[self displayNameFor:player]]
				: [NSString stringWithFormat:
					NSLocalizedString(@"%@ would not do it.", @"%@ would not do it."),
					[self displayNameFor:player]];
		}
		return NO;
	}

	/* It worked, so it is allowed — the only evidence worth keeping. */
	[self remember:NekoPlayerConsentGiven for:player];

	if([command isEqualToString:NekoPlayerPlayNamed]
	   && [[answer stringValue] isEqualToString:@"none"]) {
		if(problem != NULL)
			*problem = [NSString stringWithFormat:
				NSLocalizedString(@"There is nothing by “%@” in your library.", @"There is nothing by “%@” in your library."), argument];
		return NO;
	}
	return YES;
}

#pragma mark Being allowed to

/* This is the second design. The first one asked macOS directly —
   AEDeterminePermissionToAutomateTarget with askUserIfNeeded NO, which is
   documented as answering from the consent database without prompting — and the
   Permissions tab froze the whole application the moment it was opened.

   Measured, not guessed: sampling the stuck process gave 1723 samples out of 1723
   in the same place, the main thread inside
   AEDeterminePermissionToAutomateTarget waiting on a dispatch semaphore. That
   function needs the run loop to deliver the reply it is waiting for, and the main
   thread is what services the run loop, so calling it there is a deadlock rather
   than a slow call. No timeout would have helped: it never returns.

   So nothing is preflighted at all. Neko finds out the same way a person does — by
   trying, once, at a moment somebody chose — and remembers the answer. A recorded
   yes came from a command that worked; a recorded no came from macOS answering
   -1743. That is strictly more honest than a preflight: it cannot claim a
   permission that would not actually work. */
+ (void)remember:(NekoPlayerConsent)consent for:(NSString *)player
{
	NSUserDefaults *settings = [NSUserDefaults standardUserDefaults];
	NSString *key = NekoConsentKeyFor(player);
	if((NekoPlayerConsent)[settings integerForKey:key] == consent)
		return;
	[settings setInteger:(NSInteger)consent forKey:key];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:NekoPlayerConsentDidChangeNotification object:nil];
}

+ (NekoPlayerConsent)consentFor:(NSString *)player
{
	if([self bundleIdentifierFor:player] == nil || ![self isInstalled:player])
		return NekoPlayerConsentImpossible;

	NekoPlayerConsent remembered = (NekoPlayerConsent)
		[[NSUserDefaults standardUserDefaults] integerForKey:NekoConsentKeyFor(player)];
	if(remembered == NekoPlayerConsentGiven || remembered == NekoPlayerConsentRefused)
		return remembered;
	return NekoPlayerConsentUnknown;
}

+ (BOOL)mayControl:(NSString *)player
{
	return [self consentFor:player] == NekoPlayerConsentGiven;
}

+ (void)askToControl:(NSString *)player
{
	/* Here, and only here, the prompt is wanted: somebody pressed a button for
	   it. The smallest harmless question either application answers is what its
	   volume is — and it is asked on another thread, because the prompt stays up
	   until it is read and a settings window may not wait for that. */
	if(![self isInstalled:player])
		return;
	NSString *wanted = [player copy];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSString *source = [NSString stringWithFormat:
			@"tell application \"%@\" to return sound volume as text",
			[self scriptingNameFor:wanted]];
		NSDictionary *trouble = nil;
		NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
		NSAppleEventDescriptor *answer = [script executeAndReturnError:&trouble];
		NSInteger code = [[trouble objectForKey:NSAppleScriptErrorNumber] integerValue];
		dispatch_async(dispatch_get_main_queue(), ^{
			if(answer != nil)
				[self remember:NekoPlayerConsentGiven for:wanted];
			else if(code == -1743)
				[self remember:NekoPlayerConsentRefused for:wanted];
			else
				[[NSNotificationCenter defaultCenter]
					postNotificationName:NekoPlayerConsentDidChangeNotification
					              object:nil];
		});
	});
}

@end
