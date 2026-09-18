#import "NekoAdvisor.h"
#import "NekoAsk.h"
#import "NekoController.h"
#import "NekoCharacter.h"
#import "NekoAnswerProvider.h"
#import "NekoDesktop.h"
#import "NekoSense.h"
#import "NekoBrains.h"
#import "NekoRate.h"
#import "NekoMemory.h"

NSString * const NekoSuggestLastKey = @"NekoSuggestLast";

/* How often the cat looks up from what it is doing. Cheap: two lookups and a
   couple of comparisons, nothing that touches the disk or the network. */
static const NSTimeInterval NekoAdvisorHeartbeat = 20.0;

/* Long enough in one application to call it an activity worth commenting on. */
static const NSTimeInterval NekoAdvisorSettled = 25.0;

/* Nobody there, or someone in the middle of a word. */
static const NSTimeInterval NekoAdvisorAway = 150.0;
static const NSTimeInterval NekoAdvisorTyping = 3.0;

@implementation NekoAdvisor

+ (NekoAdvisor *)sharedAdvisor
{
	static NekoAdvisor *shared = nil;
	if(shared == nil)
		shared = [[NekoAdvisor alloc] init];
	return shared;
}

- (id)init
{
	self = [super init];
	if(self != nil) {
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
}

@synthesize thinking = waiting;

- (void)settingsChanged:(NSNotification *)note
{
	[self applySettings];
}

- (void)applySettings
{
	BOOL wanted = [[NekoController sharedController] suggestsUnasked];
	if(wanted == (heartbeat != nil))
		return;
	if(!wanted) {
		[heartbeat invalidate];
		heartbeat = nil;
		return;
	}
	/* Not retained: the timer is invalidated before it could outlive us, and
	   this object lives as long as the application does. */
	heartbeat = [NSTimer scheduledTimerWithTimeInterval:NekoAdvisorHeartbeat
	                                            target:self
	                                          selector:@selector(look:)
	                                          userInfo:nil
	                                           repeats:YES];
}

#pragma mark Watching, shallowly

/* All of it lives in NekoDesktop now, which the antics read too: one place that
   knows what is going on, rather than two that each keep half of it. */
- (NSString *)context
{
	return [[NekoDesktop sharedDesktop] summary];
}

/* Small models wrap their one sentence in quotation marks or bold it, both of
   which read as somebody quoting somebody else inside a speech bubble. */
- (NSString *)cleanUp:(NSString *)answer
{
	NSString *line = [answer stringByReplacingOccurrencesOfString:@"**" withString:@""];
	line = [line stringByReplacingOccurrencesOfString:@"*" withString:@""];
	line = [line stringByReplacingOccurrencesOfString:@"#" withString:@""];
	line = [line stringByTrimmingCharactersInSet:
		[NSCharacterSet characterSetWithCharactersInString:
			@" \t\n\r\"'\u201c\u201d\u00ab\u00bb"]];
	/* Only the first sentence, however carried away it got. */
	NSRange stop = [line rangeOfCharacterFromSet:
		[NSCharacterSet characterSetWithCharactersInString:@"\n"]];
	if(stop.location != NSNotFound)
		line = [[line substringToIndex:stop.location]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	return line;
}

#pragma mark Deciding to speak

/* Every reason not to, in the order that costs least to check. A suggestion is
   an interruption, and the whole feature dies if it interrupts badly. */
- (BOOL)shouldSpeakNow
{
	NekoController *controller = [NekoController sharedController];
	if(waiting || ![controller suggestsUnasked] || [controller isPaused])
		return NO;
	if([[NekoAsk sharedAsk] isBusy] || ![[NekoAsk sharedAsk] canSpeakUnprompted])
		return NO;

	NekoDesktop *desktop = [NekoDesktop sharedDesktop];
	NSTimeInterval idle = [desktop idleSeconds];
	if(idle > NekoAdvisorAway || idle < NekoAdvisorTyping)
		return NO;

	/* Never, whatever the clock says. */
	if([desktop isBusyElsewhere])
		return NO;
	if(lastSpoke != nil
	   && -[lastSpoke timeIntervalSinceNow] < [controller suggestionInterval])
		return NO;
	if(![NekoAsk mayInterruptNow])
		return NO;                 /* something else spoke recently */

	NSString *app = [desktop frontApp];
	if([app length] == 0 || [desktop secondsInFront] < NekoAdvisorSettled)
		return NO;

	/* The interval is a floor, not a trigger. Past it, a remark also needs a
	   seam in the work to land in and something specific to say — the two
	   things that separate a colleague from a notification. How wide a seam it
	   needs comes from how the day is going rather than from the silence alone:
	   on pace it waits for the end of a long stretch in one application, behind
	   pace a small gap will do, because by then saying nothing has its own
	   cost. */
	if([desktop breakpointNow] < [[NekoRate sharedRate] seamNeeded])
		return NO;
	if(![desktop somethingStandsOut])
		return NO;

	/* Twice the interval before saying anything else about the same
	   application: the second remark about the same window is where a helpful
	   pet turns into a nag. */
	if([app isEqualToString:lastSubject]
	   && lastSpoke != nil
	   && -[lastSpoke timeIntervalSinceNow] < [controller suggestionInterval] * 2.0)
		return NO;
	return YES;
}

- (void)look:(NSTimer *)timer
{
	[[NekoDesktop sharedDesktop] sample];
	if(![self shouldSpeakNow])
		return;
	[self suggestNow:NULL];
}

#pragma mark Asking

- (void)suggestNow:(void (^)(NSString *line, NSError *error))report
{
	/* Not the engine set for questions: the best one on this Mac. A remark
	   nobody asked for does not go to a remote service, and a remark written by
	   a model too small to hold the instructions is not worth the interruption. */
	id<NekoAnswerProvider> provider = [NekoBrains bestOnDeviceProvider];
	if(provider == nil || ![provider isConfigured]) {
		if(report != NULL)
			report(nil, [NSError errorWithDomain:NekoAskErrorDomain
			                                code:NekoAskErrorNotConfigured
			                            userInfo:nil]);
		return;
	}

	NekoCharacter *character = [[NekoController sharedController] character];
	/* Told whether there is anything to see, so that the sentence forbidding it
	   from pretending to see inside files is there when nothing was read and gone
	   when something was. Measured in tests/glance.m: without this the model was
	   handed the text and told to ignore it, 0 of 10 times. */
	NSString *seen = [[NekoDesktop sharedDesktop] summary];
	BOOL hasText = [seen rangeOfString:@"The text I am working on"].location
		!= NSNotFound;
	NSString *instructions = NekoSuggestionInstructionsSeeing([character persona],
	                                                          hasText);
	NSString *subject = [[[NekoDesktop sharedDesktop] frontApp] copy];

	/* What is going on, plus what the cat remembers. The engine here is always
	   an on-device one, so the diary is not going anywhere. */
	NSString *memory = [[NekoMemory sharedMemory] contextForPrompt];
	NSString *context = [memory length] > 0
		? [NSString stringWithFormat:@"%@\n%@", memory, [self context]]
		: [self context];
	__block void (^callerReport)(NSString *, NSError *) =
		report != NULL ? [report copy] : nil;

	waiting = YES;
	[provider askQuestion:context
	        instructions:instructions
	          completion:^(NSString *answer, NSError *error) {
		self->waiting = NO;
		/* Small models like to hand back their one sentence in quotation marks,
		   which reads as a quotation of somebody else inside the bubble. */
		NSString *line = [self cleanUp:answer];

		/* A model with nothing worth saying is told to answer with a hyphen,
		   which is easier for a small one to obey than "say nothing". */
		/* Every attempt costs the interval, whatever came of it. Nothing to say
		   counts as having looked, and so does a refusal — Apple's model
		   declines the odd question, and retrying it every twenty seconds until
		   the application changes would be a loop, not a pet. */
		self->lastSpoke = [NSDate date];
		self->lastSubject = [subject copy];

		/* Judged against what it could actually see, which is the prompt it
		   was given: the desktop summary and the diary that went with it. */
		NSString *problem = [NekoSense problemWith:line seeing:context];
		if(problem != nil && ![problem isEqualToString:@"nothing to say"])
			NSLog(@"Neko: a suggestion was thrown away — %@: %@", problem, line);

		/* And having said it once is a reason not to say it again. The rate rule
		   counts how often the cat speaks; nothing counted whether it was saying
		   the same thing, and the diary on this Mac answered that question
		   without being asked: 65 remarks over eight days, **11 of them
		   distinct**, one said twenty-two times. */
		if([NekoSense isWorthSaying:line seeing:context]
		   && [[NekoMemory sharedMemory] alreadySaidToday:line]) {
			NSLog(@"Neko: a suggestion was thrown away — said already today: %@", line);
			if(callerReport != nil) {
				callerReport(nil, error);
				callerReport = nil;
			}
			return;
		}

		if([NekoSense isWorthSaying:line seeing:context]) {
			[[NSUserDefaults standardUserDefaults]
				setObject:line forKey:NekoSuggestLastKey];
			/* Written down before it is said, so that a remark and what
			   prompted it end up next to each other in the diary. */
			NekoMemory *memory = [NekoMemory sharedMemory];
			[memory noteNoticed:[[NekoDesktop sharedDesktop] highlight]];
			[memory noteSaid:line];
			[[NekoAsk sharedAsk] sayUnprompted:line];
		}

		if(callerReport != nil) {
			callerReport([NekoSense isWorthSaying:line seeing:context] ? line : nil, error);
			callerReport = nil;
		}
	}];
}

@end
