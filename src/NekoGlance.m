#import "NekoGlance.h"
#import "NekoWhen.h"
#import "NekoDesktop.h"
#import "NekoAsk.h"

NSString * const NekoGlanceDidChangeNotification = @"NekoGlanceDidChange";

/* Ten minutes when nobody said. Long enough to work through something, short
   enough that forgetting about it costs an afternoon rather than a month. */
static const NSTimeInterval NekoGlanceDefault = 600.0;

/* And the longest anybody may ask for. An hour is a stretch of work; a day is
   the switch this replaced, wearing a different hat. */
static const NSTimeInterval NekoGlanceLongest = 3600.0;

/* The words that ask for it. A duration on its own is not a request — "fra dieci
   minuti" is the timer's — so one of these has to be there as well. */
static BOOL NekoAsksForALook(NSString *question)
{
	NSString *text = [question lowercaseString];
	static NSArray *const triggers = @[
		/* Italian */
		@"guarda cosa", @"guarda quello che", @"guarda per", @"guardami",
		@"stammi a guardare", @"dai un'occhiata", @"dai unocchiata",
		/* English */
		@"look at what", @"watch what", @"watch me", @"look for the next",
		@"have a look at what",
		/* French */
		@"regarde ce que", @"regarde pendant", @"regarde-moi",
		/* Spanish */
		@"mira lo que", @"mira durante", @"mírame"];
	for(NSString *word in triggers) {
		if([text rangeOfString:word].location != NSNotFound) {
			return YES;
		}
	}
	return NO;
}

@implementation NekoGlance

+ (NekoGlance *)sharedGlance
{
	static NekoGlance *shared = nil;
	if(shared == nil)
		shared = [[NekoGlance alloc] init];
	return shared;
}

+ (NSTimeInterval)defaultStretch { return NekoGlanceDefault; }

+ (NSTimeInterval)wantedFor:(NSString *)question
{
	if(!NekoAsksForALook(question))
		return 0.0;
	NSTimeInterval said = [NekoWhen secondsIn:question];
	if(said <= 0.0)
		return NekoGlanceDefault;      /* "guarda cosa sto facendo" — a while */
	return said > NekoGlanceLongest ? NekoGlanceLongest : said;
}

#pragma mark Looking

- (NSString *)lookFor:(NSTimeInterval)seconds
{
	if(seconds <= 0.0)
		return @"";
	[self stop];

	/* Said before anything is read, because what somebody can check is the whole
	   of the consent here — and said differently when there is nothing to read
	   with, rather than promising a look that cannot happen. */
	if(![NekoDesktop accessibilityGranted])
		return NSLocalizedString(@"I would need the Accessibility permission to read anything. It is in System Settings, Privacy & Security, Accessibility.", @"I would need the Accessibility permission to read anything. It is in System Settings, Privacy & Security, Accessibility.");

	until = [NSDate dateWithTimeIntervalSinceNow:seconds];
	ticking = [NSTimer scheduledTimerWithTimeInterval:seconds
											   target:self
											 selector:@selector(timeUp:)
											 userInfo:nil
											  repeats:NO];
	[[NSRunLoop currentRunLoop] addTimer:ticking forMode:NSRunLoopCommonModes];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:NekoGlanceDidChangeNotification object:self];

	return [NSString stringWithFormat:
		NSLocalizedString(@"I will look for %@, and then stop.", @"I will look for %@, and then stop."),
		[NekoWhen describe:seconds]];
}

- (void)timeUp:(NSTimer *)which
{
	[self stop];
	/* Said once, unprompted, because a permission that expires quietly is a
	   permission somebody cannot reason about. */
	[[NekoAsk sharedAsk] sayUnprompted:NSLocalizedString(@"I have stopped looking.", @"I have stopped looking.")];
}

- (BOOL)isLooking
{
	return until != nil && [until timeIntervalSinceNow] > 0.0;
}

- (NSTimeInterval)secondsLeft
{
	if(![self isLooking])
		return 0.0;
	return [until timeIntervalSinceNow];
}

- (NSString *)menuTitle
{
	if(![self isLooking])
		return nil;
	NSTimeInterval left = [self secondsLeft];
	NSString *remaining = left < 60.0
		? [NekoWhen describe:(double)((int)left + 1)]
		: [NekoWhen describe:(double)(((int)left / 60) * 60)];
	return [NSString stringWithFormat:
		NSLocalizedString(@"Looking — %@ left", @"Looking — %@ left"), remaining];
}

- (void)stop
{
	[ticking invalidate];
	ticking = nil;
	until = nil;
	[[NSNotificationCenter defaultCenter]
		postNotificationName:NekoGlanceDidChangeNotification object:self];
}

@end
