#import "NekoDesktop.h"
#import "NekoGlance.h"
#import "NekoWakeWord.h"
#import "NekoAsk.h"
#import <CoreAudio/CoreAudio.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>


/* Enough to know what you are working on, short enough that it cannot become a
   transcript of your afternoon. */
static const NSUInteger NekoTextLimit = 400;

@implementation NekoDesktop

+ (NekoDesktop *)sharedDesktop
{
	static NekoDesktop *shared = nil;
	if(shared == nil)
		shared = [[NekoDesktop alloc] init];
	return shared;
}

- (id)init
{
	self = [super init];
	if(self != nil) {
		switches = [[NSMutableArray alloc] init];
		[[[NSWorkspace sharedWorkspace] notificationCenter]
			addObserver:self
			   selector:@selector(applicationChanged:)
			       name:NSWorkspaceDidActivateApplicationNotification
			     object:nil];
	}
	return self;
}

- (void)dealloc
{
	[[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}

#pragma mark What is in front

- (void)applicationChanged:(NSNotification *)note
{
	NSString *name = [[[note userInfo] objectForKey:NSWorkspaceApplicationKey]
		localizedName];
	if([name length] == 0 || [name isEqualToString:frontApp])
		return;
	frontApp = [name copy];
	frontSince = [NSDate date];
	[switches addObject:[NSDictionary dictionaryWithObjectsAndKeys:
		frontSince, @"when", frontApp, @"app", nil]];
	while([switches count] > 60)
		[switches removeObjectAtIndex:0];
}

/* Also filled in lazily, so the first remark after launch knows where it is
   without waiting for you to switch applications. */
- (NSString *)frontApp
{
	NSString *name = [[[NSWorkspace sharedWorkspace] frontmostApplication]
		localizedName];
	if([name length] == 0)
		return frontApp;
	if(![name isEqualToString:frontApp]) {
		frontApp = [name copy];
		frontSince = [NSDate date];
	}
	return frontApp;
}

- (NSTimeInterval)secondsInFront
{
	return frontSince != nil ? -[frontSince timeIntervalSinceNow] : 0.0;
}

- (NSUInteger)switchesInTheLastQuarterHour
{
	NSUInteger count = 0;
	NSEnumerator *e = [switches objectEnumerator];
	NSDictionary *entry;
	while((entry = [e nextObject]) != nil)
		if([entry isKindOfClass:[NSDictionary class]]
		   && -[[entry objectForKey:@"when"] timeIntervalSinceNow] < 900.0)
			count++;
	return count;
}

/*! How many different programs, not how many times the front one changed:
   bouncing between an editor and a browser all afternoon is two programs and a
   normal way to work, and counting it as twenty switches made the cat ask why
   somebody kept changing programs every time it opened its mouth. */
- (NSUInteger)programsInTheLastQuarterHour
{
	NSMutableSet *names = [NSMutableSet set];
	NSEnumerator *e = [switches objectEnumerator];
	NSDictionary *entry;
	while((entry = [e nextObject]) != nil) {
		if(![entry isKindOfClass:[NSDictionary class]])
			continue;
		if(-[[entry objectForKey:@"when"] timeIntervalSinceNow] < 900.0)
			[names addObject:[entry objectForKey:@"app"]];
	}
	return [names count];
}

#pragma mark How busy you are

/*! Counters, not events: no tap on the input stream, nothing that could see a
   keystroke. Typing fast is a number going up. */
- (uint32_t)counterFor:(CGEventType)type
{
	return (uint32_t)CGEventSourceCounterForEventType(
		kCGEventSourceStateCombinedSessionState, type);
}

/*! A breakpoint lasts about as long as it takes to notice one. */
static const NSTimeInterval NekoBreakpointWindow = 12.0;

- (void)sample
{
	uint32_t keys = [self counterFor:kCGEventKeyDown];
	uint32_t moves = [self counterFor:kCGEventMouseMoved];
	NSTimeInterval since = sampledAt != nil ? -[sampledAt timeIntervalSinceNow] : 0.0;
	if(since > 1.0) {
		double minutes = since / 60.0;
		keysPerMinute = (uint32_t)((keys - keysBefore) / minutes);
		movesPerMinute = (uint32_t)((moves - movesBefore) / minutes);
	}
	keysBefore = keys;
	movesBefore = moves;

	if(since > 1.0)
		[self noticeBreakpoint];

	previousKeys = keysPerMinute;
	previousIdle = [self idleSeconds];
	sampledAt = [NSDate date];
}

/*! Four things worth calling a breakpoint, from the coarsest down. Each is
   something a person would recognise as a seam in their own afternoon. */
- (void)noticeBreakpoint
{
	NSString *app = [self frontApp];
	NSTimeInterval idle = [self idleSeconds];
	NekoBreakpoint found = NekoBreakpointNone;

	/* Left one program for another. How coarse depends on how long they had
	   been in the one they left. */
	if(previousApp != nil && ![previousApp isEqualToString:app]) {
		NSTimeInterval stretch = previousAppSince != nil
			? -[previousAppSince timeIntervalSinceNow] : 0.0;
		found = stretch >= 180.0 ? NekoBreakpointCoarse : NekoBreakpointMedium;
	}

	/* Back from a real break — a coffee, a meeting — which is the widest seam
	   there is. */
	if(previousIdle >= 120.0 && idle < 5.0)
		found = NekoBreakpointCoarse;

	/* A burst of typing that has just stopped: the end of a thought. */
	if(found == NekoBreakpointNone && previousKeys >= 40 && keysPerMinute < 10)
		found = NekoBreakpointMedium;

	/* Simply paused, with work either side of it. */
	if(found == NekoBreakpointNone && idle >= 3.0 && idle < 25.0
	   && (previousKeys > 0 || movesPerMinute > 0))
		found = NekoBreakpointFine;

	if(![previousApp isEqualToString:app]) {
		previousApp = [app copy];
		previousAppSince = [NSDate date];
	}

	if(found == NekoBreakpointNone)
		return;
	/* A coarser one replaces a finer one inside the same window; otherwise the
	   newest wins. */
	if([self breakpointNow] != NekoBreakpointNone && found < breakpoint)
		return;
	breakpoint = found;
	breakpointAt = [NSDate date];
}

- (NekoBreakpoint)breakpointNow
{
	if(breakpointAt == nil)
		return NekoBreakpointNone;
	return -[breakpointAt timeIntervalSinceNow] <= NekoBreakpointWindow
		? breakpoint : NekoBreakpointNone;
}

- (NSTimeInterval)secondsSinceBreakpoint
{
	return breakpointAt != nil ? -[breakpointAt timeIntervalSinceNow] : 1.0e9;
}

- (NSString *)describeBreakpoint
{
	switch([self breakpointNow]) {
		case NekoBreakpointCoarse: return NSLocalizedString(@"a clear break in what you were doing", @"NekoBreakpointCoarse");
		case NekoBreakpointMedium: return NSLocalizedString(@"a pause between two things", @"NekoBreakpointMedium");
		case NekoBreakpointFine:   return NSLocalizedString(@"a small gap", @"NekoBreakpointFine");
		default:                   return NSLocalizedString(@"nothing: you are in the middle of something", @"NekoBreakpointNone/fallthru");
	}
}

#pragma mark Times to say nothing at all

/*! A window that covers a whole screen is a presentation, a film or a game, and
   none of them want a cat with an opinion. */
- (BOOL)frontWindowFillsAScreen
{
	NSArray *windows =
	CFBridgingRelease(CGWindowListCopyWindowInfo(
												 kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
												 kCGNullWindowID));
	if(windows == NULL)
		return NO;
	NSString *wanted = [self frontApp];
	BOOL fills = NO;
	NSEnumerator *e = [windows objectEnumerator];
	NSDictionary *window;
	while((window = [e nextObject]) != nil && !fills) {
		if(![[window objectForKey:(NSString *)kCGWindowOwnerName] isEqualToString:wanted])
			continue;
		CGRect bounds = CGRectZero;
		CGRectMakeWithDictionaryRepresentation(
			(CFDictionaryRef)[window objectForKey:(NSString *)kCGWindowBounds], &bounds);
		for(NSScreen *screen in [NSScreen screens]) {
			NSRect frame = [screen frame];
			if(bounds.size.width >= frame.size.width - 1.0
			   && bounds.size.height >= frame.size.height - 1.0) {
				fills = YES;
				break;
			}
		}
	}
	return fills;
}

/*! One flag, from the audio device rather than from any application: is the
   default input running somewhere. It says nothing about who opened it or what
   is being said, and reading it asks for nothing. */
- (BOOL)microphoneInUse
{
	AudioObjectPropertyAddress which = {
		kAudioHardwarePropertyDefaultInputDevice,
		kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
	AudioDeviceID device = 0;
	UInt32 size = sizeof(device);
	if(AudioObjectGetPropertyData(kAudioObjectSystemObject, &which, 0, NULL,
	                              &size, &device) != noErr || device == 0)
		return NO;

	AudioObjectPropertyAddress running = {
		kAudioDevicePropertyDeviceIsRunningSomewhere,
		kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
	UInt32 hot = 0;
	size = sizeof(hot);
	if(AudioObjectGetPropertyData(device, &running, 0, NULL, &size, &hot) != noErr)
		return NO;

	/* Unless it is this application's own microphone. The wake word holds the
	   input open for as long as it is switched on, and a flag that is stuck at
	   "somebody is talking" whenever Neko is listening for its name would be
	   worse than no flag: it would silence the cat permanently and look like a
	   different bug entirely. */
	if(hot && ([[NekoWakeWord sharedWakeWord] isListening]
	           || [[NekoAsk sharedAsk] isBusy]))
		return NO;
	return hot != 0;
}

- (NSString *)whyNobodyIsThere
{
	NSDictionary *session = (NSDictionary *)CFBridgingRelease(CGSessionCopyCurrentDictionary());
	BOOL locked = NO, away = NO;
	if(session != nil) {
		locked = [[session objectForKey:@"CGSSessionScreenIsLocked"] boolValue];
		/* Somebody else is logged in and looking at their own desktop. */
		away = ![[session objectForKey:@"kCGSSessionOnConsoleKey"] boolValue];
		session = nil;
	}
	if(locked)
		return NSLocalizedString(@"the screen is locked", nil);
	if(away)
		return NSLocalizedString(@"somebody else is using this Mac", nil);
	if(CGDisplayIsAsleep(CGMainDisplayID()))
		return NSLocalizedString(@"the display is asleep", nil);
	return nil;
}

- (BOOL)nobodyIsThere
{
	return [self whyNobodyIsThere] != nil;
}

- (NSString *)whyBusyElsewhere
{
	if(IsSecureEventInputEnabled())
		return NSLocalizedString(@"you are typing a password", @"you are typing a password");
	if([self frontWindowFillsAScreen])
		return NSLocalizedString(@"something is filling the screen", @"something is filling the screen");
	/* The plainest sign of all, and the one this could see all along without
	   asking anybody for anything. */
	if([self microphoneInUse])
		return NSLocalizedString(@"the microphone is open, so you are probably talking", @"the microphone is open, so you are probably talking");
	NSString *nobody = [self whyNobodyIsThere];
	if(nobody != nil)
		return nobody;
	return nil;
}

- (BOOL)isBusyElsewhere
{
	return [self whyBusyElsewhere] != nil;
}

- (BOOL)somethingStandsOut
{
	return ![[self highlight] hasPrefix:@"Nothing stands out"];
}

@synthesize keysPerMinute;
@synthesize movesPerMinute;

- (NSTimeInterval)idleSeconds
{
	return CGEventSourceSecondsSinceLastEventType(
		kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType);
}

#pragma mark The window title, if it happens to be free

- (NSString *)windowTitleIfAllowed
{
	if(!CGPreflightScreenCaptureAccess())
		return nil;

	NSString *wanted = [self frontApp];
	NSArray *windows =
	CFBridgingRelease(CGWindowListCopyWindowInfo(
										 kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
										 kCGNullWindowID));
	NSString *title = nil;
	for(NSDictionary *window in windows) {
		NSString *owner = [window objectForKey:(NSString *)kCGWindowOwnerName];
		NSString *name = [window objectForKey:(NSString *)kCGWindowName];
		if([owner isEqualToString:wanted] && [name length] > 0) {
			title = [name copy];
			break;
		}
	}
	return title;
}

#pragma mark The text you are working on

+ (BOOL)accessibilityGranted
{
	return AXIsProcessTrusted();
}

+ (BOOL)requestAccessibility
{
	if(AXIsProcessTrusted())
		return YES;
	NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
	return AXIsProcessTrustedWithOptions((CFDictionaryRef)options);
}

- (BOOL)readsText
{
	/* A stretch of time somebody asked for, not a switch they left on. The switch
	   was the one standing grant in an application that asks per use everywhere
	   else, and a permission you must remember to revoke is one careful people
	   decline for ever — which left this off for exactly the people it is for.
	   See NekoGlance.h and docs/one-look-roadmap.md. */
	return [[NekoGlance sharedGlance] isLooking]
		&& [NekoDesktop accessibilityGranted];
}

static NSString *copyStringAttribute(AXUIElementRef element, CFStringRef attribute)
{
	CFTypeRef value = NULL;
	if(AXUIElementCopyAttributeValue(element, attribute, &value) != kAXErrorSuccess)
		return nil;
	NSObject *nsValue = CFBridgingRelease(value);
	NSString *result = nil;
	if(value != NULL) {
		if(CFGetTypeID(value) == CFStringGetTypeID()) {
			result = [nsValue copy];
		}
	}
	return [result length] > 0 ? result : nil;
}

/*! One line, trimmed, with the middle kept: the beginning of a document says
   less about what someone is doing right now than the end of it does. */
static NSString *tidy(NSString *text)
{
	if([text length] == 0)
		return nil;
	NSArray *pieces = [text componentsSeparatedByCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSMutableArray *words = [NSMutableArray array];
	NSEnumerator *e = [pieces objectEnumerator];
	NSString *piece;
	while((piece = [e nextObject]) != nil)
		if([piece length] > 0)
			[words addObject:piece];
	NSString *flat = [words componentsJoinedByString:@" "];
	if([flat length] <= NekoTextLimit)
		return [flat length] > 0 ? flat : nil;
	return [NSString stringWithFormat:@"…%@",
		[flat substringFromIndex:[flat length] - NekoTextLimit]];
}

/*! Refused outright: a password field, or anything at all while the system has
   secure keyboard entry on — which is what a password field in a browser turns
   on. Neither is a place for a cat to be nosy. */
- (BOOL)elementIsPrivate:(AXUIElementRef)element
{
	NSString *subrole = copyStringAttribute(element, kAXSubroleAttribute);
	return [subrole isEqualToString:(NSString *)kAXSecureTextFieldSubrole];
}

- (NSString *)textFromElement:(AXUIElementRef)element
{
	if(element == NULL || [self elementIsPrivate:element])
		return nil;
	NSString *role = copyStringAttribute(element, kAXRoleAttribute);
	BOOL writable = [role isEqualToString:(NSString *)kAXTextFieldRole]
	             || [role isEqualToString:(NSString *)kAXTextAreaRole]
	             || [role isEqualToString:(NSString *)kAXComboBoxRole]
	             || [role isEqualToString:(NSString *)kAXStaticTextRole]
	             || [role isEqualToString:@"AXWebArea"];
	if(!writable)
		return nil;

	NSString *selected = copyStringAttribute(element, kAXSelectedTextAttribute);
	if([selected length] > 0)
		return tidy(selected);
	return tidy(copyStringAttribute(element, kAXValueAttribute));
}

- (NSString *)nearbyText
{
	if(![self readsText] || IsSecureEventInputEnabled())
		return nil;

	AXUIElementRef system = AXUIElementCreateSystemWide();
	NSString *text = nil;

	CFTypeRef focused = NULL;
	if(AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute,
	                                 &focused) == kAXErrorSuccess && focused != NULL) {
		text = [self textFromElement:(AXUIElementRef)focused];
		CFRelease(focused);
	}

	/* Nothing in the field, or no field: whatever is under the pointer, which is
	   usually what someone is reading. */
	if(text == nil) {
		NSPoint mouse = [NSEvent mouseLocation];
		CGFloat height = NSMaxY([[NSScreen screens] count] > 0
			? [[[NSScreen screens] objectAtIndex:0] frame] : NSZeroRect);
		AXUIElementRef under = NULL;
		if(AXUIElementCopyElementAtPosition(system, mouse.x, height - mouse.y,
		                                    &under) == kAXErrorSuccess && under != NULL) {
			text = [self textFromElement:under];
			CFRelease(under);
		}
	}

	CFRelease(system);
	return text;
}

/* The one thing worth remarking on, worked out here rather than left to the
   model. Handed six numbers and no hint, small models write the same soft
   sentence about whichever program is in front — "Safari ti tiene compagnia
   mentre il tempo scorre lento" — because nothing in the list told them what
   was unusual. Naming the salient fact is what turns that into a remark. */
/*! One remark's worth of what is unusual right now.

   Every candidate that applies is collected and one is chosen, rather than the
   first winning every time: the switch counter used to be first and its
   threshold was low, so the cat asked why somebody kept changing programs over
   and over — which is both a nag and, for most people most of the time, not even
   true. The last one used is skipped when there is anything else to say. */
- (NSString *)highlight
{
	NSTimeInterval idle = [self idleSeconds];
	NSTimeInterval minutes = [self secondsInFront] / 60.0;
	NSUInteger programs = [self programsInTheLastQuarterHour];
	NSDateComponents *now = [[NSCalendar currentCalendar]
		components:(NSCalendarUnitHour | NSCalendarUnitWeekday) fromDate:[NSDate date]];
	NSInteger hour = [now hour];
	NSTimeInterval up = [[NSProcessInfo processInfo] systemUptime];

	NSMutableArray *candidates = [NSMutableArray array];
	if(minutes >= 45.0)
		[candidates addObject:[NSString stringWithFormat:
			@"They have not left this one program for %.0f minutes.", minutes]];
	if(programs >= 7)
		[candidates addObject:[NSString stringWithFormat:
			@"They have had %lu different programs in front of them in a quarter of an hour.",
			(unsigned long)programs]];
	if(hour >= 23 || hour < 6)
		[candidates addObject:@"It is the middle of the night and they are still at it."];
	if(keysPerMinute >= 200)
		[candidates addObject:@"They are typing very fast indeed."];
	if(keysPerMinute < 5 && movesPerMinute >= 150)
		[candidates addObject:@"All mouse and no keyboard for a while now."];
	if(idle >= 120.0)
		[candidates addObject:@"They have not touched anything for a couple of minutes."];
	if(minutes < 2.0 && programs < 7)
		[candidates addObject:@"They have only just arrived in this program."];
	if(up > 6.0 * 3600.0 && hour >= 18)
		[candidates addObject:@"This Mac has been awake all day and it is evening."];
	if([now weekday] == 1 || [now weekday] == 7)
		[candidates addObject:@"It is the weekend and they are at the computer."];
	if(hour >= 6 && hour < 9)
		[candidates addObject:@"It is early morning."];

	if([candidates count] == 0)
		return @"Nothing stands out: an ordinary few minutes.";

	/* Anything but the one just used. If that is all there is, the cat is told
	   nothing stands out rather than making the same observation twice: saying
	   "you keep changing programs" a second time is how a remark becomes a
	   complaint. */
	NSMutableArray *fresh = [NSMutableArray arrayWithArray:candidates];
	if(lastHighlight != nil)
		[fresh removeObject:lastHighlight];
	if([fresh count] == 0) {
		lastHighlight = nil;
		return @"Nothing stands out: an ordinary few minutes.";
	}
	NSString *chosen = [fresh objectAtIndex:arc4random_uniform((unsigned)[fresh count])];
	lastHighlight = [chosen copy];
	return chosen;
}

#pragma mark All of it, for a model to read

- (NSString *)summary
{
	NSString *app = [self frontApp];
	NSString *title = [self windowTitleIfAllowed];
	NSString *text = [self nearbyText];
	NSDateFormatter *clock = [[NSDateFormatter alloc] init];
	[clock setDateFormat:@"HH:mm"];

	NSMutableString *lines = [NSMutableString string];
	[lines appendString:@"Here is what I seem to be doing right now.\n"];
	[lines appendFormat:@"The program in front of me: %@\n", app ?: @"unknown"];
	if(title != nil)
		[lines appendFormat:@"Its window is titled: %@\n", title];
	[lines appendFormat:@"Minutes I have been in it: %.0f\n", [self secondsInFront] / 60.0];
	[lines appendFormat:@"Different programs I have used in the last 15 minutes: %lu\n",
		(unsigned long)[self programsInTheLastQuarterHour]];
	[lines appendFormat:@"Keys a minute: %u, mouse moves a minute: %u\n",
		keysPerMinute, movesPerMinute];
	[lines appendFormat:@"Seconds since my last key or click: %.0f\n", [self idleSeconds]];
	[lines appendFormat:@"Local time: %@\n", [clock stringFromDate:[NSDate date]]];
	if(text != nil)
		[lines appendFormat:@"The text I am working on ends like this: %@\n", text];
	[lines appendFormat:@"\nThe one thing that stands out: %@\n", [self highlight]];
	return lines;
}

@end
