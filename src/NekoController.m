#import "NekoController.h"
#import "NekoTimer.h"
#import "NekoFact.h"
#import "NekoDoors.h"
#import "NekoGlance.h"
#import "NekoPermissionsTab.h"
#import "NekoAdvisor.h"
#import "NekoAntics.h"
#import "NekoDesktop.h"
#import "NekoPainter.h"
#import "NekoAppleProvider.h"
#import "NekoAction.h"
#import "NekoFolderAccess.h"
#import "NekoWakeWord.h"
#import "NekoPermissions.h"
#import "NekoUpdate.h"
#import "NekoPlayer.h"
#import "NekoBrains.h"
#import "NekoRate.h"
#import "NekoWeb.h"
#import "NekoPlace.h"
#import "NekoPluginsPanel.h"
#import "NekoPlugins.h"
#import "NekoVoice.h"
#import "NekoMemory.h"
#import "NekoHotKey.h"
#import "NekoModelProvider.h"
#import "NekoModelStore.h"
#import "NekoLocalProvider.h"
#import "NekoAppleProvider.h"
#import "NekoAction.h"
#import "NekoFolderAccess.h"
#import "NekoWakeWord.h"
#import "NekoPermissions.h"
#import "NekoBrains.h"
#import "NekoMemory.h"
#import "NekoOpenAIProvider.h"
#import "NekoModelProvider.h"

NSString * const NekoCharacterKey  = @"NekoCharacter";
NSString * const NekoSpeedKey      = @"NekoSpeed";
NSString * const NekoScaleKey      = @"NekoScale";
NSString * const NekoStopRadiusKey = @"NekoStopRadius";
NSString * const NekoIdleSleepKey  = @"NekoIdleSleep";
NSString * const NekoWanderKey     = @"NekoWander";
NSString * const NekoBehaviourKey  = @"NekoBehaviour";
NSString * const NekoStayKey       = @"NekoStay";
NSString * const NekoStayPointKey  = @"NekoStayPoint";
NSString * const NekoPausedKey     = @"NekoPaused";
NSString * const NekoSuggestKey    = @"NekoSuggest";
NSString * const NekoSuggestEveryKey = @"NekoSuggestEvery";

NSString * const NekoSettingsDidChangeNotification = @"NekoSettingsDidChange";

/* SMAppService arrived in macOS 13 and registers the app itself as a login
   item, no helper bundle involved. It is reached through the runtime rather
   than linked, so the binary still runs on the older systems this project
   targets, where the class is simply absent. */
@protocol NekoAppService <NSObject>
- (BOOL)registerAndReturnError:(NSError **)error;
- (BOOL)unregisterAndReturnError:(NSError **)error;
- (NSInteger)status;
@end

@protocol NekoAppServiceClass <NSObject>
- (id)mainAppService;
@end

/* SMAppServiceStatus */
enum {
	NekoLoginNotRegistered = 0,
	NekoLoginEnabled = 1,
	NekoLoginRequiresApproval = 2,
	NekoLoginNotFound = 3
};

static const CGFloat NekoMinSpeed = 4.0f;
static const CGFloat NekoMaxSpeed = 30.0f;

/* How close the cat is allowed to get to the pointer. 0 puts it right under
   the cursor, which is what it did before the setting existed. */
static const CGFloat NekoMinStopRadius = 0.0;
static const CGFloat NekoMaxStopRadius = 200.0;

@implementation NekoController

+ (void)initialize
{
	if(self != [NekoController class])
		return;
	[[NSUserDefaults standardUserDefaults] registerDefaults:
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"neko", NekoCharacterKey,
			@13.0, NekoSpeedKey,
			@1.0, NekoScaleKey,
			@48.0, NekoStopRadiusKey,
			@YES, NekoIdleSleepKey,
			@YES, NekoWanderKey,
			@"follow", NekoBehaviourKey,
			@NO, NekoPausedKey,
			/* Off: a cat that starts talking about your work on first launch,
			   sending what it saw to whichever engine is set, would be a
			   decision made for you. */
			@NO, NekoSuggestKey,
			@10, NekoSuggestEveryKey, nil]];
}

+ (NekoController *)sharedController
{
	static NekoController *shared = nil;
	if(shared == nil)
		shared = [[NekoController alloc] init];
	return shared;
}

- (id)init
{
	if((self = [super init]) != nil) {
		[self installStatusItem];
	}
	return self;
}

- (void)dealloc
{
	[[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
	[statusItem release];
	[prefsPanel release];
	[super dealloc];
}

#pragma mark Status item (tray)

- (void)installStatusItem
{
	statusItem = [[[NSStatusBar systemStatusBar]
		statusItemWithLength:NSSquareStatusItemLength] retain];

	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Neko"];
	/* So the minutes left are worked out when somebody looks, rather than being
	   written once and going stale in the closed menu. */
	[menu setDelegate:self];
	pauseItem = [menu addItemWithTitle:NSLocalizedString(@"Pause Neko", @"Pause Neko")
	                           action:@selector(togglePause:)
	                    keyEquivalent:@""];
	[pauseItem setTarget:self];

	/* Where somebody is standing when they think it: the cat is in the way, and
	   the menu is one click above it. Not a drag, because the cat is not a
	   control — it ignores the mouse entirely, which is how it can sit on top of
	   everything without being in the way of a click. */
	stayItem = [menu addItemWithTitle:NSLocalizedString(@"Stay here", @"Stay here")
	                           action:@selector(toggleStay:)
	                    keyEquivalent:@""];
	[stayItem setTarget:self];
	[self updateStayItem];

	/* Only there while one is running, which is the whole of the interface a
	   single timer needs: it says how long is left, and clicking it stops. */
	timerItem = [menu addItemWithTitle:@"" action:@selector(cancelTimer:)
	                     keyEquivalent:@""];
	[timerItem setTarget:self];
	[self updateTimerItem];

	/* And the same shape for the look: there only while it is running, saying how
	   long is left, and one click stops it. A permission with a visible clock on
	   it is one somebody can reason about. */
	glanceItem = [menu addItemWithTitle:@"" action:@selector(stopGlance:)
	                      keyEquivalent:@""];
	[glanceItem setTarget:self];
	[self updateGlanceItem];

	/* And a new version, when there is one. Same shape as the two above: absent
	   until it means something, and one click is the whole of the interface. It
	   is the part of the update that does not depend on a rate rule — the cat
	   says it once out loud and then this is where it waits. */
	newVersionItem = [menu addItemWithTitle:@"" action:@selector(offerIt:)
	                         keyEquivalent:@""];
	[newVersionItem setTarget:[NekoUpdate sharedUpdate]];
	[self updateNewVersionItem];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                        selector:@selector(updateChanged:)
	                                            name:NekoUpdateDidChangeNotification
	                                          object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(updateGlanceItem)
	                                             name:NekoGlanceDidChangeNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(updateTimerItem)
	                                             name:NekoTimerDidChangeNotification
	                                           object:nil];

	[menu addItem:[NSMenuItem separatorItem]];

	NSMenuItem *item = [menu addItemWithTitle:NSLocalizedString(@"Character", @"Character") action:NULL keyEquivalent:@""];
	characterMenu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"Character", @"Character")];
	[self buildCharacterMenu];
	[item setSubmenu:characterMenu];

	item = [menu addItemWithTitle:NSLocalizedString(@"Preferences…", @"Preferences…")
	                       action:@selector(showPreferences:)
	                keyEquivalent:@","];
	[item setTarget:self];

	/* Its own item, because plugins are not settings: they are things somebody
	   installed, and the window that manages them says more than a tab has room
	   for. */
	item = [menu addItemWithTitle:NSLocalizedString(@"Plugins…", @"Plugins…")
	                       action:@selector(showPlugins:)
	                keyEquivalent:@""];
	[item setTarget:self];

	[menu addItem:[NSMenuItem separatorItem]];

	askItem = [menu addItemWithTitle:NSLocalizedString(@"Ask Neko", @"Ask Neko")
	                         action:@selector(askNeko:)
	                  keyEquivalent:@""];
	[askItem setTarget:self];

	[menu addItem:[NSMenuItem separatorItem]];

	item = [menu addItemWithTitle:NSLocalizedString(@"About Neko", @"About Neko")
	                       action:@selector(showAbout:)
	                keyEquivalent:@""];
	[item setTarget:self];

	/* No ⌘Q. A cat in the menu bar has no window you are finished with and no
	   document you are done editing, so the keystroke has nothing to mean here
	   except an accident — and the accident is expensive, because everything the
	   cat is in the middle of goes with it: a timer, a stretch of looking, a
	   question half typed.

	   It is also invisible. There is no Dock icon and no application menu on
	   screen, so nothing tells you the shortcut exists until it has fired. The
	   menu item stays, and it is the only way out. */
	item = [menu addItemWithTitle:NSLocalizedString(@"Quit Neko", @"Quit Neko")
	                       action:@selector(quit:)
	                keyEquivalent:@""];
	[item setTarget:self];

	[statusItem setMenu:menu];
	[menu release];

	[self disarmQuitShortcut];

	[self updateAskItem];
	[self updateStatusItemImage];
	[self updatePauseItemTitle];
}

- (void)updateStatusItemImage
{
	NSStatusBarButton *button = [statusItem button];
	if(button == nil)
		return;
	NSImage *icon = [[self character] menuBarImage];
	if(icon != nil)
		[button setImage:icon];
	else
		[button setTitle:@"Neko"];  /* the sprites are missing, stay visible */
	[button setToolTip:@"Neko"];
}

/* One slot that changes identity: the question when the feature is on, the way
   to turn it on when it is off. A greyed out item that does nothing is noise,
   and a checkmark would hide the five settings behind it. */
- (void)updateAskItem
{
	NekoAsk *ask = [NekoAsk sharedAsk];
	if([ask isEnabled]) {
		[askItem setTitle:[NSString stringWithFormat:@"%@  (%@)",
						   NSLocalizedString(@"Ask Neko", @"Ask Neko"), [ask hotKeyDisplayName]]];
		[askItem setAction:@selector(askNeko:)];
	} else {
		/* The ellipsis is the promise that a window opens. */
		[askItem setTitle:NSLocalizedString(@"Set up Ask Neko…", @"Set up Ask Neko…")];
		[askItem setAction:@selector(showAskPreferences:)];
	}
	[askItem setTarget:self];
	[askItem setEnabled:YES];
}

- (void)showAskPreferences:(id)sender
{
	[self showPreferences:sender];
	[prefsTabs selectTabViewItemAtIndex:1];
}

- (void)askNeko:(id)sender
{
	[[NekoAsk sharedAsk] toggle:sender];
}

/* On: remember where it is standing now. Off: forget it. The point is only ever
   written at the moment somebody asks for it, so a cat that wandered off while
   staying was switched off does not quietly move the mark. */
/* Redrawn when a timer starts or stops, and again every time the menu is about
   to open — the minutes left change on their own, and a title written once would
   be wrong by the time anybody read it. */
- (void)updateTimerItem
{
	NSString *title = [[NekoTimer sharedTimer] menuTitle];
	[timerItem setHidden:title == nil];
	[timerItem setTitle:title ?: @""];
}

- (void)menuWillOpen:(NSMenu *)which
{
	[self updateTimerItem];
	[self updateGlanceItem];
	[self updateNewVersionItem];
}

- (void)updateNewVersionItem
{
	NSString *title = [[NekoUpdate sharedUpdate] menuTitle];
	[newVersionItem setHidden:title == nil];
	[newVersionItem setTitle:title ?: @""];
}

- (void)updateChanged:(NSNotification *)note
{
	[self updateNewVersionItem];
}

- (void)checkForNewVersion
{
	[[NekoUpdate sharedUpdate] checkQuietly];
}

- (void)checkNow:(id)sender
{
	[[NekoUpdate sharedUpdate] checkAloud];
}

- (void)takeUpdateCheckFrom:(id)sender
{
	[[NSUserDefaults standardUserDefaults]
		setBool:[sender state] == NSControlStateValueOn forKey:NekoUpdateCheckKey];
}

- (void)updateGlanceItem
{
	NSString *title = [[NekoGlance sharedGlance] menuTitle];
	[glanceItem setHidden:title == nil];
	[glanceItem setTitle:title ?: @""];
}

- (void)stopGlance:(id)sender
{
	[[NekoGlance sharedGlance] stop];
	[[NekoAsk sharedAsk] sayUnprompted:NSLocalizedString(@"I have stopped looking.", @"I have stopped looking.")];
}

- (void)cancelTimer:(id)sender
{
	[[NekoTimer sharedTimer] cancel];
	[[NekoAsk sharedAsk] sayUnprompted:NSLocalizedString(@"Timer off.", @"Timer off.")];
}

- (void)toggleStay:(id)sender
{
	NSUserDefaults *settings = [NSUserDefaults standardUserDefaults];
	BOOL wanted = ![self staysWhereItIs];
	[settings setBool:wanted forKey:NekoStayKey];
	if(wanted && panel != nil)
		[settings setObject:NSStringFromPoint([panel frame].origin)
		             forKey:NekoStayPointKey];
	else if(!wanted)
		[settings removeObjectForKey:NekoStayPointKey];
	[self updateStayItem];
	[self settingsChanged];
}

- (void)updateStayItem
{
	[stayItem setState:[self staysWhereItIs] ? NSControlStateValueOn
	                                         : NSControlStateValueOff];
}

- (void)updatePauseItemTitle
{
	[pauseItem setTitle:[self isPaused] ? NSLocalizedString(@"Resume Neko", @"Resume Neko")
	                                   : NSLocalizedString(@"Pause Neko", @"Pause Neko")];
}

- (void)buildCharacterMenu
{
	[characterMenu removeAllItems];
	NSString *active = [[self character] identifier];
	for(NekoCharacter *character in [NekoCharacter availableCharacters]) {
		NSMenuItem *item = [characterMenu addItemWithTitle:[character name]
		                                           action:@selector(chooseCharacter:)
		                                    keyEquivalent:@""];
		[item setTarget:self];
		[item setRepresentedObject:[character identifier]];
		[item setState:[[character identifier] isEqualToString:active]
			? NSControlStateValueOn : NSControlStateValueOff];
	}
	if([characterMenu numberOfItems] == 0)
		[[characterMenu addItemWithTitle:NSLocalizedString(@"No characters found", @"No characters found") action:NULL
		                  keyEquivalent:@""] setEnabled:NO];
}

#pragma mark Panel

- (MyPanel *)panel
{
	return panel;
}

- (void)setPanel:(MyPanel *)thePanel
{
	panel = thePanel;
	/* Here rather than in -init: the advisor asks this controller whether it
	   should be running, and during -init the shared instance does not exist
	   yet — asking would build a second one, which would ask again. */
	[[NekoAdvisor sharedAdvisor] applySettings];
	[[NekoAntics sharedAntics] applySettings];
	[[NekoWakeWord sharedWakeWord] applySettings];
	/* Touched early on purpose: a CLLocationManager reports the real
	   authorization on its delegate a moment after it is made, and the
	   Permissions tab was being drawn before that moment. */
	if([NekoPlace isAvailable])
		(void)[NekoPlace sharedPlace];

	/* The plugins that ship inside the app are put in place before anything asks
	   what feeds exist — the news sources are one of them now. */
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                        selector:@selector(pluginsChanged:)
	                                            name:NekoPluginsDidChangeNotification
	                                          object:nil];
	[[NekoPlugins sharedPlugins] seedFromBundle];

	/* And the ways in from the rest of the Mac: the Services entry that puts
	   "Ask Neko about this" in every application's right-click menu, and the
	   neko:// URL that Shortcuts and scripts can open. */
	[NekoDoors open];

	/* Once a day, yesterday becomes a few durable lines. Costs nothing on the
	   days there is nothing to reduce. */
	[[NekoMemory sharedMemory] reflectIfDue];

	/* And a hello, at most once a day, a few seconds after it turns up: a cat
	   that greets you the instant its window appears is a dialog box. */
	[self performSelector:@selector(sayHello) withObject:nil afterDelay:8.0];
}

- (void)sayHello
{
	if([self isPaused])
		return;
	NSString *opening = [NekoVoice openingIfDue];
	if([opening length] == 0)
		return;
	[[NekoAsk sharedAsk] sayUnprompted:opening];
}

#pragma mark Settings

- (NekoCharacter *)character
{
	return [NekoCharacter characterWithIdentifier:
		[[NSUserDefaults standardUserDefaults] stringForKey:NekoCharacterKey]];
}

- (CGFloat)speed
{
	CGFloat speed = [[NSUserDefaults standardUserDefaults] doubleForKey:NekoSpeedKey];
	if(speed < NekoMinSpeed)
		return NekoMinSpeed;
	if(speed > NekoMaxSpeed)
		return NekoMaxSpeed;
	return speed;
}

- (CGFloat)stopRadius
{
	CGFloat radius = [[NSUserDefaults standardUserDefaults] doubleForKey:NekoStopRadiusKey];
	if(radius < NekoMinStopRadius)
		return NekoMinStopRadius;
	if(radius > NekoMaxStopRadius)
		return NekoMaxStopRadius;
	return radius;
}

- (CGFloat)scale
{
	CGFloat scale = [[NSUserDefaults standardUserDefaults] doubleForKey:NekoScaleKey];
	return (scale >= 2.0f) ? 2.0f : 1.0f;
}

- (BOOL)idleSleep
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:NekoIdleSleepKey];
}

- (BOOL)wandersWhenIdle
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:NekoWanderKey];
}

/* Three behaviours that cannot be mixed: chasing the pointer means resting
   wherever it stopped, living on windows means being pulled down onto them, and
   roaming means the pointer is simply not part of the cat's day. */
- (BOOL)livesOnWindowEdges
{
	return [[[NSUserDefaults standardUserDefaults] stringForKey:NekoBehaviourKey]
		isEqualToString:@"windows"];
}

- (BOOL)roamsOnItsOwn
{
	return [[[NSUserDefaults standardUserDefaults] stringForKey:NekoBehaviourKey]
		isEqualToString:@"roam"];
}

- (BOOL)fleesThePointer
{
	return [[[NSUserDefaults standardUserDefaults] stringForKey:NekoBehaviourKey]
		isEqualToString:@"flee"];
}

/* Not a fifth behaviour: a cat asked to stay is still a cat that follows the
   cursor, or lives on the Dock, or runs away — it is simply not going anywhere
   about it. Which is why this is a menu item and not another line in the
   pop-up, and why it survives changing the behaviour under it. */
- (BOOL)staysWhereItIs
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:NekoStayKey];
}

/* Deliberately an AND rather than the flag alone: a cat that follows the cursor
   and comments on your work at the same time is two features fighting for the
   bubble, and the suggestion was always meant to come from the one wandering
   around looking at what you are up to. */
- (BOOL)suggestsUnasked
{
	return [self roamsOnItsOwn]
		&& [[NSUserDefaults standardUserDefaults] boolForKey:NekoSuggestKey];
}

- (NSTimeInterval)suggestionInterval
{
	NSInteger minutes = [[NSUserDefaults standardUserDefaults]
		integerForKey:NekoSuggestEveryKey];
	if(minutes < 1)
		minutes = 10;
	return (NSTimeInterval)minutes * 60.0;
}

- (BOOL)isPaused
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:NekoPausedKey];
}

#pragma mark Opening at login

- (id<NekoAppService>)loginService
{
	Class serviceClass = NSClassFromString(@"SMAppService");
	if (serviceClass == Nil)
		return nil;
	return [(id<NekoAppServiceClass>)serviceClass mainAppService];
}

- (BOOL)canOpenAtLogin
{
	return [self loginService] != nil;
}

- (BOOL)opensAtLogin
{
	id<NekoAppService> service = [self loginService];
	if (service == nil)
		return NO;
	NSInteger status = [service status];
	return status == NekoLoginEnabled || status == NekoLoginRequiresApproval;
}

/* Returns whether the system now agrees, so the checkbox can follow it rather
   than the click. */
- (BOOL)setOpensAtLogin:(BOOL)wanted
{
	id<NekoAppService> service = [self loginService];
	if (service == nil)
		return NO;

	NSError *error = nil;
	BOOL ok = wanted ? [service registerAndReturnError:&error]
	                 : [service unregisterAndReturnError:&error];
	if (!ok)
		NSLog(@"Neko: could not %@ as a login item: %@",
		      wanted ? @"register" : @"unregister", error);
	else if (wanted && [service status] == NekoLoginRequiresApproval)
		[self explainLoginApproval];
	return [self opensAtLogin];
}

/* Registering succeeds but stays inert until the user allows it, and nothing
   says so unless we do. */
- (void)explainLoginApproval
{
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:NSLocalizedString(@"Neko needs your approval to open at login", @"Neko needs your approval to open at login")];
	[alert setInformativeText:NSLocalizedString(@"Open System Settings, then Login Items, and allow Neko.", @"Open System Settings, then Login Items, and allow Neko.")];
	[alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK")];
	[NSApp activateIgnoringOtherApps:YES];
	[alert runModal];
}

- (void)takeWanderFrom:(id)sender
{
	[[NSUserDefaults standardUserDefaults]
		setBool:([sender state] == NSControlStateValueOn) forKey:NekoWanderKey];
	[self settingsChanged];
}

- (NSUInteger)behaviourIndex
{
	if([self livesOnWindowEdges])
		return 1;
	if([self roamsOnItsOwn])
		return 2;
	return [self fleesThePointer] ? 3 : 0;
}

- (void)takeBehaviourFrom:(id)sender
{
	NSArray *names = [NSArray arrayWithObjects:@"follow", @"windows", @"roam", @"flee", nil];
	NSUInteger index = (NSUInteger)[sender indexOfSelectedItem];
	[[NSUserDefaults standardUserDefaults]
		setObject:[names objectAtIndex:MIN(index, [names count] - 1)]
		   forKey:NekoBehaviourKey];
	[self updateWanderAvailability];
	[self syncSuggestControls];
	[self syncAskControls];
	[self settingsChanged];
	[[NekoAntics sharedAntics] applySettings];
}

/* Wandering is what an idle cursor-chaser does. A cat living on the Dock is
   already moving about on its own, so the two cannot both be on. */
- (void)updateWanderAvailability
{
	BOOL follows = [self behaviourIndex] == 0;
	[wanderCheck setEnabled:follows];
	[wanderCheck setToolTip:follows ? nil
		: NSLocalizedString(@"Only while following the cursor", @"Only while following the cursor")];
}

- (void)takeOpenAtLoginFrom:(id)sender
{
	BOOL wanted = ([sender state] == NSControlStateValueOn);
	BOOL got = [self setOpensAtLogin:wanted];
	[sender setState:got ? NSControlStateValueOn : NSControlStateValueOff];
}

#pragma mark Notifications

- (void)settingsChanged
{
	[[NSUserDefaults standardUserDefaults] synchronize];
	/* Menu and tray icon follow the settings even when something other than the
	   menu changed them. */
	[self buildCharacterMenu];
	[self updateStatusItemImage];
	[self updatePauseItemTitle];
	[self updateAskItem];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:NekoSettingsDidChangeNotification object:self];
}

#pragma mark Actions

- (void)togglePause:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setBool:![self isPaused] forKey:NekoPausedKey];
	[self settingsChanged];
}

- (void)chooseCharacter:(id)sender
{
	[[NSUserDefaults standardUserDefaults]
		setObject:[sender representedObject] forKey:NekoCharacterKey];
	[self characterDidChange];
}

- (void)characterDidChange
{
	if(prefsPanel != nil)
		[characterPopUp selectItemWithTitle:[[self character] name]];
	[self settingsChanged];
}

- (void)showAbout:(id)sender
{
	[NSApp activateIgnoringOtherApps:YES];
	[NSApp orderFrontStandardAboutPanel:sender];
}

/* And the other ⌘Q, which is the one that was actually firing.

   MainMenu.nib has carried a standard application menu since 2007 — "Quit
   NewApplication", ⌘Q, wired to -terminate: — and Info.plist still names it as
   NSMainNibFile. That menu is never drawn, because this process runs as an
   accessory with no Dock icon, **and its key equivalents work anyway** whenever
   the application is active: while the preferences are open, after the About
   panel, or the moment the panel takes focus to have a question typed into it.

   So the shortcut is taken off every item in that menu that terminates, at the
   same moment the status item is installed. Done in code rather than by editing
   the nib because it is an eighteen-year-old compiled keyedobjects.nib, and a
   binary nobody can read in a diff is a poor place to keep a decision. */
- (void)disarmQuitShortcut
{
	[self disarmQuitIn:[NSApp mainMenu]];
	/* And again once the nib has finished, because the order is not ours to
	   assume: this controller is built from -awakeFromNib of a panel that lives
	   in the same nib as the menu, and nothing promises the menu has been
	   connected to NSApp by then. A second pass after launching costs nothing
	   and is the one that is guaranteed to see it. */
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                        selector:@selector(applicationLaunched:)
	                                            name:NSApplicationDidFinishLaunchingNotification
	                                          object:nil];
}

/* The one launch hook, because two would be two places to look. */
- (void)applicationLaunched:(NSNotification *)note
{
	[self disarmQuitIn:[NSApp mainMenu]];

	/* Not immediately: the first seconds after login belong to whatever else is
	   starting, and a window that appears while the desktop is still settling is
	   a window nobody reads. */
	/* Stamped now rather than the first time somebody asks how long it has been
	   here. Asked for the first time after a month, the fallback — the oldest day
	   file — would have said thirty for ever, because the older days are pruned.
	   Taken at launch it is right from the first day, and on an installation that
	   predates the stamp it is the best answer available. */
	[[NekoMemory sharedMemory] metOn];

	[self performSelector:@selector(checkPermissionsOnce) withObject:nil afterDelay:4.0];
	[self performSelector:@selector(checkForNewVersion) withObject:nil afterDelay:12.0];
}

/* A permission that is missing and needed is a feature that is silently not
   working. Said once per launch and no more: the window is the message, and a
   cat that opens it every hour is a cat somebody switches off.

   "Missing" is NekoPermissions' own word for it — switched on but not allowed —
   so nothing here decides what counts as needed. A permission nothing uses is
   worth showing in that tab and is not worth a word about. */
- (void)checkPermissionsOnce
{
	if(naggedAboutPermissions)
		return;
	naggedAboutPermissions = YES;

	NSArray *missing = [NekoPermissions missing];
	if([missing count] == 0)
		return;

	NSMutableArray *names = [NSMutableArray array];
	for(NekoPermission *one in missing)
		[names addObject:[one name]];

	NSLog(@"Neko: switched on but not allowed — %@",
		[names componentsJoinedByString:@", "]);
	[[NekoAsk sharedAsk] sayUnprompted:[NSString stringWithFormat:
		NSLocalizedString(@"Something is switched on that I am not allowed to do: %@.", @"Something is switched on that I am not allowed to do: %@."),
		[names componentsJoinedByString:@", "]]];
	[self showPermissions:nil];
}

/* The preferences, opened on the tab that is the reason for opening them. */
- (void)showPermissions:(id)sender
{
	[self showPreferences:sender];
	[prefsTabs selectTabViewItemWithIdentifier:@"permissions"];
}

- (void)disarmQuitIn:(NSMenu *)menu
{
	for(NSMenuItem *item in [menu itemArray]) {
		if([item action] == @selector(terminate:)
		   || [item action] == @selector(quit:)) {
			[item setKeyEquivalent:@""];
			[item setKeyEquivalentModifierMask:0];
		}
		if([item hasSubmenu])
			[self disarmQuitIn:[item submenu]];
	}
}

- (void)quit:(id)sender
{
	[NSApp terminate:sender];
}

#pragma mark Preferences window

- (NSTextField *)labelWithString:(NSString *)string frame:(NSRect)frame
{
	NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
	[label setStringValue:string];
	[label setBezeled:NO];
	[label setDrawsBackground:NO];
	[label setEditable:NO];
	[label setSelectable:NO];
	[label setAlignment:NSTextAlignmentRight];
	return label;
}

- (void)buildPreferencesPanel
{
	prefsPanel = [[NSPanel alloc]
		initWithContentRect:NSMakeRect(0.0f, 0.0f, 624.0f, 470.0f)
		          styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
		            backing:NSBackingStoreBuffered
		              defer:NO];
	[prefsPanel setTitle:NSLocalizedString(@"Neko Preferences", @"Neko Preferences")];
	/* The opposite of the cat's rule: this one window should come to whichever
	   desktop you are on rather than living on all of them, so that choosing
	   Preferences from the menu bar does not throw you across Spaces to where it
	   happened to be opened the first time. */
	[prefsPanel setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
	[prefsPanel setReleasedWhenClosed:NO];
	[prefsPanel setHidesOnDeactivate:NO];
	[prefsPanel center];

	/* Two tabs: the cat, and the conversation. One window's worth of controls
	   each, rather than one window with two windows' worth. */
	NSTabView *tabs = [[NSTabView alloc]
		initWithFrame:NSInsetRect([[prefsPanel contentView] bounds], 8.0f, 8.0f)];
	[[prefsPanel contentView] addSubview:tabs];
	prefsTabs = tabs;            /* to open straight onto a tab */

	NSView *content = [[[NSView alloc]
		initWithFrame:NSMakeRect(0.0f, 0.0f, 600.0f, 420.0f)] autorelease];
	NSTabViewItem *petTab = [[NSTabViewItem alloc] initWithIdentifier:@"pet"];
	[petTab setLabel:NSLocalizedString(@"Pet", @"Pet")];
	[petTab setView:content];
	[tabs addTabViewItem:petTab];
	[petTab release];

	NSView *askContent = [[[NSView alloc]
		initWithFrame:NSMakeRect(0.0f, 0.0f, 600.0f, 420.0f)] autorelease];
	NSTabViewItem *askTab = [[[NSTabViewItem alloc] initWithIdentifier:@"ask"] autorelease];
	[askTab setLabel:NSLocalizedString(@"Ask Neko", @"Ask Neko")];
	[askTab setView:askContent];
	[tabs addTabViewItem:askTab];

	NSView *localContent = [[[NSView alloc]
		initWithFrame:NSMakeRect(0.0f, 0.0f, 600.0f, 420.0f)] autorelease];
	[self buildLocalTabInView:localContent];
	NSTabViewItem *localTab = [[[NSTabViewItem alloc] initWithIdentifier:@"local"] autorelease];
	[localTab setLabel:NSLocalizedString(@"Local model", @"Local model")];
	[localTab setView:localContent];
	[tabs addTabViewItem:localTab];

	NSView *suggestContent = [[[NSView alloc]
		initWithFrame:NSMakeRect(0.0f, 0.0f, 600.0f, 420.0f)] autorelease];
	[self buildSuggestTabInView:suggestContent];
	NSTabViewItem *suggestTab = [[[NSTabViewItem alloc] initWithIdentifier:@"suggest"] autorelease];
	[suggestTab setLabel:NSLocalizedString(@"Suggestions", @"Suggestions")];
	[suggestTab setView:suggestContent];
	[tabs addTabViewItem:suggestTab];

	NSView *drawContent = [[[NSView alloc]
		initWithFrame:NSMakeRect(0.0f, 0.0f, 600.0f, 420.0f)] autorelease];
	[self buildDrawTabInView:drawContent];
	NSTabViewItem *drawTab = [[[NSTabViewItem alloc] initWithIdentifier:@"draw"] autorelease];
	[drawTab setLabel:NSLocalizedString(@"Drawings", @"Drawings")];
	[drawTab setView:drawContent];
	[tabs addTabViewItem:drawTab];

	permissionsContent = [[[NSView alloc]
		initWithFrame:NSMakeRect(0.0f, 0.0f, 600.0f, 420.0f)] autorelease];
	NSTabViewItem *permissionsTab = [[[NSTabViewItem alloc] initWithIdentifier:@"permissions"] autorelease];
	[permissionsTab setLabel:NSLocalizedString(@"Permissions", @"Permissions")];
	[permissionsTab setView:permissionsContent];
	[tabs addTabViewItem:permissionsTab];
	/* Its own class since 2.12 — see NekoPermissionsTab.h for why this one moved
	   first out of the five. */
	permissions = [[NekoPermissionsTab alloc] init];
	[permissions buildInView:permissionsContent];
	[tabs release];

	/* Behaviour */
	[content addSubview:[self labelWithString:NSLocalizedString(@"Behaviour:", @"Behaviour:")
	                                    frame:NSMakeRect(20.0f, 176.0f, 125.0f, 17.0f)]];

	behaviourPopUp = [[NSPopUpButton alloc]
		initWithFrame:NSMakeRect(152.0f, 171.0f, 260.0f, 26.0f) pullsDown:NO];
	[behaviourPopUp addItemWithTitle:NSLocalizedString(@"Follows the cursor", @"Follows the cursor")];
	[behaviourPopUp addItemWithTitle:NSLocalizedString(@"Lives on the Dock", @"Lives on the Dock")];
	[behaviourPopUp addItemWithTitle:NSLocalizedString(@"Roams on its own", @"Roams on its own")];
	[behaviourPopUp addItemWithTitle:NSLocalizedString(@"Runs from the cursor", @"Runs from the cursor")];
	[behaviourPopUp selectItemAtIndex:[self behaviourIndex]];
	[behaviourPopUp setTarget:self];
	[behaviourPopUp setAction:@selector(takeBehaviourFrom:)];
	[content addSubview:behaviourPopUp];
	[behaviourPopUp release];

	/* Character */
	[content addSubview:[self labelWithString:NSLocalizedString(@"Character:", @"Character:")
	                                    frame:NSMakeRect(20.0f, 378.0f, 125.0f, 17.0f)]];

	characterPopUp = [[NSPopUpButton alloc]
		initWithFrame:NSMakeRect(152.0f, 373.0f, 170.0f, 26.0f) pullsDown:NO];
	for(NekoCharacter *character in [NekoCharacter availableCharacters])
		[characterPopUp addItemWithTitle:[character name]];
	[characterPopUp selectItemWithTitle:[[self character] name]];
	[characterPopUp setTarget:self];
	[characterPopUp setAction:@selector(takeCharacterFrom:)];
	[content addSubview:characterPopUp];
	[characterPopUp release];

	/* Speed */
	[content addSubview:[self labelWithString:NSLocalizedString(@"Speed:", @"Speed:")
	                                    frame:NSMakeRect(20.0f, 338.0f, 125.0f, 17.0f)]];

	speedSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(152.0f, 335.0f, 200.0f, 21.0f)];
	[speedSlider setMinValue:NekoMinSpeed];
	[speedSlider setMaxValue:NekoMaxSpeed];
	[speedSlider setFloatValue:[self speed]];
	[speedSlider setContinuous:YES];
	[speedSlider setTarget:self];
	[speedSlider setAction:@selector(takeSpeedFrom:)];
	[content addSubview:speedSlider];
	[speedSlider release];

	speedField = [self labelWithString:@"" frame:NSMakeRect(362.0f, 338.0f, 90.0f, 17.0f)];
	[content addSubview:speedField];

	/* How close it comes */
	[content addSubview:[self labelWithString:NSLocalizedString(@"Stops short by:", @"Stops short by:")
	                                    frame:NSMakeRect(20.0f, 298.0f, 125.0f, 17.0f)]];

	radiusSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(152.0f, 295.0f, 200.0f, 21.0f)];
	[radiusSlider setMinValue:NekoMinStopRadius];
	[radiusSlider setMaxValue:NekoMaxStopRadius];
	[radiusSlider setFloatValue:[self stopRadius]];
	[radiusSlider setContinuous:YES];
	[radiusSlider setTarget:self];
	[radiusSlider setAction:@selector(takeStopRadiusFrom:)];
	[content addSubview:radiusSlider];
	[radiusSlider release];

	radiusField = [self labelWithString:@"" frame:NSMakeRect(362.0f, 298.0f, 90.0f, 17.0f)];
	[content addSubview:radiusField];

	/* Size */
	[content addSubview:[self labelWithString:NSLocalizedString(@"Size:", @"Size:")
	                                    frame:NSMakeRect(20.0f, 256.0f, 125.0f, 17.0f)]];

	sizePopUp = [[NSPopUpButton alloc]
		initWithFrame:NSMakeRect(152.0f, 251.0f, 100.0f, 26.0f) pullsDown:NO];
	[sizePopUp addItemWithTitle:@"1\u00d7"];
	[sizePopUp addItemWithTitle:@"2\u00d7"];
	[sizePopUp selectItemAtIndex:([self scale] >= 2.0f) ? 1 : 0];
	[sizePopUp setTarget:self];
	[sizePopUp setAction:@selector(takeScaleFrom:)];
	[content addSubview:sizePopUp];
	[sizePopUp release];

	/* Idle sleep */
	sleepCheck = [[NSButton alloc] initWithFrame:NSMakeRect(154.0f, 224.0f, 300.0f, 18.0f)];
	[sleepCheck setButtonType:NSButtonTypeSwitch];
	[sleepCheck setTitle:NSLocalizedString(@"Fall asleep when idle", @"Fall asleep when idle")];
	[sleepCheck setState:[self idleSleep] ? NSControlStateValueOn : NSControlStateValueOff];
	[sleepCheck setTarget:self];
	[sleepCheck setAction:@selector(takeIdleSleepFrom:)];
	[content addSubview:sleepCheck];
	[sleepCheck release];

	/* Wandering */
	wanderCheck = [[NSButton alloc] initWithFrame:NSMakeRect(154.0f, 200.0f, 300.0f, 18.0f)];
	[wanderCheck setButtonType:NSButtonTypeSwitch];
	[wanderCheck setTitle:NSLocalizedString(@"Wander off when idle", @"Wander off when idle")];
	[wanderCheck setState:[self wandersWhenIdle] ? NSControlStateValueOn : NSControlStateValueOff];
	[wanderCheck setTarget:self];
	[wanderCheck setAction:@selector(takeWanderFrom:)];
	[content addSubview:wanderCheck];
	[wanderCheck release];

	/* Opening at login */
	loginCheck = [[NSButton alloc] initWithFrame:NSMakeRect(154.0f, 152.0f, 300.0f, 18.0f)];
	[loginCheck setButtonType:NSButtonTypeSwitch];
	[loginCheck setTitle:NSLocalizedString(@"Open at login", @"Open at login")];
	[loginCheck setState:[self opensAtLogin] ? NSControlStateValueOn : NSControlStateValueOff];
	[loginCheck setTarget:self];
	[loginCheck setAction:@selector(takeOpenAtLoginFrom:)];
	if (![self canOpenAtLogin]) {
		[loginCheck setEnabled:NO];
		[loginCheck setToolTip:NSLocalizedString(@"Needs macOS 13 or newer", @"Needs macOS 13 or newer")];
	}
	[content addSubview:loginCheck];
	[loginCheck release];

	/* Looking for a new version. On by default, and this is the switch that
	   stops it: what it sends is one request to this project's own releases and
	   nothing about you beyond what any request carries. See NekoUpdate.h. */
	updateCheck = [[NSButton alloc] initWithFrame:NSMakeRect(154.0f, 126.0f, 300.0f, 18.0f)];
	[updateCheck setButtonType:NSButtonTypeSwitch];
	[updateCheck setTitle:NSLocalizedString(@"Look for new versions", @"Look for new versions")];
	[updateCheck setState:[[NSUserDefaults standardUserDefaults]
		boolForKey:NekoUpdateCheckKey] ? NSControlStateValueOn : NSControlStateValueOff];
	[updateCheck setTarget:self];
	[updateCheck setAction:@selector(takeUpdateCheckFrom:)];
	/* One literal, not four joined: a key split across string literals is a key
	   that can never match an entry in Localizable.strings, and tests/docs.m
	   found exactly that here. */
	[updateCheck setToolTip:NSLocalizedString(@"Neko is not signed, so it never installs anything itself: it tells you, downloads the disk image if you say so, and you drag it across.", @"Neko is not signed, so it never installs anything itself: it tells you, downloads the disk image if you say so, and you drag it across.")];
	[content addSubview:updateCheck];
	[updateCheck release];

	/* Restore defaults */
	NSButton *reset = [[NSButton alloc] initWithFrame:NSMakeRect(16.0f, 62.0f, 180.0f, 32.0f)];
	[reset setBezelStyle:NSBezelStyleRounded];
	[reset setTitle:NSLocalizedString(@"Restore Defaults", @"Restore Defaults")];
	[reset setTarget:self];
	[reset setAction:@selector(restoreDefaults:)];
	[content addSubview:reset];
	[reset release];

	NSButton *look = [[NSButton alloc] initWithFrame:NSMakeRect(206.0f, 62.0f, 160.0f, 32.0f)];
	[look setBezelStyle:NSBezelStyleRounded];
	[look setTitle:NSLocalizedString(@"Check now", @"Check now")];
	[look setTarget:self];
	[look setAction:@selector(checkNow:)];
	[content addSubview:look];
	[look release];

	[self buildAskTab:askContent];
	[self updateWanderAvailability];
	[self updateValueFields];
}

/* The conversation tab. Everything below the switch is disabled until the
   switch is on, so the shape of the feature is visible before turning it on. */
- (void)buildAskTab:(NSView *)content
{
	NekoAsk *ask = [NekoAsk sharedAsk];

	askCheck = [[NSButton alloc] initWithFrame:NSMakeRect(20.0f, 380.0f, 520.0f, 18.0f)];
	[askCheck setButtonType:NSButtonTypeSwitch];
	[askCheck setTitle:NSLocalizedString(@"Let me ask Neko questions out loud", @"Let me ask Neko questions out loud")];
	[askCheck setState:[ask isEnabled] ? NSControlStateValueOn : NSControlStateValueOff];
	[askCheck setTarget:self];
	[askCheck setAction:@selector(takeAskEnabledFrom:)];
	[content addSubview:askCheck];
	[askCheck release];

	[content addSubview:[self labelWithString:NSLocalizedString(@"Keystroke:", @"Keystroke:")
	                                    frame:NSMakeRect(20.0f, 342.0f, 125.0f, 17.0f)]];
	askHotKeyPopUp = [[NSPopUpButton alloc]
		initWithFrame:NSMakeRect(152.0f, 337.0f, 160.0f, 26.0f) pullsDown:NO];
	NSEnumerator *e = [[self hotKeyChoices] objectEnumerator];
	NSArray *choice;
	while((choice = [e nextObject]) != nil)
		[askHotKeyPopUp addItemWithTitle:[NekoHotKey
			displayNameForKeyCode:[[choice objectAtIndex:0] unsignedShortValue]
			            modifiers:[[choice objectAtIndex:1] unsignedIntegerValue]]];
	[askHotKeyPopUp setTarget:self];
	[askHotKeyPopUp setAction:@selector(takeAskHotKeyFrom:)];
	[content addSubview:askHotKeyPopUp];
	[askHotKeyPopUp release];

	[content addSubview:[self labelWithString:NSLocalizedString(@"Answers from:", @"Answers from:")
	                                    frame:NSMakeRect(20.0f, 302.0f, 125.0f, 17.0f)]];
	askProviderPopUp = [[NSPopUpButton alloc]
		initWithFrame:NSMakeRect(152.0f, 297.0f, 220.0f, 26.0f) pullsDown:NO];
	/* Same order as askProviderKeys. */
	[askProviderPopUp addItemWithTitle:NSLocalizedString(@"Apple Intelligence, on this Mac", @"Apple Intelligence, on this Mac")];
	[askProviderPopUp addItemWithTitle:NSLocalizedString(@"ChatGPT", @"ChatGPT")];
	[askProviderPopUp addItemWithTitle:NSLocalizedString(@"Claude", @"Claude")];
	[askProviderPopUp addItemWithTitle:NSLocalizedString(@"A model on this Mac", @"A model on this Mac")];
	[askProviderPopUp addItemWithTitle:NSLocalizedString(@"A Shortcut of mine", @"A Shortcut of mine")];
	[askProviderPopUp setTarget:self];
	[askProviderPopUp setAction:@selector(takeAskProviderFrom:)];
	[content addSubview:askProviderPopUp];
	[askProviderPopUp release];

	[content addSubview:[self labelWithString:NSLocalizedString(@"Shortcut name:", @"Shortcut name:")
	                                    frame:NSMakeRect(20.0f, 262.0f, 125.0f, 17.0f)]];
	askShortcutField = [[NSTextField alloc] initWithFrame:NSMakeRect(152.0f, 259.0f, 220.0f, 22.0f)];
	[askShortcutField setTarget:self];
	[askShortcutField setAction:@selector(takeAskShortcutNameFrom:)];
	[content addSubview:askShortcutField];
	[askShortcutField release];

	[content addSubview:[self labelWithString:NSLocalizedString(@"API key:", @"API key:")
	                                    frame:NSMakeRect(20.0f, 222.0f, 125.0f, 17.0f)]];
	askKeyField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(152.0f, 219.0f, 220.0f, 22.0f)];
	[askKeyField setTarget:self];
	[askKeyField setAction:@selector(takeAskKeyFrom:)];
	[content addSubview:askKeyField];
	[askKeyField release];

	askSpeakCheck = [[NSButton alloc] initWithFrame:NSMakeRect(152.0f, 162.0f, 196.0f, 18.0f)];
	[askSpeakCheck setButtonType:NSButtonTypeSwitch];
	[askSpeakCheck setTitle:NSLocalizedString(@"Read the answer aloud", @"Read the answer aloud")];
	[askSpeakCheck setTarget:self];
	[askSpeakCheck setAction:@selector(takeAskSpeakFrom:)];
	[content addSubview:askSpeakCheck];
	[askSpeakCheck release];

	/* On the same row as the voice because they are the same subject: how a turn
	   ends, and whether the next one needs a keystroke. */
	followUpCheck = [[NSButton alloc] initWithFrame:NSMakeRect(356.0f, 162.0f, 224.0f, 18.0f)];
	[followUpCheck setButtonType:NSButtonTypeSwitch];
	[followUpCheck setTitle:NSLocalizedString(@"Listen for a reply after", @"Listen for a reply after")];
	[followUpCheck setToolTip:NSLocalizedString(@"For a few seconds after it speaks, so an answer needs no keystroke. The bubble says so while the microphone is open.", @"For a few seconds after it speaks, so an answer needs no keystroke. The bubble says so while the microphone is open.")];
	[followUpCheck setTarget:self];
	[followUpCheck setAction:@selector(takeFollowUpFrom:)];
	[content addSubview:followUpCheck];
	[followUpCheck release];

	wakeCheck = [[NSButton alloc] initWithFrame:NSMakeRect(152.0f, 186.0f, 300.0f, 18.0f)];
	[wakeCheck setButtonType:NSButtonTypeSwitch];
	[wakeCheck setTitle:NSLocalizedString(@"Answer when I say “Neko” (beta)", @"Answer when I say “Neko” (beta)")];
	[wakeCheck setTarget:self];
	[wakeCheck setAction:@selector(takeWakeWordFrom:)];
	[content addSubview:wakeCheck];
	[wakeCheck release];

	/* Beside the other switch that lets something outside this Mac into the
	   conversation: one lets it do things here, the other lets it read things
	   from elsewhere. */
	webCheck = [[NSButton alloc] initWithFrame:NSMakeRect(356.0f, 138.0f, 224.0f, 18.0f)];
	[webCheck setButtonType:NSButtonTypeSwitch];
	[webCheck setTitle:NSLocalizedString(@"Let it look up the news", @"Let it look up the news")];
	[webCheck setTarget:self];
	[webCheck setAction:@selector(takeWebFrom:)];
	[content addSubview:webCheck];
	[webCheck release];

	actionsCheck = [[NSButton alloc] initWithFrame:NSMakeRect(152.0f, 138.0f, 196.0f, 18.0f)];
	[actionsCheck setButtonType:NSButtonTypeSwitch];
	[actionsCheck setTitle:NSLocalizedString(@"Let it open things when I ask", @"Let it open things when I ask")];
	[actionsCheck setTarget:self];
	[actionsCheck setAction:@selector(takeActionsFrom:)];
	[content addSubview:actionsCheck];
	[actionsCheck release];

	foldersButton = [[NSButton alloc] initWithFrame:NSMakeRect(148.0f, 100.0f, 168.0f, 28.0f)];
	[foldersButton setBezelStyle:NSBezelStyleRounded];
	[foldersButton setControlSize:NSControlSizeSmall];
	[foldersButton setTitle:NSLocalizedString(@"Show it a folder…", @"Show it a folder…")];
	[foldersButton setTarget:self];
	[foldersButton setAction:@selector(showFolderPressed:)];
	[content addSubview:foldersButton];
	[foldersButton release];

	forgetFoldersButton = [[NSButton alloc] initWithFrame:NSMakeRect(450.0f, 100.0f, 130.0f, 28.0f)];
	[forgetFoldersButton setBezelStyle:NSBezelStyleRounded];
	[forgetFoldersButton setControlSize:NSControlSizeSmall];
	[forgetFoldersButton setTitle:NSLocalizedString(@"Forget them", @"Forget them")];
	[forgetFoldersButton setTarget:self];
	[forgetFoldersButton setAction:@selector(forgetFoldersPressed:)];
	[content addSubview:forgetFoldersButton];
	[forgetFoldersButton release];

	/* Same treatment as the suggestions tab, and for the same reason: with
	   everything switched on this paragraph says more than eighty-six points
	   will hold, and the part that got cut off was the part about what leaves
	   the Mac. */
	NSScrollView *askScroll = [[NSScrollView alloc]
		initWithFrame:NSMakeRect(20.0f, 8.0f, 556.0f, 86.0f)];
	[askScroll setHasVerticalScroller:YES];
	[askScroll setDrawsBackground:NO];
	[askScroll setBorderType:NSNoBorder];
	askStatusField = [self labelWithString:@"" frame:NSMakeRect(0.0f, 0.0f, 538.0f, 86.0f)];
	[askStatusField setAlignment:NSTextAlignmentLeft];
	[[askStatusField cell] setWraps:YES];
	[askStatusField setFont:[NSFont systemFontOfSize:11.0f]];
	[askStatusField setTextColor:[NSColor secondaryLabelColor]];
	[askScroll setDocumentView:askStatusField];
	[content addSubview:askScroll];
	[askScroll release];

	[self syncAskControls];
}

/* The combinations offered. A recorder field would be nicer; a short list of
   things that do not collide with anything is more useful sooner. */
- (NSArray *)hotKeyChoices
{
	NSEventModifierFlags control = NSEventModifierFlagControl;
	NSEventModifierFlags option = NSEventModifierFlagOption;
	NSEventModifierFlags command = NSEventModifierFlagCommand;
	NSEventModifierFlags shift = NSEventModifierFlagShift;
	return [NSArray arrayWithObjects:
		[NSArray arrayWithObjects:[NSNumber numberWithUnsignedShort:0x2D],
			[NSNumber numberWithUnsignedInteger:control | option], nil],
		[NSArray arrayWithObjects:[NSNumber numberWithUnsignedShort:0x31],
			[NSNumber numberWithUnsignedInteger:control | option], nil],
		[NSArray arrayWithObjects:[NSNumber numberWithUnsignedShort:0x2D],
			[NSNumber numberWithUnsignedInteger:command | control], nil],
		[NSArray arrayWithObjects:[NSNumber numberWithUnsignedShort:0x2D],
			[NSNumber numberWithUnsignedInteger:option | shift], nil], nil];
}

- (void)takeWakeWordFrom:(id)sender
{
	[[NSUserDefaults standardUserDefaults]
		setBool:([sender state] == NSControlStateValueOn) forKey:NekoWakeWordKey];
	[[NekoWakeWord sharedWakeWord] applySettings];
	[self syncAskControls];
}

- (void)takeFollowUpFrom:(id)sender
{
	[[NSUserDefaults standardUserDefaults]
		setBool:([sender state] == NSControlStateValueOn) forKey:NekoAskFollowUpKey];
	[self syncAskControls];
}

- (void)takeWebFrom:(id)sender
{
	[[NSUserDefaults standardUserDefaults]
		setBool:([sender state] == NSControlStateValueOn) forKey:NekoWebEnabledKey];
	[self syncAskControls];
}

- (void)takeActionsFrom:(id)sender
{
	[[NSUserDefaults standardUserDefaults]
		setBool:([sender state] == NSControlStateValueOn) forKey:NekoActionsEnabledKey];
	[self syncAskControls];
}

/* Handing a folder over is the user's own act, in the system's own panel, and
   this is where it is done on purpose rather than in the middle of a request. */
- (void)showFolderPressed:(id)sender
{
	NekoFolderAccess *access = [NekoFolderAccess sharedAccess];
	NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
	NSEnumerator *e = [[NekoFolderAccess folderKeys] objectEnumerator];
	NSString *key;
	while((key = [e nextObject]) != nil) {
		NSMenuItem *item = [menu addItemWithTitle:[access displayNameFor:key]
		                                   action:@selector(chooseFolder:)
		                            keyEquivalent:@""];
		[item setTarget:self];
		[item setRepresentedObject:key];
		[item setState:[access hasAccessTo:key] ? NSControlStateValueOn : NSControlStateValueOff];
	}
	[menu popUpMenuPositioningItem:nil
	                    atLocation:NSMakePoint(0.0f, NSHeight([sender bounds]))
	                        inView:sender];
}

- (void)chooseFolder:(id)sender
{
	NSString *why = nil;
	[[NekoFolderAccess sharedAccess] requestAccessTo:[sender representedObject]
	                                          saying:&why];
	[self syncAskControls];
	/* Through the cat, because this is a menu item and has no window to hang a
	   sheet on — and because the cat is who was going to be given the folder. */
	if([why length] > 0)
		[[NekoAsk sharedAsk] sayUnprompted:why];
}

- (void)forgetFoldersPressed:(id)sender
{
	NekoFolderAccess *access = [NekoFolderAccess sharedAccess];
	NSEnumerator *e = [[access allowedKeys] objectEnumerator];
	NSString *key;
	while((key = [e nextObject]) != nil)
		[access forget:key];
	[self syncAskControls];
}

- (void)setAskStatus:(NSString *)text
{
	[askStatusField setStringValue:(text ?: @"")];
	NSSize needed = [[askStatusField cell] cellSizeForBounds:
		NSMakeRect(0.0f, 0.0f, 538.0f, 100000.0f)];
	CGFloat height = ceil(needed.height);
	if(height < 86.0)
		height = 86.0;
	[askStatusField setFrame:NSMakeRect(0.0, 0.0, 538.0, height)];
	[askStatusField scrollRectToVisible:NSMakeRect(0.0, height - 1.0, 538.0, 1.0)];
}

- (void)syncAskControls
{
	NekoAsk *ask = [NekoAsk sharedAsk];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL on = [ask isEnabled];
	/* The engine is chosen here but used by two features, so these controls stay
	   live for someone who wants suggestions and no talking cat. */
	BOOL engineWanted = on || [self suggestsUnasked];
	NSString *choice = [defaults stringForKey:NekoAskProviderKey];
	BOOL shortcut = [choice isEqualToString:@"shortcut"];
	id keyed = [self askKeyedProvider];
	NSUInteger providerIndex = [[self askProviderKeys] indexOfObject:choice ?: @"apple"];
	if(providerIndex == NSNotFound)
		providerIndex = 0;

	[askCheck setState:on ? NSControlStateValueOn : NSControlStateValueOff];
	[askHotKeyPopUp setEnabled:on];
	[askProviderPopUp setEnabled:engineWanted];
	[askProviderPopUp selectItemAtIndex:providerIndex];
	[askShortcutField setEnabled:engineWanted && shortcut];
	[askShortcutField setStringValue:
		[defaults stringForKey:NekoAskShortcutNameKey] ?: @""];
	[askKeyField setEnabled:engineWanted && keyed != nil];
	[askKeyField setStringValue:[keyed hasApiKey] ? @"••••••••••••" : @""];
	[askSpeakCheck setEnabled:on];
	[wakeCheck setEnabled:on && [NekoWakeWord isAvailable]];
	[wakeCheck setState:[defaults boolForKey:NekoWakeWordKey]
		? NSControlStateValueOn : NSControlStateValueOff];
	[wakeCheck setToolTip:[NekoWakeWord unavailableReason]];
	[actionsCheck setEnabled:on];
	[webCheck setEnabled:on];
	[webCheck setState:[defaults boolForKey:NekoWebEnabledKey]
		? NSControlStateValueOn : NSControlStateValueOff];
	BOOL acting = on && [defaults boolForKey:NekoActionsEnabledKey];
	[foldersButton setEnabled:acting];
	[forgetFoldersButton setEnabled:acting
		&& [[[NekoFolderAccess sharedAccess] allowedKeys] count] > 0];
	[actionsCheck setState:[defaults boolForKey:NekoActionsEnabledKey]
		? NSControlStateValueOn : NSControlStateValueOff];
	[askSpeakCheck setState:[defaults boolForKey:NekoAskSpeakKey]
		? NSControlStateValueOn : NSControlStateValueOff];
	[followUpCheck setEnabled:on];
	[followUpCheck setState:[defaults boolForKey:NekoAskFollowUpKey]
		? NSControlStateValueOn : NSControlStateValueOff];

	/* Which combination is selected, if it is one of the offered ones. */
	unsigned short code = (unsigned short)[defaults integerForKey:NekoAskHotKeyCodeKey];
	NSUInteger flags = (NSUInteger)[defaults integerForKey:NekoAskHotKeyModifiersKey];
	NSArray *choices = [self hotKeyChoices];
	NSUInteger i;
	for(i = 0; i < [choices count]; i++) {
		NSArray *choice = [choices objectAtIndex:i];
		if([[choice objectAtIndex:0] unsignedShortValue] == code
		   && [[choice objectAtIndex:1] unsignedIntegerValue] == flags) {
			[askHotKeyPopUp selectItemAtIndex:i];
			break;
		}
	}

	[self setAskStatus:[self askStatusLine]];
}

#pragma mark The local model

/* The suggestions tab. The switch is the small part; the paragraph under it is
   the point, because this is the one feature that looks at what you are doing
   and, with a remote engine chosen, tells somebody else about it. */
/* The drawing tab. A gigabyte and a half of model and twenty seconds a picture,
   both of which are said here rather than discovered. */
/* The permissions tab: five rows, each saying what the system currently thinks
   and offering the only move that is still available — asking, or opening the
   pane where a previous no can be undone. Rebuilt every time the window is
   shown, since all five can change behind the app's back. */

- (void)buildDrawTabInView:(NSView *)content
{
	drawCheck = [[NSButton alloc] initWithFrame:NSMakeRect(20.0f, 380.0f, 556.0f, 18.0f)];
	[drawCheck setButtonType:NSButtonTypeSwitch];
	[drawCheck setTitle:NSLocalizedString(@"Let Neko draw when I ask to see something", @"Let Neko draw when I ask to see something")];
	[drawCheck setTarget:self];
	[drawCheck setAction:@selector(takeDrawEnabledFrom:)];
	[content addSubview:drawCheck];
	[drawCheck release];

	/* Which of them draws. There is more than one now, and until this row
	   existed the answer was -firstObject in two different files. */
	[content addSubview:[self labelWithString:NSLocalizedString(@"Model:", @"Model:")
	                                    frame:NSMakeRect(20.0f, 351.0f, 125.0f, 17.0f)]];
	drawModelPopUp = [[NSPopUpButton alloc]
		initWithFrame:NSMakeRect(152.0f, 346.0f, 260.0f, 26.0f) pullsDown:NO];
	NSEnumerator *pictures = [[[NekoModelStore sharedStore] pictureCatalogue]
		objectEnumerator];
	NekoLocalModel *picture;
	while((picture = [pictures nextObject]) != nil)
		[drawModelPopUp addItemWithTitle:[picture name]];
	[drawModelPopUp setTarget:self];
	[drawModelPopUp setAction:@selector(takeDrawModelFrom:)];
	[content addSubview:drawModelPopUp];
	[drawModelPopUp release];

	drawActionButton = [[NSButton alloc] initWithFrame:NSMakeRect(20.0f, 306.0f, 180.0f, 32.0f)];
	[drawActionButton setBezelStyle:NSBezelStyleRounded];
	[drawActionButton setTarget:self];
	[drawActionButton setAction:@selector(drawActionPressed:)];
	[content addSubview:drawActionButton];
	[drawActionButton release];

	drawProgress = [[NSProgressIndicator alloc]
		initWithFrame:NSMakeRect(212.0f, 314.0f, 230.0f, 16.0f)];
	[drawProgress setStyle:NSProgressIndicatorStyleBar];
	[drawProgress setIndeterminate:NO];
	[drawProgress setMinValue:0.0];
	[drawProgress setMaxValue:1.0];
	[drawProgress setHidden:YES];
	[content addSubview:drawProgress];
	[drawProgress release];

	[content addSubview:[self labelWithString:NSLocalizedString(@"Effort:", @"Effort:")
	                                    frame:NSMakeRect(20.0f, 277.0f, 125.0f, 17.0f)]];
	drawStepsPopUp = [[NSPopUpButton alloc]
		initWithFrame:NSMakeRect(152.0f, 272.0f, 200.0f, 26.0f) pullsDown:NO];
	NSEnumerator *e = [[self drawStepChoices] objectEnumerator];
	NSNumber *steps;
	while((steps = [e nextObject]) != nil)
		[drawStepsPopUp addItemWithTitle:[NSString localizedStringWithFormat:
			NSLocalizedString(@"%ld steps", @"%ld steps"), (long)[steps integerValue]]];
	[drawStepsPopUp setTarget:self];
	[drawStepsPopUp setAction:@selector(takeDrawStepsFrom:)];
	[content addSubview:drawStepsPopUp];
	[drawStepsPopUp release];

	[content addSubview:[self labelWithString:NSLocalizedString(@"Size:", @"Size:")
	                                    frame:NSMakeRect(20.0f, 243.0f, 125.0f, 17.0f)]];
	drawSizePopUp = [[NSPopUpButton alloc]
		initWithFrame:NSMakeRect(152.0f, 238.0f, 200.0f, 26.0f) pullsDown:NO];
	NSEnumerator *sizes = [[self drawSizeChoices] objectEnumerator];
	NSNumber *side;
	while((side = [sizes nextObject]) != nil)
		[drawSizePopUp addItemWithTitle:[NSString localizedStringWithFormat:@"%ld × %ld",
			(long)[side integerValue], (long)[side integerValue]]];
	[drawSizePopUp setTarget:self];
	[drawSizePopUp setAction:@selector(takeDrawSizeFrom:)];
	[content addSubview:drawSizePopUp];
	[drawSizePopUp release];

	drawNowButton = [[NSButton alloc] initWithFrame:NSMakeRect(20.0f, 198.0f, 200.0f, 32.0f)];
	[drawNowButton setBezelStyle:NSBezelStyleRounded];
	[drawNowButton setTitle:NSLocalizedString(@"Draw a cat now", @"Draw a cat now")];
	[drawNowButton setTarget:self];
	[drawNowButton setAction:@selector(drawNowPressed:)];
	[content addSubview:drawNowButton];
	[drawNowButton release];

	/* Tall enough for the longest translation of it, not the shortest: in
	   Italian this paragraph runs three lines further than in English. */
	drawStatusField = [self labelWithString:@""
	                                  frame:NSMakeRect(20.0f, 62.0f, 556.0f, 128.0f)];
	[drawStatusField setAlignment:NSTextAlignmentLeft];
	[[drawStatusField cell] setWraps:YES];
	[content addSubview:drawStatusField];

	[self syncDrawControls];
}

- (NSArray *)drawStepChoices
{
	return [NSArray arrayWithObjects:[NSNumber numberWithInt:8],
		[NSNumber numberWithInt:14], [NSNumber numberWithInt:20],
		[NSNumber numberWithInt:30], nil];
}

- (NSArray *)drawSizeChoices
{
	return [NSArray arrayWithObjects:[NSNumber numberWithInt:384],
		[NSNumber numberWithInt:512], [NSNumber numberWithInt:768], nil];
}

- (NekoLocalModel *)pictureModel
{
	return [[NekoPainter sharedPainter] model];
}

/* Choosing one carries its own recipe with it: the steps and the size go back to
   what that checkpoint wants, because a turbo model left on fourteen steps at a
   guidance of seven draws mush and nobody would have chosen that. The guidance
   itself is never somebody's to set — see NekoPainter. */
- (void)takeDrawModelFrom:(id)sender
{
	NSArray *pictures = [[NekoModelStore sharedStore] pictureCatalogue];
	NSInteger index = [sender indexOfSelectedItem];
	if(index < 0 || index >= (NSInteger)[pictures count])
		return;
	NekoLocalModel *picture = [pictures objectAtIndex:(NSUInteger)index];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:[picture identifier] forKey:NekoDrawModelKey];
	[defaults setObject:[NSNumber numberWithInt:[picture drawSteps]]
	             forKey:NekoDrawStepsKey];
	[defaults setObject:[NSNumber numberWithInt:[picture drawSide]]
	             forKey:NekoDrawSizeKey];
	[self syncDrawControls];
}

- (void)takeDrawEnabledFrom:(id)sender
{
	[[NSUserDefaults standardUserDefaults]
		setBool:([sender state] == NSControlStateValueOn) forKey:NekoDrawEnabledKey];
	[self syncDrawControls];
}

- (void)takeDrawStepsFrom:(id)sender
{
	NSArray *choices = [self drawStepChoices];
	NSUInteger index = MIN((NSUInteger)[sender indexOfSelectedItem], [choices count] - 1);
	[[NSUserDefaults standardUserDefaults]
		setObject:[choices objectAtIndex:index] forKey:NekoDrawStepsKey];
	[self syncDrawControls];
}

- (void)takeDrawSizeFrom:(id)sender
{
	NSArray *choices = [self drawSizeChoices];
	NSUInteger index = MIN((NSUInteger)[sender indexOfSelectedItem], [choices count] - 1);
	[[NSUserDefaults standardUserDefaults]
		setObject:[choices objectAtIndex:index] forKey:NekoDrawSizeKey];
	[self syncDrawControls];
}

- (void)drawActionPressed:(id)sender
{
	NekoModelStore *store = [NekoModelStore sharedStore];
	NekoLocalModel *model = [self pictureModel];
	if([store isDownloading]) {
		[store cancelDownload];
		[self syncDrawControls];
		return;
	}
	if([store installedURLForIdentifier:[model identifier]] != nil) {
		[store removeIdentifier:[model identifier]];
		[self syncDrawControls];
		return;
	}
	if(![self mayDownload:model]) {
		[self syncDrawControls];
		return;
	}
	[store downloadModel:model progress:^(double fraction) {
		[drawProgress setDoubleValue:fraction];
	} completion:^(NSURL *file, NSError *error) {
		if(error != nil)
			[drawStatusField setStringValue:[error localizedDescription]];
		[self syncDrawControls];
	}];
	[self syncDrawControls];
}

/* Something small and quick to prove the thing works, without making anyone
   speak to the cat first. */
- (void)drawNowPressed:(id)sender
{
	[drawNowButton setEnabled:NO];
	[drawStatusField setStringValue:NSLocalizedString(@"Drawing…", @"Drawing…")];
	NSDate *started = [NSDate date];
	[[NekoPainter sharedPainter] draw:@"a small tabby cat sitting on a desk, photograph"
	                       completion:^(NSImage *picture, NSError *error) {
		[drawNowButton setEnabled:YES];
		if(picture == nil) {
			[drawStatusField setStringValue:[error localizedDescription]
				?: NSLocalizedString(@"The drawing did not come out.", @"The drawing did not come out.")];
			return;
		}
		[drawStatusField setStringValue:[NSString localizedStringWithFormat:
			NSLocalizedString(@"Drawn in %.0f seconds.", @"Drawn in %.0f seconds."), -[started timeIntervalSinceNow]]];
		MyPanel *catPanel = [self panel];
		[[NekoAsk sharedAsk] showDrawing:picture near:catPanel];
	}];
}

- (void)syncDrawControls
{
	NekoModelStore *store = [NekoModelStore sharedStore];
	NekoLocalModel *model = [self pictureModel];
	BOOL installed = [store installedURLForIdentifier:[model identifier]] != nil;
	BOOL busy = [store isDownloading]
		&& [[[store downloadingModel] identifier] isEqualToString:[model identifier]];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL on = [defaults boolForKey:NekoDrawEnabledKey];

	[drawCheck setState:on ? NSControlStateValueOn : NSControlStateValueOff];
	[drawActionButton setTitle:busy ? NSLocalizedString(@"Stop", @"Stop")
	                                : (installed ? NSLocalizedString(@"Remove", @"Remove")
	                                             : NSLocalizedString(@"Download", @"Download"))];
	[drawProgress setHidden:!busy];
	if(busy)
		[drawProgress setDoubleValue:[store fraction]];
	NSArray *pictures = [store pictureCatalogue];
	NSUInteger chosen = [pictures indexOfObject:model];
	[drawModelPopUp selectItemAtIndex:chosen == NSNotFound ? 0 : (NSInteger)chosen];
	[drawModelPopUp setEnabled:on && !busy];
	[drawStepsPopUp setEnabled:on && installed];
	[drawSizePopUp setEnabled:on && installed];
	[drawNowButton setEnabled:on && installed && ![[NekoPainter sharedPainter] isDrawing]];

	NSArray *steps = [self drawStepChoices];
	NSUInteger index = [steps indexOfObject:
		[NSNumber numberWithInteger:[defaults integerForKey:NekoDrawStepsKey]]];
	[drawStepsPopUp selectItemAtIndex:(index == NSNotFound) ? 1 : index];
	NSArray *sizes = [self drawSizeChoices];
	index = [sizes indexOfObject:
		[NSNumber numberWithInteger:[defaults integerForKey:NekoDrawSizeKey]]];
	[drawSizePopUp selectItemAtIndex:(index == NSNotFound) ? 1 : index];

	if(!busy)
		[drawStatusField setStringValue:[self drawStatusLine:installed]];
}

- (NSString *)drawStatusLine:(BOOL)installed
{
	NSMutableString *line = [NSMutableString string];
	if([[NekoPainter sharedPainter] helperPath] == nil) {
		[line appendString:NSLocalizedString(@"This build has no drawing program in it, so nothing here can work yet.", @"This build has no drawing program in it, so nothing here can work yet.")];
		return line;
	}
	[line appendString:NSLocalizedString(@"Ask to be shown something — “show me the Colosseum” — and the cat draws it here, on this Mac's GPU, with Stable Diffusion. Nothing is sent anywhere, and it costs nothing but the time.", @"Ask to be shown something — “show me the Colosseum” — and the cat draws it here, on this Mac's GPU, with Stable Diffusion. Nothing is sent anywhere, and it costs nothing but the time.")];
	[line appendString:@"\n\n"];
	if(!installed)
		[line appendFormat:NSLocalizedString(@"The model is %@ and has not been downloaded yet. ", @"The model is %@ and has not been downloaded yet. "),
			[[self pictureModel] detail]];
	else
		[line appendFormat:NSLocalizedString(@"Measured on this Mac: a 512 pixel picture at 14 steps took 14 seconds to draw, plus about nine to open the model the first time. More steps means a better picture and a longer wait. The model takes %@ of disk. ", @"Measured on this Mac: a 512 pixel picture at 14 steps took 14 seconds to draw, plus about nine to open the model the first time. More steps means a better picture and a longer wait. The model takes %@ of disk. "),
			[NSByteCountFormatter stringFromByteCount:
				[[NekoModelStore sharedStore] installedBytesForIdentifier:[[self pictureModel] identifier]]
			                               countStyle:NSByteCountFormatterCountStyleFile]];
	[line appendString:NSLocalizedString(@"The words that describe the picture come from whichever engine Ask Neko is set to; only that sentence leaves the Mac, and only if that engine is a remote one.", @"The words that describe the picture come from whichever engine Ask Neko is set to; only that sentence leaves the Mac, and only if that engine is a remote one.")];
	return line;
}

- (void)buildSuggestTabInView:(NSView *)content
{
	suggestCheck = [[NSButton alloc] initWithFrame:NSMakeRect(20.0f, 380.0f, 556.0f, 18.0f)];
	[suggestCheck setButtonType:NSButtonTypeSwitch];
	[suggestCheck setTitle:NSLocalizedString(@"Let Neko suggest things while it roams", @"Let Neko suggest things while it roams")];
	[suggestCheck setTarget:self];
	[suggestCheck setAction:@selector(takeSuggestFrom:)];
	[content addSubview:suggestCheck];
	[suggestCheck release];

	/* Was a switch, on until somebody remembered it; is a stretch of ten minutes
	   now, with the time left in the menu and one click to end it. The switch was
	   the one standing grant in an application that asks per use everywhere else.
	   See NekoGlance.h. */
	lookButton = [[NSButton alloc] initWithFrame:NSMakeRect(20.0f, 350.0f, 300.0f, 24.0f)];
	[lookButton setBezelStyle:NSBezelStyleRounded];
	[lookButton setTitle:NSLocalizedString(@"Let it look for ten minutes", @"Let it look for ten minutes")];
	[lookButton setTarget:self];
	[lookButton setAction:@selector(takeReadTextFrom:)];
	[content addSubview:lookButton];
	[lookButton release];

	[content addSubview:[self labelWithString:NSLocalizedString(@"Speaks at most every:", @"Speaks at most every:")
	                                    frame:NSMakeRect(20.0f, 320.0f, 125.0f, 17.0f)]];

	suggestEveryPopUp = [[NSPopUpButton alloc]
		initWithFrame:NSMakeRect(152.0f, 315.0f, 160.0f, 26.0f) pullsDown:NO];
	NSEnumerator *e = [[self suggestIntervalChoices] objectEnumerator];
	NSNumber *minutes;
	while((minutes = [e nextObject]) != nil)
		[suggestEveryPopUp addItemWithTitle:[NSString localizedStringWithFormat:
			NSLocalizedString(@"%ld minutes", @"%ld minutes"), (long)[minutes integerValue]]];
	[suggestEveryPopUp setTarget:self];
	[suggestEveryPopUp setAction:@selector(takeSuggestEveryFrom:)];
	[content addSubview:suggestEveryPopUp];
	[suggestEveryPopUp release];

	suggestNowButton = [[NSButton alloc] initWithFrame:NSMakeRect(20.0f, 272.0f, 200.0f, 32.0f)];
	[suggestNowButton setBezelStyle:NSBezelStyleRounded];
	[suggestNowButton setTitle:NSLocalizedString(@"Suggest something now", @"Suggest something now")];
	[suggestNowButton setTarget:self];
	[suggestNowButton setAction:@selector(suggestNowPressed:)];
	[content addSubview:suggestNowButton];
	[suggestNowButton release];

	/* This paragraph is where everything the feature can see, everything it
	   sends, and how it is going today are written down, and it runs to more
	   than the tab is tall — four hundred points more in Italian, all of which
	   used to be cut off at the bottom edge. So it scrolls, and nothing has to
	   be left out of it to fit. */
	NSScrollView *scroll = [[NSScrollView alloc]
		initWithFrame:NSMakeRect(20.0f, 96.0f, 556.0f, 168.0f)];
	[scroll setHasVerticalScroller:YES];
	[scroll setDrawsBackground:NO];
	[scroll setBorderType:NSNoBorder];
	suggestStatusField = [self labelWithString:@""
	                                     frame:NSMakeRect(0.0f, 0.0f, 538.0f, 168.0f)];
	[suggestStatusField setAlignment:NSTextAlignmentLeft];
	[[suggestStatusField cell] setWraps:YES];
	[scroll setDocumentView:suggestStatusField];
	[content addSubview:scroll];
	[scroll release];

	/* What it remembers, and the two things anyone should be able to do about
	   it: look at it, and delete it. */
	memoryField = [self labelWithString:@"" frame:NSMakeRect(20.0f, 52.0f, 556.0f, 42.0f)];
	[memoryField setAlignment:NSTextAlignmentLeft];
	[memoryField setFont:[NSFont systemFontOfSize:11.0f]];
	[[memoryField cell] setWraps:YES];
	[content addSubview:memoryField];

	NSButton *reveal = [[NSButton alloc] initWithFrame:NSMakeRect(20.0f, 22.0f, 190.0f, 28.0f)];
	[reveal setBezelStyle:NSBezelStyleRounded];
	[reveal setControlSize:NSControlSizeSmall];
	[reveal setTitle:NSLocalizedString(@"Show what it remembers", @"Show what it remembers")];
	[reveal setTarget:self];
	[reveal setAction:@selector(revealMemoryPressed:)];
	[content addSubview:reveal];
	[reveal release];

	NSButton *forget = [[NSButton alloc] initWithFrame:NSMakeRect(216.0f, 22.0f, 160.0f, 28.0f)];
	[forget setBezelStyle:NSBezelStyleRounded];
	[forget setControlSize:NSControlSizeSmall];
	[forget setTitle:NSLocalizedString(@"Forget everything", @"Forget everything")];
	[forget setTarget:self];
	[forget setAction:@selector(forgetMemoryPressed:)];
	[content addSubview:forget];
	[forget release];

	[self syncSuggestControls];
}

- (NSArray *)suggestIntervalChoices
{
	return [NSArray arrayWithObjects:
		[NSNumber numberWithInt:2], [NSNumber numberWithInt:5],
		[NSNumber numberWithInt:10], [NSNumber numberWithInt:30],
		[NSNumber numberWithInt:60], nil];
}

- (void)takeSuggestFrom:(id)sender
{
	[[NSUserDefaults standardUserDefaults]
		setBool:([sender state] == NSControlStateValueOn) forKey:NekoSuggestKey];
	[[NekoAdvisor sharedAdvisor] applySettings];
	[self syncSuggestControls];
	[self syncAskControls];
}

/* Turning this on is a real decision — it reads what you are typing — so it
   asks the system for the permission there and then, which puts up the standard
   alert and opens the pane. The switch stays where the user put it either way,
   and the paragraph underneath says whether it is actually working. */
- (void)takeReadTextFrom:(id)sender
{
	/* The permission first, because a stretch that cannot read anything is a
	   countdown that means nothing. */
	[NekoDesktop requestAccessibility];
	NSString *said = [[NekoGlance sharedGlance]
		lookFor:[NekoGlance defaultStretch]];
	if([said length] > 0)
		[[NekoAsk sharedAsk] sayUnprompted:said];
	[self syncSuggestControls];
}

- (void)takeSuggestEveryFrom:(id)sender
{
	NSArray *choices = [self suggestIntervalChoices];
	NSUInteger index = MIN((NSUInteger)[sender indexOfSelectedItem], [choices count] - 1);
	[[NSUserDefaults standardUserDefaults]
		setObject:[choices objectAtIndex:index] forKey:NekoSuggestEveryKey];
	[self syncSuggestControls];
}

/* One suggestion on demand, so the feature can be judged in ten seconds instead
   of waited for. Failures land in the status line rather than in a dialogue. */
- (void)suggestNowPressed:(id)sender
{
	[suggestNowButton setEnabled:NO];
	[self setSuggestStatus:NSLocalizedString(@"Having a look…", @"Having a look…")];
	[[NekoAdvisor sharedAdvisor] suggestNow:^(NSString *line, NSError *error) {
		[suggestNowButton setEnabled:YES];
		if([line length] > 0 && ![line isEqualToString:@"-"])
			[self setSuggestStatus:[NSString stringWithFormat:
				NSLocalizedString(@"It said: %@", @"It said: %@"), line]];
		else if(error != nil)
			[self setSuggestStatus:[error localizedDescription]
				?: NSLocalizedString(@"No engine answered.", @"No engine answered.")];
		else
			[self setSuggestStatus:
				NSLocalizedString(@"It had nothing worth saying about this.", @"It had nothing worth saying about this.")];
	}];
}

/* The diary is a file about a person, so the way to see it is the Finder rather
   than a window of the app's own devising. */
- (void)revealMemoryPressed:(id)sender
{
	NekoMemory *memory = [NekoMemory sharedMemory];
	[[NSWorkspace sharedWorkspace] openURL:[memory directory]];
}

- (void)forgetMemoryPressed:(id)sender
{
	NekoMemory *memory = [NekoMemory sharedMemory];
	if([memory dayCount] == 0 && [[memory durableLines] count] == 0
	   && [[NekoFact all] count] == 0)
		return;

	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:NSLocalizedString(@"Forget everything Neko remembers?", @"Forget everything Neko remembers?")];
	/* The things somebody asked it to remember are counted separately, because
	   they are the ones a person will actually miss: the rest it worked out on
	   its own, and these it was told. */
	[alert setInformativeText:[NSString localizedStringWithFormat:
		NSLocalizedString(@"%lu day(s) of notes, %lu line(s) it had kept, and %lu thing(s) you asked it to remember. This cannot be undone.", @"%lu day(s) of notes, %lu line(s) it had kept, and %lu thing(s) you asked it to remember. This cannot be undone."),
		(unsigned long)[memory dayCount], (unsigned long)[[memory durableLines] count],
		(unsigned long)[[NekoFact all] count]]];
	[alert addButtonWithTitle:NSLocalizedString(@"Forget", @"Forget")].hasDestructiveAction = YES;
	[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel")];
	[NSApp activateIgnoringOtherApps:YES];
	if([alert runModal] != NSAlertFirstButtonReturn)
		return;
	[memory forgetEverything];
	/* How you reacted to what it said is something it learned about you too. */
	[[NekoRate sharedRate] forgetPace];
	[self syncSuggestControls];
}

/* Set through here rather than directly: the field is inside a scroll view now,
   and a document view that is not as tall as its text is the same as no scroll
   view at all. */
- (void)setSuggestStatus:(NSString *)text
{
	[suggestStatusField setStringValue:(text ?: @"")];
	NSSize needed = [[suggestStatusField cell] cellSizeForBounds:
		NSMakeRect(0.0f, 0.0f, 538.0f, 100000.0f)];
	CGFloat height = ceil(needed.height);
	if(height < 168.0f)
		height = 168.0f;
	[suggestStatusField setFrame:NSMakeRect(0.0f, 0.0f, 538.0f, height)];
	/* Showing the end of a paragraph nobody has read yet is a strange way to
	   start: the top of it, always. */
	[suggestStatusField scrollRectToVisible:NSMakeRect(0.0f, height - 1.0f, 538.0f, 1.0f)];
}

- (void)syncSuggestControls
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL roaming = [self roamsOnItsOwn];
	BOOL on = [defaults boolForKey:NekoSuggestKey];

	[suggestCheck setState:on ? NSControlStateValueOn : NSControlStateValueOff];
	[suggestCheck setEnabled:roaming];
	[suggestCheck setToolTip:roaming ? nil
		: NSLocalizedString(@"Only in the “Roams on its own” behaviour", @"Only in the “Roams on its own” behaviour")];
	[suggestEveryPopUp setEnabled:roaming && on];
	[suggestNowButton setEnabled:roaming && on];
	/* A button rather than a switch now: nothing to reflect, only whether it
	   can be pressed at all. */
	[lookButton setEnabled:roaming];

	NSArray *choices = [self suggestIntervalChoices];
	NSUInteger index = [choices indexOfObject:
		[NSNumber numberWithInteger:[defaults integerForKey:NekoSuggestEveryKey]]];
	[suggestEveryPopUp selectItemAtIndex:(index == NSNotFound) ? 2 : index];

	[self setSuggestStatus:[self suggestStatusLine:roaming]];

	NekoMemory *memory = [NekoMemory sharedMemory];
	NSUInteger days = [memory dayCount];
	NSUInteger kept = [[memory durableLines] count];
	if(days == 0 && kept == 0)
		[memoryField setStringValue:NSLocalizedString(@"It remembers nothing yet. What it notices is written a day at a time, in plain text, on this Mac — never sent anywhere — kept for thirty days, and reduced each night to a few lines worth keeping.", @"It remembers nothing yet. What it notices is written a day at a time, in plain text, on this Mac — never sent anywhere — kept for thirty days, and reduced each night to a few lines worth keeping.")];
	else
		[memoryField setStringValue:[NSString localizedStringWithFormat:
			NSLocalizedString(@"It remembers %lu day(s) and %lu line(s) worth keeping, %@ in plain text on this Mac. Older days are removed after thirty.", @"It remembers %lu day(s) and %lu line(s) worth keeping, %@ in plain text on this Mac. Older days are removed after thirty."),
			(unsigned long)days, (unsigned long)kept,
			[NSByteCountFormatter stringFromByteCount:[memory bytesOnDisk]
			                               countStyle:NSByteCountFormatterCountStyleFile]]];
}

- (NSString *)suggestStatusLine:(BOOL)roaming
{
	if(!roaming)
		return NSLocalizedString(@"This belongs to one behaviour only. Set Behaviour to “Roams on its own” in the Pet tab: a cat chasing the cursor has its attention elsewhere, and one living on the Dock is already busy.", @"This belongs to one behaviour only. Set Behaviour to “Roams on its own” in the Pet tab: a cat chasing the cursor has its attention elsewhere, and one living on the Dock is already busy.");

	NSMutableString *line = [NSMutableString string];
	[line appendString:NSLocalizedString(@"Curiosity comes with roaming whatever this switch says: every minute or two the cat comes over to the pointer, asks what you are writing, or goes to claw the edge of the screen. That part needs no engine and sends nothing anywhere.", @"Curiosity comes with roaming whatever this switch says: every minute or two the cat comes over to the pointer, asks what you are writing, or goes to claw the edge of the screen. That part needs no engine and sends nothing anywhere.")];
	[line appendString:@"\n\n"];
	[line appendString:NSLocalizedString(@"It waits for a seam in your work before saying anything: a program you have just left after a long stretch, a burst of typing that has ended, a pause. In the middle of something it stays quiet, and it says nothing at all while a window fills the screen or you are typing a password. The interval below is a floor rather than an alarm clock: how good a moment it holds out for depends on how the day has gone so far.", @"It waits for a seam in your work before saying anything: a program you have just left after a long stretch, a burst of typing that has ended, a pause. In the middle of something it stays quiet, and it says nothing at all while a window fills the screen or you are typing a password. The interval below is a floor rather than an alarm clock: how good a moment it holds out for depends on how the day has gone so far.")];
	[line appendString:@"\n\n"];
	[line appendString:NSLocalizedString(@"While roaming, Neko glances at what you are doing and now and then says something about it — a tip, a nudge, or a joke. It waits until you have been in one application for a while, keeps quiet when you are away from the keyboard, and says nothing at all when it has nothing worth saying.", @"While roaming, Neko glances at what you are doing and now and then says something about it — a tip, a nudge, or a joke. It waits until you have been in one application for a while, keeps quiet when you are away from the keyboard, and says nothing at all when it has nothing worth saying.")];
	[line appendString:@"\n\n"];
	[line appendString:NSLocalizedString(@"All it can see, and all that is sent, is this:", @"All it can see, and all that is sent, is this:")];
	[line appendString:@"\n"];
	[line appendString:[[NekoAdvisor sharedAdvisor] context]];
	[line appendString:@"\n"];
	/* Which engine actually speaks, said here rather than inferred from the Ask
	   Neko tab: that setting governs questions, this one governs remarks. */
	[line appendString:@"\n\n"];
	[line appendString:[NekoBrains describeChoice]];

	/* How many today, how they landed, and what it has made of that. The pace is
	   the one thing here that moves by itself, so it is the one thing that has
	   to be visible. */
	[line appendString:@"\n\n"];
	[line appendString:[[NekoRate sharedRate] describeToday]];

	[line appendString:@"\n\n"];
	/* This sentence used to end "with ChatGPT, Claude or a Shortcut, it is sent
	   to that service like any other question", which was false — and false in
	   the direction of frightening somebody. Everything that reads the desktop
	   summary asks NekoBrains for the best engine that stays on this Mac, and
	   there is no path from here to a remote one. tests/screen.m reads both
	   callers and fails if a third one ever forgets. */
	[line appendString:NSLocalizedString(@"Window titles are included only if this Mac has already granted Neko screen recording; that permission is never asked for. None of this ever leaves the Mac: what the cat notices is read by a model on this Mac or not at all, whichever engine you chose for answering questions.", @"Window titles are included only if this Mac has already granted Neko screen recording; that permission is never asked for. None of this ever leaves the Mac: what the cat notices is read by a model on this Mac or not at all, whichever engine you chose for answering questions.")];

	[line appendString:@"\n\n"];
	if([[NekoGlance sharedGlance] isLooking])
		[line appendString:NSLocalizedString(@"It is looking right now — what is in the field you are typing in, or under the pointer, is included above. It stops on its own, the time left is in the cat's menu, and one click there ends it. Password fields are refused, nothing at all is read while macOS has secure keyboard entry on, and only the last few hundred characters are taken.", @"It is looking right now — what is in the field you are typing in, or under the pointer, is included above. It stops on its own, the time left is in the cat's menu, and one click there ends it. Password fields are refused, nothing at all is read while macOS has secure keyboard entry on, and only the last few hundred characters are taken.")];
	else if([NekoDesktop accessibilityGranted])
		[line appendString:NSLocalizedString(@"It is not looking. Ask it to — “guarda cosa sto facendo”, or the button above — and it reads the text you are working on for ten minutes and then stops by itself. There is no way to leave this on: a permission you have to remember to revoke is one nobody should have to remember.", @"It is not looking. Ask it to — “guarda cosa sto facendo”, or the button above — and it reads the text you are working on for ten minutes and then stops by itself. There is no way to leave this on: a permission you have to remember to revoke is one nobody should have to remember.")];
	else
		[line appendString:NSLocalizedString(@"It is not looking, and it has no Accessibility permission either, so it could not. The button above asks for both at once; the permission is in System Settings, Privacy & Security, Accessibility.", @"It is not looking, and it has no Accessibility permission either, so it could not. The button above asks for both at once; the permission is in System Settings, Privacy & Security, Accessibility.")];
	return line;
}

- (void)buildLocalTabInView:(NSView *)content
{
	[content addSubview:[self labelWithString:NSLocalizedString(@"Model:", @"Model:")
	                                    frame:NSMakeRect(20.0f, 356.0f, 125.0f, 17.0f)]];

	localModelPopUp = [[NSPopUpButton alloc]
		initWithFrame:NSMakeRect(152.0f, 351.0f, 280.0f, 26.0f) pullsDown:NO];
	NSEnumerator *e = [[[NekoModelStore sharedStore] catalogue] objectEnumerator];
	NekoLocalModel *model;
	while((model = [e nextObject]) != nil)
		[localModelPopUp addItemWithTitle:[model name]];
	[localModelPopUp setTarget:self];
	[localModelPopUp setAction:@selector(takeLocalModelFrom:)];
	[content addSubview:localModelPopUp];
	[localModelPopUp release];

	/* Two lines, not one. The catalogue's own sentence is the first; whether this
	   Mac can run the thing is the second, and it only ever appears when there is
	   something to say. At seventeen points it wrapped and then clipped, which
	   made the warning invisible — a warning nobody sees is not one.

	   Thirty-four and not twenty-nine, because tests/room.m measures the longest
	   of those sentences in all four languages and it comes to thirty-two. The
	   first attempt at this passed only by a tolerance I had written into the
	   check myself, which is not the same as fitting. The room comes from the gap
	   that was already empty above the button. */
	localDetailField = [self labelWithString:@""
	                                   frame:NSMakeRect(152.0f, 313.0f, 420.0f, 34.0f)];
	[localDetailField setAlignment:NSTextAlignmentLeft];
	[[localDetailField cell] setWraps:YES];
	[content addSubview:localDetailField];

	localActionButton = [[NSButton alloc] initWithFrame:NSMakeRect(152.0f, 280.0f, 150.0f, 32.0f)];
	[localActionButton setBezelStyle:NSBezelStyleRounded];
	[localActionButton setTarget:self];
	[localActionButton setAction:@selector(localActionPressed:)];
	[content addSubview:localActionButton];
	[localActionButton release];

	localProgress = [[NSProgressIndicator alloc]
		initWithFrame:NSMakeRect(312.0f, 288.0f, 130.0f, 16.0f)];
	[localProgress setStyle:NSProgressIndicatorStyleBar];
	[localProgress setIndeterminate:NO];
	[localProgress setMinValue:0.0];
	[localProgress setMaxValue:1.0];
	[localProgress setHidden:YES];
	[content addSubview:localProgress];
	[localProgress release];

	localCleanButton = [[NSButton alloc] initWithFrame:NSMakeRect(20.0f, 240.0f, 556.0f, 32.0f)];
	[localCleanButton setBezelStyle:NSBezelStyleRounded];
	[localCleanButton setTarget:self];
	[localCleanButton setAction:@selector(localCleanPressed:)];
	[content addSubview:localCleanButton];
	[localCleanButton release];

	localStatusField = [self labelWithString:@""
	                                   frame:NSMakeRect(20.0f, 110.0f, 556.0f, 120.0f)];
	[localStatusField setAlignment:NSTextAlignmentLeft];
	[[localStatusField cell] setWraps:YES];
	[content addSubview:localStatusField];

	[self syncLocalControls];
}

- (NekoLocalModel *)selectedLocalModel
{
	NSArray *catalogue = [[NekoModelStore sharedStore] catalogue];
	NSInteger index = [localModelPopUp indexOfSelectedItem];
	if(index < 0 || index >= (NSInteger)[catalogue count])
		index = 0;
	return [catalogue objectAtIndex:index];
}

- (void)takeLocalModelFrom:(id)sender
{
	NekoLocalModel *model = [self selectedLocalModel];
	[[NSUserDefaults standardUserDefaults]
		setObject:[model identifier] forKey:@"NekoAskLocalModel"];
	[self syncLocalControls];

	/* Choosing one that is already on the disk and cannot be loaded is the other
	   half of the same warning, and it has to arrive now rather than the next
	   time somebody asks a question and gets nothing. Said once per choice, and
	   the choice stands — it is theirs, and the row keeps saying so in red. */
	if([[NekoModelStore sharedStore] installedURLForIdentifier:[model identifier]] != nil
	   && [model fitOnThisMac] == NekoModelWillNotLoad) {
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert setAlertStyle:NSAlertStyleCritical];
		[alert setMessageText:[NSString stringWithFormat:
			NSLocalizedString(@"%@ will not load on this Mac", @"%@ will not load on this Mac"), [model name]]];
		[alert setInformativeText:[NSString stringWithFormat:@"%@\n\n%@",
			[model memoryWarning],
			NSLocalizedString(@"It is on the disk, and questions sent to it will come back empty. Choose a smaller one, or remove it to get the space back.", @"It is on the disk, and questions sent to it will come back empty. Choose a smaller one, or remove it to get the space back.")]];
		[alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK")];
		[NSApp activateIgnoringOtherApps:YES];
		[alert runModal];
	}
}

/* Whether a download is worth starting, asked of any of them.

   Sixteen gigabytes is an hour of somebody's connection. If it cannot be loaded
   at the end of it, or will not fit on the disk in the first place, that is
   worth an alert rather than a line of grey text — and the choice stays theirs,
   because a Mac they plug more memory into next month is still their Mac.

   Shared by the two tabs that download something. It lived inside the one for
   models that answer in words, which left the one for models that draw with no
   check at all — and the largest of those is four gigabytes. */
- (BOOL)mayDownload:(NekoLocalModel *)model
{
	NekoModelStore *store = [NekoModelStore sharedStore];
	NSString *cannot = [model fitOnThisMac] == NekoModelWillNotLoad
		? [model memoryWarning] : nil;
	NSString *noRoom = [store diskWarningFor:model];
	if(cannot == nil && noRoom == nil)
		return YES;

	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setAlertStyle:NSAlertStyleCritical];
	[alert setMessageText:cannot != nil
		? [NSString stringWithFormat:
			NSLocalizedString(@"%@ will not run on this Mac", @"%@ will not run on this Mac"), [model name]]
		: [NSString stringWithFormat:
			NSLocalizedString(@"There is not room for %@", @"There is not room for %@"), [model name]]];
	NSMutableArray *why = [NSMutableArray array];
	if(cannot != nil)
		[why addObject:cannot];
	if(noRoom != nil)
		[why addObject:noRoom];
	[why addObject:NSLocalizedString(@"Downloading it will work. Loading it will not, and the download is several gigabytes.", @"Downloading it will work. Loading it will not, and the download is several gigabytes.")];
	[alert setInformativeText:[why componentsJoinedByString:@"\n\n"]];
	[alert addButtonWithTitle:NSLocalizedString(@"Do not download", @"Do not download")];
	[alert addButtonWithTitle:NSLocalizedString(@"Download anyway", @"Download anyway")];
	[NSApp activateIgnoringOtherApps:YES];
	return [alert runModal] != NSAlertFirstButtonReturn;
}

/* One button, three jobs, depending on what there is to do. */
- (void)localActionPressed:(id)sender
{
	NekoModelStore *store = [NekoModelStore sharedStore];
	NekoLocalModel *model = [self selectedLocalModel];

	if([store isDownloading]) {
		[store cancelDownload];
		[self syncLocalControls];
		return;
	}
	if([store installedURLForIdentifier:[model identifier]] != nil) {
		[store removeIdentifier:[model identifier]];
		[self syncLocalControls];
		return;
	}

	if(![self mayDownload:model]) {
		[self syncLocalControls];
		return;
	}

	[store downloadModel:model
	            progress:^(double fraction) {
		[localProgress setDoubleValue:fraction];
		[localStatusField setStringValue:[NSString localizedStringWithFormat:
			NSLocalizedString(@"Downloading %@ — %.0f%%", @"Downloading %@ — %.0f%%"), [model name], fraction * 100.0]];
	}
	          completion:^(NSURL *file, NSError *error) {
		if(error != nil)
			[localStatusField setStringValue:[NSString stringWithFormat:
				NSLocalizedString(@"That download failed: %@", @"That download failed: %@"), [error localizedDescription]]];
		[self syncLocalControls];
		[self syncAskControls];
	}];
	[self syncLocalControls];
}

- (void)localCleanPressed:(id)sender
{
	NekoModelStore *store = [NekoModelStore sharedStore];
	NekoLocalModel *keeper = [self selectedLocalModel];
	NSString *keep = [keeper identifier];
	NSUInteger others = [[store identifiersOtherThan:keep] count];
	if(others == 0)
		return;

	/* Gigabytes are about to leave the disk, and downloading them again is a
	   long wait: say plainly what goes and what stays before doing it. */
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:[NSString localizedStringWithFormat:
		NSLocalizedString(@"Remove %lu model(s) you are not using?", @"Remove %lu model(s) you are not using?"), (unsigned long)others]];
	[alert setInformativeText:[NSString stringWithFormat:
		NSLocalizedString(@"%@ is kept. The others free %@ and can be downloaded again later.", @"%@ is kept. The others free %@ and can be downloaded again later."),
		[keeper name],
		[NSByteCountFormatter stringFromByteCount:[store installedBytesOtherThan:keep]
		                               countStyle:NSByteCountFormatterCountStyleFile]]];
	[alert addButtonWithTitle:NSLocalizedString(@"Remove", @"Remove")].hasDestructiveAction = YES;
	[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel")];
	if([alert runModal] != NSAlertFirstButtonReturn)
		return;

	NSUInteger removed = [store removeAllExcept:keep];
	[self syncLocalControls];
	[self syncAskControls];
	/* After the refresh, so the outcome is what stays on screen. */
	[localStatusField setStringValue:removed == 0
		? NSLocalizedString(@"There was nothing else to remove.", @"There was nothing else to remove.")
		: [NSString localizedStringWithFormat:
			NSLocalizedString(@"Removed %lu model(s) that were not in use.", @"Removed %lu model(s) that were not in use."), (unsigned long)removed]];
}

- (void)syncLocalControls
{
	NekoModelStore *store = [NekoModelStore sharedStore];

	/* The menu is put where the settings say before anything is read from it.
	   The other way round — which is how this was — every freshly opened window
	   asked the first model in the catalogue whether it was installed, so a
	   downloaded model that was selected still offered a Download button. */
	NSString *chosen = [[NSUserDefaults standardUserDefaults] stringForKey:@"NekoAskLocalModel"];
	NSUInteger index = 0, i = 0;
	NSEnumerator *e = [[store catalogue] objectEnumerator];
	NekoLocalModel *each;
	while((each = [e nextObject]) != nil) {
		if([[each identifier] isEqualToString:chosen])
			index = i;
		i++;
	}
	[localModelPopUp selectItemAtIndex:index];

	NekoLocalModel *model = [self selectedLocalModel];
	BOOL installed = [store installedURLForIdentifier:[model identifier]] != nil;
	BOOL busy = [store isDownloading];
	/* And whether it writes its notes first, said in the list rather than
	   discovered in a bubble. NekoLocalProvider takes the notes out; this is so
	   that choosing one is a choice and not a surprise. */
	NSMutableString *says = [NSMutableString stringWithString:[model detail]];
	if([model thinks])
		[says appendFormat:@" · %@", NSLocalizedString(@"reasons before answering", @"reasons before answering")];

	/* Whether this Mac can actually run it, which is a different question from
	   whether it can fetch it — and for a 27B the two answers differ. Said in
	   the row whichever way it falls, because a warning nobody sees is not one.

	   Two sentences at most and only when there is something to say: memory
	   always, disk only while it is still a download. A model already on the
	   disk has spent that space, and repeating it would be noise. */
	NekoModelFit fit = [model fitOnThisMac];
	/* One warning line at most, because there is room for one — and memory
	   outranks the disk, since a model that cannot be loaded is not made better
	   by there being somewhere to put it. The alert before a download says both.
	   The disk is only asked about while it is still a download: a model already
	   on the disk has spent that space, and saying so again would be noise. */
	NSString *warning = [model memoryWarning];
	if(warning == nil && !installed)
		warning = [store diskWarningFor:model];
	if(warning != nil)
		[says appendFormat:@"\n%@", warning];
	[localDetailField setStringValue:says];
	[localDetailField setTextColor:fit == NekoModelWillNotLoad
		? [NSColor systemRedColor]
		: (fit == NekoModelFitsTightly ? [NSColor systemOrangeColor]
		                               : [NSColor secondaryLabelColor])];

	BOOL broken = [store isIncomplete:[model identifier]];
	[localActionButton setTitle:busy ? NSLocalizedString(@"Stop", @"Stop")
	                                 : (installed ? NSLocalizedString(@"Remove", @"Remove")
	                                              : (broken ? NSLocalizedString(@"Download again", @"Download again")
	                                                        : NSLocalizedString(@"Download", @"Download")))];
	[localActionButton setEnabled:YES];
	[localProgress setHidden:!busy];
	if(busy)
		[localProgress setDoubleValue:[store fraction]];

	/* What the housekeeping button is for, and whether there is any. */
	NekoLocalModel *selected = [self selectedLocalModel];
	long long spare = [store installedBytesOtherThan:[selected identifier]];
	NSUInteger others = [[store identifiersOtherThan:[selected identifier]] count];
	[localCleanButton setEnabled:!busy && others > 0];
	[localCleanButton setTitle:others == 0
		? NSLocalizedString(@"No unused models to remove", @"No unused models to remove")
		: [NSString localizedStringWithFormat:
			NSLocalizedString(@"Remove %lu unused model(s) — %@", @"Remove %lu unused model(s) — %@"), (unsigned long)others,
			[NSByteCountFormatter stringFromByteCount:spare
			                               countStyle:NSByteCountFormatterCountStyleFile]]];

	if(!busy)
		[localStatusField setStringValue:[self localStatusLine:installed]];
}

- (NSString *)localStatusLine:(BOOL)installed
{
	NSMutableString *line = [NSMutableString string];
	NekoModelStore *store = [NekoModelStore sharedStore];
	NekoLocalProvider *local = [[[NekoLocalProvider alloc] init] autorelease];
	NSString *chosen = [local chosenModelIdentifier];
	NSString *using = [local modelIdentifier];
	if([chosen length] > 0 && ![chosen isEqualToString:using]
	   && [store installedURLForIdentifier:using] != nil) {
		NekoLocalModel *fallback = [store modelWithIdentifier:using];
		[line appendFormat:NSLocalizedString(@"“%@” is selected but was never downloaded, so %@ is answering instead. ", @"“%@” is selected but was never downloaded, so %@ is answering instead. "),
			[[store modelWithIdentifier:chosen] name] ?: chosen,
			[fallback name] ?: using];
	}
	if([NekoLocalProvider makeEngine] == nil)
		[line appendString:NSLocalizedString(@"No engine is compiled into this build yet, so a downloaded model cannot answer. Everything around it is ready: the model can be fetched now and will be used the moment the engine lands.", @"No engine is compiled into this build yet, so a downloaded model cannot answer. Everything around it is ready: the model can be fetched now and will be used the moment the engine lands.")];
	else if(installed)
		[line appendString:NSLocalizedString(@"Ready. Choose “A model on this Mac” under Ask Neko.", @"Ready. Choose “A model on this Mac” under Ask Neko.")];
	else if([store isIncomplete:[[self selectedLocalModel] identifier]])
		[line appendString:NSLocalizedString(@"That download did not finish: the file is there but too small to be read. Downloading it again picks up where it stopped.", @"That download did not finish: the file is there but too small to be read. Downloading it again picks up where it stopped.")];
	else
		[line appendString:NSLocalizedString(@"Nothing downloaded yet.", @"Nothing downloaded yet.")];

	[line appendString:@"\n\n"];
	long long total = [[NekoModelStore sharedStore] totalInstalledBytes];
	if(total > 0)
		[line appendFormat:NSLocalizedString(@"%@ of models on disk. ", @"%@ of models on disk. "),
			[NSByteCountFormatter stringFromByteCount:total
			                               countStyle:NSByteCountFormatterCountStyleFile]];
	[line appendFormat:NSLocalizedString(@"They are kept in %@ and nothing else is installed: no daemon, no package manager, no other application.", @"They are kept in %@ and nothing else is installed: no daemon, no package manager, no other application."),
		[[[NekoModelStore sharedStore] modelsDirectory] path]];
	return line;
}

- (NSString *)askStatusLine
{
	NekoAsk *ask = [NekoAsk sharedAsk];
	if(![ask isEnabled])
		return NSLocalizedString(@"The microphone is asked for the first time you use this, never before.", @"The microphone is asked for the first time you use this, never before.");
	if([ask hotKeyUnavailable])
		return NSLocalizedString(@"Another application already owns that keystroke. Pick a different one.", @"Another application already owns that keystroke. Pick a different one.");

	NSString *hint = [[ask provider] configurationHint];
	if(hint != nil)
		return hint;

	NSMutableString *line = [NSMutableString stringWithFormat:
		NSLocalizedString(@"Press %@ and ask. Neko listens until you stop talking. Hold the same keys instead and a line to type in opens beside it.", @"Press %@ and ask. Neko listens until you stop talking. Hold the same keys instead and a line to type in opens beside it."),
		[ask hotKeyDisplayName]];
	if([[NSUserDefaults standardUserDefaults] boolForKey:NekoAskFollowUpKey])
		[line appendString:NSLocalizedString(@" After it speaks it keeps listening for a few seconds — the bubble says so while it does, and talking over it stops it mid-sentence.", @" After it speaks it keeps listening for a few seconds — the bubble says so while it does, and talking over it stops it mid-sentence.")];
	if([[NSUserDefaults standardUserDefaults] boolForKey:NekoWakeWordKey]) {
		NekoWakeWord *wake = [NekoWakeWord sharedWakeWord];
		[line appendString:@"\n\n"];
		if(![NekoWakeWord isAvailable])
			[line appendString:[NekoWakeWord unavailableReason] ?: @""];
		else if([wake isHearing])
			[line appendString:NSLocalizedString(@"Listening for its name right now.", @"Listening for its name right now.")];
		else if([wake isListening])
			[line appendString:NSLocalizedString(@"The microphone is open but the recogniser has not said anything yet.", @"The microphone is open but the recogniser has not said anything yet.")];
		else
			[line appendString:NSLocalizedString(@"Not listening: speech recognition has not been allowed. The Permissions tab can ask for it.", @"Not listening: speech recognition has not been allowed. The Permissions tab can ask for it.")];
	}
	if([[NSUserDefaults standardUserDefaults] boolForKey:NekoWakeWordKey]
	   && [NekoWakeWord isAvailable]) {
		[line appendString:@" "];
		[line appendString:NSLocalizedString(@"Saying its name works too — which means the microphone stays open, the orange recording light stays on, and the battery notices. The listening is done on this Mac and the audio goes nowhere; it hears one word and forgets the rest.", @"Saying its name works too — which means the microphone stays open, the orange recording light stays on, and the battery notices. The listening is done on this Mac and the audio goes nowhere; it hears one word and forgets the rest.")];
	}
	if([[NSUserDefaults standardUserDefaults] boolForKey:NekoWebEnabledKey]) {
		[line appendString:@"\n\n"];
		[line appendString:NSLocalizedString(@"Asked about today's news or the weather, it can fetch one of a fixed list of two dozen feeds: ANSA (the wire, world, technology, politics, culture, sport, and your own region), la Repubblica, Corriere della Sera, Il Fatto Quotidiano, Il Sole 24 Ore, RaiNews, Tgcom24, AGI, La Gazzetta dello Sport, Wired, DDay, Focus, MeteoAlarm's warnings for Italy, Hacker News, BBC News, The Guardian, The New York Times and NPR. Every one of them was fetched with this application's own name on the request before it went on the list. The plain forecast comes from open-meteo, because neither 3B Meteo nor meteo.it publishes a feed any more.", @"Asked about today's news or the weather, it can fetch one of a fixed list of two dozen feeds: ANSA (the wire, world, technology, politics, culture, sport, and your own region), la Repubblica, Corriere della Sera, Il Fatto Quotidiano, Il Sole 24 Ore, RaiNews, Tgcom24, AGI, La Gazzetta dello Sport, Wired, DDay, Focus, MeteoAlarm's warnings for Italy, Hacker News, BBC News, The Guardian, The New York Times and NPR. Every one of them was fetched with this application's own name on the request before it went on the list. The plain forecast comes from open-meteo, because neither 3B Meteo nor meteo.it publishes a feed any more.")];
		[line appendString:@"\n\n"];
		[line appendString:NSLocalizedString(@"Told where this Mac is — the Permissions tab asks macOS, and keeps the name of the town and of the region rather than any coordinates — it also knows which regional feed is the local one, and needs no city named to answer about the weather. It cannot name an address of its own — only one of those words — so nothing it reads can send it somewhere else. What comes back is quoted to it as somebody else's words, and an answer built on them is not allowed to open, copy or move anything: a headline is written by a stranger. The request carries no question, no account and no cookies; the site sees that a public feed was fetched. With Apple Intelligence or a model on this Mac the headlines stay here; with ChatGPT, Claude or a Shortcut they are sent on like any other question.", @"Told where this Mac is — the Permissions tab asks macOS, and keeps the name of the town and of the region rather than any coordinates — it also knows which regional feed is the local one, and needs no city named to answer about the weather. It cannot name an address of its own — only one of those words — so nothing it reads can send it somewhere else. What comes back is quoted to it as somebody else's words, and an answer built on them is not allowed to open, copy or move anything: a headline is written by a stranger. The request carries no question, no account and no cookies; the site sees that a public feed was fetched. With Apple Intelligence or a model on this Mac the headlines stay here; with ChatGPT, Claude or a Shortcut they are sent on like any other question.")];
	}

	if([[NSUserDefaults standardUserDefaults] boolForKey:NekoActionsEnabledKey]) {
		[line appendString:@"\n\n"];
		[line appendString:NSLocalizedString(@"It can open an application, an address in a browser, one of your folders in the Finder, run one of your own Shortcuts, and copy or move a single file between your folders. That list is all of it. It always shows what it is about to do and waits for a yes; dismissing the bubble is a no. It never overwrites, never deletes, and never acts on text it read from the screen — only on what you said out loud.", @"It can open an application, an address in a browser, one of your folders in the Finder, run one of your own Shortcuts, and copy or move a single file between your folders. That list is all of it. It always shows what it is about to do and waits for a yes; dismissing the bubble is a no. It never overwrites, never deletes, and never acts on text it read from the screen — only on what you said out loud.")];
		NekoFolderAccess *access = [NekoFolderAccess sharedAccess];
		NSArray *allowed = [access allowedKeys];
		[line appendString:@"\n\n"];
		if([allowed count] == 0) {
			[line appendString:NSLocalizedString(@"It has been shown no folders, so it cannot touch a file yet. Handing one over is a panel you fill in yourself; nothing else can grant it.", @"It has been shown no folders, so it cannot touch a file yet. Handing one over is a panel you fill in yourself; nothing else can grant it.")];
		} else {
			NSMutableArray *names = [NSMutableArray array];
			NSEnumerator *e = [allowed objectEnumerator];
			NSString *key;
			while((key = [e nextObject]) != nil)
				[names addObject:[access displayNameFor:key]];
			[line appendFormat:NSLocalizedString(@"Folders it has been shown: %@.", @"Folders it has been shown: %@."),
				[names componentsJoinedByString:@", "]];
		}
	}
	return line;
}

#pragma mark Ask Neko actions

- (void)takeAskEnabledFrom:(id)sender
{
	[[NSUserDefaults standardUserDefaults]
		setBool:([sender state] == NSControlStateValueOn) forKey:NekoAskEnabledKey];
	[[NekoAsk sharedAsk] applySettings];
	[self updateAskItem];
	[self syncAskControls];
}

- (void)takeAskHotKeyFrom:(id)sender
{
	NSArray *choice = [[self hotKeyChoices] objectAtIndex:[sender indexOfSelectedItem]];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setInteger:[[choice objectAtIndex:0] unsignedShortValue]
	              forKey:NekoAskHotKeyCodeKey];
	[defaults setInteger:(NSInteger)[[choice objectAtIndex:1] unsignedIntegerValue]
	              forKey:NekoAskHotKeyModifiersKey];
	[[NekoAsk sharedAsk] applySettings];
	[self updateAskItem];
	[self syncAskControls];
}

/* The order the popup is built in. */
- (NSArray *)askProviderKeys
{
	return [NSArray arrayWithObjects:@"apple", @"openai", @"model", @"local", @"shortcut", nil];
}

- (void)takeAskProviderFrom:(id)sender
{
	NSArray *keys = [self askProviderKeys];
	NSInteger index = [sender indexOfSelectedItem];
	[[NSUserDefaults standardUserDefaults]
		setObject:[keys objectAtIndex:(index >= 0 && index < (NSInteger)[keys count]) ? index : 0]
		   forKey:NekoAskProviderKey];
	[self syncAskControls];
}

/* Whichever key-holding provider is selected, or nil for the two that need no
   key. The field below writes to this one. */
- (id)askKeyedProvider
{
	NSString *choice = [[NSUserDefaults standardUserDefaults] stringForKey:NekoAskProviderKey];
	if([choice isEqualToString:@"model"])
		return [[NekoAsk sharedAsk] modelProvider];
	if([choice isEqualToString:@"openai"])
		return [[NekoAsk sharedAsk] openaiProvider];
	return nil;
}

- (void)takeAskShortcutNameFrom:(id)sender
{
	[[NSUserDefaults standardUserDefaults]
		setObject:[sender stringValue] forKey:NekoAskShortcutNameKey];
	[self syncAskControls];
}

- (void)takeAskKeyFrom:(id)sender
{
	NSString *typed = [sender stringValue];
	if([typed hasPrefix:@"•"])
		return;                  /* the placeholder, not a new key */
	/* Each provider keeps its own key, so switching between them loses neither. */
	[[self askKeyedProvider] setApiKey:typed];
	[self syncAskControls];
}

- (void)takeAskSpeakFrom:(id)sender
{
	[[NSUserDefaults standardUserDefaults]
		setBool:([sender state] == NSControlStateValueOn) forKey:NekoAskSpeakKey];
}

- (void)updateValueFields
{
	[speedField setStringValue:
		[NSString localizedStringWithFormat:NSLocalizedString(@"%.0f pt/s", @"%.0f pt/s"), [self speed] * 8.0f]];
	CGFloat radius = [self stopRadius];
	[radiusField setStringValue:(radius <= 0.0)
		? NSLocalizedString(@"touches", @"touches")
		: [NSString localizedStringWithFormat:NSLocalizedString(@"%.0f pt", @"%.0f pt"), radius]];
}

- (void)syncPreferencesControls
{
	[characterPopUp selectItemWithTitle:[[self character] name]];
	[speedSlider setFloatValue:[self speed]];
	[radiusSlider setFloatValue:[self stopRadius]];
	[sizePopUp selectItemAtIndex:([self scale] >= 2.0f) ? 1 : 0];
	[sleepCheck setState:[self idleSleep] ? NSControlStateValueOn : NSControlStateValueOff];
	[wanderCheck setState:[self wandersWhenIdle] ? NSControlStateValueOn : NSControlStateValueOff];
	[behaviourPopUp selectItemAtIndex:[self behaviourIndex]];
	[self updateWanderAvailability];
	[self syncSuggestControls];
	[self syncDrawControls];
	[self syncAskControls];
	/* The system owns this one, so it is read back rather than remembered. */
	[loginCheck setState:[self opensAtLogin] ? NSControlStateValueOn : NSControlStateValueOff];
	[self updateValueFields];
}

/* A plugin that arrives, leaves, or is switched can bring characters with it. */
- (void)pluginsChanged:(NSNotification *)note
{
	[NekoCharacter forgetTheList];
	[self buildCharacterMenu];
	[self settingsChanged];
}

- (void)showPlugins:(id)sender
{
	[[NekoPluginsPanel sharedPanel] show:sender];
}

- (void)showPreferences:(id)sender
{
	if(prefsPanel == nil)
		[self buildPreferencesPanel];
	else {
		[self syncPreferencesControls];
		[permissions rebuild];        /* all five can change outside the app */
	}
	[NSApp activateIgnoringOtherApps:YES];
	[prefsPanel makeKeyAndOrderFront:sender];
}

- (void)takeCharacterFrom:(id)sender
{
	NSArray *characters = [NekoCharacter availableCharacters];
	NSInteger index = [sender indexOfSelectedItem];
	if(index < 0 || index >= (NSInteger)[characters count])
		return;
	[[NSUserDefaults standardUserDefaults]
		setObject:[[characters objectAtIndex:index] identifier]
		   forKey:NekoCharacterKey];
	[self characterDidChange];
}

- (void)takeSpeedFrom:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setFloat:[sender floatValue] forKey:NekoSpeedKey];
	[self updateValueFields];
	[self settingsChanged];
}

- (void)takeStopRadiusFrom:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setFloat:[sender floatValue] forKey:NekoStopRadiusKey];
	[self updateValueFields];
	[self settingsChanged];
}

- (void)takeScaleFrom:(id)sender
{
	CGFloat scale = ([sender indexOfSelectedItem] == 1) ? 2.0f : 1.0f;
	[[NSUserDefaults standardUserDefaults] setDouble:scale forKey:NekoScaleKey];
	[self settingsChanged];
}

- (void)takeIdleSleepFrom:(id)sender
{
	[[NSUserDefaults standardUserDefaults]
		setBool:([sender state] == NSControlStateValueOn) forKey:NekoIdleSleepKey];
	[self settingsChanged];
}

- (void)restoreDefaults:(id)sender
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults removeObjectForKey:NekoCharacterKey];
	[defaults removeObjectForKey:NekoSpeedKey];
	[defaults removeObjectForKey:NekoScaleKey];
	[defaults removeObjectForKey:NekoStopRadiusKey];
	[defaults removeObjectForKey:NekoIdleSleepKey];
	[defaults removeObjectForKey:NekoWanderKey];
	[defaults removeObjectForKey:NekoBehaviourKey];
	[defaults removeObjectForKey:NekoSuggestKey];
	[defaults removeObjectForKey:NekoSuggestEveryKey];
	[defaults removeObjectForKey:NekoPausedKey];
	if(prefsPanel != nil)
		[self syncPreferencesControls];
	[self settingsChanged];
}

@end
