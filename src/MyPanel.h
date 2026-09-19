/* MyPanel */

#import <Cocoa/Cocoa.h>
#import "MyView.h"
#import "NekoCharacter.h"

@interface MyPanel : NSPanel
{
	IBOutlet MyView *view;
	
	NekoCharacter *character;
	NekoState nekoState;
	NSArray<NSImage*> *stateFrames;         /*!< frames of nekoState, never empty */
	unsigned stateTicksPerFrame;
	
	unsigned char tickCount, stateCount;
	CGFloat moveDx, moveDy;
	NSTimer *myTimer;
	
	CGFloat speed, scale, stopRadius;
	BOOL idleSleep;
	BOOL held;                   /*!< frozen mid-conversation */
	BOOL windowsMode;            /*!< lives on window tops instead of chasing */
	BOOL roamMode;               /*!< goes where it likes, the pointer means nothing */
	BOOL fleeMode;               /*!< the pointer is something to get away from */
	BOOL fleeing;                /*!< and it is doing that right now */
	BOOL staying;                /*!< asked to stay where it is, whatever the mode */
	BOOL restoredStay;           /*!< and the remembered spot has been taken up */
	
	BOOL wanderEnabled;
	BOOL wandering;
	NSPoint wanderTarget;        /*!< where it decided to go on its own */
	NSPoint wanderMouse;         /*!< the pointer when it set off, to notice you moving */
	unsigned restedTicks;        /*!< how long it has been settled and asleep */
	unsigned roamTicks;          /*!< how long this roaming stretch has lasted */
	unsigned roamRest;           /*!< ticks to sit still before the next errand */
	unsigned idleDwell;          /*!< how long this idle pose lasts, this time */
	unsigned scratchAgain;       /*!< a second scratch, now and then */

	int errandPhase;             /*!< 0 none, 1 on its way, 2 doing the thing */
	NekoState errandState;       /*!< what it does when it arrives */
	unsigned errandHold;         /*!< how long it does it for */
	unsigned errandTicks;
	
	NSArray<NSValue*> *shelves;  /*!< top edges of other apps' windows */
	unsigned shelvesAge;
	
}

/* Reads the current preferences and applies them to the cat. */
- (void)applySettings;

/* Stops chasing and shows one pose, for as long as something more important
   than the pointer is going on. The frames still animate. */
/* Somewhere to go, on somebody else's behalf, and something to do when it gets
   there — the curious antics are built out of this. Pass NekoStateCount to
   arrive and carry on as normal. Roaming only: the other two behaviours have
   their own ideas about where the cat belongs. */
- (void)errandTo:(NSPoint)point thenState:(NekoState)state forTicks:(unsigned)ticks;

/* Turns toward something and takes a step or two, ending sitting up alert.

   Orientation is the cheapest attention signal a character has, and in this
   sprite set it can only be said by moving: the eight directional poses are a
   gallop, and one frozen mid-stride reads as a cat stuck rather than a cat
   looking. So attention is a step, not a stare.

   Returns how many ticks it will take, or 0 when it is close enough already and
   nothing needs to happen. Unlike an errand this ignores whether the cat is
   busy speaking: whoever calls it is the reason it is about to speak. */
- (unsigned)turnToward:(NSPoint)point;
@property (readonly, getter=isOnErrand) BOOL onErrand;

/*! Put down at a remembered spot, kept on a screen that still exists. */
- (void)placeAt:(NSPoint)origin;

/*! Where a sprite of this size belongs when the screens are these. Pure, and
   separate from NSScreen, because the case worth testing is the one this Mac
   does not have: two displays of different heights, and the empty rectangle the
   bounding box invents between them. */
NSPoint NekoOriginOnAScreen(NSPoint origin, CGFloat side, NSArray<NSValue*> *visibleFrames);

/*! The screen the cat is on, or the nearest real one when it is on none.

   `-[NSWindow screen]` answers **nil** for a window that overlaps no display, and
   with two monitors that do not tile a rectangle that happens: the union the cat
   walks in contains room no screen covers. nil then answers `NSZeroRect` to
   `-visibleFrame`, and anything working out an edge from that computes it at the
   origin. Never empty, so nobody has to remember to check. */
- (NSRect)nekoScreenBounds;
@property (readonly, getter=isRoaming) BOOL roaming;

- (void)holdWithState:(NekoState)state;

/* Which pose it is in. Read by the tests, and by anything that needs to know
   whether the cat has visibly reacted yet. */
@property (readonly) NekoState state;
- (void)releaseHold;
@property (readonly, getter=isHeld) BOOL held;

@end
