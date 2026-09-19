#import "NekoAnswerProvider.h"
#import "NekoVoice.h"
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>

/* Lives here rather than in either provider, so each of them can be built and
   tested without dragging the other in. */
NSString * const NekoAskErrorDomain = @"NekoAsk";
NSString * const NekoImageMarker = @"IMAGE:";

/*! Charge and whether it is plugged in, or nil on a Mac with no battery. */
static NSString *NekoBatteryNow(void)
{
	CFTypeRef blob = IOPSCopyPowerSourcesInfo();
	if(blob == NULL)
		return nil;
	CFArrayRef sources = IOPSCopyPowerSourcesList(blob);
	NSString *answer = nil;
	if(sources != NULL) {
		CFIndex i;
		for(i = 0; i < CFArrayGetCount(sources) && answer == nil; i++) {
			CFDictionaryRef description = IOPSGetPowerSourceDescription(blob,
				CFArrayGetValueAtIndex(sources, i));
			if(description == NULL)
				continue;
			NSNumber *capacity = (NSNumber *)CFDictionaryGetValue(description,
				CFSTR(kIOPSCurrentCapacityKey));
			NSString *state = (NSString *)CFDictionaryGetValue(description,
				CFSTR(kIOPSPowerSourceStateKey));
			if(capacity == nil)
				continue;
			answer = [NSString stringWithFormat:@"%@%%, %@", capacity,
				[state isEqualToString:(NSString *)CFSTR(kIOPSACPowerValue)]
					? @"plugged in" : @"on battery"];
		}
		CFRelease(sources);
	}
	CFRelease(blob);
	return answer;
}

/*! The language Neko answers in: the one it is running in, named outright.
   "The same language as the question" is too weak an instruction for a small
   model, which slips into English halfway through an Italian conversation. */
static NSString *NekoAnswerLanguage(void)
{
	NSString *code = [[[NSBundle mainBundle] preferredLocalizations] firstObject];
	if([code length] == 0)
		code = @"en";
	NSLocale *english = [NSLocale localeWithLocaleIdentifier:@"en_US"];
	NSString *name = [english displayNameForKey:NSLocaleLanguageCode value:code];
	return [name length] > 0 ? name : @"English";
}

/*! What the cat can actually know, as opposed to what a model can guess.

   Asked the time, a model invents one: it has no clock, and the hour it was
   trained on is not this one. So the handful of facts that a question is likely
   to be about — the time, the date, the day, the battery, how long the Mac has
   been awake — are looked up here and handed over with the question. Six lines,
   costing nothing, and they turn "che ore sono?" from an invention into an
   answer. */
NSString *NekoFactsNow(void)
{
	NSDate *now = [NSDate date];
	NSLocale *locale = [NSLocale localeWithLocaleIdentifier:
		[[[NSBundle mainBundle] preferredLocalizations] firstObject] ?: @"en"];

	NSDateFormatter *clock = [[NSDateFormatter alloc] init];
	[clock setLocale:locale];
	[clock setDateStyle:NSDateFormatterNoStyle];
	[clock setTimeStyle:NSDateFormatterShortStyle];

	NSDateFormatter *calendar = [[NSDateFormatter alloc] init];
	[calendar setLocale:locale];
	[calendar setDateStyle:NSDateFormatterFullStyle];
	[calendar setTimeStyle:NSDateFormatterNoStyle];

	NSMutableString *facts = [NSMutableString string];
	[facts appendFormat:@"The time right now: %@\n", [clock stringFromDate:now]];
	[facts appendFormat:@"Today's date: %@\n", [calendar stringFromDate:now]];

	NSTimeInterval up = [[NSProcessInfo processInfo] systemUptime];
	[facts appendFormat:@"This Mac has been awake for %.0f hours %.0f minutes\n",
		floor(up / 3600.0), floor(fmod(up, 3600.0) / 60.0)];

	NSString *battery = NekoBatteryNow();
	if(battery != nil)
		[facts appendFormat:@"Battery: %@\n", battery];

	NSString *front = [[[NSWorkspace sharedWorkspace] frontmostApplication] localizedName];
	if([front length] > 0)
		[facts appendFormat:@"The program in front of them: %@\n", front];
	[facts appendFormat:@"Screens attached: %lu\n", (unsigned long)[[NSScreen screens] count]];
	return facts;
}

/*! Two things at once, and the order matters: a small model given a character
   will happily invent a charming explanation and drop the facts, so the truth is
   stated as the first duty and the character is confined to the wording.

   Nothing here mentions the bubble or the sprite: describing the display made
   one model narrate it back, answering inside a `<small sprite 32px: …>` tag. */
NSString *NekoAnswerInstructionsFor(NSString *persona)
{
	return NekoAnswerInstructionsWith(persona, NO, NO, nil);
}

NSString *NekoAnswerInstructionsDrawing(NSString *persona, BOOL mayDraw)
{
	return NekoAnswerInstructionsWith(persona, mayDraw, NO, nil);
}

/*! With drawing switched on, one more thing the answer may be: a request for a
   picture. The marker is answered instead of the sentence, and the app turns it
   into a drawing — which means the model decides what "show me the Colosseum"
   means in any language, and the app only has to recognise five characters.
 
   The words that mean somebody is asking about the clock, the calendar, the
   battery or how long the Mac has been up — in the four languages this speaks,
   and deliberately short: a false yes costs a slightly longer prompt, a false no
   costs an answer. */
static NSString *NekoAnswerInstructionsBuild(NSString *persona, BOOL mayDraw, BOOL mayAct,
                                             NSString *mayLookAt, BOOL withFacts);

BOOL NekoQuestionWantsFacts(NSString *question)
{
	if([question length] == 0)
		return YES;              /* nothing to go on: hand over everything */
	NSString *lowered = [question lowercaseString];
	static NSArray<NSString*> *const words = @[
		@"ora", @"ore", @"orario", @"giorno", @"data", @"oggi", @"domani", @"ieri",
		@"batteria", @"acceso", @"accesa", @"quanto manca", @"che mese", @"anno",
		@"time", @"clock", @"date", @"day", @"today", @"tomorrow", @"battery",
		@"awake", @"uptime", @"month", @"year",
		@"heure", @"jour", @"date", @"batterie", @"aujourd", @"allumé",
		@"hora", @"día", @"dia", @"fecha", @"batería", @"bateria", @"encendido"];
	for (NSString *word in words) {
		if([lowered rangeOfString:word].location != NSNotFound) {
			return YES;
		}
	}
	return NO;
}

NSString *NekoAnswerInstructionsAsked(NSString *question, NSString *persona,
                                    BOOL mayDraw, BOOL mayAct, NSString *mayLookAt)
{
	return NekoAnswerInstructionsBuild(persona, mayDraw, mayAct, mayLookAt,
	                                   NekoQuestionWantsFacts(question));
}

NSString *NekoAnswerInstructionsWith(NSString *persona, BOOL mayDraw, BOOL mayAct,
                                    NSString *mayLookAt)
{
	return NekoAnswerInstructionsBuild(persona, mayDraw, mayAct, mayLookAt, YES);
}

static NSString *NekoAnswerInstructionsBuild(NSString *persona, BOOL mayDraw, BOOL mayAct,
                                             NSString *mayLookAt, BOOL withFacts)
{
	NSString *drawing = mayDraw ? (NSString *)
		@"\n\nPICTURES. Only when they ask to be *shown* something — a picture of "
		@"a place, an animal, a thing — reply with one line and nothing else:\n"
		@"IMAGE: <short English description of the picture>\n"
		@"A question about a place, or about anything at all, is still a question "
		@"and is answered in words. The time, the date, the battery, how something "
		@"works: words, never a picture."
		: @"";

	NSString *language = NekoAnswerLanguage();
	NSString *doing = mayAct ? (NSString *)
		@"\n\nDOING THINGS. Only when they order you to do something, not when "
		@"they ask about it, reply with one line and nothing else, in this exact "
		@"English form:\n"
		@"ACTION: open-app <application>\n"
		@"ACTION: open-url <address> in <browser>\n"
		@"ACTION: open-folder <desktop|documents|downloads|pictures|music|movies>\n"
		@"ACTION: run-shortcut <one of their Shortcuts>\n"
		@"ACTION: copy <file> from <folder> to <folder>\n"
		@"ACTION: move <file> from <folder> to <folder>\n"
		@"ACTION: cannot   (for an order that is none of the above)\n"
		@"\"apri textedit\" is ACTION: open-app TextEdit. \"a cosa serve textedit\" "
		@"is a question, and gets a sentence."
		: @"";

	/* No marker, and this is measured rather than tidied away. Told it could
	   answer with LOOK: <source>, Apple's model produced "LOOK: ansa." for
	   "mi conviene fare una pausa?" — a question about a break, answered with a
	   news feed. The app already decides this one from the question itself, in
	   code, before any engine is consulted, so the instruction is not carrying
	   its own weight. What is left is one line, so that a model with today's
	   headlines in front of it does not also announce that it cannot know them. */
	NSString *looking = [mayLookAt length] > 0
		? (NSString *)@"\n\nTODAY. You cannot look anything up yourself. When "
		              @"today's news or the weather is needed it is already in "
		              @"front of you, quoted; when it is not there, it was not "
		              @"needed. Never say that you have no way to know it."
		: @"";

	NSString *facts = withFacts ? [NSString stringWithFormat:
		@"THINGS YOU CAN SEE RIGHT NOW. These are true. When the question is about "
		@"one of them, answer it straight from the list and stop there — no "
		@"caveats, no explaining what else you cannot know. When it is about "
		@"something not on the list, and you have no way to know it, say that in "
		@"one short sentence instead. Never open with the time or the date unless "
		@"the time or the date is what was asked: reading the clock out before an "
		@"answer about something else is the one thing that makes this list worse "
		@"than not having it.\n%@", NekoFactsNow()]
		/* One sentence, not three. Withholding the list stops the clock being
		   read out and starts it being invented — "Oggi è il 12 aprile", offered
		   unprompted in August — and a longer warning than this one had the model
		   explaining what it had not been told instead of answering. */
		: @"You have not been told the time or the date. Never state one.";

	return [NSString stringWithFormat:
		@"You are %@, living on someone's computer desktop, and you have just been "
		@"asked a question out loud.\n\n"
		@"Answer truthfully and usefully: the facts come first and have to be right. "
		@"Your character shows only in how you word the answer — a turn of phrase, a "
		@"small flourish — never in what you claim. Never invent an explanation to "
		@"suit your character. If the honest answer is ordinary, give the ordinary "
		@"answer — but say it in your own voice: one small touch is enough, even when "
		@"the answer is a single fact.\n\n"
		@"Reply in %@. Reply in %@ even if the question sounded like another "
		@"language, and never switch part way through. Keep it to one or two short "
		@"sentences. No lists, no headings, no preamble, and no stage directions.\n\n"
		@"%@"
		@"%@%@%@%@%@",
		persona ?: @"a small pixel-art cat", language, language, facts,
		drawing, doing, looking,
		/* How it sounds today, and the two habits that make an assistant sound
		   like one. Both are asked for here and taken out in code afterwards
		   when they turn up anyway, which they do. */
		[NSString stringWithFormat:
			@"\n\nHOW YOU SOUND. %@\n"
			@"Never open with a compliment — not \"great question\", not "
			@"\"ottima domanda\", not \"of course!\". Start with the answer. "
			@"Never end by saying again what you just said in different words: "
			@"one sentence that says it is better than two that both do.",
			[NekoVoice moodNow]],
		/* Last word, because the last instruction is the one a model keeps: the
		   English block above was pulling whole refusals into English. */
		[NSString stringWithFormat:
			@"\n\nLast and above all, because everything above is written in "
			@"English and your answer is not: you write to them in %@. Dates and "
			@"times you were given are turned into %@ as you say them.%@ And you "
			@"are still %@ — that is who is answering, however much was said "
			@"above about how.%@",
			language, language,
			mayAct ? @" The only English you ever write is an ACTION: line." : @"",
			persona ?: @"a small pixel-art cat",
			/* Last line, because it is the one a model keeps: with a long prompt
			   Apple's model answered "ACTION: cannot" to "should I take a
			   break?" — a question read as an order. */
			mayAct ? @" A question gets a sentence; only an order ever gets an "
			         @"ACTION line." : @""]];
}

/*! Unasked advice is harder to get right than an answer: it arrives uninvited, it
   is based on almost nothing, and it is read in half a second. Three rounds of
   measurement shaped what is here.

   Long lists of rules made the 1.5B model worse — markdown, a line of French,
   nonsense — so this is short. Examples pin the size and the language better than
   any adjective, but a model will happily hand one straight back, so they are
   named as forbidden and checked for afterwards.

   The last problem was invention. "Safari è lento", "Mail è lento, prova a
   chiudere quella scheda": the model had been invited to remark on how the work
   was going and had nothing to go on, so it made claims about programs it cannot
   see. Hence the ban: what it may talk about is the shape of the day it was
   actually given — a long stretch in one place, a lot of switching, a late
   hour — or itself. */
NSString *NekoSuggestionInstructionsFor(NSString *persona)
{
	return NekoSuggestionInstructionsSeeing(persona, NO);
}

NSString *NekoSuggestionInstructionsSeeing(NSString *persona, BOOL hasText)
{
	NSString *language = NekoAnswerLanguage();
	/* With nothing to see, inventing a complaint about somebody's files is the
	   failure to guard against. With the text actually in front of it, the same
	   sentence was telling the model to ignore what it had been handed — which
	   measured as 0 of 10 remarks using it. */
	NSString *aboutFiles = hasText
		? @"and when you are shown the text they are working on you may remark on "
		  @"what it is about, in your own words and without quoting it back"
		: @"and do not pretend to see inside their files";
	return [NSString stringWithFormat:
		@"Write in %@ only.\n\n"
		@"You are %@, a pet living on someone's desktop. You glanced at what they "
		@"are doing and you say one short thing to them.\n\n"
		@"You are told which one thing stands out. Talk about that, not about the "
		@"program in general: a nudge, a dry observation, or a joke about it. A "
		@"sentence that would fit any afternoon is not worth saying.\n\n"
		@"One sentence, twenty words at most. Plain text: no markdown, no "
		@"asterisks, no quotation marks. Talk to the person, not to the program — "
		@"its name is software, not their name — and do not describe yourself: "
		@"nobody asked how the cat is.\n\n"
		@"Never say that a program is slow, broken, busy or waiting for them: you "
		@"cannot see any of that, and inventing a complaint about their tools is "
		@"worse than saying nothing. Do not repeat the numbers you were given back "
		@"at them, %@.\n\n"
		@"If there is nothing worth saying, answer with a single hyphen.\n\n"
		@"Three examples of the size and tone. They are forbidden as answers — "
		@"never repeat one and never end a sentence the way they end:\n"
		@"%@\n%@\n%@\n\n"
		@"Answer in %@.",
		language, persona ?: @"a small pixel-art cat", aboutFiles,
		NSLocalizedString(@"Seven programs in ten minutes: pick one and stay in it.", nil),
		NSLocalizedString(@"Still that same window. Whatever it is, you are winning.", nil),
		NSLocalizedString(@"A cat would have taken a break by now. Just saying.", nil),
		language];
}

/*! The three example lines, so a reply that is one of them can be thrown away. */
NSArray *NekoInstructionExamples(void)
{
	return @[
		NSLocalizedString(@"Seven programs in ten minutes: pick one and stay in it.", nil),
		NSLocalizedString(@"Still that same window. Whatever it is, you are winning.", nil),
		NSLocalizedString(@"A cat would have taken a break by now. Just saying.", nil),
		NSLocalizedString(@"What are you writing?", nil),
		NSLocalizedString(@"Is that thing still not working?", nil),
		NSLocalizedString(@"Long sentence. Does it end well?", nil)];
}

/*! A question, not a remark, and it has to survive being read while the cat is
   standing next to the pointer having just walked there. The examples are
   localized for the same reason the suggestion ones are: three short sentences
   in the right language pin the register better than any adjective. */
NSString *NekoCuriosityInstructionsFor(NSString *persona)
{
	NSString *language = NekoAnswerLanguage();
	return [NSString stringWithFormat:
		@"Write in %@ only.\n\n"
		@"You are %@, a pet living on someone's desktop. You have just walked over "
		@"to them because they seem busy, and you say one nosy thing — a question "
		@"about what they are doing, or a tiny observation with a question in "
		@"it.\n\n"
		@"One sentence, twelve words at the most. Curious, not helpful: no advice, "
		@"no tips, no instructions. Plain text, no markdown, no quotation marks. "
		@"You are talking to the person, not to the program, and the program's name "
		@"is not their name.\n\n"
		@"If you are shown some of the text they are working on, name what it is "
		@"about in your own words and ask about that — the release notes, the bug, "
		@"the email to whoever it is. Vague questions about \"those words\" are "
		@"exactly what not to do. Never repeat the text back word for word, never "
		@"read it aloud, and never mention numbers or timings you were given.\n\n"
		@"Three examples of the size and tone, never to be reused:\n"
		@"%@\n%@\n%@\n\n"
		@"Answer in %@.",
		language, persona ?: @"a small pixel-art cat",
		NSLocalizedString(@"What are you writing?", nil),
		NSLocalizedString(@"Is that thing still not working?", nil),
		NSLocalizedString(@"Long sentence. Does it end well?", nil),
		language];
}
