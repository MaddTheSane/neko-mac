/* NekoDesktop */

#import <Cocoa/Cocoa.h>

/* There is no setting for reading the text any more. It was NekoReadTextKey, a
   switch that stayed on until somebody remembered it, and it is a stretch of time
   somebody asks for — see NekoGlance.h, and docs/one-look-roadmap.md for why the
   shape mattered more than the capability. The key is gone rather than left
   declared: a defaults key nothing reads is a thing the next person has to work
   out is dead. */

/*! How good a moment this is to say something.

   Interruptions cost about ten minutes of task switching plus another ten or
   fifteen before the original work resumes, and the cost depends on when they
   land: at a breakpoint in the activity it is measurably lower, and the coarser
   the breakpoint the cheaper it is (Iqbal & Bailey, CHI 2007/2008). These are
   the breakpoints that can be seen from application switches, typing rate and
   idleness alone — no screen reading, no permission. */
typedef NS_ENUM(int, NekoBreakpoint) {
	NekoBreakpointNone = 0,   /*!< mid-flow: say nothing */
	NekoBreakpointFine,       /*!< a few seconds of quiet after working */
	NekoBreakpointMedium,     /*!< a burst of typing just ended, or a short visit */
	NekoBreakpointCoarse      /*!< a long stretch ended, or a real break did */
};

/*! What the cat can tell about your day, in one place.

   Two tiers, deliberately separated. The first needs no permission at all and is
   what the suggestions and the antics have always run on: which application is
   in front, how long you have been in it, how often you have been switching, how
   fast you are typing and moving the mouse, how long since you last touched
   anything, the time. Counters and timestamps, never content.

   The second tier is content, and is off until you turn it on: the text in the
   field you are typing in, or under the pointer, read through the Accessibility
   API. Password fields are refused, secure keyboard entry silences it entirely,
   and what comes back is trimmed to a few hundred characters. With a remote
   engine chosen, that text is sent to that service — which is why it is a
   separate switch with its own paragraph rather than a detail of another one. */
@interface NekoDesktop : NSObject
{
	NSString *frontApp;
	NSDate *frontSince;
	NSMutableArray *switches;      /* {when, app} for each application change */
	NSString *lastHighlight;       /* so the same remark is not made twice running */

	uint32_t keysBefore, movesBefore;
	NSDate *sampledAt;
	uint32_t keysPerMinute, movesPerMinute;

	NSString *previousApp;         /* to notice a switch, and how long it lasted */
	NSDate *previousAppSince;
	NSTimeInterval previousIdle;
	uint32_t previousKeys;         /* keys a minute at the last sample */
	NekoBreakpoint breakpoint;
	NSDate *breakpointAt;
}

+ (NekoDesktop *)sharedDesktop;
@property (class, readonly, retain) NekoDesktop *sharedDesktop;

/*! Cheap: two counters and a couple of dates. Call it on whatever timer you
   already have. */
- (void)sample;

- (NSString *)frontApp;
- (NSTimeInterval)secondsInFront;
- (NSUInteger)switchesInTheLastQuarterHour;

/*! How many different programs, which is the honest measure of jumping about. */
- (NSUInteger)programsInTheLastQuarterHour;
@property (nonatomic, readonly) NSTimeInterval idleSeconds;
@property (readonly) uint32_t keysPerMinute;
@property (readonly) uint32_t movesPerMinute;

/*! Only when screen recording was already granted for some other reason; never
   asked for. */
- (NSString *)windowTitleIfAllowed;

/*! The switch and the permission together. */
@property (readonly) BOOL readsText;
@property (class, readonly) BOOL accessibilityGranted;

/*! Asks the system for the permission, which shows the standard alert and opens
   the pane. Returns whether it was already granted. */
+ (BOOL)requestAccessibility;

/*! The text being worked on, or nil: switch off, permission missing, secure
   input, a password field, or simply nothing there. */
- (NSString *)nearbyText;

/*! The best breakpoint seen in the last few seconds, and how long ago it was.
   A breakpoint is a moment, not a state: it is worth acting on briefly and then
   it is gone. */
- (NekoBreakpoint)breakpointNow;
- (NSTimeInterval)secondsSinceBreakpoint;
- (NSString *)describeBreakpoint;

/*! Times when nothing should be said at all, whatever the interval says, with the
   reason for the preferences to show. Focus and Do Not Disturb are deliberately
   absent: macOS keeps that state where no sandboxed app can read it, so this
   uses what can honestly be seen — a full-screen window, secure keyboard entry
   (which is what a password field turns on), somebody talking, and nobody being
   there at all. */
@property (readonly) BOOL isBusyElsewhere;
- (NSString *)whyBusyElsewhere;

/*! Is the microphone open in some application. Not *what* is being said and not
   *which* application: one flag from CoreAudio that needs no permission and
   carries no content, and the plainest sign there is that somebody is on a call
   and should not be spoken to.

   Measured before it went in: cold, then hot while a tap was open on the input,
   then cold again a second after it closed. */
- (BOOL)microphoneInUse;

/*! Nobody is there: the screen is locked, or the display has gone to sleep. Not
   the same thing as a bad moment — a bad moment passes in seconds, and this does
   not. What is waiting to be said should wait, rather than being said to an empty
   room and counted as said. */
- (BOOL)nobodyIsThere;
- (NSString *)whyNobodyIsThere;

/*! Whether the highlight is anything more than "an ordinary few minutes". The
   bar a remark has to clear along with the breakpoint. */
- (BOOL)somethingStandsOut;

/*! The single fact worth a remark right now — a long stretch in one program, a
   lot of jumping about, the small hours — in one English sentence. */
- (NSString *)highlight;

/*! Everything above as the plain text a model is given. */
- (NSString *)summary;

@end
