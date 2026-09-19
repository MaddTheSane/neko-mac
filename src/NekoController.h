/* NekoController */

#import <Cocoa/Cocoa.h>
#import "NekoCharacter.h"
#import "NekoAsk.h"

@class MyPanel, NekoPermissionsTab;

/* NSUserDefaults keys */
extern NSString * const NekoCharacterKey;  /* identifier of the sprite set */
extern NSString * const NekoSpeedKey;      /* points the cat moves per tick */
extern NSString * const NekoScaleKey;      /* 1.0 or 2.0 */
extern NSString * const NekoStopRadiusKey; /* points to keep from the pointer */
extern NSString * const NekoIdleSleepKey;  /* BOOL, cat falls asleep when idle */
extern NSString * const NekoWanderKey;     /* BOOL, cat strolls off on its own */
extern NSString * const NekoBehaviourKey; /* "follow", "windows", "roam" or "flee" */
extern NSString * const NekoStayKey;      /* asked to stay where it is */
extern NSString * const NekoStayPointKey; /* and where that was */
extern NSString * const NekoSuggestKey;    /* BOOL, unasked suggestions while roaming */
extern NSString * const NekoSuggestEveryKey; /* minutes between suggestions */
extern NSString * const NekoPausedKey;     /* BOOL, cat hidden and frozen */

/*! Posted whenever a setting changes. */
extern NSNotificationName const NekoSettingsDidChangeNotification;

@interface NekoController : NSObject <NSMenuDelegate>
{
	__weak MyPanel *panel;         /* not retained, owned by the nib */
	NSStatusItem *statusItem;
	BOOL naggedAboutPermissions;   /* once a launch, and no more than once */
	NSMenuItem *newVersionItem;    /* only there when there is one */
	NSButton *updateCheck;
	NSMenuItem *pauseItem;
	NSMenuItem *stayItem;
	NSMenuItem *timerItem;
	NSMenuItem *glanceItem;
	__weak NekoPermissionsTab *permissions; /* NekoPermissionsTab, which owns that tab */
	NSMenuItem *askItem;
	NSTabView *prefsTabs;
	NSMenu *characterMenu;
	NSPanel *prefsPanel;
	NSTextField *speedField;
	NSSlider *speedSlider;
	NSTextField *radiusField;
	NSSlider *radiusSlider;
	NSPopUpButton *characterPopUp;
	NSPopUpButton *sizePopUp;
	NSButton *sleepCheck;
	NSButton *wanderCheck;
	NSPopUpButton *behaviourPopUp;
	NSButton *askCheck;
	NSPopUpButton *askHotKeyPopUp;
	NSPopUpButton *askProviderPopUp;
	NSTextField *askShortcutField;
	NSSecureTextField *askKeyField;
	NSButton *askSpeakCheck;
	NSButton *followUpCheck;
	NSButton *actionsCheck;
	NSButton *webCheck;
	NSButton *wakeCheck;
	NSButton *foldersButton;
	NSButton *forgetFoldersButton;
	NSTextField *askStatusField;
	NSPopUpButton *localModelPopUp;
	NSTextField *localDetailField;
	NSButton *localActionButton;
	NSProgressIndicator *localProgress;
	NSTextField *localStatusField;
	NSButton *localCleanButton;
	NSButton *loginCheck;
	NSView *permissionsContent;
	NSTextField *permissionsSummary;
	NSButton *suggestCheck;
	NSButton *lookButton;
	NSButton *drawCheck;
	NSButton *drawActionButton;
	NSProgressIndicator *drawProgress;
	NSPopUpButton *drawModelPopUp;
	NSPopUpButton *drawStepsPopUp;
	NSPopUpButton *drawSizePopUp;
	NSButton *drawNowButton;
	NSTextField *drawStatusField;
	NSPopUpButton *suggestEveryPopUp;
	NSTextField *suggestStatusField;
	NSTextField *memoryField;
	NSButton *suggestNowButton;
}

@property (class, readonly, retain) NekoController *sharedController;

@property (nonatomic, weak) MyPanel *panel;

@property (readonly, strong) NekoCharacter *character;
@property (nonatomic, readonly) CGFloat speed;
@property (nonatomic, readonly) CGFloat stopRadius;
@property (nonatomic, readonly) CGFloat scale;
@property (readonly) BOOL idleSleep;
@property (readonly) BOOL wandersWhenIdle;
@property (readonly) BOOL livesOnWindowEdges;

/*! The third behaviour: the cat goes where it likes and the pointer means
   nothing to it. Suggestions live here and nowhere else. */
@property (readonly) BOOL roamsOnItsOwn;

/*! The pointer as something to get away from rather than something to sit
   beside. */
@property (readonly) BOOL fleesThePointer;

/*! Orthogonal to all four: whatever it was doing, it does it here. Toggled from
   the menu, remembered across launches along with the spot. */
@property (readonly) BOOL staysWhereItIs;
- (void)toggleStay:(id)sender;

/*! `YES` only while roaming and switched on: the flag alone is not enough. */
@property (readonly) BOOL suggestsUnasked;

/*! Minutes between one suggestion and the next. */
@property (nonatomic, readonly) NSTimeInterval suggestionInterval;

- (BOOL)isPaused;
@property (readonly, getter=isPaused) BOOL paused;

/* Whether the system has been told to open Neko at login. Always NO before
   macOS 13, which has no SMAppService. */
- (BOOL)opensAtLogin;
- (BOOL)canOpenAtLogin;

- (void)showPreferences:(id)sender;

/* The preferences, opened on the Permissions tab — which is what happens by
   itself, once, a few seconds after login, when something is switched on that
   macOS is not allowing. */
- (void)showPermissions:(id)sender;

/* Asks GitHub what the newest release is, and says so either way. The quiet
   version of this runs once a day on its own — see NekoUpdate.h. */
- (void)checkNow:(id)sender;

/* The menu that asks which folder, shared with the Permissions tab: the folders
   row there is not one permission but six, and the menu belongs where the folders
   are chosen rather than where the row is drawn. */
- (void)showFolderPressed:(id)sender;
- (void)togglePause:(id)sender;
- (void)showAbout:(id)sender;
- (void)quit:(id)sender;

@end
