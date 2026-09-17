#import "NekoAppointment.h"
#import "NekoWhen.h"
#import "NekoMemory.h"

/* An hour, when nobody said. Long enough to be worth blocking out and short
   enough that correcting it in Calendar is one drag. */
static const NSTimeInterval NekoAppointmentDefault = 3600.0;

/* The phrases that turn a date into a request. Without one of these, "la riunione
   è durata due ore" would put something in somebody's calendar. */
static NSArray *NekoCalendarOpenings(void)
{
	static NSArray * const openings = @[
		/* Italian */
		   @"metti in calendario", @"in calendario", @"segna in agenda",
		   @"segna un appuntamento", @"appuntamento", @"aggiungi al calendario",
		   @"metti in agenda",
		   /* English */
		   @"add to my calendar", @"add to calendar", @"put in my calendar",
		   @"in my calendar", @"schedule ", @"appointment",
		   /* French */
		   @"dans mon calendrier", @"au calendrier", @"rendez-vous",
		   /* Spanish */
		   @"en mi calendario", @"al calendario", @"añade al calendario",
		   @"cita ", @"agenda "];
	return openings;
}

@implementation NekoAppointment

+ (BOOL)asksForOne:(NSString *)said
{
	for (NSString *opening in NekoCalendarOpenings()) {
		if([said rangeOfString:opening].location != NSNotFound) {
			return YES;
		}
	}
	return NO;
}

/* The rule that keeps this honest: a bare time that has already gone by today
   means tomorrow. Somebody saying "alle 7" at four in the afternoon is not asking
   for this morning, and a calendar entry in the past is worse than none.

   Only a bare time, though. "Il 3 settembre" in December is a date somebody got
   wrong, and moving it a year would be inventing something they did not say — so
   that is refused instead, out loud. */
+ (NSDate *)settle:(NSDate *)when saidWords:(NSString *)words wasBare:(BOOL *)bare
{
	NSDate *now = [NSDate date];
	if([when timeIntervalSinceDate:now] > 0.0) {
		if(bare != NULL) *bare = NO;
		return when;
	}

	NSCalendar *calendar = [NSCalendar currentCalendar];
	BOOL sameDay = [calendar isDate:when inSameDayAsDate:now];
	if(bare != NULL) *bare = sameDay;
	if(!sameDay)
		return nil;                 /* a real date, and it has gone */
	return [when dateByAddingTimeInterval:24.0 * 3600.0];
}

+ (NSDictionary *)wantedFor:(NSString *)question
{
	if([question length] == 0 || ![self asksForOne:[question lowercaseString]])
		return nil;

	NSDataDetector *dates = [NSDataDetector dataDetectorWithTypes:
		NSTextCheckingTypeDate error:NULL];
	NSTextCheckingResult *hit = [[dates matchesInString:question options:0
	                                              range:NSMakeRange(0, [question length])]
		firstObject];
	if(hit == nil || [hit date] == nil)
		return nil;

	BOOL wasBare = NO;
	NSDate *when = [self settle:[hit date]
	                  saidWords:[question substringWithRange:[hit range]]
	                    wasBare:&wasBare];
	if(when == nil)
		return [NSDictionary dictionaryWithObjectsAndKeys:
			@"past", @"Problem",
			NSLocalizedString(@"That was already yesterday — say a day that is still coming.", @"That was already yesterday — say a day that is still coming."),
			@"Sentence", nil];

	/* However long they said, or an hour. "Per un'ora" is a duration and
	   NekoWhen is what reads those. */
	NSTimeInterval lasts = [NekoWhen secondsIn:question];
	if(lasts <= 0.0 || lasts > 12.0 * 3600.0)
		lasts = NekoAppointmentDefault;

	/* What is left of the sentence once the date and the asking are out of it. */
	NSMutableString *title = [NSMutableString stringWithString:question];
	[title deleteCharactersInRange:[hit range]];
	/* Longest first. Taken in the order they are listed, "añade al calendario"
	   lost its "al calendario" to the shorter phrase and left "añade" sitting in
	   front of the title. */
	NSArray *byLength = [NekoCalendarOpenings() sortedArrayUsingComparator:
		^NSComparisonResult(NSString *a, NSString *b) {
		if([a length] == [b length]) return NSOrderedSame;
		return [a length] > [b length] ? NSOrderedAscending : NSOrderedDescending;
	}];
	for (NSString *opening in byLength) {
		NSRange where = [title rangeOfString:opening options:NSCaseInsensitiveSearch];
		if(where.location != NSNotFound)
			[title deleteCharactersInRange:where];
	}
	NSString *plain = [title stringByTrimmingCharactersInSet:
		[NSCharacterSet characterSetWithCharactersInString:@" \t\n\r,;:.!?-–—"]];
	/* Leading joining words left behind by the cut: "la riunione con Marco". */
	static NSArray *const leading = @[@"la ", @"il ", @"lo ", @"le ",
		@"un ", @"una ", @"the ", @"a ", @"an ", @"per ", @"for ", @"di ", @"of "];
	NSEnumerator *l = [leading objectEnumerator];
	NSString *word;
	while((word = [l nextObject]) != nil)
		if([[plain lowercaseString] hasPrefix:word]) {
			plain = [[plain substringFromIndex:[word length]]
				stringByTrimmingCharactersInSet:
					[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			l = [leading objectEnumerator];       /* and again, "per la riunione" */
		}
	if([plain length] == 0)
		plain = NSLocalizedString(@"Appointment", @"Appointment");

	NSDateFormatter *readable = [[[NSDateFormatter alloc] init] autorelease];
	[readable setDateStyle:NSDateFormatterFullStyle];
	[readable setTimeStyle:NSDateFormatterShortStyle];
	NSDateFormatter *clock = [[[NSDateFormatter alloc] init] autorelease];
	[clock setDateStyle:NSDateFormatterNoStyle];
	[clock setTimeStyle:NSDateFormatterShortStyle];

	NSString *sentence = [NSString stringWithFormat:
		NSLocalizedString(@"%@ to %@ — “%@”. Shall I put it in your calendar?", @"%@ to %@ — “%@”. Shall I put it in your calendar?"),
		[readable stringFromDate:when],
		[clock stringFromDate:[when dateByAddingTimeInterval:lasts]],
		plain];

	return @{@"When": when,
			 @"Ends": [when dateByAddingTimeInterval:lasts],
			 @"Title": plain,
			 @"Sentence": sentence,
			 @"MovedToTomorrow": @(wasBare)};
}

#pragma mark Handing it over

+ (NSString *)stamp:(NSDate *)when
{
	NSDateFormatter *utc = [[[NSDateFormatter alloc] init] autorelease];
	[utc setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
	[utc setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
	[utc setDateFormat:@"yyyyMMdd'T'HHmmss'Z'"];
	return [utc stringFromDate:when];
}

/* Anything that would end a line or a field is taken out rather than escaped:
   this is a title somebody typed, and a calendar file is not the place to find
   out what happens to a stray newline. */
+ (NSString *)safe:(NSString *)text
{
	NSString *plain = [text stringByReplacingOccurrencesOfString:@"\\" withString:@""];
	plain = [plain stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
	plain = [plain stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
	plain = [plain stringByReplacingOccurrencesOfString:@";" withString:@" "];
	plain = [plain stringByReplacingOccurrencesOfString:@"," withString:@" "];
	return [plain length] > 200 ? [plain substringToIndex:200] : plain;
}

+ (NSString *)calendarFileFor:(NSDictionary *)appointment
{
	NSDate *when = [appointment objectForKey:@"When"];
	NSDate *ends = [appointment objectForKey:@"Ends"];
	if(when == nil || ends == nil)
		return @"";
	return [NSString stringWithFormat:
		@"BEGIN:VCALENDAR\r\n"
		@"VERSION:2.0\r\n"
		@"PRODID:-//Neko//a cat on somebody's desktop//EN\r\n"
		@"CALSCALE:GREGORIAN\r\n"
		@"BEGIN:VEVENT\r\n"
		@"UID:%@@neko.local\r\n"
		@"DTSTAMP:%@\r\n"
		@"DTSTART:%@\r\n"
		@"DTEND:%@\r\n"
		@"SUMMARY:%@\r\n"
		@"END:VEVENT\r\n"
		@"END:VCALENDAR\r\n",
		[[NSUUID UUID] UUIDString], [self stamp:[NSDate date]],
		[self stamp:when], [self stamp:ends],
		[self safe:[appointment objectForKey:@"Title"]]];
}

+ (NSString *)make:(NSDictionary *)appointment
{
	NSString *body = [self calendarFileFor:appointment];
	if([body length] == 0)
		return NSLocalizedString(@"That did not work.", @"That did not work.");

	/* In this application's own folder, beside the diary, and named after the
	   thing so that somebody who goes looking knows what they are looking at. */
	NSURL *file = [[[NekoMemory sharedMemory] directory]
		URLByAppendingPathComponent:@"appuntamento.ics"];
	NSError *problem = nil;
	if(![body writeToURL:file atomically:YES
	            encoding:NSUTF8StringEncoding error:&problem])
		return NSLocalizedString(@"That did not work.", @"That did not work.");

	if(![[NSWorkspace sharedWorkspace] openURL:file])
		return NSLocalizedString(@"That did not work.", @"That did not work.");

	[[NekoMemory sharedMemory] noteNoticed:[NSString stringWithFormat:
		@"handed the calendar an appointment: %@",
		[appointment objectForKey:@"Title"]]];
	return NSLocalizedString(@"It is in front of your calendar — press Add there.", @"It is in front of your calendar — press Add there.");
}

@end
