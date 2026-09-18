#import "NekoSense.h"
#import "NekoRecall.h"
#import "NekoWhen.h"
#import "NekoAction.h"
#import "NekoVoice.h"
#import "NekoAnswerProvider.h"
#import <NaturalLanguage/NaturalLanguage.h>

/* One sentence, twenty words. Twice that is a model ignoring the brief. */
static const NSUInteger NekoSenseMaxWords = 45;
static const NSUInteger NekoSenseMinLength = 6;

@implementation NekoSense

+ (NSArray *)wordsIn:(NSString *)line
{
	NSMutableCharacterSet *breaks = [[NSCharacterSet
									  whitespaceAndNewlineCharacterSet] mutableCopy];
	[breaks formUnionWithCharacterSet:[NSCharacterSet punctuationCharacterSet]];
	NSMutableArray *words = [NSMutableArray array];
	NSEnumerator *e = [[[line lowercaseString]
		componentsSeparatedByCharactersInSet:breaks] objectEnumerator];
	for(NSString *word in e) {
		if([word length] > 0) {
			[words addObject:word];
		}
	}
	return words;
}

/* "Codice, codice, codice, codice." Three of the same word out of a handful is
   not emphasis, it is a model stuck in a groove. */
+ (BOOL)repeatsItself:(NSArray *)words
{
	NSCountedSet *counted = [NSCountedSet setWithArray:words];
	NSEnumerator *e = [counted objectEnumerator];
	NSString *word;
	while((word = [e nextObject]) != nil) {
		if([word length] < 3)
			continue;                  /* "di", "la", "the" are meant to repeat */
		if([counted countForObject:word] >= 3)
			return YES;
		if([counted countForObject:word] >= 2 && [words count] <= 6)
			return YES;
	}
	return NO;
}

/* The language the interface is in, which is the language the answer was asked
   for twice over. Only judged when there is enough text to judge. */
+ (BOOL)isInTheWrongLanguage:(NSString *)line
{
	if([line length] < 25)
		return NO;
	if(![NLLanguageRecognizer class])
		return NO;
	NSString *wanted = [[[NSBundle mainBundle] preferredLocalizations] firstObject];
	if([wanted length] == 0)
		return NO;
	NLLanguageRecognizer *recognizer = [[NLLanguageRecognizer alloc] init];
	[recognizer processString:line];
	NSString *found = [recognizer dominantLanguage];
	if([found length] == 0)
		return NO;
	NSDictionary *confidence = [recognizer languageHypothesesWithMaximum:3];
	double sure = [[confidence objectForKey:found] doubleValue];
	if(sure < 0.75)
		return NO;                     /* short cat remarks are hard to place */
	return ![[found substringToIndex:2] isEqualToString:
		[wanted substringToIndex:MIN((NSUInteger)2, [wanted length])]];
}

/* A word macOS has never heard of, in the language the app runs in.

   Small models conjugate Italian by inventing the participle: "hai togliuto il
   file" for "hai tolto". The system dictionary catches exactly that, and — tried
   on a page of real output — leaves alone the things that would be false alarms:
   Xcode, Safari, TextEdit, Neko, colloquialisms, dates and numbers all pass. The
   grammar checker was tried too and is not worth having: it accepts "il gatto
   sono andato al mare" without complaint.

   Nonsense that is spelled correctly still gets through. This catches the
   invented word, not the invented thought. */
+ (NSString *)unknownWordIn:(NSString *)line
{
	NSString *language = [[[NSBundle mainBundle] preferredLocalizations] firstObject];
	if([language length] == 0)
		return nil;
	NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
	if(![[checker availableLanguages] containsObject:language])
		return nil;                /* no dictionary, no opinion */

	NSUInteger at = 0;
	while(at < [line length]) {
		NSRange found = [checker checkSpellingOfString:line
		                                   startingAt:at
		                                     language:language
		                                         wrap:NO
		                       inSpellDocumentWithTag:0
		                                    wordCount:NULL];
		if(found.location == NSNotFound || NSMaxRange(found) > [line length])
			return nil;
		NSString *word = [line substringWithRange:found];
		at = NSMaxRange(found);

		/* Anything with a digit or an inner capital is a name, a version or a
		   file, and the dictionary is not the authority on those. */
		if([word rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location
		   != NSNotFound)
			continue;
		if([word length] > 1
		   && [[word substringFromIndex:1] rangeOfCharacterFromSet:
			[NSCharacterSet uppercaseLetterCharacterSet]].location != NSNotFound)
			continue;
		return word;
	}
	return nil;
}

+ (BOOL)isAnExample:(NSString *)line
{
	NSString *plain = [[line lowercaseString] stringByTrimmingCharactersInSet:
		[NSCharacterSet punctuationCharacterSet]];
	NSEnumerator *e = [NekoInstructionExamples() objectEnumerator];
	NSString *example;
	while((example = [e nextObject]) != nil) {
		NSString *other = [[example lowercaseString] stringByTrimmingCharactersInSet:
			[NSCharacterSet punctuationCharacterSet]];
		if([plain isEqualToString:other])
			return YES;
	}
	return NO;
}


#pragma mark What the diary taught this file

/* The clock, read back.

   The suggestion prompt says, in so many words, never to open with the time or
   the date unless it was what was asked. Eight days of real diary say it was
   ignored 22 times in one corpus, so it is a check now and not a request. An
   instruction is not a filter, which this project has now learned twice.

   Precise on purpose: it looks for **the time it is** and **the date it is**,
   not for any time and any date. So "l'orario attuale 10:44" said at 10:44 goes,
   and "alle 18:30 hai la riunione" stays — a remark about something later is a
   remark, and rejecting it would cost more than the failure does. */
+ (BOOL)saysTheTimeItIs:(NSString *)line
{
	NSLocale *locale = [NSLocale localeWithLocaleIdentifier:
		[[[NSBundle mainBundle] preferredLocalizations] firstObject] ?: @"en"];
	NSDate *now = [NSDate date];
	NSMutableArray *saying = [NSMutableArray array];

	NSDateFormatter *clock = [[NSDateFormatter alloc] init];
	[clock setLocale:locale];
	[clock setDateFormat:@"HH:mm"];
	[saying addObject:[clock stringFromDate:now]];
	[clock setDateFormat:@"H:mm"];
	[saying addObject:[clock stringFromDate:now]];
	/* "d MMMM" and the year, but never the weekday on its own: "mercoledì hai la
	   riunione" is about a Wednesday, not about today. */
	[clock setDateFormat:@"d MMMM yyyy"];
	[saying addObject:[clock stringFromDate:now]];
	[clock setDateFormat:@"d MMMM"];
	[saying addObject:[clock stringFromDate:now]];

	NSEnumerator *e = [saying objectEnumerator];
	NSString *said;
	while((said = [e nextObject]) != nil)
		if([said length] >= 4
		   && [line rangeOfString:said options:NSCaseInsensitiveSearch].location
		      != NSNotFound)
			return YES;
	return NO;
}

/* The words of a piece of text that could make a remark about it concrete: its
   nouns and adjectives, plus anything with a digit in it, which is how a program
   name, a version and a count all arrive. */
static NSSet *NekoConcreteWords(NSString *text)
{
	NSMutableSet *words = [NSMutableSet set];
	if([text length] == 0)
		return words;

	NSDictionary *tagged = [NekoRecall askedIn:text];
	NSEnumerator *e = [tagged keyEnumerator];
	NSString *word;
	while((word = [e nextObject]) != nil)
		if([[tagged objectForKey:word] doubleValue] >= 0.8 && [word length] >= 4)
			[words addObject:word];

	/* And the numbers, in both forms, because the desktop summary counts in
	   digits and a cat counts in words. Spelled out by the system rather than
	   from a table: the table this used first stopped at forty-five, and
	   "quarantadue minuti nello stesso file" — about a summary that said 42 —
	   was thrown away for naming nothing. */
	NSNumberFormatter *spelling = [[NSNumberFormatter alloc] init];
	[spelling setLocale:[NSLocale localeWithLocaleIdentifier:
		[[[NSBundle mainBundle] preferredLocalizations] firstObject] ?: @"en"]];
	[spelling setNumberStyle:NSNumberFormatterSpellOutStyle];

	NSMutableArray *found = [NSMutableArray array];
	NSEnumerator *pieces = [[text componentsSeparatedByCharactersInSet:
		[[NSCharacterSet alphanumericCharacterSet] invertedSet]] objectEnumerator];
	NSString *piece;
	while((piece = [pieces nextObject]) != nil)
		if([piece length] > 0)
			[found addObject:[piece lowercaseString]];

	NSEnumerator *each = [found objectEnumerator];
	while((piece = [each nextObject]) != nil) {
		if([piece rangeOfCharacterFromSet:
			[NSCharacterSet decimalDigitCharacterSet]].location != NSNotFound) {
			[words addObject:piece];
			/* 42 also stands for "quarantadue". */
			NSNumber *value = [NSNumber numberWithLongLong:[piece longLongValue]];
			NSString *asWords = [[spelling stringFromNumber:value] lowercaseString];
			NSEnumerator *parts = [[asWords componentsSeparatedByCharactersInSet:
				[[NSCharacterSet alphanumericCharacterSet] invertedSet]]
				objectEnumerator];
			NSString *part;
			while((part = [parts nextObject]) != nil)
				if([part length] >= 3)
					[words addObject:part];
		} else if([piece length] >= 3) {
			/* And "quarantadue" stands for 42. */
			[spelling setNumberStyle:NSNumberFormatterSpellOutStyle];
			NSNumber *value = [spelling numberFromString:piece];
			if(value != nil)
				[words addObject:[value stringValue]];
		}
	}
	return words;
}

/* An explanation of something the cat never saw.

   **This started out wider and was narrowed by its own negative table**, which is
   the outcome docs/personality-roadmap.md named as the thing that would stop this
   stage. The first version threw away any remark that named nothing on the
   screen, and it worked on the failures — and it also threw away *"una pausa ti
   conviene"*, *"sei concentrato"* and *"alle 18:30 hai la riunione"*. A gate that
   silences ordinary advice is worse than the failure it prevents, so it does not
   ship in that shape.

   What is left targets the family that actually filled a real diary, and it is
   the conjunction of two things: the remark **explains** something — *perché*,
   *because*, *parce que*, *porque* — and **nothing it names was in front of it**.
   *"Build lento perché progetto grande"* has no build and no project in anything
   the cat was shown. *"Xcode è lento perché ci lavori da quarantadue minuti"*
   names two things it saw and stays.

   What it therefore does **not** catch, said plainly: a bare invention with no
   explaining word in it — *"test chiatta ancora attivo"* — and a cause carried by
   grammar rather than by a conjunction — *"il progetto è grande e la compilazione
   ne soffre"*. The first is what -alreadySaidToday: is for, since an invention
   that matters gets repeated. The second is not caught by anything here. */
+ (BOOL)explainsSomethingItDidNotSee:(NSString *)line seeing:(NSString *)seen
{
	if([seen length] == 0)
		return NO;                     /* nothing to judge against */

	static NSArray *const because =
	@[@"perché", @"perche", @"poiché", @"poiche", @"siccome", @"dato che",
	  @"visto che", @"because", @"since ", @"parce que", @"puisque",
	  @"porque", @"ya que"];
	
	NSString *text = [line lowercaseString];
	BOOL explains = NO;
	for(NSString *word in because)
		if([text rangeOfString:word].location != NSNotFound) {
			explains = YES;
			break;
		}
	if(!explains)
		return NO;

	NSSet *mine = NekoConcreteWords(line);
	if([mine count] == 0)
		return YES;
	NSMutableSet *shared = [mine mutableCopy];
	[shared intersectSet:NekoConcreteWords(seen)];
	return [shared count] == 0;
}

/* A reproach. Völkel's fourth factor, *Unstable*, has **faultfinding** in it, and
   a desktop companion that tells somebody what they should have done is the one
   thing on that list nobody would keep. A closed list, four languages, and it
   only looks for the constructions that carry blame rather than for advice —
   "ti conviene una pausa" is advice and stays. */
+ (BOOL)isAReproach:(NSString *)line
{
	static NSArray *const blaming =
	@[
		/* Italian */
		@"dovresti", @"avresti dovuto", @"non dovresti", @"avresti potuto",
		@"hai sbagliato", @"è colpa tua", @"te l'avevo detto",
		/* English */
		@"you should have", @"you shouldn't have", @"you ought to have",
		@"your fault", @"i told you so", @"you were wrong",
		/* French */
		@"tu aurais dû", @"tu devrais", @"c'est ta faute",
		/* Spanish */
		@"deberías", @"deberías haber", @"es tu culpa", @"te lo dije",
	];
	
	NSString *text = [line lowercaseString];
	for(NSString *one in blaming)
		if([text rangeOfString:one].location != NSNotFound)
			return YES;
	return NO;
}

/* Two more of Völkel's descriptors were considered and are **not** here, said
   out loud rather than quietly skipped:

   *superficial* — a cause asserted with no evidence for it, which is the second
   half of "build lento **perché progetto grande**". Everything tried for it
   either caught ordinary remarks or caught nothing: a cause can be right without
   anything on the screen supporting it, and this file cannot tell which. What
   -namesNothingItSaw: catches is the case where the *subject* was invented too,
   which is the version that actually happened.

   *egocentric* — a remark about itself. Italian drops its pronouns, so the
   constructions that would find it are the ones a cat legitimately uses, and
   every rule drafted for it rejected "ti conviene una pausa". Left out for want
   of a check rather than for want of a reason. */

+ (NSString *)problemWith:(NSString *)line
{
	return [self problemWith:line seeing:nil];
}

+ (BOOL)isWorthSaying:(NSString *)line seeing:(NSString *)seen
{
	return [self problemWith:line seeing:seen] == nil;
}

+ (NSString *)problemWith:(NSString *)line seeing:(NSString *)seen
{
	NSString *trimmed = [line stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if([trimmed length] < NekoSenseMinLength)
		return @"too short";
	if([trimmed isEqualToString:@"-"])
		return @"nothing to say";
	/* A remark is generated from what is on somebody's screen, and a line that
	   asks for a deed is the shape an injected instruction would take. Nothing
	   downstream would perform it — only an answer to a question you asked can
	   reach an action, and that one is read back and waits for a yes — but it
	   has no business being shown either, and this is where it is thrown away. */
	if([NekoAction looksLikeAnAction:trimmed])
		return @"a deed, in something nobody asked for";
	NSArray *words = [self wordsIn:trimmed];
	if([words count] > NekoSenseMaxWords)
		return @"a paragraph, not a sentence";
	if([self repeatsItself:words])
		return @"the same word over and over";
	if([self isAnExample:trimmed])
		return @"one of the examples, handed back";
	if([self saysTheTimeItIs:trimmed])
		return @"the clock, read back";
	if([self isAReproach:trimmed])
		return @"a reproach";
	if([self explainsSomethingItDidNotSee:trimmed seeing:seen])
		return @"an explanation of nothing it saw";
	if([self isInTheWrongLanguage:trimmed])
		return @"the wrong language";
	if([NekoVoice claimsAFeeling:trimmed])
		return @"a feeling it does not have";
	if([NekoVoice isNothingButFlattery:trimmed])
		return @"a compliment with nothing behind it";
	if([NekoVoice saysItTwice:trimmed])
		return @"the same thing twice";
	NSString *invented = [self unknownWordIn:trimmed];
	if(invented != nil)
		return [NSString stringWithFormat:@"a word that does not exist: %@", invented];
	return nil;
}

+ (BOOL)isWorthSaying:(NSString *)line
{
	return [self problemWith:line] == nil;
}

@end
