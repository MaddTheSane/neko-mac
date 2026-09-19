#import "NekoAntics.h"
#import "NekoAsk.h"
#import "NekoController.h"
#import "MyPanel.h"
#import "NekoDesktop.h"
#import "NekoSense.h"
#import "NekoBrains.h"
#import "NekoAnswerProvider.h"
#import "NekoCharacter.h"
#import "NekoNoise.h"

@interface NekoAntics ()
@property (copy) NSString *pendingLine;
@end

/* How often it considers being curious, and how long it waits between antics.
   Often enough to feel alive, rare enough not to be a colleague who taps you on
   the shoulder every minute. */
static const NSTimeInterval NekoAnticsHeartbeat = 5.0;
static const NSTimeInterval NekoAnticsMinWait = 90.0;
static const NSTimeInterval NekoAnticsWaitSpread = 150.0;

/* Nobody there. */
static const NSTimeInterval NekoAnticsAway = 150.0;

@implementation NekoAntics
@synthesize pendingLine;

+ (NekoAntics *)sharedAntics
{
	static NekoAntics *shared = nil;
	if(shared == nil)
		shared = [[NekoAntics alloc] init];
	return shared;
}

- (id)init
{
	self = [super init];
	if(self != nil) {
		cooldown = NekoAnticsMinWait;
		[[NSNotificationCenter defaultCenter]
			addObserver:self
			   selector:@selector(settingsChanged:)
			       name:NekoSettingsDidChangeNotification
			     object:nil];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[heartbeat invalidate];
	[arrival invalidate];
}

- (void)settingsChanged:(NSNotification *)note
{
	[self applySettings];
}

- (void)applySettings
{
	BOOL wanted = [[NekoController sharedController] roamsOnItsOwn];
	if(wanted == (heartbeat != nil))
		return;
	if(!wanted) {
		[heartbeat invalidate];
		heartbeat = nil;
		[arrival invalidate];
		arrival = nil;
		return;
	}
	heartbeat = [NSTimer scheduledTimerWithTimeInterval:NekoAnticsHeartbeat
	                                            target:self
	                                          selector:@selector(consider:)
	                                          userInfo:nil
	                                           repeats:YES];
}

#pragma mark What the machine will admit to

/* Everything the antics run on comes from NekoDesktop, which the suggestions
   read too. */
- (NSTimeInterval)idleSeconds
{
	return [[NekoDesktop sharedDesktop] idleSeconds];
}

#pragma mark Deciding

- (BOOL)mayBeCuriousNow
{
	NekoController *controller = [NekoController sharedController];
	MyPanel *panel = [controller panel];
	if(panel == nil || ![panel isRoaming] || [controller isPaused])
		return NO;
	if([panel isOnErrand] || [panel isHeld])
		return NO;
	if(![[NekoAsk sharedAsk] canSpeakUnprompted])
		return NO;
	if([self idleSeconds] > NekoAnticsAway)
		return NO;
	if([[NekoDesktop sharedDesktop] isBusyElsewhere])
		return NO;                 /* a film, a presentation, a password field */
	return lastAntic == nil || -[lastAntic timeIntervalSinceNow] > cooldown;
}

- (void)consider:(NSTimer *)timer
{
	[[NekoDesktop sharedDesktop] sample];
	if(![self mayBeCuriousNow])
		return;
	[self anticNow];
}

#pragma mark The antics themselves

- (NSString *)questionAboutTyping
{
	NSArray *lines = @[
		NSLocalizedString(@"What are you writing?", @"What are you writing?"),
		NSLocalizedString(@"Is it about me?", @"Is it about me?"),
		NSLocalizedString(@"That is a lot of words. Any of them mine?", @"That is a lot of words. Any of them mine?"),
		NSLocalizedString(@"May I watch you type?", @"May I watch you type?"),
		NSLocalizedString(@"Need a hand? I only have paws.", @"Need a hand? I only have paws.")];
	return [lines objectAtIndex:arc4random_uniform((unsigned)[lines count])];
}

- (NSString *)lineAboutThePointer
{
	NSArray *lines = @[
		NSLocalizedString(@"Got it. It was getting away.", @"Got it. It was getting away."),
		NSLocalizedString(@"This arrow keeps moving. Suspicious.", @"This arrow keeps moving. Suspicious."),
		NSLocalizedString(@"Caught your cursor. You may have it back.", @"Caught your cursor. You may have it back.")];
	return [lines objectAtIndex:arc4random_uniform((unsigned)[lines count])];
}

/* An arm's length for a cat: near enough to be nosy, far enough not to be on the
   caret. Varied through the pink-noise stream so it is not the same spot twice. */
static const CGFloat NekoAnticsNear = 60.0;
static const CGFloat NekoAnticsFar = 90.0;

/* And off the line it walked in on, by this much: 40 to 70 degrees puts it
   beside the thing rather than in front of it. */
static const CGFloat NekoAnticsSideMin = 40.0;
static const CGFloat NekoAnticsSideMax = 70.0;

- (NSPoint)spotBeside:(NSPoint)what from:(NSPoint)cat within:(NSRect)bounds
{
	NekoNoise *noise = [NekoNoise sharedNoise];
	CGFloat radius = NekoAnticsNear + [noise next] * (NekoAnticsFar - NekoAnticsNear);
	CGFloat side = NekoAnticsSideMin + [noise next] * (NekoAnticsSideMax - NekoAnticsSideMin);
	if([noise next] < 0.5f)
		side = -side;            /* either side of the approach */

	/* The direction it came from, turned by that much. */
	CGFloat dx = what.x - cat.x, dy = what.y - cat.y;
	CGFloat length = sqrt(dx * dx + dy * dy);
	if(length < 1.0f) {
		dx = 1.0f;
		dy = 0.0f;
		length = 1.0f;
	}
	CGFloat angle = atan2(dy, dx) + side * (CGFloat)M_PI / 180.0f;
	/* Measured back from the thing toward where the cat is coming from, so the
	   spot ends up beside it on the near side rather than beyond it. */
	NSPoint spot = NSMakePoint(what.x - cos(angle) * radius,
	                           what.y - sin(angle) * radius);

	/* On screen, and not so clamped that it lands on the thing anyway. */
	spot.x = MIN(MAX(spot.x, NSMinX(bounds) + 16.0), NSMaxX(bounds) - 16.0);
	spot.y = MIN(MAX(spot.y, NSMinY(bounds) + 16.0), NSMaxY(bounds) - 16.0);
	return spot;
}

/*! Where the cat should stand to be nosy: beside the pointer, which is where the
   caret usually is and, more to the point, where you are looking. */
- (NSPoint)pointerSpot
{
	MyPanel *panel = [[NekoController sharedController] panel];
	NSPoint pointer = [NSEvent mouseLocation];
	if(panel == nil)
		return pointer;
	NSRect frame = [panel frame];
	return [self spotBeside:pointer
	                   from:NSMakePoint(NSMidX(frame), NSMinY(frame))
	                 within:[panel nekoScreenBounds]];
}

/*! It came over because somebody was typing hard, and somebody typing hard when
   it arrives has not stopped for it. Then the polite thing is the thing a
   colleague does: notice, and not say it. */
- (BOOL)shouldWithdrawInstead
{
	return [[NekoDesktop sharedDesktop] keysPerMinute] > 40;
}

/*! The walk covers the latency: the cat sets off at once and the model is asked
   while it crosses the desk, so a question that takes a second to write arrives
   just as the cat sits down. If no engine is set up, or it fails, or it takes
   longer than the walk plus a moment, the written-in line is used instead — the
   antic still happens, which matters more than which words it ends with. */
- (void)askForLineInsteadOf:(NSString *)fallback
{
	/* Same rule as the suggestions: on this Mac, and good enough to be worth
	   hearing. When neither holds, the written-in line stays. */
	id<NekoAnswerProvider> provider = [NekoBrains bestOnDeviceProvider];
	if(provider == nil || ![provider isConfigured])
		return;

	NekoCharacter *character = [[NekoController sharedController] character];
	NSString *instructions = NekoCuriosityInstructionsFor([character persona]);
	NSString *context = [[NekoDesktop sharedDesktop] summary];
	NSDate *asked = [NSDate date];

	[provider askQuestion:context
	        instructions:instructions
	          completion:^(NSString *answer, NSError *error) {
		/* Only if this antic is still the one in progress: a slow answer that
		   arrives after the cat has wandered off is a line nobody asked for. */
		if(self->lastAntic == nil || [self->lastAntic compare:asked] == NSOrderedDescending)
			return;
		NSString *line = [self cleanUp:answer];
		/* A question that came out badly leaves the written-in one in place,
		   which is why pendingLine was set before asking. */
		if(![NekoSense isWorthSaying:line])
			return;
		self.pendingLine = line;
	}];
}

/*! Small models bold their one sentence or wrap it in quotation marks, which
   inside a speech bubble reads as somebody quoting somebody else. */
- (NSString *)cleanUp:(NSString *)answer
{
	NSString *line = [answer stringByReplacingOccurrencesOfString:@"**" withString:@""];
	line = [line stringByReplacingOccurrencesOfString:@"*" withString:@""];
	line = [line stringByReplacingOccurrencesOfString:@"#" withString:@""];
	NSRange stop = [line rangeOfString:@"\n"];
	if(stop.location != NSNotFound)
		line = [line substringToIndex:stop.location];
	return [line stringByTrimmingCharactersInSet:
		[NSCharacterSet characterSetWithCharactersInString:
			@" \t\n\r\"'\u201c\u201d\u00ab\u00bb"]];
}

- (void)beginAntic:(NSString *)line
        goingTo:(NSPoint)spot
             pose:(NekoState)pose
        forTicks:(unsigned)ticks
{
	/* The walk is not an interruption; the sentence is. Inside the quiet period
	   the cat still comes over, sits down and looks at you, and then goes away
	   again without saying anything — which is most of the charm and none of the
	   nagging. */
	if(![NekoAsk mayInterruptNow])
		line = nil;

	MyPanel *panel = [[NekoController sharedController] panel];
	lastAntic = [NSDate date];
	cooldown = NekoAnticsMinWait + (NSTimeInterval)arc4random_uniform(
		(unsigned)NekoAnticsWaitSpread);

	self.pendingLine = line;
	[panel errandTo:spot thenState:pose forTicks:ticks];
	if(line != nil)
		[self askForLineInsteadOf:line];

	/* The line waits for the cat: saying "what are you writing?" from the other
	   side of the screen is a different, worse joke. */
	[arrival invalidate];
	arrival = nil;
	if(pendingLine != nil)
		arrival = [NSTimer scheduledTimerWithTimeInterval:0.5
		                                          target:self
		                                        selector:@selector(sayItThere:)
		                                        userInfo:nil
		                                         repeats:YES];
}

- (void)sayItThere:(NSTimer *)timer
{
	MyPanel *panel = [[NekoController sharedController] panel];
	if(panel == nil || ![panel isRoaming]) {
		[arrival invalidate];
		arrival = nil;
		return;
	}
	if([panel isOnErrand])
		return;                          /* still on its way */

	[arrival invalidate];
	arrival = nil;

	if([pendingLine length] > 0 && [self shouldWithdrawInstead]) {
		/* It came over, saw the typing had not stopped, and went away without
		   saying anything. Nothing is spoken, so nothing counts against the
		   day's remarks either — this was a visit, not an interruption. */
		self.pendingLine = nil;
		[self withdrawFrom:[NSEvent mouseLocation]];
		return;
	}

	if([pendingLine length] > 0)
		[[NekoAsk sharedAsk] sayUnprompted:pendingLine];
	self.pendingLine = nil;
}

/* Which antic suits the moment. Typing hard is the interesting one — that is
   somebody at work, and a cat that came over to read it is the joke. */
/* Away from whatever it came to look at, far enough that it reads as leaving. */
- (void)withdrawFrom:(NSPoint)what
{
	MyPanel *panel = [[NekoController sharedController] panel];
	if(panel == nil)
		return;
	NSRect frame = [panel frame];
	NSPoint here = NSMakePoint(NSMidX(frame), NSMinY(frame));
	CGFloat dx = here.x - what.x, dy = here.y - what.y;
	CGFloat length = sqrt(dx * dx + dy * dy);
	if(length < 1.0f) {
		dx = -1.0f;
		dy = 0.0f;
		length = 1.0f;
	}
	NSRect bounds = [panel nekoScreenBounds];
	NSPoint away = NSMakePoint(here.x + dx / length * 140.0,
	                           here.y + dy / length * 140.0);
	away.x = MIN(MAX(away.x, NSMinX(bounds) + 16.0), NSMaxX(bounds) - 16.0);
	away.y = MIN(MAX(away.y, NSMinY(bounds) + 16.0), NSMaxY(bounds) - 16.0);
	[panel errandTo:away thenState:NekoStateStop forTicks:8];
}

- (NSString *)anticNow
{
	[[NekoDesktop sharedDesktop] sample];
	MyPanel *panel = [[NekoController sharedController] panel];
	if(panel == nil || ![panel isRoaming])
		return NSLocalizedString(@"Only while roaming.", @"Only while roaming.");

	NekoDesktop *desktop = [NekoDesktop sharedDesktop];
	NSTimeInterval idle = [desktop idleSeconds];

	if([desktop keysPerMinute] > 40) {
		/* Reading over your shoulder: it comes over, sits, and asks. */
		[self beginAntic:[self questionAboutTyping]
		         goingTo:[self pointerSpot]
		            pose:NekoStateKaki
		        forTicks:40];
		return NSLocalizedString(@"It came over to ask what you are writing.", @"It came over to ask what you are writing.");
	}
	if([desktop movesPerMinute] > 120) {
		/* The one antic that is supposed to land on the pointer: pouncing beside
		   the cursor is not pouncing. */
		[self beginAntic:(arc4random_uniform(2) == 0) ? [self lineAboutThePointer] : nil
		         goingTo:[NSEvent mouseLocation]
		            pose:NekoStateKaki
		        forTicks:16];
		return NSLocalizedString(@"It pounced on the cursor.", @"It pounced on the cursor.");
	}
	if(idle > 20.0) {
		/* Nobody typing, nobody clicking: it goes and claws the edge of the
		   screen, which the wall behaviour turns into scratching on arrival. */
		/* The panel's own accessor and not the window's screen: a window on no
		   display answers nil, nil answers an empty rectangle, and this then
		   works out the edge of the screen from a rectangle at the origin —
		   sending the cat to x = 0 from wherever it was standing. With a
		   portrait monitor above a laptop that is reachable, and it is what
		   "the cat goes mad along the borders" turned out to be. */
		NSRect bounds = [panel nekoScreenBounds];
		NSRect frame = [panel frame];
		BOOL left = NSMidX(frame) < NSMidX(bounds);
		[self beginAntic:nil
		         goingTo:NSMakePoint(left ? NSMinX(bounds) : NSMaxX(bounds),
		                             NSMinY(frame))
		            pose:NekoStateCount
		        forTicks:0];
		return NSLocalizedString(@"It went to claw the edge of the screen.", @"It went to claw the edge of the screen.");
	}

	/* Something is happening, just not much: a look in your direction. */
	[self beginAntic:nil
	         goingTo:[self pointerSpot]
	            pose:NekoStateJare
	        forTicks:24];
	return NSLocalizedString(@"It wandered over to see what you were up to.", @"It wandered over to see what you were up to.");
}

@end
