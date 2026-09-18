#import "NekoLocalProvider.h"
#import "NekoModelStore.h"

NSString * const NekoAskLocalModelKey = @"NekoAskLocalModel";

@implementation NekoLocalProvider

+ (id<NekoLocalEngine>)makeEngine
{
	/* Looked up by name so that adding the engine is a matter of compiling one
	   more class in, with nothing here to change. */
	Class engineClass = NSClassFromString(@"NekoLlamaEngine");
	return engineClass != Nil ? [[engineClass alloc] init] : nil;
}

- (id)init
{
	self = [super init];
	if(self != nil)
		loader = dispatch_queue_create("neko.local.loader", DISPATCH_QUEUE_SERIAL);
	return self;
}

- (void)dealloc
{
	if(loader != NULL)
		loader = nil;;
	[engine cancel];
}

- (NSString *)name
{
	return NSLocalizedString(@"A model on this Mac", nil);
}

- (void)setPreferredModel:(NSString *)identifier
{
	if(preferred == identifier)
		return;
	/* Changing model means the loaded one is the wrong one. */
	if(![preferred isEqualToString:identifier]) {
		[engine cancel];
		engine = nil;
	}
	preferred = [identifier copy];
}

- (NSString *)modelIdentifier
{
	NSArray *installed = [[NekoModelStore sharedStore] installedIdentifiers];
	if([preferred length] > 0 && [installed containsObject:preferred])
		return preferred;
	NSString *chosen = [[NSUserDefaults standardUserDefaults]
		stringForKey:NekoAskLocalModelKey];

	/* Picking a model in the menu and never downloading it used to leave the
	   provider unconfigured for ever: questions fell back to the canned reply
	   and the roaming cat went silent, with nothing anywhere saying why. A model
	   that is actually on the disk beats the one that was merely chosen. */
	if([chosen length] > 0 && [installed containsObject:chosen])
		return chosen;
	if([installed count] > 0)
		return [installed firstObject];
	if([chosen length] > 0)
		return chosen;                 /* nothing installed: name the intent */
	NekoLocalModel *first = [[[NekoModelStore sharedStore] catalogue] firstObject];
	return [first identifier];
}

/* What was chosen, whether or not it is here — the preferences need to say
   "using X because Y was never downloaded" rather than quietly swapping. */
- (NSString *)chosenModelIdentifier
{
	return [[NSUserDefaults standardUserDefaults] stringForKey:NekoAskLocalModelKey];
}

- (BOOL)isConfigured
{
	if([NekoLocalProvider makeEngine] == nil)
		return NO;
	return [[NekoModelStore sharedStore]
		installedURLForIdentifier:[self modelIdentifier]] != nil;
}

- (NSString *)configurationHint
{
	if([NekoLocalProvider makeEngine] == nil)
		return NSLocalizedString(@"This build has no local engine yet — the model can be downloaded ready for it", nil);
	if([[NekoModelStore sharedStore] installedURLForIdentifier:[self modelIdentifier]] == nil)
		return NSLocalizedString(@"Download a model first", nil);
	return nil;
}

#pragma mark Asking

- (BOOL)prepareEngine:(NSError **)error
{
	if(engine == nil)
		engine = [NekoLocalProvider makeEngine];
	if(engine == nil)
		return NO;
	if([engine isLoaded])
		return YES;

	NSURL *file = [[NekoModelStore sharedStore]
		installedURLForIdentifier:[self modelIdentifier]];
	if(file == nil)
		return NO;
	return [engine loadModelAtURL:file error:error];
}

- (void)askQuestion:(NSString *)question
       instructions:(NSString *)instructions
         completion:(void (^)(NSString *answer, NSError *error))completion
{
	[self askQuestion:question instructions:instructions partial:NULL completion:completion];
}

/* The tags a reasoning model wraps its notes in. */
static NSArray *NekoReasoningTags(void)
{
	static NSArray * const tags = @[@"think", @"thinking", @"thought", @"reasoning"];
	
	return tags;
}

/* What the model is actually asked, which is not always what was asked.

   Measured, after -withoutReasoning: was already in place: Qwen3.5 4B answered
   "quotazione oggi borsa Apple" with **nothing at all**. The scratchpad was
   taken out and there was nothing behind it — the generation budget is 200
   tokens, small on purpose because a cat says a sentence or two, and a reasoning
   model spends all 200 on its notes and never reaches the answer.

   Raising the budget for those models was the other option and it is the wrong
   one: it would make every answer from them several times slower for notes
   nobody sees. The Qwen family documents a switch instead, and `/no_think` in
   the user turn is it.

   Only for models the catalogue says reason, and only on the way to the engine:
   what somebody said is what is written in the diary and what is read back to
   them, and neither gets this. */
- (NSString *)askedOf:(NSString *)question
{
	return question;
}

/* Room for the notes, and only for the models that write them.

   Five times the ordinary budget, which is what it took to get past 829
   characters of thinking and reach a sentence. It is spent only by a model the
   person chose from a list that says it reasons, and it is not spent by any of
   the other seven. */
static const int NekoLocalThinkingTokens = 1000;

- (void)giveRoomToThink
{
	if(![engine respondsToSelector:@selector(setTokenBudget:)])
		return;
	NekoLocalModel *model = [[NekoModelStore sharedStore]
		modelWithIdentifier:[self modelIdentifier]];
	[engine setTokenBudget:[model thinks] ? NekoLocalThinkingTokens : 0];
}

+ (NSString *)withoutReasoning:(NSString *)text
{
	if([text length] == 0)
		return text;
	NSMutableString *left = [text mutableCopy];

	for(NSString *tag in NekoReasoningTags()) {
		NSString *opens = [NSString stringWithFormat:@"<%@>", tag];
		NSString *closes = [NSString stringWithFormat:@"</%@>", tag];
		for(;;) {
			NSRange from = [left rangeOfString:opens
			                          options:NSCaseInsensitiveSearch];
			if(from.location == NSNotFound)
				break;
			NSRange after = NSMakeRange(NSMaxRange(from),
				[left length] - NSMaxRange(from));
			NSRange to = [left rangeOfString:closes
			                        options:NSCaseInsensitiveSearch range:after];
			if(to.location == NSNotFound) {
				/* Still inside it, or the budget ran out inside it. Everything
				   from here on is more of the same. */
				[left deleteCharactersInRange:
					NSMakeRange(from.location, [left length] - from.location)];
				break;
			}
			[left deleteCharactersInRange:
				NSMakeRange(from.location, NSMaxRange(to) - from.location)];
		}
	}
	return [left stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)askQuestion:(NSString *)question
       instructions:(NSString *)instructions
            partial:(void (^)(NSString *sofar))partial
         completion:(void (^)(NSString *answer, NSError *error))completion
{
	/* Opening a GGUF means reading a gigabyte or two and compiling the Metal
	   kernels: seconds, the first time. Doing that here on the main thread would
	   freeze the whole app — the cat, the bubble, the spinner that is meant to
	   say something is happening — so the load goes to a queue of its own and
	   the question follows it there. */
	/* Everything the engine says goes through -withoutReasoning: on the way out,
	   so no caller has to remember. A partial that is *entirely* scratchpad is
	   not forwarded at all: an empty bubble flashing while the model thinks is
	   worse than the spinner it would replace. */
	void (^partialCopy)(NSString *) = nil;
	if(partial != NULL) {
		void (^caller)(NSString *) = [partial copy];
		partialCopy = [^(NSString *sofar) {
			NSString *shown = [NekoLocalProvider withoutReasoning:sofar];
			if([shown length] > 0)
				caller(shown);
		} copy];
	}
	void (^callerDone)(NSString *, NSError *) = [completion copy];
	void (^completionCopy)(NSString *, NSError *) =
		[^(NSString *answer, NSError *error) {
		callerDone([NekoLocalProvider withoutReasoning:answer], error);
	} copy];

	dispatch_async(loader, ^{
		NSError *problem = nil;
		BOOL ready = [self prepareEngine:&problem];
		NSError *failure = ready ? nil :
			(problem ?: [NSError errorWithDomain:NekoAskErrorDomain
			                                code:NekoAskErrorNotConfigured
			                            userInfo:nil]);
		dispatch_async(dispatch_get_main_queue(), ^{
			if(!ready) {
				completionCopy(nil, failure);
			} else {
				[self giveRoomToThink];
				[self->engine generateFor:[self askedOf:question]
				       instructions:instructions
				            partial:partialCopy
				         completion:completionCopy];
			}
		});
	});
}

- (void)cancel
{
	[engine cancel];
}

@end
