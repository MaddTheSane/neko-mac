#import "MyPanel.h"
#import "NekoController.h"
#import "NekoAsk.h"
#import "NekoAdvisor.h"
#import "NekoNoise.h"

@implementation MyPanel

/* The original chain held each idle pose for a fixed number of ticks — four,
   ten, four, six — which is a metronome however carefully the poses are drawn.
   The same averages now, scaled by a stream that drifts: some minutes the cat
   settles quickly, some it dawdles, and the two are not independent. */
static unsigned NekoIdleTicksFor(NekoState state)
{
	switch(state) {
		case NekoStateStop:  return 4;
		case NekoStateJare:  return 10;
		case NekoStateKaki:  return 4;
		case NekoStateAkubi: return 6;
		/* Scratching a wall was on ten ticks too, and has as little business
		   being on a fixed count as the rest of them. */
		case NekoStateUTogi:
		case NekoStateDTogi:
		case NekoStateLTogi:
		case NekoStateRTogi: return 10;
		default:             return 0;
	}
}

- (void)setStateTo:(NekoState)theState
{
	if(stateFrames != nil && nekoState == theState)
		return;
	//printf("state %d\n", theState);
	tickCount = 0;
	stateCount = 0;
	nekoState = theState;

	unsigned base = NekoIdleTicksFor(theState);
	if(base > 0) {
		double scaled = (double)base * [[NekoNoise sharedNoise] nextScale];
		idleDwell = (unsigned)(scaled + 0.5);
		if(idleDwell < 1)
			idleDwell = 1;       /* a pose nobody sees is not a pose */
	}
	stateFrames = [character framesForState:theState];
	stateTicksPerFrame = [character ticksPerFrameForState:theState];
	/* Handed over here and not left until the next tick: between the two, a
	   redraw would draw a frame of the pose this one replaced — and after a
	   character swap that frame belongs to an array nobody is holding any more.
	   tickCount is zero, so frame zero is what the next tick would pick anyway. */
	if([stateFrames count] > 0)
		[view setImageTo:(NSImage *)[stateFrames objectAtIndex:0]];
	[view setNeedsDisplay:YES];
}

- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)styleMask backing:(NSBackingStoreType)bufferingType defer:(BOOL)deferCreation
{
	self = [super initWithContentRect:contentRect styleMask:NSWindowStyleMaskBorderless backing:bufferingType defer:deferCreation];
	[self setBecomesKeyOnlyIfNeeded:YES];
	[self setLevel:NSStatusWindowLevel];
	/* Belonging to a Space is a property of the window, not of where it is on
	   screen, and a window that says nothing belongs to the one it was born in:
	   a three finger swipe left the cat stranded on the previous desktop. The
	   same four flags the Dock and the menu bar extras use — present everywhere,
	   not dragged along by the switching animation, out of the way of window
	   cycling, and allowed to share a full screen app's Space.

	   Two displays were never the same problem: screens are geometry, and the
	   cat crossing a display border stays in the Space it was already in. */
	[self setCollectionBehavior:(NSWindowCollectionBehaviorCanJoinAllSpaces
	                             | NSWindowCollectionBehaviorStationary
	                             | NSWindowCollectionBehaviorIgnoresCycle
	                             | NSWindowCollectionBehaviorFullScreenAuxiliary)];
	[self setOpaque:NO];
	[self setCanHide:NO];
	[self setIgnoresMouseEvents:YES];
	[self setMovableByWindowBackground:NO];
	[self setFrame:NSMakeRect(0.0f, 0.0f, 32.0f, 32.0f) display:NO];
	[self center];
	[self setBackgroundColor:[NSColor clearColor]];
	
	speed = 13.0f;
	scale = 1.0f;
	stopRadius = 48.0f;
	idleSleep = YES;
	
	[self startTimer];
	return self;
}

- (void)awakeFromNib
{
	NekoController *controller = [NekoController sharedController];
	[controller setPanel:self];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                        selector:@selector(settingsDidChange:)
	                                            name:NekoSettingsDidChangeNotification
	                                          object:nil];
	[self applySettings];
}

- (void)startTimer
{
	if(myTimer != nil)
		return;
	myTimer = [NSTimer scheduledTimerWithTimeInterval:0.125f target:self selector:@selector(handleTimer:) userInfo:nil repeats:YES];
}

- (void)stopTimer
{
	[myTimer invalidate];
	myTimer = nil;
}

- (void)settingsDidChange:(NSNotification*)notification
{
	[self applySettings];
}

/* Resizes the window around its own centre so swapping character or size does
   not make the cat drift across the screen. */
- (void)setSpriteSide:(CGFloat)side
{
	NSRect frame = [self frame];
	if(frame.size.width == side && frame.size.height == side)
		return;
	frame.origin.x += floor((frame.size.width - side) / 2.0f);
	frame.origin.y += floor((frame.size.height - side) / 2.0f);
	frame.size = NSMakeSize(side, side);
	[self setFrame:frame display:YES];
}

- (void)applySettings
{
	NekoController *controller = [NekoController sharedController];
	speed = [controller speed];
	scale = [controller scale];
	stopRadius = [controller stopRadius];
	idleSleep = [controller idleSleep];
	windowsMode = [controller livesOnWindowEdges];
	roamMode = [controller roamsOnItsOwn];
	fleeMode = [controller fleesThePointer];
	staying = [controller staysWhereItIs];
	if(!fleeMode)
		fleeing = NO;
	if(staying) {
		errandPhase = 0;
		errandTicks = 0;
		/* The spot it was asked to keep, taken up once: at the launch after the
		   one where somebody asked. Here rather than in the controller because
		   this is what knows how to keep a sprite on a screen, and the display
		   it was standing on may not be there any more. */
		if(!restoredStay) {
			restoredStay = YES;
			NSString *saved = [[NSUserDefaults standardUserDefaults]
				stringForKey:NekoStayPointKey];
			if([saved length] > 0)
				[self placeAt:NSPointFromString(saved)];
		}
	}
	else
		restoredStay = NO;
	wanderEnabled = [controller wandersWhenIdle];
	if((!wanderEnabled && !windowsMode && !roamMode) || fleeMode || staying)
		wandering = NO;
	if(!roamMode) {
		roamTicks = 0;
		errandPhase = 0;
	}
	shelvesAge = 0;
	
	NekoCharacter *newCharacter = [controller character];
	if(newCharacter != character) {
		character = newCharacter;
		stateFrames = nil;             /* forces setStateTo: to reload */
		[self setStateTo:NekoStateStop];
	}
	
	/* Sprites are square in every character shipped so far; the larger side
	   drives the window so a non-square one is letterboxed instead of cropped. */
	/* A missing character would otherwise size the window to nothing. */
	NSSize sprite = (character != nil) ? [character spriteSize] : NSMakeSize(32.0, 32.0);
	CGFloat side = MAX(MAX(sprite.width, sprite.height), 8.0) * scale;
	[self setSpriteSide:side];
	[view setFrame:[[self contentView] bounds]];
	[view setNeedsDisplay:YES];
	
	if([controller isPaused]) {
		[self stopTimer];
		[self orderOut:nil];
	} else {
		if(![self isVisible])
			[self orderFront:nil];
		[self startTimer];
	}
}

/* The eight walking states, which several decisions turn on. */
- (BOOL)isWalking
{
	return nekoState == NekoStateUMove || nekoState == NekoStateDMove
	    || nekoState == NekoStateLMove || nekoState == NekoStateRMove
	    || nekoState == NekoStateULMove || nekoState == NekoStateURMove
	    || nekoState == NekoStateDLMove || nekoState == NekoStateDRMove;
}

#pragma mark Being held

- (void)holdWithState:(NekoState)state
{
	held = YES;
	[self setStateTo:state];
	[self startTimer];           /* the frames keep moving even while it waits */
}

@synthesize state = nekoState;

- (void)releaseHold
{
	held = NO;
	restedTicks = 0;
}

@synthesize held;

/* Roaming, in ticks of an eighth of a second: a couple of seconds' pause
   between errands, and five minutes of that before the cat has earned a nap. */
static const unsigned NekoRoamMinRest = 8;       /* one second */
static const unsigned NekoRoamRestSpread = 24;   /* up to four */
static const unsigned NekoRoamBeforeNap = 2400;  /* five minutes */
static const unsigned NekoRoamNap = 240;         /* half a minute asleep */

/* How close the pointer may come before a fleeing cat moves off, and how far it
   has to be before the cat settles again — as multiples of the arm's length it
   already keeps in the other modes, so the two do not disagree when somebody
   changes that setting. At the default 48 points that is 168 and 192.

   Two different radii on purpose. With one, a cat sitting exactly on the
   boundary steps out, finds itself outside, steps back in, and does that for
   ever. The idea, and the reason for the gap, is ferlor-BSG's. */
static const CGFloat NekoFleeNear = 3.5f;
static const CGFloat NekoFleeFar  = 4.0f;

#pragma mark Wandering

/* Somewhere else on the desk, a few sprites away, pointing away from wherever
   the pointer is: a cat that has been left alone drifts off, it does not circle
   the cursor it just gave up on. */
- (void)startWanderingAwayFromPointer
{
	NSRect bounds = [self nekoBounds];
	NSRect frame = [self frame];
	NSPoint mouse = [NSEvent mouseLocation];

	double away = atan2(NSMinY(frame) - mouse.y, NSMidX(frame) - mouse.x);
	if(isnan(away))
		away = (double)arc4random_uniform(360) * M_PI / 180.0;
	/* within a third of a turn either side of straight away */
	away += ((double)arc4random_uniform(120) - 60.0) * M_PI / 180.0;
	CGFloat reach = 150.0 + (CGFloat)arc4random_uniform(200);

	wanderTarget = NSMakePoint(NSMidX(frame) + reach * cos(away),
	                           NSMinY(frame) + reach * sin(away));
	wanderTarget.x = MIN(MAX(wanderTarget.x, NSMinX(bounds) + frame.size.width),
	                     NSMaxX(bounds) - frame.size.width);
	wanderTarget.y = MIN(MAX(wanderTarget.y, NSMinY(bounds)),
	                     NSMaxY(bounds) - frame.size.height);
	wanderTarget = [self somewhereItCanStand:wanderTarget];
	wanderMouse = mouse;
	wandering = YES;
}

/* In the other behaviour the cat picks one of your window tops, or the desk,
   and goes to sit on it. The pointer has no say. */
- (void)startWanderingOntoShelf
{
	NSRect bounds = [self nekoBounds];
	NSRect frame = [self frame];
	NSMutableArray *surfaces = [NSMutableArray arrayWithArray:shelves];
	if([surfaces count] == 0)
		[surfaces addObject:[NSValue valueWithRect:NSMakeRect(
			NSMinX(bounds), NSMinY(bounds), bounds.size.width, 1.0f)]];  /* the desk */

	NSRect surface = [[surfaces objectAtIndex:arc4random_uniform([surfaces count])] rectValue];
	CGFloat room = surface.size.width - frame.size.width;
	CGFloat x = NSMinX(surface) + (room > 0.0f ? (CGFloat)arc4random_uniform((unsigned)room) : 0.0f);

	wanderTarget = [self somewhereItCanStand:
		NSMakePoint(x + frame.size.width / 2.0f, surface.origin.y)];
	wanderMouse = [NSEvent mouseLocation];
	wandering = YES;
}

/* Roaming: anywhere on the desk at all. The pointer is not a destination and
   not a repellent — this cat is going about its own business, and where you
   happen to be pointing is none of it. */
- (void)startWanderingAnywhere
{
	NSRect bounds = [self nekoBounds];
	NSRect frame = [self frame];
	CGFloat roomX = MAX(bounds.size.width - frame.size.width, 1.0);
	CGFloat roomY = MAX(bounds.size.height - frame.size.height, 1.0);
	NSPoint here = NSMakePoint(NSMidX(frame), NSMinY(frame));

	/* A worthwhile walk rather than a shuffle: somewhere at least a third of
	   the desk away, given a few tries to find one. Uniform points came out
	   next door often enough that the cat looked like it could not decide. */
	CGFloat wanted = MIN(bounds.size.width, bounds.size.height) / 3.0f;
	NSPoint spot = here;
	unsigned try;
	for(try = 0; try < 8; try++) {
		spot = NSMakePoint(NSMinX(bounds) + frame.size.width / 2.0f
		                   + (CGFloat)arc4random_uniform((unsigned)roomX),
		                   NSMinY(bounds) + (CGFloat)arc4random_uniform((unsigned)roomY));
		if(hypotf(spot.x - here.x, spot.y - here.y) >= wanted)
			break;
	}

	wanderTarget = [self somewhereItCanStand:spot];
	wanderMouse = [NSEvent mouseLocation];
	wandering = YES;
}

- (void)stopWandering
{
	wandering = NO;
}

/* Chasing the pointer: it drifts off only after having properly settled and
   slept, about half a minute of being left alone. Living on windows: it moves
   between them whenever it has sat still long enough. */
/* A bubble on screen pins the cat: whatever it was going to do, being read
   comes first. In-place animations carry on — it can sit, wash, yawn — but the
   walking states, the wandering and the errands all wait, and if the bubble
   comes back the cat stops again. */
- (BOOL)isSpeaking
{
	NekoAsk *ask = [NekoAsk sharedAsk];
	/* Three states, one rule: a bubble on screen, a question being handled —
	   listening, thinking, drawing — or a suggestion being written. All of them
	   are the cat's attention being elsewhere, and a cat whose attention is
	   elsewhere does not cross the desk. */
	return [ask isSpeaking] || [ask isBusy] || [[NekoAdvisor sharedAdvisor] isThinking];
}

- (BOOL)shouldWanderNow
{
	if(wandering || [self isSpeaking])
		return NO;
	if(staying || fleeMode)
		return NO;               /* it has somewhere to be, or nowhere to go */
	if(roamMode) {
		if(errandPhase != 0)
			return NO;                 /* it is already going somewhere */
		if(nekoState == NekoStateSleep)
			return restedTicks > NekoRoamNap;   /* nap over, back on its feet */
		if(roamTicks > NekoRoamBeforeNap)
			return NO;                 /* let the idle chain put it to sleep */
		return restedTicks > roamRest;
	}
	if(windowsMode)
		return restedTicks > 80;      /* ten seconds on a window top */
	return wanderEnabled && restedTicks > 240;   /* thirty seconds asleep */
}

- (void)beginWandering
{
	if(roamMode) {
		/* A different pause each time, so it does not tick round like a
		   metronome. */
		roamRest = NekoRoamMinRest + [[NekoNoise sharedNoise] nextBelow:NekoRoamRestSpread];
		if(nekoState == NekoStateSleep)
			roamTicks = 0;             /* the nap paid for the next five minutes */
		[self startWanderingAnywhere];
	}
	else if(windowsMode)
		[self startWanderingOntoShelf];
	else
		[self startWanderingAwayFromPointer];
	restedTicks = 0;
}

/* Sleeping is for cats that have earned it. A roamer that dozed off three
   seconds into its first pause — which is what the idle chain does — looked
   broken rather than sleepy. */
- (BOOL)mayFallAsleep
{
	if(!idleSleep)
		return NO;
	return !roamMode || roamTicks > NekoRoamBeforeNap;
}

#pragma mark Errands

/* Anything nearer than the stopping radius plus this is already close enough
   that turning would be fussing — and anything nearer than the radius itself
   cannot be walked to at all, since arriving is defined as being that close.
   That is the mistake this constant exists to record: the first version stepped
   44 points, the radius is 48, and the cat stood still while insisting it had
   set off. */
static const CGFloat NekoTurnSlack = 40.0f;
static const CGFloat NekoTurnStep = 30.0f;

- (unsigned)turnToward:(NSPoint)point
{
	if(!roamMode || staying || held)
		return 0;

	/* The same reference point the chasing code uses: the middle of the sprite
	   horizontally, its feet vertically. Measuring from anywhere else makes the
	   distances disagree by half a cat. */
	NSRect frame = [self frame];
	NSPoint here = NSMakePoint(NSMidX(frame), NSMinY(frame));
	CGFloat dx = point.x - here.x, dy = point.y - here.y;
	CGFloat distance = sqrt(dx * dx + dy * dy);
	if(distance < stopRadius + NekoTurnSlack)
		return 0;               /* it is already looking at the right corner */

	/* A step toward it, not a journey to it. It stops a radius short of
	   whatever it walks at, so the target has to be that much further out than
	   the distance actually travelled. */
	CGFloat reach = MIN(stopRadius + NekoTurnStep, distance - stopRadius / 2.0);
	if(reach <= stopRadius + 4.0f)
		return 0;
	NSPoint target = NSMakePoint(here.x + dx / distance * reach,
	                             here.y + dy / distance * reach);

	wanderTarget = target;
	wanderMouse = [NSEvent mouseLocation];
	wandering = YES;
	errandPhase = 1;
	errandState = NekoStateAwake;
	errandHold = 4;
	errandTicks = 0;
	restedTicks = 0;
	if(![self isWalking])
		[self setStateTo:NekoStateAwake];
	[self startTimer];

	/* Ticks for the part it actually walks — the target less the radius it stops
	   short by — plus the pose at the end, plus the few ticks the chain spends
	   sitting up before it sets off. */
	CGFloat travel = MAX(reach - stopRadius, 4.0f);
	unsigned walking = (unsigned)(travel / MAX(speed, 1.0f)) + 1;
	return walking + errandHold + 4;
}

- (void)errandTo:(NSPoint)point thenState:(NekoState)state forTicks:(unsigned)ticks
{
	if(!roamMode || staying || held || [self isSpeaking])
		return;
	wanderTarget = point;
	wanderMouse = [NSEvent mouseLocation];
	wandering = YES;
	errandPhase = 1;
	errandState = state;
	errandHold = ticks;
	errandTicks = 0;
	restedTicks = 0;
	if(![self isWalking])
		[self setStateTo:NekoStateAwake];
	[self startTimer];
}

- (BOOL)isOnErrand
{
	return errandPhase != 0;
}

@synthesize roaming = roamMode;

/* What the cat is walking towards: the pointer, or wherever it decided to go. */
/* Away from the pointer, while it is close enough to be worth minding.

   Straight away if there is room, and along the wall if there is not: a cat
   backed into a corner sidles out sideways rather than pressing into the corner
   until you move. Each direction is tried in turn and taken only if it is both
   inside the room and further from the pointer than standing still — so when
   nothing is, the cat stays put, which is what a cornered animal does. */
- (NSPoint)escapeTarget
{
	NSRect frame = [self frame];
	CGFloat side = frame.size.width;
	NSPoint here = NSMakePoint(NSMidX(frame), NSMinY(frame));
	NSPoint mouse = [NSEvent mouseLocation];
	CGFloat dx = here.x - mouse.x, dy = here.y - mouse.y;
	CGFloat distance = hypot(dx, dy);

	fleeing = fleeing ? (distance < stopRadius * NekoFleeFar)
	                  : (distance < stopRadius * NekoFleeNear);
	if(!fleeing)
		return here;

	/* Far enough to be out of range when it arrives, and never less than one
	   step, so a cat already at the edge of the ring still moves. It stops
	   stopRadius short of whatever it walks at, so the target carries that. */
	CGFloat wanted = stopRadius * NekoFleeFar - distance;
	CGFloat reach = stopRadius + MAX(wanted, speed);

	double away = atan2(dy, dx);
	if(distance < 1.0f || isnan(away))
		away = (double)arc4random_uniform(360) * M_PI / 180.0;

	NSRect bounds = [self nekoBounds];
	static const CGFloat turns[] = { 0.0, 45.0f, -45.0, 90.0, -90.0,
	                               135.0, -135.0, 180.0 };
	unsigned i;
	for(i = 0; i < sizeof(turns) / sizeof(turns[0]); i++) {
		double angle = away + (double)turns[i] * M_PI / 180.0;
		NSPoint target = NSMakePoint(here.x + cos(angle) * reach,
		                             here.y + sin(angle) * reach);
		if(target.x < NSMinX(bounds) + side / 2.0
		   || target.x > NSMaxX(bounds) - side / 2.0
		   || target.y < NSMinY(bounds)
		   || target.y > NSMaxY(bounds) - side)
			continue;
		if(hypotf(target.x - mouse.x, target.y - mouse.y) <= distance)
			continue;
		return target;
	}
	return here;                   /* cornered, and nowhere better to be */
}

- (NSPoint)chaseTarget
{
	/* Before the wander, not after it: asked to stay in the middle of a walk
	   across the desk, a roaming cat would otherwise finish the walk first. */
	if(staying)
		return NSMakePoint(NSMidX([self frame]), NSMinY([self frame]));
	if(wandering)
		return wanderTarget;
	if(windowsMode || roamMode)
		return NSMakePoint(NSMidX([self frame]), NSMinY([self frame]));  /* stay put */
	if(fleeMode)
		return [self escapeTarget];
	return [NSEvent mouseLocation];
}

#pragma mark Walls and window edges

/* Every screen together, so the cat can follow the pointer onto another
   display instead of treating its own screen border as a wall. */
- (NSRect)nekoBounds
{
	NSRect bounds = NSZeroRect;
	for(NSScreen *screen in [NSScreen screens])
		bounds = NSIsEmptyRect(bounds) ? [screen visibleFrame]
		                               : NSUnionRect(bounds, [screen visibleFrame]);
	return NSIsEmptyRect(bounds) ? [[NSScreen mainScreen] visibleFrame] : bounds;
}

/* A place the cat can actually stand, given one it was aiming at.

   Everything that picks somewhere to walk to picks it inside -nekoBounds, which
   is every screen unioned so that the cat can cross from one display to another.
   When two monitors do not tile a rectangle that union contains room no screen
   covers, and a share of every walk is aimed there: on the desk in
   tests/edges.m — a portrait display above a laptop — it is one walk in
   forty-five. The rescue already existed for a cat that had *arrived* somewhere
   impossible; this is the same rescue applied to the target, which is where it
   belongs. The target is a midpoint and the rescue works in origins, so it goes
   there and back. */
- (NSPoint)somewhereItCanStand:(NSPoint)target
{
	NSRect frame = [self frame];
	CGFloat side = MAX(frame.size.width, 1.0);
	/* Through floats of its own rather than the point's fields: NSPoint holds
	   CGFloat, which is a double here, and handing &origin.x to a float* writes
	   four bytes into eight. The compiler said so. */
	CGFloat x = (target.x - side / 2.0);
	CGFloat y = target.y;
	[self nudgeOntoAScreen:&x Y:&y side:side];
	return NSMakePoint((CGFloat)x + side / 2.0f, (CGFloat)y);
}

/* One screen rather than all of them, for the things that are about the display
   the cat is standing on: which way its own edge is, how far the wall is.

   Never NSZeroRect. -[NSWindow screen] is nil for a window on no display, and
   the union the cat roams in has room that no display covers whenever two
   monitors do not tile a rectangle — a portrait screen above a laptop leaves a
   strip beside it seventy points wide. Asking a nil screen for -visibleFrame
   gives a rectangle at the origin, and an antic that works out the edge of the
   screen from that sends the cat to x = 0 from wherever it was. tests/edges.m
   has the desk it was reported from. */
- (NSRect)nekoScreenBounds
{
	NSScreen *here = [self screen];
	if(here != nil)
		return [here visibleFrame];

	/* On no screen: the nearest one to the middle of the sprite, by the same
	   measure NekoOriginOnAScreen uses to rescue it. */
	NSRect frame = [self frame];
	NSPoint centre = NSMakePoint(NSMidX(frame), NSMidY(frame));
	NSRect nearest = NSZeroRect;
	CGFloat nearestDistance = 0.0;
	for(NSScreen *screen in [NSScreen screens]) {
		NSRect visible = [screen visibleFrame];
		CGFloat dx = 0.0, dy = 0.0;
		if(centre.x < NSMinX(visible))      dx = NSMinX(visible) - centre.x;
		else if(centre.x > NSMaxX(visible)) dx = centre.x - NSMaxX(visible);
		if(centre.y < NSMinY(visible))      dy = NSMinY(visible) - centre.y;
		else if(centre.y > NSMaxY(visible)) dy = centre.y - NSMaxY(visible);
		CGFloat distance = dx * dx + dy * dy;
		if(NSIsEmptyRect(nearest) || distance < nearestDistance) {
			nearest = visible;
			nearestDistance = distance;
		}
	}
	return NSIsEmptyRect(nearest) ? [[NSScreen mainScreen] visibleFrame] : nearest;
}

/* Where the Dock is, as a surface to stand on, or an empty rect when it is
   hidden. Its own Quartz window covers the whole screen and says nothing, so the
   room it reserves is read from the screen instead: visibleFrame stops where the
   Dock starts. Only a Dock along the bottom is handled; on the sides the cat
   falls back to windows. */
- (NSRect)dockSurface
{
	NSScreen *screen = [self screen] ? [self screen] : [NSScreen mainScreen];
	NSRect frame = [screen frame];
	NSRect visible = [screen visibleFrame];
	CGFloat reserved = NSMinY(visible) - NSMinY(frame);
	if(reserved < 20.0f)
		return NSZeroRect;           /* hidden, or on a side */

	/* The Dock sits in the middle of the edge, so the cat is kept over the part
	   that is actually there rather than the empty desk beside it. */
	CGFloat inset = frame.size.width * 0.15;
	return NSMakeRect(NSMinX(frame) + inset, NSMinY(visible),
	                  frame.size.width - 2.0 * inset, 1.0);
}

/* The surfaces the cat may stand on: the Dock when it is out, otherwise the top
   edge of any window that is not filling the screen, otherwise the desk itself.
   Refreshed every few ticks, since windows do not move eight times a second. */
- (void)refreshShelves
{
	if(shelves != nil && shelvesAge > 0) {
		shelvesAge--;
		return;
	}
	shelvesAge = 4;

	NSMutableArray *found = [NSMutableArray array];
	NSRect dock = [self dockSurface];
	if(!NSIsEmptyRect(dock)) {
		shelves = @[[NSValue valueWithRect:dock]];
		return;
	}

	NSArray *list = CFBridgingRelease(CGWindowListCopyWindowInfo(
		kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
		kCGNullWindowID));
	if(list == NULL)
		return;

	/* Quartz measures from the top of the main display downwards. */
	NSRect screenFrame = [[[NSScreen screens] objectAtIndex:0] frame];
	CGFloat flip = NSMaxY(screenFrame);
	double screenArea = screenFrame.size.width * screenFrame.size.height;
	int mine = [[NSProcessInfo processInfo] processIdentifier];
	for(NSDictionary *window in list) {
		if([[window objectForKey:(id)kCGWindowLayer] integerValue] != 0)
			continue;
		if([[window objectForKey:(id)kCGWindowOwnerPID] intValue] == mine)
			continue;
		NSNumber *alpha = [window objectForKey:(id)kCGWindowAlpha];
		if(alpha != nil && [alpha floatValue] < 0.5f)
			continue;
		CGRect bounds = CGRectZero;
		if(!CGRectMakeWithDictionaryRepresentation(
			(CFDictionaryRef)[window objectForKey:(id)kCGWindowBounds], &bounds))
			continue;
		if(bounds.size.width < 120.0f || bounds.size.height < 60.0f)
			continue;
		/* A window filling the screen leaves nowhere to be seen standing. */
		if(bounds.size.width * bounds.size.height > 0.85 * screenArea)
			continue;
		[found addObject:[NSValue valueWithRect:NSMakeRect(
			bounds.origin.x, flip - bounds.origin.y, bounds.size.width, 1.0f)]];
	}

	shelves = [found copy];
}

/* The highest surface the cat can stand on at this horizontal position, never
   above where its feet already are: it lands on things, it is not lifted. */
- (CGFloat)floorUnderCentre:(CGFloat)centre feet:(CGFloat)feet
{
	CGFloat floor = NSMinY([self nekoBounds]);
	if(!windowsMode)
		return floor;

	NSEnumerator *e = [shelves objectEnumerator];
	NSValue *value;
	for(NSValue *value in e) {
		NSRect shelf = [value rectValue];
		if(centre < NSMinX(shelf) || centre > NSMaxX(shelf))
			continue;
		CGFloat top = shelf.origin.y;
		if(top > feet + 1.0f || top <= floor)
			continue;
		floor = top;
	}
	return floor;
}

/* The bounding box of every screen is the room the cat walks in, and with two
   displays of the same size and the same top edge that box is exactly the two
   screens. With displays of different heights, or an L, it is not: the box
   contains rectangles where there is no screen at all, and a cat that walks into
   one sits in a place nobody can see.

   So a sprite that has come to rest entirely off every screen is put back onto
   the nearest one. Only entirely: a cat halfway across the seam between two
   displays is doing the right thing and is left alone. */
NSPoint NekoOriginOnAScreen(NSPoint origin, CGFloat side, NSArray<NSValue*> *visibleFrames)
{
	NSRect sprite = NSMakeRect(origin.x, origin.y, side, side);
	NSPoint centre = NSMakePoint(NSMidX(sprite), NSMidY(sprite));
	NSRect nearest = NSZeroRect;
	CGFloat nearestDistance = 0.0f;

	NSEnumerator *e = [visibleFrames objectEnumerator];
	NSValue *value;
	for(NSValue *value in visibleFrames) {
		NSRect visible = [value rectValue];
		if(NSIntersectsRect(sprite, visible))
			return origin;             /* on a screen, or across two of them */

		CGFloat dx = 0.0f, dy = 0.0f;
		if(centre.x < NSMinX(visible))      dx = NSMinX(visible) - centre.x;
		else if(centre.x > NSMaxX(visible)) dx = centre.x - NSMaxX(visible);
		if(centre.y < NSMinY(visible))      dy = NSMinY(visible) - centre.y;
		else if(centre.y > NSMaxY(visible)) dy = centre.y - NSMaxY(visible);
		CGFloat distance = dx * dx + dy * dy;

		if(NSIsEmptyRect(nearest) || distance < nearestDistance) {
			nearest = visible;
			nearestDistance = distance;
		}
	}
	if(NSIsEmptyRect(nearest))
		return origin;

	return NSMakePoint(MIN(MAX(origin.x, NSMinX(nearest)), NSMaxX(nearest) - side),
	                   MIN(MAX(origin.y, NSMinY(nearest)), NSMaxY(nearest) - side));
}

- (void)nudgeOntoAScreen:(CGFloat *)x Y:(CGFloat *)y side:(CGFloat)side
{
	NSMutableArray *frames = [NSMutableArray array];
	for (NSScreen *screen in [NSScreen screens])
		[frames addObject:[NSValue valueWithRect:[screen visibleFrame]]];

	NSPoint put = NekoOriginOnAScreen(NSMakePoint(*x, *y), side, frames);
	*x = put.x;
	*y = put.y;
}

/* A spot somebody asked it to keep, from a launch that may have had a different
   set of displays: clamped to the room and then onto a screen that is actually
   there, rather than trusted as written. */
- (void)placeAt:(NSPoint)origin
{
	CGFloat side = [self frame].size.width;
	CGFloat x = origin.x, y = origin.y;
	[self settleX:&x Y:&y from:y];
	[self setFrameOrigin:NSMakePoint(x, y)];
}

/* Keeps the whole sprite on a screen, and standing on whatever is under it. */
- (void)settleX:(CGFloat *)x Y:(CGFloat *)y from:(CGFloat)previousY
{
	NSRect bounds = [self nekoBounds];
	CGFloat side = [self frame].size.width;
	*x = MIN(MAX(*x, NSMinX(bounds)), NSMaxX(bounds) - side);
	*y = MIN(MAX(*y, NSMinY(bounds)), NSMaxY(bounds) - side);
	[self nudgeOntoAScreen:x Y:y side:side];
	*y = MAX(*y, [self floorUnderCentre:*x + side / 2.0f feet:previousY]);
}

/* The scratching state for whatever the cat is pressed against while still
   trying to get past it, or NekoStateCount when it is not blocked. */
- (NekoState)blockedWallState
{
	NSRect bounds = [self nekoBounds];
	NSRect frame = [self frame];
	CGFloat edge = 1.0f;

	if(moveDx < 0.0f && NSMinX(frame) <= NSMinX(bounds) + edge)
		return NekoStateLTogi;
	if(moveDx > 0.0f && NSMaxX(frame) >= NSMaxX(bounds) - edge)
		return NekoStateRTogi;
	if(moveDy > 0.0f && NSMaxY(frame) >= NSMaxY(bounds) - edge)
		return NekoStateUTogi;
	if(moveDy < 0.0f) {
		CGFloat floor = [self floorUnderCentre:NSMidX(frame) feet:NSMinY(frame)];
		if(NSMinY(frame) <= floor + edge)
			return NekoStateDTogi;   /* the desk, or the window it is standing on */
	}
	return NekoStateCount;
}

- (void)calcDxDyForX:(CGFloat)x Y:(CGFloat)y
{
	CGFloat		MouseX, MouseY;
	CGFloat		DeltaX, DeltaY;
	CGFloat		Length;
	
	NSPoint p = [self chaseTarget];
	MouseX = p.x;
	MouseY = p.y;
	
	DeltaX = floor(MouseX - x - [self frame].size.width / 2.0f);
	DeltaY = floor(MouseY - y);
	
	Length = hypotf(DeltaX, DeltaY);
	
	/* The cat keeps stopRadius points between itself and the pointer. Capping
	   the step by whatever distance is left over that ring makes it settle on
	   the ring instead of stepping across it and jittering back. */
	/* The deltas are whole points, so the distance left over the ring can sit
	   just above zero for ever and the cat would creep towards the pointer a
	   fraction of a point per tick, walking animation and all. Anything under
	   a point counts as arrived. */
	CGFloat travel = Length - stopRadius;
	if (travel <= 1.0f) {
		moveDx = moveDy = 0.0f;
	} else {
		CGFloat step = (travel < speed) ? travel : speed;
		moveDx = (step * DeltaX) / Length;
		moveDy = (step * DeltaY) / Length;
	}
}

- (BOOL)isNekoMoveStart
{
	CGFloat threshold = speed / 2.0f;
	return moveDx > threshold || moveDx < -threshold || moveDy > threshold || moveDy < -threshold;
}

- (void)advanceClock
{
	if (++tickCount >= 255) {
		tickCount = 0;
    }
	
    if (tickCount % 2 == 0) {
		if (stateCount < 255) {
			stateCount++;
		}
    }
}

- (void)NekoDirection
{
    NekoState	NewState;
    double		LargeX, LargeY;
    double		Length;
    double		SinTheta;
	
    if (moveDx == 0.0f && moveDy == 0.0f) {
		NewState = NekoStateStop;
    } else {
		LargeX = (double)moveDx;
		LargeY = (double)moveDy;
		Length = sqrt(LargeX * LargeX + LargeY * LargeY);
		SinTheta = LargeY / Length;
		//printf("SinTheta = %f\n", SinTheta);
		
		if (moveDx > 0) {
			if (SinTheta > 0.9239) {
				NewState = NekoStateUMove;
			} else if (SinTheta > 0.3827) {
				NewState = NekoStateURMove;
			} else if (SinTheta > -0.3827) {
				NewState = NekoStateRMove;
			} else if (SinTheta > -0.9239) {
				NewState = NekoStateDRMove;
			} else {
				NewState = NekoStateDMove;
			}
		} else {
			if (SinTheta > 0.9239) {
				NewState = NekoStateUMove;
			} else if (SinTheta > 0.3827) {
				NewState = NekoStateULMove;
			} else if (SinTheta > -0.3827) {
				NewState = NekoStateLMove;
			} else if (SinTheta > -0.9239) {
				NewState = NekoStateDLMove;
			} else {
				NewState = NekoStateDMove;
			}
		}
    }
	
    [self setStateTo:NewState];
}

- (void)handleTimer:(NSTimer*)timer
{
	CGFloat x = [self frame].origin.x;
	CGFloat y = [self frame].origin.y;
	CGFloat previousY = y;
	
	if(stateFrames == nil)
		return;                        /* not wired up to a character yet */
	
	if(windowsMode)
		[self refreshShelves];
	
	if([self isWalking])
		restedTicks = 0;
	else if(restedTicks < 60000)
		restedTicks++;

	if(roamMode && roamTicks < 60000)
		roamTicks++;

	/* An errand has two halves — getting there and doing the thing — and a
	   clock on each, so a target that turns out to be unreachable cannot leave
	   the cat walking into a wall for ever. */
	if(errandPhase == 2) {
		if(++errandTicks > errandHold) {
			errandPhase = 0;
			[self releaseHold];
		}
	} else if(errandPhase == 1) {
		errandTicks++;
		if(!wandering || errandTicks > 480) {
			BOOL arrived = !wandering;
			errandPhase = 0;
			errandTicks = 0;
			[self stopWandering];
			if(arrived && errandState != NekoStateCount && errandHold > 0) {
				errandPhase = 2;
				[self holdWithState:errandState];
			}
		}
	}
	
	/* Whatever it had in mind, you moving the pointer wins — except when it is
	   roaming, where the pointer was never the point. */
	if(wandering && !roamMode) {
		NSPoint mouse = [NSEvent mouseLocation];
		if(hypot(mouse.x - wanderMouse.x, mouse.y - wanderMouse.y) > 24.0f)
			[self stopWandering];
	}
	
	[self calcDxDyForX:x Y:y];
	BOOL isNekoMoveStart = [self isNekoMoveStart];
	NekoState wall = [self blockedWallState];
	
	NSInteger frame = (tickCount / stateTicksPerFrame) % [stateFrames count];
	[view setImageTo:(NSImage*)[stateFrames objectAtIndex:frame]];
	
	[self advanceClock];
	
	if(held)
		goto breakout;           /* being asked a question outranks the pointer */

	if([self isSpeaking]) {
		/* Anything that moves it across the desk is dropped; the idle chain is
		   left alone so it still blinks and washes while you read. */
		[self stopWandering];
		errandPhase = 0;
		moveDx = moveDy = 0.0;
		if([self isWalking])
			[self setStateTo:NekoStateStop];
		if(nekoState == NekoStateAwake)
			[self setStateTo:NekoStateStop];
		goto breakout;
	}
	
    if(nekoState == NekoStateStop) {
		if (wall != NekoStateCount && isNekoMoveStart) {
			[self setStateTo:wall];    /* pressed against something, claw at it */
			goto breakout;
		}
		if (isNekoMoveStart) {
			[self setStateTo:NekoStateAwake];
			goto breakout;
		}
		if ([self shouldWanderNow]) {
			[self beginWandering];
			[self setStateTo:NekoStateAwake];
			goto breakout;
		}
		if (stateCount < idleDwell) {
			goto breakout;
		}
		[self setStateTo:NekoStateJare];
	} else if(nekoState == NekoStateJare) {
		if (isNekoMoveStart) {
			[self setStateTo:NekoStateAwake];
			goto breakout;
		}
		if ([self shouldWanderNow]) {
			[self beginWandering];
			[self setStateTo:NekoStateAwake];
			goto breakout;
		}
		if (stateCount < idleDwell) {
			goto breakout;
		}
		[self setStateTo:NekoStateKaki];
	} else if(nekoState == NekoStateKaki) {
		if (isNekoMoveStart) {
			[self setStateTo:NekoStateAwake];
			goto breakout;
		}
		if (stateCount < idleDwell) {
			goto breakout;
		}
		/* Twice in a row now and then: scratching comes in bursts, the way
		   blinking does, and one scratch every time is the tell. */
		if(scratchAgain == 0 && [[NekoNoise sharedNoise] next] > 0.82) {
			scratchAgain = 1;
			stateCount = 0;
			idleDwell = NekoIdleTicksFor(NekoStateKaki);
			goto breakout;
		}
		scratchAgain = 0;
		[self setStateTo:NekoStateAkubi];
	} else if(nekoState == NekoStateAkubi) {
		if (isNekoMoveStart) {
			[self setStateTo:NekoStateAwake];
			goto breakout;
		}
		if (stateCount < idleDwell) {
			goto breakout;
		}
		[self setStateTo:([self mayFallAsleep] ? NekoStateSleep : NekoStateStop)];
	} else if(nekoState == NekoStateSleep) {
		if (isNekoMoveStart) {
			[self setStateTo:NekoStateAwake];
			goto breakout;
		}
		if ([self shouldWanderNow]) {
			[self beginWandering];
			[self setStateTo:NekoStateAwake];
		}
	} else if(nekoState == NekoStateAwake) {
		if (stateCount < 3) {
			goto breakout;
		}
		[self NekoDirection];	/* work out which way the cat moves */
	} else if(nekoState == NekoStateUMove || nekoState == NekoStateDMove || nekoState == NekoStateLMove || nekoState == NekoStateRMove || nekoState == NekoStateULMove || nekoState == NekoStateURMove || nekoState == NekoStateDLMove || nekoState == NekoStateDRMove) {
		x += moveDx;
		y += moveDy;
		[self settleX:&x Y:&y from:previousY];
		if (wall != NekoStateCount) {
			/* It cannot get any closer, so it scratches instead of walking on
			   the spot for ever. */
			[self setStateTo:wall];
		} else {
			[self NekoDirection];
			if (wandering && nekoState == NekoStateStop)
				[self stopWandering];   /* arrived where it wanted to go */
		}
	} else if(nekoState == NekoStateUTogi || nekoState == NekoStateDTogi || nekoState == NekoStateLTogi || nekoState == NekoStateRTogi) {
		if (wall == NekoStateCount && isNekoMoveStart) {
			[self setStateTo:NekoStateAwake];
			goto breakout;
		}
		if (stateCount < idleDwell) {
			goto breakout;
		}
		[self setStateTo:NekoStateKaki];
	} else {
		/* Internal Error */
		[self setStateTo:NekoStateStop];
	}

	breakout:
	/* Only the window dweller is pulled downwards: a cat chasing the pointer
	   rests wherever it stopped, and dragging it to the floor there sent it
	   into a loop of arriving, falling and setting off again. */
	if (windowsMode && !held && ![self isWalking]) {
		CGFloat floor = [self floorUnderCentre:x + [self frame].size.width / 2.0
		                                  feet:previousY];
		if (y > floor)
			y = MAX(floor, y - speed);
	}
	[view displayIfNeeded];
	[self setFrameOrigin:NSMakePoint(x, y)];
}

@end
