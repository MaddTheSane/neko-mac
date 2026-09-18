#import "NekoRate.h"
#import "NekoAsk.h"
#import "NekoController.h"

NSString * const NekoRateTargetKey    = @"NekoRateTarget";
NSString * const NekoRateDayKey       = @"NekoRateDay";
NSString * const NekoRateSaidKey      = @"NekoRateSaid";
NSString * const NekoRateAnsweredKey  = @"NekoRateAnswered";
NSString * const NekoRateIgnoredKey   = @"NekoRateIgnored";
NSString * const NekoRateDismissedKey = @"NekoRateDismissed";
NSString * const NekoRateActiveKey    = @"NekoRateActive";

/* The band a colleague occupies, from the reading: eight to fifteen remarks in a
   working day. Twelve to begin with, because starting at either end teaches the
   wrong lesson on the first day. */
static const double NekoRateStart = 12.0;
static const double NekoRateHigh  = 15.0;
/* Below the band on purpose. Somebody who ignores everything is saying
   something, and the answer to it is not eight a day. */
static const double NekoRateLow   = 4.0;

/* The day the budget is spread over: eight hours actually spent at the Mac.
   Work four and you get half the remarks, which is the point of measuring the
   time rather than the clock. */
static const NSTimeInterval NekoRateWorkingDay = 8.0 * 3600.0;

/* Nobody there. The same number the advisor uses for going away. */
static const NSTimeInterval NekoRateAway = 150.0;

@implementation NekoRate

+ (void)initialize
{
	if(self != [NekoRate class])
		return;
	[[NSUserDefaults standardUserDefaults] registerDefaults:
		[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithDouble:NekoRateStart], NekoRateTargetKey, nil]];
}

+ (NekoRate *)sharedRate
{
	static NekoRate *shared = nil;
	if(shared == nil)
		shared = [[NekoRate alloc] init];
	return shared;
}

#pragma mark What the world looks like

- (NSDate *)now
{
	return [NSDate date];
}

- (NSTimeInterval)secondsSinceLastRemark
{
	return [NekoAsk secondsSinceSpokeUnprompted];
}

- (BOOL)atTheMac
{
	return [[NekoDesktop sharedDesktop] idleSeconds] < NekoRateAway;
}

- (NSTimeInterval)floorFromPreferences
{
	return [[NekoController sharedController] suggestionInterval];
}

#pragma mark The day

- (NSString *)dayOf:(NSDate *)date
{
	static NSDateFormatter *formatter = nil;
	if(formatter == nil) {
		formatter = [[NSDateFormatter alloc] init];
		[formatter setDateFormat:@"yyyy-MM-dd"];
	}
	return [formatter stringFromDate:date];
}

/* Two things at once, because both are answers to "how much of today has
   happened": the counts start again on a new day, and the time spent at the Mac
   grows by however long it has been since anyone last asked.

   Counted here rather than on a timer of its own. Whoever wants to speak asks
   this first, so the accounting happens exactly as often as it is needed and
   stops entirely when nothing is asking. */
- (void)accrue
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSDate *now = [self now];
	NSString *today = [self dayOf:now];

	if(![[defaults stringForKey:NekoRateDayKey] isEqualToString:today]) {
		[defaults setObject:today forKey:NekoRateDayKey];
		[defaults setInteger:0 forKey:NekoRateSaidKey];
		[defaults setInteger:0 forKey:NekoRateAnsweredKey];
		[defaults setInteger:0 forKey:NekoRateIgnoredKey];
		[defaults setInteger:0 forKey:NekoRateDismissedKey];
		[defaults setDouble:0.0 forKey:NekoRateActiveKey];
		lastAccrual = nil;
	}

	if(lastAccrual != nil) {
		NSTimeInterval since = [now timeIntervalSinceDate:lastAccrual];
		/* A gap longer than five minutes is the app having been asleep, shut,
		   or nobody at the Mac; it is not time somebody spent working. */
		if(since > 0.0 && since <= 300.0 && [self atTheMac])
			[defaults setDouble:[defaults doubleForKey:NekoRateActiveKey] + since
			             forKey:NekoRateActiveKey];
	}
	lastAccrual = now;
}

- (double)target
{
	double target = [[NSUserDefaults standardUserDefaults] doubleForKey:NekoRateTargetKey];
	if(target < NekoRateLow || target > NekoRateHigh)
		target = target < NekoRateLow ? NekoRateLow : NekoRateHigh;
	return target;
}

- (NSUInteger)saidToday
{
	[self accrue];
	return (NSUInteger)[[NSUserDefaults standardUserDefaults] integerForKey:NekoRateSaidKey];
}

- (NSUInteger)answeredToday
{
	[self accrue];
	return (NSUInteger)[[NSUserDefaults standardUserDefaults] integerForKey:NekoRateAnsweredKey];
}

- (NSTimeInterval)activeToday
{
	[self accrue];
	return [[NSUserDefaults standardUserDefaults] doubleForKey:NekoRateActiveKey];
}

/* How many remarks the day should have produced by now if it were spread
   evenly over the hours somebody is actually here. */
- (double)expectedByNow
{
	double through = [self activeToday] / NekoRateWorkingDay;
	if(through > 1.0)
		through = 1.0;
	return [self target] * through;
}

- (NSTimeInterval)gap
{
	return [self floorFromPreferences];
}

#pragma mark The two answers

- (BOOL)mayInterruptNow
{
	[self accrue];
	double said = (double)[self saidToday];

	/* The budget for the day. Fifteen is the top of the band whatever else
	   happens. */
	if(said >= [self target])
		return NO;

	/* Never before the interval somebody chose. That setting is the ceiling on
	   how often this may happen at all, and nothing here raises it. */
	if([self secondsSinceLastRemark] < [self gap])
		return NO;

	/* Two remarks in a row well ahead of the day's pace is a cluster, and a
	   cluster is what people remember about a feature like this. */
	if(said >= [self expectedByNow] + 2.0)
		return NO;

	return YES;
}

/* The bar a moment has to clear, from how far behind the day is. On pace, only
   a wide seam will do — the end of a long stretch in one application. Behind,
   a smaller gap is enough, because by then saying nothing has its own cost.
   This replaces measuring the silence directly: being behind the pace is the
   same fact, said in a way that knows how long the day has been. */
- (NekoBreakpoint)seamNeeded
{
	double behind = [self expectedByNow] - (double)[self saidToday];
	if(behind >= 1.5)
		return NekoBreakpointFine;
	if(behind >= 0.5)
		return NekoBreakpointMedium;
	return NekoBreakpointCoarse;
}

#pragma mark What became of them

- (void)bump:(NSString *)key by:(NSInteger)amount
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setInteger:[defaults integerForKey:key] + amount forKey:key];
}

- (void)movePaceBy:(double)amount
{
	double target = [self target] + amount;
	if(target > NekoRateHigh)
		target = NekoRateHigh;
	if(target < NekoRateLow)
		target = NekoRateLow;
	[[NSUserDefaults standardUserDefaults] setDouble:target forKey:NekoRateTargetKey];
}

- (void)noteSaid
{
	[self accrue];
	[self bump:NekoRateSaidKey by:1];
}

- (void)noteAnswered
{
	[self accrue];
	[self bump:NekoRateAnsweredKey by:1];
	[self movePaceBy:1.0];
}

- (void)noteIgnored
{
	[self accrue];
	[self bump:NekoRateIgnoredKey by:1];
	[self movePaceBy:-1.0];
}

/* Clicking a bubble away is not the same as being busy: it is somebody saying
   no with their hand, and it is worth twice as much as silence. */
- (void)noteDismissed
{
	[self accrue];
	[self bump:NekoRateDismissedKey by:1];
	[self movePaceBy:-2.0];
}

- (void)forgetPace
{
	[[NSUserDefaults standardUserDefaults] setDouble:NekoRateStart
	                                          forKey:NekoRateTargetKey];
}

#pragma mark Saying it out loud

- (NSString *)describeToday
{
	[self accrue];
	NSUInteger said = [self saidToday];
	NSUInteger answered = [self answeredToday];
	long hours = (long)([self activeToday] / 3600.0);
	long minutes = ((long)[self activeToday] % 3600) / 60;

	NSString *counts = [NSString stringWithFormat:
		NSLocalizedString(@"Today: %lu remark(s), %lu answered, over %ldh %02ldm at the Mac.", nil),
		(unsigned long)said, (unsigned long)answered, hours, minutes];
	NSString *pace = [NSString stringWithFormat:
		NSLocalizedString(@" It is aiming at about %ld a day and will not speak more often than every %ld minutes.", nil),
		(long)([self target] + 0.5), (long)([self gap] / 60.0)];
	return [counts stringByAppendingString:pace];
}

@end
