#import "NekoWords.h"
#import "NekoMemory.h"
#import "NekoRecall.h"
#import "NekoBrains.h"
#import "NekoAsk.h"
#import "NekoAnswerProvider.h"

/* How many of the diary's words are offered at once. Measured: twenty candidates
   answered in half a second and forty in under a second, and past that the small
   models start answering with the list rather than about it. */
static const NSUInteger NekoWordsCandidates = 40;

/* And how long after a missed question the asking happens, if nothing else is
   going on. Long enough that the answer somebody is waiting for has the engine
   to itself. */
static const NSTimeInterval NekoWordsAfter = 20.0;

/* A ceiling, so a month of questions about things not in the diary cannot turn
   a text file into a dictionary. */
static const NSUInteger NekoWordsMost = 300;

@implementation NekoWords

+ (NekoWords *)sharedWords
{
	static NekoWords *shared = nil;
	if(shared == nil)
		shared = [[NekoWords alloc] init];
	return shared;
}

- (id)init
{
	if((self = [super init]) != nil) {
		table = [[NSMutableDictionary alloc] init];
		waiting = [[NSMutableArray alloc] init];
		[self read];
	}
	return self;
}

- (void)dealloc
{
	[later invalidate];
}

#pragma mark The file

- (NSURL *)file
{
	return [[[NekoMemory sharedMemory] directory]
		URLByAppendingPathComponent:@"synonyms.txt"];
}

- (void)read
{
	NSString *text = [NSString stringWithContentsOfURL:[self file]
	                                          encoding:NSUTF8StringEncoding error:NULL];
	for(NSString *line in [text componentsSeparatedByString:@"\n"]) {
		if([line hasPrefix:@"#"])
			continue;
		NSRange colon = [line rangeOfString:@":"];
		if(colon.location == NSNotFound)
			continue;
		NSString *word = [[line substringToIndex:colon.location]
			stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceCharacterSet]];
		NSString *rest = [[line substringFromIndex:NSMaxRange(colon)]
			stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceCharacterSet]];
		if([word length] == 0)
			continue;
		NSMutableArray *means = [NSMutableArray array];
		NSEnumerator *parts = [[rest componentsSeparatedByString:@","] objectEnumerator];
		for(__strong NSString *part in parts) {
			part = [[part stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
			if([part length] > 0)
				[means addObject:part];
		}
		[table setObject:means forKey:[word lowercaseString]];
	}
}

- (void)write
{
	NSMutableString *text = [NSMutableString stringWithString:
		@"# The words this Mac has worked out mean the same as each other, in the\n"
		@"# diary's own vocabulary. Delete a line you disagree with; it is read\n"
		@"# again next time. A word with nothing after it was asked about once and\n"
		@"# nothing was found, and is not asked about again.\n"];
	NSArray *words = [[table allKeys] sortedArrayUsingSelector:@selector(compare:)];
	for(NSString *word in words)
		[text appendFormat:@"%@: %@\n", word,
			[[table objectForKey:word] componentsJoinedByString:@", "]];
	[text writeToURL:[self file] atomically:YES
	        encoding:NSUTF8StringEncoding error:NULL];
}

- (NSDictionary *)table
{
	return table;
}

- (void)forgetEverything
{
	[table removeAllObjects];
	[waiting removeAllObjects];
	[[NSFileManager defaultManager] removeItemAtURL:[self file] error:NULL];
}

#pragma mark What is worth asking about

/* The one word in a question most likely to be the reason nothing was found: the
   heaviest word of substance that the diary does not already use and that has not
   been asked about before. */
- (NSString *)wordWorthAsking:(NSString *)question among:(NSArray<NSString*> *)vocabulary
{
	NSDictionary<NSString*,NSNumber*> *asked = [NekoRecall askedIn:question];
	NSSet<NSString*> *known = [NSSet setWithArray:vocabulary];

	/* Two words of substance, at least. One is not a shortage of vocabulary, it
	   is a short sentence — and the tagger is fallible in exactly that case:
	   measured, NLTagger reads the "stai" of "come stai?" as a **noun** with the
	   full weight of one, which would have spent a model call on a greeting. */
	NSUInteger substantial = 0;
	for(NSString *each in asked)
		if([[asked objectForKey:each] doubleValue] >= 0.8)
			substantial++;
	if(substantial < 2)
		return nil;

	NSString *best = nil;
	double bestWeight = 0.0;
	for(NSString *word in asked) {
		if([table objectForKey:word] != nil)
			continue;                       /* asked about once already */
		if([known containsObject:word])
			continue;                       /* the diary uses this word itself */
		if([word length] < 4)
			continue;
		double weight = [[asked objectForKey:word] doubleValue];
		/* Ties broken by length, which is nothing but a way of always picking
		   the same one: a question with two nouns it does not know gets the
		   other one next time, since this one will be in the file by then. */
		if(weight > bestWeight
		   || (weight == bestWeight && [word length] > [best length])) {
			bestWeight = weight;
			best = word;
		}
	}
	/* Only a noun or an adjective. A question is carried by its verbs and they
	   are not what it is about — the same rule NekoRecall scores by. */
	return bestWeight >= 0.8 ? best : nil;
}

- (void)missedOn:(NSString *)question
{
	if([table count] >= NekoWordsMost || [waiting count] >= 4)
		return;
	if([NekoBrains bestOnDeviceProvider] == nil)
		return;                              /* nothing on this Mac to ask */
	/* Only the question is kept. Which word in it is worth a model call needs
	   the diary's vocabulary, and working that out costs a tagger pass over the
	   month — which is not something to do while somebody waits for an answer. */
	if(![waiting containsObject:question])
		[waiting addObject:question];
	[self askLater];
}

- (void)askLater
{
	if(later != nil)
		return;
	later = [NSTimer scheduledTimerWithTimeInterval:NekoWordsAfter
	                                         target:self
	                                       selector:@selector(askOneNow:)
	                                       userInfo:nil
	                                        repeats:NO];
}

- (void)askOneNow:(NSTimer *)timer
{
	later = nil;
	if(asking || [waiting count] == 0)
		return;
	/* Never while somebody is waiting for an answer: there is one engine and the
	   question in front of the person comes first. */
	if([[NekoAsk sharedAsk] isBusy]) {
		[self askLater];
		return;
	}
	NSString *question = [waiting objectAtIndex:0];
	[waiting removeObjectAtIndex:0];

	NSArray *vocabulary = [[NekoMemory sharedMemory] vocabularyOfSubstance];
	NSString *word = [self wordWorthAsking:question among:vocabulary];
	if(word == nil) {
		if([waiting count] > 0)
			[self askLater];
		return;
	}
	[self askAbout:word among:vocabulary then:^(BOOL learned) {
		if([waiting count] > 0)
			[self askLater];
	}];
}

#pragma mark Asking

/* The candidates, rarest first: a word in every line of the diary says nothing
   about which line, so it is no use as a synonym either. */
- (NSArray<NSString*> *)candidatesFrom:(NSArray<NSString*> *)vocabulary without:(NSString *)word
{
	NSMutableArray *worth = [NSMutableArray array];
	for(NSString *one in vocabulary)
		if([one length] >= 4 && ![one isEqualToString:word]
		   && ![worth containsObject:one])
			[worth addObject:one];
	if([worth count] > NekoWordsCandidates)
		return [worth subarrayWithRange:NSMakeRange(0, NekoWordsCandidates)];
	return worth;
}

- (NSString *)promptFor:(NSString *)word among:(NSArray *)candidates
{
	/* Word for word what tests/words.m measured, so that the nine out of nine in
	   that harness describes what actually ships. The same prompt written in
	   Italian was measured beside it and answered no better — nine of nine and a
	   word more noise — so this stays English like every other prompt here. */
	return [NSString stringWithFormat:
		@"Words: %@\n\nWhich of those words, if any, mean the same thing as "
		@"\"%@\"? Answer with nothing but those words, separated by commas, and "
		@"with NONE if there are none.",
		[candidates componentsJoinedByString:@", "], word];
}

/* Whatever came back, kept only where it is in the list that was offered. This
   is the guard that makes the whole thing safe: the model cannot introduce a
   word, only pick one. */
- (NSArray<NSString*> *)wordsOf:(NSString *)answer among:(NSArray<NSString*> *)candidates
{
	NSSet *offered = [NSSet setWithArray:candidates];
	NSMutableArray<NSString*> *picked = [NSMutableArray array];
	NSCharacterSet *breaks = [NSCharacterSet
		characterSetWithCharactersInString:@",;\n.·-—\t "];
	NSEnumerator *e = [[[answer lowercaseString]
		componentsSeparatedByCharactersInSet:breaks] objectEnumerator];
	for(__strong NSString *part in e) {
		part = [part stringByTrimmingCharactersInSet:
			[NSCharacterSet punctuationCharacterSet]];
		if([offered containsObject:part] && ![picked containsObject:part]
		   && [picked count] < 3)
			[picked addObject:part];
	}
	return picked;
}

- (void)askAbout:(NSString *)word
           among:(NSArray *)vocabulary
            then:(void (^)(BOOL learned))done
{
	id<NekoAnswerProvider> engine = [NekoBrains bestOnDeviceProvider];
	NSArray *candidates = [self candidatesFrom:vocabulary without:word];
	if(engine == nil || [candidates count] < 4) {
		if(done != nil)
			done(NO);
		return;
	}
	asking = YES;
	[engine askQuestion:[self promptFor:word among:candidates]
	       instructions:@"You match words to other words."
	         completion:^(NSString *answer, NSError *error) {
		asking = NO;
		NSArray *found = [answer length] > 0
			? [self wordsOf:answer among:candidates] : [NSArray array];
		/* Written down either way: a word nothing was found for is a word not
		   worth asking about again. */
		[table setObject:found forKey:word];
		[self write];
		if(done != nil)
			done([found count] > 0);
	}];
}

- (BOOL)learnNowFor:(NSString *)word among:(NSArray *)vocabulary
{
	__block BOOL finished = NO, learned = NO;
	[self askAbout:word among:vocabulary then:^(BOOL got) {
		learned = got;
		finished = YES;
	}];
	NSDate *until = [NSDate dateWithTimeIntervalSinceNow:120.0];
	while(!finished && [until timeIntervalSinceNow] > 0.0)
		[[NSRunLoop currentRunLoop] runUntilDate:
			[NSDate dateWithTimeIntervalSinceNow:0.05]];
	return learned;
}

@end
