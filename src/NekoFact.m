#import "NekoFact.h"
#import "NekoMemory.h"

/* Forty, which is more than anybody will tell a cat on purpose and few enough
   that the block handed to a model stays a block. Past it the oldest goes, and
   the diary records that it went — silently dropping the oldest is what the
   memory used to do before 2.4 and it was wrong then too. */
static const NSUInteger NekoFactsKept = 40;

/* The openings that mean "keep this". Each one is followed by the thing itself,
   and each is a whole phrase somebody says on purpose — not a word that might
   turn up in passing. "Ricordami di" is deliberately absent: that is a reminder,
   which is the timer's job, and the difference between "ricordati **che**" and
   "ricordami **di**" is exactly the difference between a fact and an errand. */
static NSArray *NekoKeepOpenings(void)
{
	static NSArray *const openings =
	@[@"ricordati che ", @"ricorda che ", @"tieni presente che ",
	  @"segnati che ", @"non dimenticare che ",
	  @"remember that ", @"remember i ", @"remember my ", @"keep in mind that ",
	  @"note that i ", @"don't forget that ",
	  @"souviens-toi que ", @"rappelle-toi que ", @"n'oublie pas que ",
	  @"recuerda que ", @"ten en cuenta que ", @"no olvides que "];
	
	return openings;
}

static NSArray *NekoForgetOpenings(void)
{
	static NSArray *const openings =
	@[@"dimentica ", @"dimenticati ", @"scordati ", @"non ricordare ",
	  @"forget ", @"forget about ",
	  @"oublie ", @"olvida ", @"olvídate de "];
	
	return openings;
}

static NSArray *NekoNameOpenings(void)
{
	static NSArray *const openings =
	@[@"mi chiamo ", @"il mio nome è ",
	  @"my name is ", @"i'm called ", @"call me ",
	  @"je m'appelle ", @"mon nom est ",
	  @"me llamo ", @"mi nombre es "];
	
	return openings;
}

@implementation NekoFact

+ (NSURL *)file
{
	return [[[NekoMemory sharedMemory] directory]
		URLByAppendingPathComponent:@"facts.txt"];
}

+ (NSArray *)lines
{
	NSString *body = [NSString stringWithContentsOfURL:[self file]
	                                          encoding:NSUTF8StringEncoding error:NULL];
	if([body length] == 0)
		return [NSArray array];
	NSMutableArray *kept = [NSMutableArray array];
	NSEnumerator *e = [[body componentsSeparatedByString:@"\n"] objectEnumerator];
	NSString *line;
	while((line = [e nextObject]) != nil)
		if([[line stringByTrimmingCharactersInSet:
		        [NSCharacterSet whitespaceCharacterSet]] length] > 0)
			[kept addObject:line];
	return kept;
}

+ (void)write:(NSArray *)lines
{
	[[lines componentsJoinedByString:@"\n"] writeToURL:[self file] atomically:YES
	                                          encoding:NSUTF8StringEncoding error:NULL];
}

/* A line is "2026-08-30\tthe thing itself". */
+ (NSString *)thingIn:(NSString *)line
{
	NSRange tab = [line rangeOfString:@"\t"];
	return tab.location == NSNotFound ? line
		: [line substringFromIndex:NSMaxRange(tab)];
}

+ (NSArray *)all
{
	NSMutableArray *things = [NSMutableArray array];
	NSEnumerator *e = [[self lines] objectEnumerator];
	NSString *line;
	while((line = [e nextObject]) != nil)
		[things addObject:[self thingIn:line]];
	return things;
}

+ (void)forgetEverything
{
	[[NSFileManager defaultManager] removeItemAtURL:[self file] error:NULL];
}

#pragma mark Hearing it

/* The rest of the sentence after an opening, tidied of the punctuation somebody
   ends a sentence with and of a leading "che" that survives some phrasings. */
+ (NSString *)restOf:(NSString *)said after:(NSRange)opening
{
	NSString *rest = [[said substringFromIndex:NSMaxRange(opening)]
		stringByTrimmingCharactersInSet:
			[NSCharacterSet characterSetWithCharactersInString:@" \t\n\r.!?;:,"]];
	return rest;
}

+ (NSDictionary *)wantedFor:(NSString *)question
{
	if([question length] == 0)
		return nil;
	NSString *said = [question lowercaseString];

	/* Longest opening first, so that "non dimenticare che" is not read as the
	   shorter "dimentica" hiding inside a different sentence. */
	struct { NSArray *openings; NSString *kind; } kinds[] = {
		{ NekoKeepOpenings(), @"keep" },
		{ NekoNameOpenings(), @"name" },
		{ NekoForgetOpenings(), @"forget" },
	};
	NSString *bestKind = nil, *bestThing = nil;
	NSUInteger longest = 0;
	NSUInteger k;
	for(k = 0; k < 3; k++) {
		NSEnumerator *e = [kinds[k].openings objectEnumerator];
		NSString *opening;
		while((opening = [e nextObject]) != nil) {
			NSRange where = [said rangeOfString:opening];
			/* At the start, or just after something like "senti," — but not
			   buried in the middle of a longer sentence, where it is being
			   talked about rather than said. */
			if(where.location == NSNotFound || where.location > 12)
				continue;
			if([opening length] <= longest)
				continue;
			NSString *thing = [self restOf:question after:where];
			if([thing length] < 2)
				continue;
			longest = [opening length];
			bestKind = kinds[k].kind;
			bestThing = thing;
		}
	}
	if(bestKind == nil)
		return nil;

	return [NSDictionary dictionaryWithObjectsAndKeys:
		bestThing, @"What", bestKind, @"Kind", nil];
}

#pragma mark Doing it

+ (NSString *)act:(NSDictionary *)wanted
{
	NSString *kind = [wanted objectForKey:@"Kind"];
	NSString *thing = [wanted objectForKey:@"What"];
	if([kind length] == 0 || [thing length] == 0)
		return @"";

	if([kind isEqualToString:@"forget"]) {
		NSMutableArray *kept = [NSMutableArray array];
		NSUInteger gone = 0;
		NSEnumerator *e = [[self lines] objectEnumerator];
		NSString *line;
		while((line = [e nextObject]) != nil) {
			if([[self thingIn:line] rangeOfString:thing
			                              options:NSCaseInsensitiveSearch].location
			   != NSNotFound)
				gone++;
			else
				[kept addObject:line];
		}
		[self write:kept];
		return gone > 0
			? [NSString stringWithFormat:
				NSLocalizedString(@"Forgotten: %@", @"Forgotten: %@"), thing]
			: NSLocalizedString(@"I was not remembering that.", @"I was not remembering that.");
	}

	NSString *keeping = [kind isEqualToString:@"name"]
		? [NSString stringWithFormat:NSLocalizedString(@"they are called %@", @"they are called %@"), thing]
		: thing;

	NSMutableArray *lines = [NSMutableArray arrayWithArray:[self lines]];
	/* The same thing twice is one thing, and the newer wording wins — somebody
	   correcting themselves is the commonest reason to say it again. */
	NSMutableArray *without = [NSMutableArray array];
	NSEnumerator *e = [lines objectEnumerator];
	NSString *line;
	while((line = [e nextObject]) != nil) {
		NSString *had = [self thingIn:line];
		if([had caseInsensitiveCompare:keeping] == NSOrderedSame)
			continue;
		/* A name replaces a name rather than sitting beside it. */
		if([kind isEqualToString:@"name"]
		   && [had hasPrefix:[NSLocalizedString(@"they are called %@", @"they are called %@")
		        substringToIndex:[NSLocalizedString(@"they are called %@", @"they are called %@") length] - 2]])
			continue;
		[without addObject:line];
	}
	lines = without;

	NSDateFormatter *day = [[[NSDateFormatter alloc] init] autorelease];
	[day setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
	[day setDateFormat:@"yyyy-MM-dd"];
	[lines addObject:[NSString stringWithFormat:@"%@\t%@",
		[day stringFromDate:[NSDate date]], keeping]];

	while([lines count] > NekoFactsKept) {
		NSString *dropped = [self thingIn:[lines objectAtIndex:0]];
		[lines removeObjectAtIndex:0];
		/* Said in the diary rather than out loud: it is housekeeping, and the
		   one thing it must not be is silent. */
		[[NekoMemory sharedMemory] noteNoticed:[NSString stringWithFormat:
			@"forgot the oldest thing it was asked to remember: %@", dropped]];
	}
	[self write:lines];

	return [kind isEqualToString:@"name"]
		? [NSString stringWithFormat:NSLocalizedString(@"Hello, %@.", @"Hello, %@."), thing]
		: NSLocalizedString(@"I will remember that.", @"things it was told to remember");
}

@end
