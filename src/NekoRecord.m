#import "NekoRecord.h"
#import "NekoMemory.h"

/* Two, not three: the bubble holds a sentence or two, and a third quotation is
   somebody's diary being read out at them. */
static const NSUInteger NekoRecordMost = 2;

/* The phrases that ask what was said before. A first person and a past between
   them, both required — "ti ricordi" on its own is in "ti ricordi come si
   scrive?", which is a question about spelling and none of this file's business. */
static NSArray *NekoRecordAsking(void)
{
	static NSArray *const asking =
	@[
		/* Italian */
		@"cosa avevo detto", @"che cosa avevo detto", @"che avevo detto",
		@"avevo detto", @"avevo scritto", @"l'avevo detto", @"te l'avevo detto",
		@"ti avevo detto", @"quando avevo", @"cosa ho detto", @"che ho detto",
		@"ti ricordi cosa", @"ti ricordi quando", @"ti ricordi che cosa",
		@"cosa ti ho detto", @"come avevo",
		/* English */
		@"what did i say", @"did i say", @"had i said", @"what had i said",
		@"when did i say", @"what did i tell you", @"did i tell you",
		@"do you remember what", @"do you remember when",
		/* French */
		@"j'avais dit", @"qu'avais-je dit", @"je t'avais dit",
		@"qu'est-ce que j'avais dit", @"tu te souviens quand",
		@"tu te souviens de ce que",
		/* Spanish */
		@"había dicho", @"habia dicho", @"te había dicho", @"qué había dicho",
		@"que habia dicho", @"te acuerdas de lo que", @"te acuerdas cuándo"];
	
	return asking;
}

/* The day, as somebody would say it rather than as a file is named. */
static NSString *NekoRecordDay(NSString *stamp)
{
	NSDateFormatter *stored = [[NSDateFormatter alloc] init];
	[stored setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
	[stored setDateFormat:@"yyyy-MM-dd"];
	NSDate *when = [stored dateFromString:stamp];
	if(when == nil)
		return stamp;

	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDate *midnight = nil, *thatDay = nil;
	[calendar rangeOfUnit:NSCalendarUnitDay startDate:&midnight interval:NULL
	              forDate:[NSDate date]];
	[calendar rangeOfUnit:NSCalendarUnitDay startDate:&thatDay interval:NULL
	              forDate:when];
	NSInteger back = [[calendar components:NSCalendarUnitDay fromDate:thatDay
	                               toDate:midnight options:0] day];
	if(back == 1)
		return NSLocalizedString(@"yesterday", @"yesterday");

	NSDateFormatter *said = [[NSDateFormatter alloc] init];
	[said setLocale:[NSLocale localeWithLocaleIdentifier:
		[[[NSBundle mainBundle] preferredLocalizations] firstObject] ?: @"en"]];
	/* The year only when it is not this one: "il 27 agosto" reads better than
	   "il 27 agosto 2026" and says the same thing until January. */
	NSDateComponents *now = [calendar components:NSCalendarUnitYear fromDate:[NSDate date]];
	NSDateComponents *then = [calendar components:NSCalendarUnitYear fromDate:when];
	[said setDateFormat:[now year] == [then year] ? @"d MMMM" : @"d MMMM yyyy"];
	return [said stringFromDate:when];
}

/* The phrases that ask *when* rather than *what*. Checked before the others,
   because "quando ti ho detto" contains "ti ho detto". */
static NSArray *NekoRecordAskingWhen(void)
{
	static NSArray *const asking =
	@[
		/* Italian */
		@"quando te l'ho detto", @"quando te l'avevo detto",
		@"quando ne abbiamo parlato", @"quando ne ho parlato",
		@"quando l'ho detto", @"quando l'avevo detto",
		@"quando ti ho parlato di", @"quando ti ho detto",
		@"l'ultima volta che ne abbiamo parlato", @"quand'è che ne abbiamo parlato",
		/* English */
		@"when did i tell you", @"when did we talk about",
		@"when did i mention", @"when did i say", @"when was the last time i",
		/* French */
		@"quand est-ce que je t'ai dit", @"quand en avons-nous parlé",
		@"quand t'ai-je dit",
		/* Spanish */
		@"cuándo te lo dije", @"cuando te lo dije", @"cuándo hablamos de",
		@"cuando hablamos de"];
	
	return asking;
}

/* How many days ago that day was, counted midnight to midnight the way somebody
   counts them. */
static NSInteger NekoRecordDaysAgo(NSString *stamp)
{
	NSDateFormatter *stored = [[NSDateFormatter alloc] init];
	[stored setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
	[stored setDateFormat:@"yyyy-MM-dd"];
	NSDate *when = [stored dateFromString:stamp];
	if(when == nil)
		return -1;
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDate *from = nil, *to = nil;
	[calendar rangeOfUnit:NSCalendarUnitDay startDate:&from interval:NULL forDate:when];
	[calendar rangeOfUnit:NSCalendarUnitDay startDate:&to interval:NULL
	              forDate:[NSDate date]];
	return [[calendar components:NSCalendarUnitDay fromDate:from toDate:to
	                     options:0] day];
}

@implementation NekoRecord

+ (BOOL)asksWhen:(NSString *)question
{
	NSString *text = [question lowercaseString];
	NSEnumerator *e = [NekoRecordAskingWhen() objectEnumerator];
	NSString *phrase;
	while((phrase = [e nextObject]) != nil)
		if([text rangeOfString:phrase].location != NSNotFound)
			return YES;
	return NO;
}

+ (BOOL)wantedFor:(NSString *)question
{
	if([self asksWhen:question])
		return YES;
	NSString *text = [question lowercaseString];
	NSEnumerator *e = [NekoRecordAsking() objectEnumerator];
	NSString *phrase;
	while((phrase = [e nextObject]) != nil)
		if([text rangeOfString:phrase].location != NSNotFound)
			return YES;
	return NO;
}

+ (NSString *)answerFor:(NSString *)question
{
	NSArray *found = [[NekoMemory sharedMemory] recordAbout:question
	                                                  limit:NekoRecordMost];
	if([found count] == 0)
		return NSLocalizedString(@"I have nothing written down about that.", @"I have nothing written down about that.");

	/* Asked *when*, the day and how long ago is the whole answer: quoting the
	   line back would be answering a different question. */
	if([self asksWhen:question]) {
		/* The **most recent** mention, not the best-scoring one. -recordAbout:
		   ranks by how much a line is about the question, which is right for
		   "cosa avevo detto" and wrong here: "quando te l'ho detto" asks when it
		   was last said. Measured before this line existed — two mentions of the
		   same meeting, nine days back and two, and it answered nine. */
		NSDictionary *first = [found objectAtIndex:0];
		NSUInteger n;
		for(n = 1; n < [found count]; n++)
			if([[[found objectAtIndex:n] objectForKey:@"Day"]
					compare:[first objectForKey:@"Day"]] == NSOrderedDescending)
				first = [found objectAtIndex:n];
		NSString *stamp = [first objectForKey:@"Day"];
		NSInteger ago = NekoRecordDaysAgo(stamp);
		if(ago == 0)
			return NSLocalizedString(@"Today.", @"Today.");
		if(ago == 1)
			return NSLocalizedString(@"Yesterday.", @"Yesterday.");
		if(ago < 0)
			return NekoRecordDay(stamp);
		return [NSString stringWithFormat:
			NSLocalizedString(@"On %@, %ld days ago.", @"On %@, %ld days ago."),
			NekoRecordDay(stamp), (long)ago];
	}

	NSMutableArray *sentences = [NSMutableArray array];
	NSEnumerator *e = [found objectEnumerator];
	NSDictionary *one;
	while((one = [e nextObject]) != nil) {
		BOOL theirs = [[one objectForKey:@"Kind"] isEqualToString:@"you"];
		[sentences addObject:[NSString stringWithFormat:
			theirs ? NSLocalizedString(@"On %@ you said: “%@”", @"On %@ you said: “%@”")
			       : NSLocalizedString(@"On %@ I noted: “%@”", @"On %@ I noted: \"%@\""),
			NekoRecordDay([one objectForKey:@"Day"]),
			[one objectForKey:@"Text"]]];
	}
	return [sentences componentsJoinedByString:@" "];
}

@end
