#import "NekoWhen.h"

/* A number written out, in the four languages, up to twelve — past that people
   write digits. "Un" and "una" are here because "un'ora" is one hour. */
static NSDictionary *NekoWrittenNumbers(void)
{
	static NSDictionary * const numbers =
	@{@"un": @1, @"uno": @1, @"una": @1, @"one": @1, @"une": @1, @"a": @1,
	  @"an": @1,
	  @"due": @2, @"two": @2, @"deux": @2, @"dos": @2,
	  @"tre": @3, @"three": @3, @"trois": @3, @"tres": @3,
	  @"quattro": @4, @"four": @4, @"quatre": @4, @"cuatro": @4,
	  @"cinque": @5, @"five": @5, @"cinq": @5, @"cinco": @5,
	  @"sei": @6, @"six": @6, @"seis": @6,
	  @"sette": @7, @"seven": @7, @"sept": @7, @"siete": @7,
	  @"otto": @8, @"eight": @8, @"huit": @8, @"ocho": @8,
	  @"nove": @9, @"nine": @9, @"neuf": @9, @"nueve": @9,
	  @"dieci": @10, @"ten": @10, @"dix": @10, @"diez": @10,
	  @"undici": @11, @"eleven": @11, @"onze": @11, @"once": @11,
	  @"dodici": @12, @"twelve": @12, @"douze": @12, @"doce": @12,
	  @"quindici": @15, @"fifteen": @15, @"quinze": @15, @"quince": @15,
	  @"venti": @20, @"twenty": @20, @"vingt": @20, @"veinte": @20,
	  @"trenta": @30, @"thirty": @30, @"trente": @30, @"treinta": @30,
	  @"quarantacinque": @45, @"forty-five": @45};
	
	return numbers;
}

/* A unit, and what one of it is worth. Longest first when they overlap: "ore"
   must be tried before "ora" would match inside it. */
static NSArray *NekoUnits(void)
{
	static NSArray *const units =
	@[@[@"secondi", @1],
	  @[@"secondo", @1],
	  @[@"seconds", @1],
	  @[@"second", @1],
	  @[@"secondes", @1],
	  @[@"seconde", @1],
	  @[@"segundos", @1],
	  @[@"segundo", @1],
	  @[@"sec", @1],
	  
	  @[@"minuti", @60],
	  @[@"minuto", @60],
	  @[@"minutes", @60],
	  @[@"minute", @60],
	  @[@"minutos", @60],
	  @[@"min", @60],
	  
	  @[@"heures", @3600],
	  @[@"heure", @3600],
	  @[@"hours", @3600],
	  @[@"hour", @3600],
	  @[@"horas", @3600],
	  @[@"hora", @3600],
	  @[@"ore", @3600],
	  @[@"ora", @3600],
	  @[@"hrs", @3600],
	  @[@"hr", @3600],
	  @[@"h", @3600]];
	return units;
}

/* The set phrases, which are not a number and a unit and have to be looked for
   whole. Longest first, again: "un quarto d'ora" contains "un ora". */
static NSArray *NekoSetPhrases(void)
{
	static NSArray *const phrases =
	@[@[@"un quarto d'ora", @900],
	  @[@"un quarto d’ora", @900],
	  @[@"quarto d'ora", @900],
	  @[@"quarto d’ora", @900],
	  @[@"quarter of an hour", @900],
	  @[@"quarter hour", @900],
	  @[@"quart d'heure", @900],
	  @[@"quart d’heure", @900],
	  @[@"cuarto de hora", @900],
	  
	  @[@"mezz'ora", @1800],
	  @[@"mezz’ora", @1800],
	  @[@"mezza ora", @1800],
	  @[@"half an hour", @1800],
	  @[@"half hour", @1800],
	  @[@"demi-heure", @1800],
	  @[@"demi heure", @1800],
	  @[@"media hora", @1800]];
	return phrases;
}

/* "E mezza", "and a half", "et demie", "y media" — half as much again of
   whatever unit was just said. */
static BOOL NekoSaysAndAHalf(NSString *rest)
{
	static NSArray *const halves = @[
		@"e mezza", @"e mezzo", @"and a half", @"et demie", @"et demi",
		@"y media", @"y medio"];
	for(NSString *half in halves) {
		if([rest hasPrefix:half]) {
			return YES;
		}
	}
	return NO;
}

@implementation NekoWhen

+ (NSDictionary *)writtenNumbers
{
	return NekoWrittenNumbers();
}

+ (NSTimeInterval)secondsIn:(NSString *)said
{
	if([said length] == 0)
		return 0.0;
	/* Apostrophes are two characters in the wild and one word to a person. */
	NSString *text = [[said lowercaseString]
		stringByReplacingOccurrencesOfString:@"’" withString:@"'"];

	/* The set phrases first: "un quarto d'ora" has a number and a unit inside it
	   that mean something else together. */
	for(NSArray *phrase in NekoSetPhrases()) {
		NSString *words = [[phrase objectAtIndex:0]
			stringByReplacingOccurrencesOfString:@"’" withString:@"'"];
		if([text rangeOfString:words].location != NSNotFound)
			return [[phrase objectAtIndex:1] doubleValue];
	}

	/* Then a number and a unit, taken in order across the sentence so that
	   "un'ora e mezza" and "1 h 30" both add up. */
	NSCharacterSet *breaks = [NSCharacterSet characterSetWithCharactersInString:
		@" \t\n\r,;:.!?'’"];
	NSArray *words = [text componentsSeparatedByCharactersInSet:breaks];
	NSDictionary *written = NekoWrittenNumbers();

	NSTimeInterval total = 0.0;
	double pending = -1.0;
	BOOL pendingInFigures = NO;
	double lastUnit = 0.0;
	NSUInteger i;
	for(i = 0; i < [words count]; i++) {
		NSString *word = [words objectAtIndex:i];
		if([word length] == 0)
			continue;

		NSNumber *spelled = [written objectForKey:word];
		if(spelled != nil) {
			pending = [spelled doubleValue];
			pendingInFigures = NO;
			continue;
		}
		if([word rangeOfCharacterFromSet:
		        [[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location
		   == NSNotFound) {
			pending = [word doubleValue];
			pendingInFigures = YES;
			continue;
		}

		double unit = 0.0;
		for(NSArray *known in NekoUnits())
			if([word isEqualToString:[known objectAtIndex:0]]) {
				unit = [[known objectAtIndex:1] doubleValue];
				break;
			}
		if(unit == 0.0)
			continue;

		/* A unit needs a number in front of it. It used to default to one, which
		   read "che ore sono" — what time is it — as a timer for an hour. Every
		   real phrase already has the number: "tra un'ora" comes apart into "un"
		   and "ora", and "in an hour" into "an" and "hour". */
		if(pending < 0.0)
			continue;
		double howMany = pending;
		total += howMany * unit;
		pending = -1.0;
		lastUnit = unit;

		/* "E mezza" belongs to the unit just counted. */
		NSRange after = [text rangeOfString:word];
		if(after.location != NSNotFound) {
			NSString *rest = [[text substringFromIndex:NSMaxRange(after)]
				stringByTrimmingCharactersInSet:
					[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if(NekoSaysAndAHalf(rest))
				total += howMany * unit / 2.0;
		}
	}

	/* "1 h 30" is how a clock is written down: a number left over after an hours
	   unit, and smaller than sixty, is the minutes. Anywhere else a number with
	   no unit after it is nothing at all.
	   Only figures: the "a" of "and a half" is a written one, and reading it as a
	   minute made an hour and a half into an hour, a half and a minute. */
	if(pending > 0.0 && pending < 60.0 && lastUnit == 3600.0 && pendingInFigures)
		total += pending * 60.0;

	/* A whole day is not a timer, and neither is a negative one. */
	if(total <= 0.0 || total > 24.0 * 3600.0)
		return 0.0;
	return total;
}

+ (NSString *)describe:(NSTimeInterval)seconds
{
	if(seconds <= 0.0)
		return @"";
	NSDateComponentsFormatter *spell = [[NSDateComponentsFormatter alloc] init];
	[spell setUnitsStyle:NSDateComponentsFormatterUnitsStyleFull];
	/* Days as well. Nothing this file *parses* is longer than a day — see
	   -secondsIn:, which refuses anything past twenty-four hours — but NekoSelf
	   asks it to describe how long since somebody last said anything, and three
	   days came back as "72 ore". */
	[spell setAllowedUnits:NSCalendarUnitDay | NSCalendarUnitHour
	                       | NSCalendarUnitMinute | NSCalendarUnitSecond];
	[spell setZeroFormattingBehavior:NSDateComponentsFormatterZeroFormattingBehaviorDropAll];
	return [spell stringFromTimeInterval:seconds] ?: @"";
}

+ (NSString *)clockTimeIn:(NSTimeInterval)seconds
{
	NSDateFormatter *clock = [[NSDateFormatter alloc] init];
	[clock setTimeStyle:NSDateFormatterShortStyle];
	[clock setDateStyle:NSDateFormatterNoStyle];
	return [clock stringFromDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

@end
