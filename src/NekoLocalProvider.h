/* NekoLocalProvider */

#import <Cocoa/Cocoa.h>
#import "NekoAnswerProvider.h"

/*! What a local engine has to be able to do. Implement this, hand it to the
   provider, and the feature is complete: everything else — the catalogue, the
   download, the file on disk, the settings — is already here.

   The intended implementation is llama.cpp built as a static library and linked
   into the app, reading the GGUF the store downloaded. That keeps the app
   self-sufficient at runtime: no daemon to install, no Python, no other
   application to keep running. */
@protocol NekoLocalEngine <NSObject>
- (BOOL)loadModelAtURL:(NSURL *)file error:(NSError **)error;
- (BOOL)isLoaded;
- (void)generateFor:(NSString *)prompt
        instructions:(NSString *)instructions
             partial:(void (^)(NSString *sofar))partial
          completion:(void (^)(NSString *answer, NSError *error))completion;
- (void)cancel;

@optional
/*! How many tokens the next answer may take. Optional, and asked for only when
   the catalogue says the chosen model reasons before answering.

   Measured on Qwen3.5 4B: asked "quotazione oggi borsa Apple" it writes 829
   characters of notes and the default budget of 200 tokens runs out inside them,
   so the answer never begins. Asked "che ore sono?" it writes `<think></think>`
   with nothing between and answers in one line. It is not a switchable habit —
   `/no_think`, which Qwen3 honoured, is gone: this model reasons *about* the
   token instead of obeying it. So the only thing left is room. */
- (void)setTokenBudget:(int)tokens;
@end


/*! A model running on this Mac, downloaded through the preferences.

   Distinct from the Apple Intelligence provider, which is also local but is the
   system's model on the system's terms: this one is a file you chose, on a Mac
   that may be too old for Apple Intelligence or have it switched off. */
@interface NekoLocalProvider : NSObject <NekoAnswerProvider>
{
	id<NekoLocalEngine> engine;
	dispatch_queue_t loader;        /*!< the model file is opened off the main thread */
	NSString *preferred;           /*!< set by whoever wants a particular model */
}

/*! The identifier of the model that will actually answer: whatever was chosen if
   it is on the disk, otherwise something that is. */
- (NSString *)modelIdentifier;

/*! What the menu says, installed or not. */
- (NSString *)chosenModelIdentifier;

/*! Asks this instance to use one particular model, whatever the preferences say.
   Used by NekoBrains, which needs the most capable model on the disk rather than
   the one someone picked for asking the capital of France. Ignored when that
   model is not installed. */
- (void)setPreferredModel:(NSString *)identifier;

/* A reasoning model's scratchpad, taken out of what it said.

   Reported from use, and it is the worst thing that has been visible in this
   application: asked for Apple's share price, the cat answered with

       <think> Thinking Process: 1. **Analyze Request:** * **Role:** fox living
       someone's computer desktop (quick, sly, pleased own cleverness). *
       **Task:** Answer que…

   — the model's own notes, in the bubble, with the persona quoted back verbatim.
   Qwen3, Qwen3.5 and every other reasoning build emits a `<think>` block before
   answering, and nothing here took it out. `NekoSense` does not catch it by
   design: it judges the remarks the cat makes on its own, never an answer to a
   question, because dropping an answer would leave somebody who asked staring at
   a cat.

   The cause was a catalogue entry added without asking what the model **writes**.
   Its URL, its bytes and its licence were all checked. See `-thinks` on
   NekoLocalModel, which is the other half of this fix.

   Done here rather than at the call sites because there are five of them — the
   question, the unprompted remark, the nightly reflection, the word learning and
   the drawing — and a sixth would forget. This is the engine's own adapter, and
   the scratchpad is the engine's own habit.

   **What it covers:** `<think>`, `<thinking>`, `<thought>` and `<reasoning>`,
   in any case, closed or left open by a budget that ran out — an unclosed block
   takes everything after it, because everything after it is more of the same.
   Not covered: the channel syntax some models use instead (`<|channel|>analysis`),
   which nothing in this catalogue emits and which would be guesswork to write
   against. */
+ (NSString *)withoutReasoning:(NSString *)text;

/*! `nil` until an engine is compiled into the app. The provider reports itself
   unconfigured while this is the case, and says so in the preferences rather
   than failing at the moment someone asks a question. */
+ (id<NekoLocalEngine>)makeEngine;

@end
