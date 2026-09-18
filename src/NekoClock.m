#import "NekoClock.h"
#import "NekoWhen.h"

/* The application's own language, which is what it answers in. */
static NSLocale *NekoClockLocale(void)
{
	NSString *code = [[[NSBundle mainBundle] preferredLocalizations] firstObject];
	return [NSLocale localeWithLocaleIdentifier:code ?: @"en"];
}

/* Whichever of these the sentence starts with, and what is left after it. Longest
   first, so that "quanti giorni mancano a" is tried before "quanto manca a". */
static NSString *NekoTailAfterAny(NSString *lowered, NSArray<NSString*> *triggers)
{
	for(NSString *trigger in triggers) {
		NSRange found = [lowered rangeOfString:trigger];
		if(found.location == NSNotFound)
			continue;
		return [[lowered substringFromIndex:NSMaxRange(found)]
			stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	}
	return nil;
}

/* The words in front of a date that stop NSDataDetector reading it. Measured:
   "al 3 marzo" comes back as today at noon and claims to have used the whole
   phrase; "3 marzo" comes back as the third of March. */
static NSString *NekoWithoutLeadingWords(NSString *tail)
{
	static NSArray<NSString*> *const words =
	@[
		/* Italian */
		@"al", @"alla", @"allo", @"agli", @"alle", @"ai", @"all'", @"a",
		@"il", @"lo", @"la", @"i", @"gli", @"le", @"l'", @"del", @"di",
		/* English */
		@"until", @"till", @"to", @"the", @"for",
		/* French */
		@"jusqu'au", @"jusqu'à", @"au", @"aux", @"le", @"la", @"les",
		/* Spanish */
		@"hasta", @"para", @"el", @"los", @"las"];

	NSString *text = tail;
	BOOL cut = YES;
	while(cut) {
		cut = NO;
		for(NSString *word in words) {
			/* An apostrophe is not a word boundary the way a space is, so the
			   two shapes are asked for separately. */
			NSString *withSpace = [word stringByAppendingString:@" "];
			if([word hasSuffix:@"'"] && [text hasPrefix:word]) {
				text = [text substringFromIndex:[word length]];
				cut = YES;
				break;
			}
			if([text hasPrefix:withSpace]) {
				text = [[text substringFromIndex:[withSpace length]]
					stringByTrimmingCharactersInSet:
						[NSCharacterSet whitespaceCharacterSet]];
				cut = YES;
				break;
			}
		}
	}
	return text;
}

/* Nothing but punctuation left. The guard that keeps "che giorno è meglio per
   uscire" from being answered with a date. */
static BOOL NekoNothingLeft(NSString *tail)
{
	NSCharacterSet *letters = [NSCharacterSet alphanumericCharacterSet];
	return [tail rangeOfCharacterFromSet:letters].location == NSNotFound;
}

/* How many days a sentence means by "domani". nil when it names no day at all. */
static NSNumber *NekoDayOffset(NSString *tail)
{
	static NSDictionary<NSString*,NSNumber*> * const offsets = @{
		@"oggi": @0, @"today": @0, @"aujourd'hui": @0, @"hoy": @0,
		@"domani": @1, @"tomorrow": @1, @"demain": @1, @"mañana": @1,
		@"dopodomani": @2, @"dopo domani": @2, @"après-demain": @2,
		@"apres-demain": @2, @"pasado mañana": @2,
		@"the day after tomorrow": @2, @"day after tomorrow": @2,
		@"ieri": @-1, @"yesterday": @-1, @"hier": @-1, @"ayer": @-1,
	};

	if(NekoNothingLeft(tail))
		return @0;        /* "che giorno è" — today */

	/* Longest first: "dopo domani" must beat "domani". */
	NSArray *keys = [[offsets allKeys] sortedArrayUsingComparator:
		^NSComparisonResult(NSString *a, NSString *b) {
			return [b length] - [a length] > 0 ? NSOrderedAscending
			     : ([b length] == [a length] ? NSOrderedSame : NSOrderedDescending);
		}];
	for(NSString *word in keys) {
		NSRange found = [tail rangeOfString:word];
		if(found.location == NSNotFound)
			continue;
		/* And nothing else in the tail, so that "che giorno è domani il mercato"
		   is left to somebody who can answer it. */
		NSString *rest = [[tail stringByReplacingCharactersInRange:found
		                                               withString:@""]
			stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if(NekoNothingLeft(rest))
			return [offsets objectForKey:word];
	}
	return nil;
}

static NSString *NekoDateWritten(NSDate *when)
{
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setLocale:NekoClockLocale()];
	[formatter setDateStyle:NSDateFormatterFullStyle];
	[formatter setTimeStyle:NSDateFormatterNoStyle];
	return [formatter stringFromDate:when];
}

/* The same date with the weekday left off. NekoDateWritten uses the full style,
   which names the day — right everywhere else in this file, and absurd in the one
   sentence whose whole job is to name it: "il martedì 3 marzo 2026 era un
   martedì". */
static NSString *NekoDateWithoutDay(NSDate *when)
{
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setLocale:NekoClockLocale()];
	[formatter setDateStyle:NSDateFormatterLongStyle];
	[formatter setTimeStyle:NSDateFormatterNoStyle];
	return [formatter stringFromDate:when];
}

static NSString *NekoTimeWritten(NSDate *when)
{
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setLocale:NekoClockLocale()];
	[formatter setDateStyle:NSDateFormatterNoStyle];
	[formatter setTimeStyle:NSDateFormatterShortStyle];
	return [formatter stringFromDate:when];
}

@implementation NekoClock

#pragma mark What time it is

+ (NSString *)timeIfAsked:(NSString *)lowered
{
	static NSArray * const triggers = @[
		@"che ore sono", @"che ora è", @"che ora e'", @"che ore fa",
		@"what time is it", @"what's the time", @"what is the time",
		@"quelle heure est-il", @"quelle heure il est", @"il est quelle heure",
		@"qué hora es", @"que hora es"];
	NSString *tail = NekoTailAfterAny(lowered, triggers);
	if(tail == nil || !NekoNothingLeft(tail))
		return nil;
	return [NSString stringWithFormat:NSLocalizedString(@"It is %@.", @"It is %@."),
		NekoTimeWritten([NSDate date])];
}

#pragma mark What day it is

+ (NSString *)dayIfAsked:(NSString *)lowered
{
	static NSArray<NSString*> * const triggers = @[
		@"che giorno della settimana è", @"che giorno è", @"che giorno e'",
		@"che giorno siamo", @"in che giorno siamo", @"che giorno era",
		@"che data è",
		@"che data e'", @"quanti ne abbiamo",
		@"what day of the week is it", @"what day is it", @"what day is",
		@"what day was it", @"what day was", @"what weekday was",
		@"what weekday is",
		@"what's the date", @"what is the date", @"what's today's date",
		@"quel jour sommes-nous", @"quel jour est-ce", @"quel jour est",
		@"quelle est la date", @"on est quel jour",
		@"qué día es", @"que dia es", @"qué fecha es", @"en qué fecha estamos"];
	NSString *tail = NekoTailAfterAny(lowered, triggers);
	if(tail == nil)
		return nil;
	NSNumber *offset = NekoDayOffset(tail);
	if(offset == nil) {
		/* Not today, tomorrow or yesterday — so a date, if the tail names one.
		   "che giorno era il 3 marzo 2026?" used to stop here and reach a model,
		   and the site said this worked, which it did not. Past and future both:
		   this one is a lookup in the calendar, not a subtraction, so nothing
		   about it prefers the future. */
		NSDate *dated = NekoDateIn(NekoWithoutLeadingWords(tail), YES);
		if(dated == nil)
			return nil;              /* "che giorno è meglio per uscire" */
		NSDateFormatter *weekday = [[NSDateFormatter alloc] init];
		[weekday setLocale:NekoClockLocale()];
		[weekday setDateFormat:@"EEEE"];
		/* Two sentences rather than one, because a language with tenses needs
		   them: "il 3 marzo era un martedì" and "il 25 dicembre sarà un
		   venerdì" are not the same sentence with a different noun in it. */
		BOOL gone = [dated timeIntervalSinceNow] < 0.0;
		return [NSString stringWithFormat:
			gone ? NSLocalizedString(@"%@ was a %@.", @"%@ was a %@.")
			     : NSLocalizedString(@"%@ will be a %@.", @"%@ will be a %@."),
			NekoDateWithoutDay(dated), [weekday stringFromDate:dated]];
	}

	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDate *when = [calendar dateByAddingUnit:NSCalendarUnitDay
	                                    value:[offset intValue]
	                                   toDate:[NSDate date]
	                                  options:0];
	NSString *written = NekoDateWritten(when);
	switch([offset intValue]) {
		case 1:  return [NSString stringWithFormat:
						 NSLocalizedString(@"Tomorrow is %@.", @"Tomorrow is %@."), written];
		case 2:  return [NSString stringWithFormat:
						 NSLocalizedString(@"The day after tomorrow is %@.", @"The day after tomorrow is %@."), written];
		case -1: return [NSString stringWithFormat:
						 NSLocalizedString(@"Yesterday was %@.", @"Yesterday was %@."), written];
		default: return [NSString stringWithFormat:
						 NSLocalizedString(@"Today is %@.", @"Today is %@."), written];
	}
}

#pragma mark How long until something

/* Enough of a date for the detector to be trusted with it.

   Without this the detector's documented failure — handed a phrase it cannot
   read, it answers **today at noon** and reports that it used all of it — turns
   every "che giorno è meglio per uscire" into a confident answer about today.
   -untilIfAsked: is shielded from that by throwing away anything in the past;
   a question about a day that has *been* cannot use that guard, so it uses this
   one instead. */
static BOOL NekoLooksLikeADate(NSString *tail)
{
	if([tail rangeOfCharacterFromSet:
			[NSCharacterSet decimalDigitCharacterSet]].location != NSNotFound)
		return YES;

	static NSArray * const months =
	@[@"gennaio", @"febbraio", @"marzo", @"aprile", @"maggio", @"giugno",
	  @"luglio", @"agosto", @"settembre", @"ottobre", @"novembre", @"dicembre",
	  @"january", @"february", @"march", @"april", @"june", @"july",
	  @"august", @"september", @"october", @"november", @"december",
	  @"janvier", @"février", @"mars", @"avril", @"mai", @"juin", @"juillet",
	  @"août", @"septembre", @"octobre", @"novembre", @"décembre",
	  @"enero", @"febrero", @"marzo", @"abril", @"mayo", @"junio", @"julio",
	  @"agosto", @"septiembre", @"octubre", @"noviembre", @"diciembre"];
	for(NSString *month in months) {
		if([tail rangeOfString:month].location != NSNotFound) {
			return YES;
		}
	}
	return NO;
}

/* The date a tail names, or nil.

   `shaped` is whether NekoLooksLikeADate must vouch for it first, and the two
   callers genuinely differ. -untilIfAsked: does not want it: "quanti giorni
   mancano a venerdì" names a weekday, which has neither a digit nor a month in
   it, and that question is the one this file was written for. It is safe there
   because it throws away anything landing in the past, which is what the
   detector's failure looks like. The question about a day that has *been* cannot
   use that guard and so asks for the shape instead. */
static NSDate *NekoDateIn(NSString *tail, BOOL shaped)
{
	if(shaped && !NekoLooksLikeADate(tail))
		return nil;
	NSDataDetector *detector = [NSDataDetector
		dataDetectorWithTypes:NSTextCheckingTypeDate error:NULL];
	NSTextCheckingResult *found = [detector firstMatchInString:tail options:0
	                                                     range:NSMakeRange(0, [tail length])];
	return [found date];
}

/* The detector's own way of saying it was given no time of day: noon. Anything
   landing exactly there is a day rather than a moment, and is counted in days. */
static BOOL NekoIsNoon(NSDate *when)
{
	NSDateComponents *parts = [[NSCalendar currentCalendar]
		components:NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond
		  fromDate:when];
	return [parts hour] == 12 && [parts minute] == 0 && [parts second] == 0;
}

+ (NSString *)untilIfAsked:(NSString *)lowered
{
	NSArray *triggers = [NSArray arrayWithObjects:
		/* Italian — the longer ones first, since one contains the other. */
		@"quanti giorni mancano", @"quanti giorni ci sono", @"quanti giorni",
		@"quante settimane mancano", @"quanto tempo manca", @"quanto manca",
		/* English */
		@"how many days until", @"how many days till", @"how many days to",
		@"how many weeks until", @"how long until", @"how long till",
		@"how long to", @"days until", @"days till",
		/* French */
		@"combien de jours avant", @"combien de jours jusqu",
		@"combien de temps avant", @"combien de temps jusqu",
		@"dans combien de temps",
		/* Spanish */
		@"cuántos días faltan", @"cuantos dias faltan", @"cuántos días",
		@"cuantos dias", @"cuánto falta", @"cuanto falta",
		@"cuánto tiempo falta", @"cuanto tiempo falta", nil];
	NSString *tail = NekoTailAfterAny(lowered, triggers);
	if([tail length] == 0)
		return nil;
	tail = NekoWithoutLeadingWords(tail);
	if([tail length] == 0)
		return nil;

	NSDate *target = NekoDateIn(tail, NO);
	if(target == nil)
		return nil;                  /* "quanto manca al lancio del prodotto" */

	NSDate *now = [NSDate date];
	if([target timeIntervalSinceDate:now] <= 0.0)
		return nil;                  /* the detector's other way of failing */

	NSCalendar *calendar = [NSCalendar currentCalendar];
	if(NekoIsNoon(target)) {
		/* No hour was said, so this is a number of days and not a stretch of
		   hours: counted from midnight to midnight, which is how somebody
		   counts them. */
		NSDate *from = nil, *to = nil;
		[calendar rangeOfUnit:NSCalendarUnitDay startDate:&from interval:NULL forDate:now];
		[calendar rangeOfUnit:NSCalendarUnitDay startDate:&to interval:NULL forDate:target];
		NSInteger days = [[calendar components:NSCalendarUnitDay fromDate:from toDate:to
		                               options:0] day];
		if(days <= 0)
			return NSLocalizedString(@"That is today.", @"That is today.");
		if(days == 1)
			return NSLocalizedString(@"That is tomorrow.", @"That is tomorrow.");
		return [NSString stringWithFormat:
			NSLocalizedString(@"%ld days, on %@.", @"%ld days, on %@."), (long)days, NekoDateWritten(target)];
	}

	NSTimeInterval away = [target timeIntervalSinceDate:now];
	return [NSString stringWithFormat:NSLocalizedString(@"%@, at %@.", @"%@, at %@."),
		[NekoWhen describe:away], NekoTimeWritten(target)];
}

#pragma mark

+ (NSString *)wantedFor:(NSString *)question
{
	NSString *lowered = [question lowercaseString];
	NSString *answer = [self timeIfAsked:lowered];
	if(answer != nil)
		return answer;
	answer = [self untilIfAsked:lowered];
	if(answer != nil)
		return answer;
	return [self dayIfAsked:lowered];
}

@end
