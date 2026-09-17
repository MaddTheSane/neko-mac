#import "NekoVoice.h"
#import "NekoAnswerProvider.h"
#import "NekoRate.h"

NSString * const NekoVoiceLastSeenKey = @"NekoVoiceLastSeen";
NSString * const NekoVoiceGreetedKey  = @"NekoVoiceGreeted";

@implementation NekoVoice

#pragma mark The mood

/* Six hours of the day, each with a different thing to sound like. None of them
   says anything about what is true — only about how a true thing is worded,
   which is the whole of what a character is allowed to change. */
+ (NSString *)moodAt:(NSDate *)when
{
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDateComponents *parts = [calendar components:
		(NSCalendarUnitHour | NSCalendarUnitWeekday | NSCalendarUnitDay
		 | NSCalendarUnitMonth) fromDate:when];
	NSInteger hour = [parts hour];
	NSInteger weekday = [parts weekday];     /* 1 = Sunday */
	/* Day of the year without NSCalendarUnitDayOfYear, which arrived in macOS
	   15 and this still builds for 11: a month and a day is enough to make the
	   turn of phrase move through the year. */
	NSInteger dayOfYear = [parts month] * 31 + [parts day];

	NSString *time;
	if(hour < 5)
		time = @"It is the middle of the night and they are still up. Sound like "
		       @"a cat that would rather be asleep: short, a little flat.";
	else if(hour < 9)
		time = @"It is early. Sound like something that has just woken up and is "
		       @"not entirely convinced by the day yet.";
	else if(hour < 13)
		time = @"It is the morning and the day is going. Sound brisk, awake, "
		       @"unbothered.";
	else if(hour < 15)
		time = @"It is the middle of the day. Sound comfortable and slightly "
		       @"lazy, the way a cat is after lunch.";
	else if(hour < 19)
		time = @"It is the afternoon. Sound settled and a little dry.";
	else if(hour < 23)
		time = @"It is the evening. Sound softer than during the day, and in no "
		       @"hurry.";
	else
		time = @"It is late. Sound tired but not sulky, and keep it shorter than "
		       @"you would in the morning.";

	NSString *day = @"";
	if(weekday == 1 || weekday == 7)
		day = @" It is the weekend, and you are aware that they are working "
		      @"anyway.";
	else if(weekday == 2 && hour < 13)
		day = @" It is Monday morning, which you have opinions about.";
	else if(weekday == 6 && hour >= 15)
		day = @" It is Friday afternoon and the week is nearly over.";

	/* And one turn of phrase to lean on, changing through the day so that the
	   same question twice does not come back word for word. */
	NSArray *colours = [NSArray arrayWithObjects:
		@"Lean on an image from the room around you rather than an abstraction.",
		@"Use a very short second clause, if any.",
		@"Understate it. The plainer word is the better one today.",
		@"Allow yourself one small aside, in brackets or after a dash.",
		@"Start with the thing itself rather than with a preamble.",
		@"A little wry, without a joke in it.", nil];
	NSInteger which = (dayOfYear * 7 + hour / 4) % (NSInteger)[colours count];

	return [NSString stringWithFormat:@"%@%@ %@", time, day,
		[colours objectAtIndex:(NSUInteger)which]];
}

/* Under the hour and the day, a slower layer: how the day has gone. The two are
   the standard shape for this — a short-lived emotion over a mood that moves in
   hours — and the signals are the ones the rate already keeps, so nothing new is
   watched to get it.

   Small on purpose. A cat that sulks measurably is worse than one that does not
   notice, and this is the same open question the rate raised: less because it was
   ignored is either tact or passive aggression, and only living with it settles
   which. */
+ (NSString *)appraisal
{
	NekoRate *rate = [NekoRate sharedRate];
	double aiming = [rate target];
	NSUInteger said = [rate saidToday];
	NSUInteger answered = [rate answeredToday];

	if(aiming >= 13.0 || (said >= 3 && answered * 2 >= said))
		return @" They have been answering you today: you may be a shade more "
		       @"forward than usual.";
	if(aiming <= 6.0)
		return @" Today has not gone your way. Shorter than usual, and no "
		       @"complaining about it.";
	return @"";
}

+ (NSString *)moodNow
{
	return [[self moodAt:[NSDate date]] stringByAppendingString:[self appraisal]];
}

#pragma mark Turning up

+ (NSString *)pick:(NSArray *)lines
{
	if([lines count] == 0)
		return nil;
	return [lines objectAtIndex:arc4random_uniform((unsigned)[lines count])];
}

+ (NSString *)openingFor:(NSDate *)when lastSeen:(NSDate *)before
{
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSInteger hour = [[calendar components:NSCalendarUnitHour fromDate:when] hour];

	/* Never seen before: the only greeting that is really a greeting. */
	if(before == nil)
		return [self pick:[NSArray arrayWithObjects:
			NSLocalizedString(@"So this is where you work.", @"So this is where you work."),
			NSLocalizedString(@"Right. I live here now.", @"Right. I live here now."), nil]];

	NSTimeInterval away = [when timeIntervalSinceDate:before];
	if(away < 0.0)
		return nil;              /* a clock that moved backwards */

	/* Same day, already seen: nothing. A greeting every time the app starts is
	   not a greeting, it is a notification. */
	if([calendar isDate:when inSameDayAsDate:before])
		return nil;

	if(away > 7.0 * 86400.0)
		return [self pick:@[
			NSLocalizedString(@"You have been gone a week. I sat on the desk the whole time.", @"You have been gone a week. I sat on the desk the whole time."),
			NSLocalizedString(@"A week. I had almost got used to the quiet.", @"A week. I had almost got used to the quiet.")]];
	if(away > 2.0 * 86400.0)
		return [self pick:[NSArray arrayWithObjects:
			NSLocalizedString(@"You were away a couple of days. Nothing moved.", @"You were away a couple of days. Nothing moved."),
			NSLocalizedString(@"Back, then.", @"Back, then."), nil]];

	if(hour < 5 || hour >= 23)
		return [self pick:[NSArray arrayWithObjects:
			NSLocalizedString(@"Working at this hour. All right.", @"Working at this hour. All right."),
			NSLocalizedString(@"It is late. I will keep it down.", @"It is late. I will keep it down."), nil]];
	if(hour < 10)
		return [self pick:[NSArray arrayWithObjects:
			NSLocalizedString(@"Morning.", @"Morning."),
			NSLocalizedString(@"Early. Good.", @"Early. Good."), nil]];
	if(hour >= 19)
		return [self pick:[NSArray arrayWithObjects:
			NSLocalizedString(@"Evening.", @"Evening."),
			NSLocalizedString(@"Still here, I see.", @"Still here, I see."), nil]];
	return [self pick:[NSArray arrayWithObjects:
		NSLocalizedString(@"There you are.", @"There you are."),
		NSLocalizedString(@"Back at it.", @"Back at it."), nil]];
}

+ (NSString *)openingIfDue
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSDate *before = [defaults objectForKey:NekoVoiceLastSeenKey];
	if(![before isKindOfClass:[NSDate class]])
		before = nil;
	NSDate *now = [NSDate date];

	/* Written down before the greeting is used, so that a greeting is at most a
	   once-a-day thing however often the app is started. */
	[defaults setObject:now forKey:NekoVoiceLastSeenKey];
	return [self openingFor:now lastSeen:before];
}

#pragma mark Taking the assistant out of it

/* The openings a model reaches for when it is being agreeable. Every one of them
   is a sentence that could be deleted without losing anything. */
+ (NSArray<NSString*> *)complimentOpenings
{
	return @[
		@"great question", @"good question", @"excellent question",
		@"that's a great", @"that is a great", @"what a good",
		@"i'm glad you asked", @"im glad you asked", @"happy to help",
		@"of course!", @"certainly!", @"absolutely!", @"sure thing",
		@"ottima domanda", @"bella domanda", @"buona domanda", @"che bella domanda",
		@"ottima osservazione", @"assolutamente", @"certamente!", @"volentieri!",
		@"certo!", @"certo,", @"perfetto!", @"ovviamente!", @"sure!", @"sure,",
		@"excellente question", @"bonne question", @"bien sûr !", @"avec plaisir",
		@"buena pregunta", @"excelente pregunta", @"por supuesto!", @"por supuesto,",
		@"claro!", @"claro,", @"bien sûr,", @"bien sûr !", @"évidemment !"];
}

+ (NSArray *)sentencesIn:(NSString *)line
{
	NSMutableArray *sentences = [NSMutableArray array];
	NSMutableString *current = [NSMutableString string];
	NSUInteger i;
	for(i = 0; i < [line length]; i++) {
		unichar c = [line characterAtIndex:i];
		[current appendFormat:@"%C", c];
		if(c == '.' || c == '!' || c == '?' || c == '\n') {
			NSString *done = [current stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if([done length] > 0)
				[sentences addObject:done];
			[current setString:@""];
		}
	}
	NSString *tail = [current stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if([tail length] > 0)
		[sentences addObject:tail];
	return sentences;
}

+ (BOOL)sentenceIsACompliment:(NSString *)sentence
{
	NSString *lowered = [[sentence stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
	if([lowered length] > 60)
		return NO;               /* long enough to be carrying something */
	for(NSString *opening in [self complimentOpenings])
		if([lowered hasPrefix:opening])
			return YES;
	return NO;
}

+ (BOOL)isNothingButFlattery:(NSString *)line
{
	NSArray *sentences = [self sentencesIn:line];
	if([sentences count] == 0)
		return NO;
	for(NSString *sentence in sentences)
		if(![self sentenceIsACompliment:sentence])
			return NO;
	return YES;
}

+ (NSSet<NSString*> *)meaningfulWordsIn:(NSString *)sentence
{
	NSMutableSet *words = [NSMutableSet set];
	NSEnumerator *e = [[[sentence lowercaseString] componentsSeparatedByCharactersInSet:
		[[NSCharacterSet letterCharacterSet] invertedSet]] objectEnumerator];
	for(NSString *word in e)
		if([word length] > 3)    /* short words repeat in any two sentences */
			[words addObject:word];
	return words;
}

/* The second sentence saying the first one again: a habit of models that have
   been taught to round things off. Measured by how many of the longer words are
   shared, which catches a restatement without catching a sentence that simply
   continues. */
+ (BOOL)saysItTwice:(NSString *)line
{
	NSArray *sentences = [self sentencesIn:line];
	if([sentences count] < 2)
		return NO;
	NSSet *first = [self meaningfulWordsIn:[sentences objectAtIndex:0]];
	NSSet *second = [self meaningfulWordsIn:[sentences objectAtIndex:1]];
	if([first count] < 3 || [second count] < 3)
		return NO;

	NSMutableSet *shared = [[second mutableCopy] autorelease];
	[shared intersectSet:first];
	double smaller = (double)MIN([first count], [second count]);
	return (double)[shared count] / smaller >= 0.7;
}

/* First person plus an inner state. Written as whole phrases rather than as a
   pronoun and a word list, because "sono" carries identity as often as feeling
   and a cat saying what it is must go through. */
+ (NSArray *)feelingClaims
{
	return @[
		/* Italian */
		@"mi sento", @"sono triste", @"sono felice", @"sono contento", @"sono contenta",
		@"sono solo", @"sono sola", @"mi annoio", @"mi manchi", @"ho paura",
		@"sono geloso", @"sono ferito", @"sono offeso", @"mi sono offeso",
		@"mi fa male", @"soffro",
		/* English */
		@"i feel", @"i'm feeling", @"im feeling", @"i am feeling", @"i am sad",
		@"i'm sad", @"i am happy", @"i'm happy", @"i am lonely", @"i'm lonely",
		@"i miss you", @"i am hurt", @"i'm hurt", @"i am bored", @"i'm bored",
		@"i am afraid", @"i'm afraid", @"it hurts me",
		/* French */
		@"je me sens", @"je suis triste", @"je suis heureux", @"je suis seul",
		@"tu me manques", @"j'ai peur", @"je m'ennuie",
		/* Spanish */
		@"me siento", @"estoy triste", @"estoy feliz", @"estoy solo", @"estoy sola",
		@"te echo de menos", @"tengo miedo", @"me aburro"];
}

+ (BOOL)claimsAFeeling:(NSString *)line
{
	NSString *lowered = [line lowercaseString];
	for(NSString *claim in [self feelingClaims])
		if([lowered rangeOfString:claim].location != NSNotFound)
			return YES;
	return NO;
}

+ (NSString *)withoutFlattery:(NSString *)line
{
	NSArray *sentences = [self sentencesIn:line];
	if([sentences count] == 0)
		return line;

	NSMutableArray *kept = [[sentences mutableCopy] autorelease];

	/* The compliment in front, while there is one and something behind it. */
	while([kept count] > 1 && [self sentenceIsACompliment:[kept objectAtIndex:0]])
		[kept removeObjectAtIndex:0];

	/* And the sentence at the end that says the one before it again. */
	if([kept count] > 1) {
		NSSet *last = [self meaningfulWordsIn:[kept lastObject]];
		NSSet *before = [self meaningfulWordsIn:[kept objectAtIndex:[kept count] - 2]];
		if([last count] >= 3 && [before count] >= 3) {
			NSMutableSet *shared = [[last mutableCopy] autorelease];
			[shared intersectSet:before];
			double smaller = (double)MIN([last count], [before count]);
			if((double)[shared count] / smaller >= 0.7)
				[kept removeLastObject];
		}
	}

	NSString *tidied = [[kept componentsJoinedByString:@" "]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return [tidied length] > 0 ? tidied : line;
}

@end
