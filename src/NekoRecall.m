#import "NekoRecall.h"
#import <NaturalLanguage/NaturalLanguage.h>

/*! Below this a line is not about the question, it merely shares a word with it.
   Measured in tests/recall.m: the lines that ought to be found score well above
   it, and a hundred questions about nothing at all stay under. */
static const double NekoRecallFloor = 1.0;

/*! A word heavy enough to be what a question is about rather than how it is
   asked. Nouns, names, numbers and adjectives clear it on their class alone. */
static const double NekoRecallSubstance = 0.8;

/*! The verbs and question words a language carries a question with, in the four
   this application speaks. They are why "quanto fa sette per otto?" used to
   recall "che tempo fa a Roma?" — one shared "fare" and nothing else.

   A list rather than rarity, because rarity cannot know: in a diary of three days
   "essere" is a rare word, and a diary of three days is what somebody has on
   their first Wednesday. Distinctive verbs are not here on purpose — "ascoltare",
   "staccare", "firmare" are what a question is about, and a rule that threw away
   every verb threw those away too, which cost three of ten. */
static NSSet *NekoCarryingWords(void)
{
	static NSSet *words = nil;
	if(words == nil)
		words = [NSSet setWithObjects:
			/* Italian */
			@"essere", @"avere", @"fare", @"dire", @"stare", @"dare", @"andare",
			@"venire", @"potere", @"volere", @"dovere", @"sapere", @"cosa",
			@"come", @"quando", @"quanto", @"quale", @"dove", @"perché", @"chi",
			/* English */
			@"the", @"and", @"have", @"has", @"had", @"was", @"were", @"been",
			@"being", @"does", @"did", @"say", @"said", @"tell", @"told",
			@"what", @"when", @"where", @"which", @"who", @"why", @"how",
			/* French */
			@"être", @"avoir", @"faire", @"dire", @"aller", @"venir", @"pouvoir",
			@"vouloir", @"devoir", @"savoir", @"quoi", @"quand", @"comment",
			@"combien", @"quel", @"où", @"pourquoi", @"qui",
			/* Spanish */
			@"ser", @"estar", @"haber", @"hacer", @"decir", @"ir", @"venir",
			@"poder", @"querer", @"deber", @"saber", @"qué", @"cuándo", @"cómo",
			@"cuánto", @"cuál", @"dónde", @"por", @"quién", nil];
	return words;
}

/* A question is about its nouns. Everything else is how the question is carried. */
static double NekoWeightForClass(NLTag tag)
{
	if([tag isEqualToString:NLTagNoun] || [tag isEqualToString:NLTagPersonalName]
	   || [tag isEqualToString:NLTagPlaceName]
	   || [tag isEqualToString:NLTagOrganizationName]
	   || [tag isEqualToString:NLTagOtherWord])
		return 1.0;
	if([tag isEqualToString:NLTagAdjective] || [tag isEqualToString:NLTagNumber])
		return 0.8;
	if([tag isEqualToString:NLTagVerb] || [tag isEqualToString:NLTagAdverb])
		return 0.35;
	return 0.0;
}

@implementation NekoRecall

+ (double)floor { return NekoRecallFloor; }

+ (NSArray *)wordsOf:(NSString *)text
{
	if([text length] == 0)
		return [NSArray array];
	NLTagger *tagger = [[NLTagger alloc] initWithTagSchemes:@[NLTagSchemeLemma]];
	[tagger setString:text];
	NSMutableArray *words = [NSMutableArray array];
	[tagger enumerateTagsInRange:NSMakeRange(0, [text length])
	                        unit:NLTokenUnitWord
	                      scheme:NLTagSchemeLemma
	                     options:NLTaggerOmitPunctuation | NLTaggerOmitWhitespace
	                  usingBlock:^(NLTag tag, NSRange range, BOOL *stop) {
		/* The lemma when the tagger has one, the word as written when it does
		   not — which is what happens to names, and names are worth keeping. */
		NSString *word = [tag length] > 0 ? [tag lowercaseString]
			: [[text substringWithRange:range] lowercaseString];
		if([word length] >= 3)
			[words addObject:word];
	}];
	return words;
}

+ (NSDictionary *)askedIn:(NSString *)question
{
	if([question length] == 0)
		return [NSDictionary dictionary];
	NLTagger *tagger = [[NLTagger alloc] initWithTagSchemes:
						@[NLTagSchemeLemma, NLTagSchemeLexicalClass]];
	[tagger setString:question];
	NSMutableDictionary *asked = [NSMutableDictionary dictionary];
	[tagger enumerateTagsInRange:NSMakeRange(0, [question length])
	                        unit:NLTokenUnitWord
	                      scheme:NLTagSchemeLexicalClass
	                     options:NLTaggerOmitPunctuation | NLTaggerOmitWhitespace
	                  usingBlock:^(NLTag tag, NSRange range, BOOL *stop) {
		double weight = NekoWeightForClass(tag);
		if(weight == 0.0)
			return;
		NLTag lemma = [tagger tagAtIndex:range.location unit:NLTokenUnitWord
		                          scheme:NLTagSchemeLemma tokenRange:NULL];
		NSString *word = [lemma length] > 0 ? [lemma lowercaseString]
			: [[question substringWithRange:range] lowercaseString];
		if([word length] < 3)
			return;
		/* The same word twice in one question is one word, and the heavier
		   reading of it wins. */
		double already = [[asked objectForKey:word] doubleValue];
		if(weight > already)
			[asked setObject:[NSNumber numberWithDouble:weight] forKey:word];
	}];
	return asked;
}

/* What a word borrowed from somebody's own vocabulary is worth against the word
   they actually used. Below one, always: a line with the real word in it must
   never lose to a line with its synonym. */
static const double NekoRecallBorrowed = 0.7;

+ (NSDictionary *)askedIn:(NSString *)question widenedBy:(NSDictionary *)synonyms
{
	NSDictionary *asked = [self askedIn:question];
	if([synonyms count] == 0 || [asked count] == 0)
		return asked;
	NSMutableDictionary *wider = [NSMutableDictionary dictionaryWithDictionary:asked];
	NSEnumerator *e = [asked keyEnumerator];
	NSString *word;
	while((word = [e nextObject]) != nil) {
		NSEnumerator *means = [[synonyms objectForKey:word] objectEnumerator];
		NSString *other;
		while((other = [means nextObject]) != nil) {
			double borrowed = [[asked objectForKey:word] doubleValue] * NekoRecallBorrowed;
			/* Never over the word somebody actually said, if they said both. */
			if([[wider objectForKey:other] doubleValue] < borrowed)
				[wider setObject:[NSNumber numberWithDouble:borrowed] forKey:other];
		}
	}
	return wider;
}

+ (NSDictionary *)rarityAcross:(NSArray *)lines
{
	NSMutableDictionary *seenIn = [NSMutableDictionary dictionary];
	NSEnumerator *e = [lines objectEnumerator];
	NSString *line;
	while((line = [e nextObject]) != nil) {
		NSEnumerator *w = [[NSSet setWithArray:[self wordsOf:line]] objectEnumerator];
		NSString *word;
		while((word = [w nextObject]) != nil)
			[seenIn setObject:[NSNumber numberWithInteger:
				[[seenIn objectForKey:word] integerValue] + 1] forKey:word];
	}

	NSMutableDictionary *rarity = [NSMutableDictionary dictionary];
	double total = (double)[lines count];
	NSEnumerator *k = [seenIn keyEnumerator];
	NSString *word;
	while((word = [k nextObject]) != nil)
		[rarity setObject:[NSNumber numberWithDouble:
			log(1.0 + total / (double)[[seenIn objectForKey:word] integerValue])]
		           forKey:word];
	return rarity;
}

+ (NSArray *)wordSetsFor:(NSArray *)lines
{
	NSMutableArray *sets = [NSMutableArray array];
	NSEnumerator *e = [lines objectEnumerator];
	NSString *line;
	while((line = [e nextObject]) != nil)
		[sets addObject:[NSSet setWithArray:[self wordsOf:line]]];
	return sets;
}

+ (double)scoreOf:(NSString *)line asked:(NSDictionary *)asked
           rarity:(NSDictionary *)rarity
{
	return [self scoreOfWords:[NSSet setWithArray:[self wordsOf:line]]
	                    asked:asked rarity:rarity];
}

+ (double)scoreOfWords:(NSSet *)has asked:(NSDictionary *)asked
                rarity:(NSDictionary *)rarity
{
	double score = 0.0;
	BOOL substantial = NO;
	NSEnumerator *e = [asked keyEnumerator];
	NSString *word;
	while((word = [e nextObject]) != nil) {
		if(![has containsObject:word])
			continue;
		double weight = [[asked objectForKey:word] doubleValue];
		if(![NekoCarryingWords() containsObject:word]
		   && (weight >= NekoRecallSubstance || weight > 0.0))
			substantial = YES;
		/* A word the corpus has never seen is as rare as a word can be: it was
		   asked and it is here, and that is the whole of what is known. */
		NSNumber *rare = [rarity objectForKey:word];
		score += weight * (rare != nil ? [rare doubleValue] : 1.0);
	}
	/* Sharing only the words a question is carried with is not being about
	   something. This is what stopped "quanto fa sette per otto?" recalling "che
	   tempo fa a Roma?", which shared "fare" and nothing else. */
	return substantial ? score : 0.0;
}

+ (NSArray *)linesIn:(NSArray *)lines
               about:(NSString *)question
               limit:(NSUInteger)limit
              rarity:(NSDictionary *)rarity
{
	return [self linesIn:lines words:[self wordSetsFor:lines]
	               about:question limit:limit rarity:rarity];
}

+ (NSArray *)linesIn:(NSArray *)lines
               words:(NSArray *)sets
               about:(NSString *)question
               limit:(NSUInteger)limit
              rarity:(NSDictionary *)rarity
{
	return [self linesIn:lines words:sets about:question limit:limit
	              rarity:rarity synonyms:nil];
}

+ (NSArray *)linesIn:(NSArray *)lines
               words:(NSArray *)sets
               about:(NSString *)question
               limit:(NSUInteger)limit
              rarity:(NSDictionary *)rarity
            synonyms:(NSDictionary *)synonyms
{
	NSDictionary *asked = [self askedIn:question widenedBy:synonyms];
	if([asked count] == 0 || limit == 0 || [sets count] != [lines count])
		return [NSArray array];

	NSMutableArray *scored = [NSMutableArray array];
	NSUInteger i;
	for(i = 0; i < [lines count]; i++) {
		double score = [self scoreOfWords:[sets objectAtIndex:i]
		                            asked:asked rarity:rarity];
		if(score >= NekoRecallFloor)
			[scored addObject:[NSArray arrayWithObjects:
				[NSNumber numberWithDouble:score], [lines objectAtIndex:i], nil]];
	}
	[scored sortUsingComparator:^NSComparisonResult(id a, id b) {
		return [[b objectAtIndex:0] compare:[a objectAtIndex:0]];
	}];

	NSMutableArray *best = [NSMutableArray array];
	for(i = 0; i < [scored count] && [best count] < limit; i++) {
		NSString *found = [[scored objectAtIndex:i] objectAtIndex:1];
		if(![best containsObject:found])       /* the same note on two days is one */
			[best addObject:found];
	}
	return best;
}

@end
