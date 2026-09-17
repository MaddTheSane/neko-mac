/* NekoAntics */

#import <Cocoa/Cocoa.h>

/*! The curious half of roaming.

   Wandering from place to place is what the cat does; this is what makes it
   look interested in you. Every so often it drops what it was doing, comes over
   to the pointer and asks what you are writing, or pounces on the cursor, or
   goes to claw the edge of the screen.

   What it goes on comes from NekoDesktop: counters the system hands out with no
   permission at all — keys and mouse moves since boot, seconds since the last
   one — plus, if that switch is on, the text being worked on.

   What it says comes from whichever engine Ask Neko is set to, asked while the
   cat is still walking over, with written-in lines as the fallback for when
   there is no engine or it does not answer in time. */
@interface NekoAntics : NSObject
{
	NSTimer *heartbeat;
	NSTimer *arrival;            /*!< watches for the cat reaching the pointer */
	NSDate *lastAntic;
	NSTimeInterval cooldown;     /*!< seconds until it is allowed to be curious */
	NSString *pendingLine;       /*!< what it will say once it arrives */
}

+ (NekoAntics *)sharedAntics;
@property (class, readonly, retain) NekoAntics *sharedAntics;

/*! Runs in the roaming behaviour and stops in the other two. Safe to call
   whenever the settings change. */
- (void)applySettings;

/*! One antic now, whatever the timers think — the preferences use it so the
   thing can be watched once instead of waited for. Returns what it decided to
   do, for the status line. */
- (NSString *)anticNow;

/*! Where to stand when it comes over to be nosy: beside whatever it is looking
   at rather than on top of it, and off the line it walked in on.

   People keep a distance from an agent that attends to them, and the closer and
   more head-on the attention, the more they compensate — measured with robots,
   and the same instinct applies to a cat that lands on the caret. So the spot is
   an arm's length away and to one side. Public because the geometry is worth
   testing without a screen.

   Typing fast is what sends it over in the first place, so it may well still be
   happening when it arrives: this is the number that decides whether it says
   anything or thinks better of it and leaves. */
- (NSPoint)spotBeside:(NSPoint)what from:(NSPoint)cat within:(NSRect)bounds;
- (BOOL)shouldWithdrawInstead;

@end
