/* NekoPlayer */

#import <Cocoa/Cocoa.h>

/* The commands, and every one of them a verb somebody can say out loud. */
extern NSString * const NekoPlayerPlay;
extern NSString * const NekoPlayerPause;
extern NSString * const NekoPlayerPlayPause;
extern NSString * const NekoPlayerNext;
extern NSString * const NekoPlayerPrevious;
extern NSString * const NekoPlayerVolumeUp;
extern NSString * const NekoPlayerVolumeDown;
extern NSString * const NekoPlayerPlayNamed;   /* from your own library */

/*! Music and Spotify, spoken to directly.

   Both publish a scripting dictionary, and a sandboxed application may use it
   with com.apple.security.temporary-exception.apple-events naming the two bundle
   identifiers and nothing else. That was measured before it was designed: a
   throwaway bundle signed exactly like this one read Music's volume, set it and
   put it back, counted the library, and read Spotify's player state and current
   track. All of it from inside the sandbox.

   The alternative was a Shortcut per command, which is what 2.6 shipped and what
   somebody rightly complained about: "alza il volume" answering that a Shortcut
   they had never heard of was missing.

   What a plugin gets is a player and a command, both from closed lists. It never
   supplies a line of AppleScript — the scripts live here, in the app, where they
   can be read. A plugin that could hand over script text would be a plugin that
   runs code, which is the one thing this design has refused since it started. */
@interface NekoPlayer : NSObject

/* "music" and "spotify". Anything else is refused when the manifest is read. */
+ (NSArray *)players;
+ (NSArray *)commands;
+ (BOOL)knows:(NSString *)player;
+ (BOOL)knowsCommand:(NSString *)command;

/*! Whether that application is on this Mac at all. A verb for a player nobody has
   installed is not an error in the manifest; it is a sentence at the moment of
   doing. */
+ (BOOL)isInstalled:(NSString *)player;
+ (NSString *)displayNameFor:(NSString *)player;

/*! Does it, and says why not. The sentence is for the person, not the log: a
   refusal from macOS names the Automation setting, a missing application names
   the application, and a song that is not in the library says so. */
+ (BOOL)perform:(NSString *)command
             on:(NSString *)player
           with:(NSString *)argument
         saying:(NSString **)problem;

/*! What happened last time, which is the only thing that can be read without
   risking anything: see the comment in NekoPlayer.m. Reading this never brings a
   prompt up, never sends an Apple Event, and never blocks. */
typedef NS_ENUM(int, NekoPlayerConsent) {
	NekoPlayerConsentUnknown = 0,   /*!< never asked; asking is possible */
	NekoPlayerConsentGiven,
	NekoPlayerConsentRefused,       /*!< only System Settings can undo it */
	NekoPlayerConsentImpossible     /*!< that application is not on this Mac */
};

+ (NekoPlayerConsent)consentFor:(NSString *)player;

/*! Whether macOS has been asked yet, and asking. Reading the volume is the
   smallest question either application answers, so it is what the Permissions tab
   uses to bring the system's own prompt up at a moment somebody chose.

   askToControl: returns immediately and does the asking on another thread: the
   prompt is the system's and it takes as long as somebody takes to read it, which
   is not time the settings window may spend frozen. When it is answered, this
   notification says so and the tab redraws itself. */
+ (BOOL)mayControl:(NSString *)player;
+ (void)askToControl:(NSString *)player;

extern NSNotificationName const NekoPlayerConsentDidChangeNotification;

@end
