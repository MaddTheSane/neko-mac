/* NekoAnswerProvider */

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/*! Where an answer comes from. Two of these exist — a Shortcut the user owns and
   a model called directly — and the rest of the feature knows neither.

   Every provider obeys the same contract: answer or fail within its own
   timeout, always call back on the main thread, and treat a cancellation as
   neither an answer nor an error. */
@protocol NekoAnswerProvider <NSObject>

/*! Shown in the preferences. */
@property (readonly, copy) NSString *name;

/*! `NO` sends the caller to the canned reply instead. */
@property (readonly, getter=isConfigured) BOOL configured;

/*! Why it is not configured, for the preferences to show. nil when it is. */
- (NSString *_Nullable)configurationHint;

/*! instructions describe who is answering; a provider that cannot set a system
   prompt of its own is expected to work them into the question. */
- (void)askQuestion:(NSString *)question
       instructions:(NSString *)instructions
         completion:(void (^)(NSString *_Nullable answer, NSError *_Nullable error))completion;

- (void)cancel;

@optional

/*! Answers as it goes: `partial` receives the whole answer so far, `completion`
   closes it. A provider that can do this is preferred, because words on screen
   in half a second read as quick even when the whole answer takes two. */
- (void)askQuestion:(NSString *)question
       instructions:(NSString *)instructions
            partial:(void (^)(NSString *sofar))partial
         completion:(void (^)(NSString *_Nullable answer, NSError *_Nullable error))completion;

@end

/*! The voice the character answers in, built around who it is. Shared by every
   provider so they cannot drift apart. */
extern NSString *NekoAnswerInstructionsFor(NSString *_Nullable persona);

/*! The same, plus the one extra rule that lets an answer be a picture: reply with
   "IMAGE: something to draw" and the app draws it instead. */
extern NSString *NekoAnswerInstructionsDrawing(NSString *_Nullable persona, BOOL mayDraw);

/*! And with the four things it is allowed to actually do. */
extern NSString *NekoAnswerInstructionsWith(NSString *_Nullable persona, BOOL mayDraw,
											BOOL mayAct, NSString *_Nullable mayLookAt);

/*! The same, told what was asked. The facts the app can look up — the time, the
   date, the battery, how long the Mac has been awake — are handed over only when
   the question plausibly wants one of them.

   Measured, and the reason this exists: given the list unconditionally, Apple's
   model opens with it. "Perché il build è lento?" came back as "L'ora attuale è
   le 16:44 e il giorno è mercoledì… non posso sapere perché il build sia lento."
   A model cannot read out a list it was not given, and every other question gets
   a shorter prompt for it. */
extern NSString *NekoAnswerInstructionsAsked(NSString *question, NSString *_Nullable persona,
                                           BOOL mayDraw, BOOL mayAct,
                                           NSString *_Nullable mayLookAt);

/*! Whether a question is asking for one of those facts. */
extern BOOL NekoQuestionWantsFacts(NSString *question);

/*! The handful of things the cat can truthfully know at this moment — the time,
   the date, the battery, how long the Mac has been awake — as plain lines for a
   model to read. */
extern NSString *NekoFactsNow(void);

/*! The example lines the instructions carry, which a model will sometimes hand
   straight back and which are therefore worth recognising. */
extern NSArray<NSString*> *NekoInstructionExamples(void);

/*! The marker a model uses to ask for a drawing. */
extern NSString * const NekoImageMarker;

/*! The voice for something nobody asked for: a remark about what you appear to
   be doing, offered by a cat that only knows which application is in front.
   Shorter, humbler and allowed to say nothing at all. */
extern NSString *NekoSuggestionInstructionsFor(NSString * _Nullable persona);

/*! The same, told whether the text somebody is working on is in front of it.

   These two sentences used to contradict each other and one of them was in the
   preferences. The instructions said "do not pretend to see inside their files",
   which is right when there is nothing to see and wrong when somebody has
   switched reading on: the model was being handed the text and told to ignore it.

   Measured in tests/glance.m, ten staged desktops asked three ways: as the prompt
   stood, **0 of 10** remarks used what was read; with that one sentence replaced,
   2 of 10 — and those two were the only remarks in the run that no amount of
   knowing the minutes could have produced. Two in ten is a modest return and it is
   not nothing, and it was zero because of a sentence rather than because of the
   capability. */
extern NSString *NekoSuggestionInstructionsSeeing(NSString * _Nullable persona, BOOL hasText);

/*! The voice for coming over and being nosy: a question about what you are doing,
   shorter than a suggestion and with no advice in it at all. */
extern NSString *NekoCuriosityInstructionsFor(NSString * _Nullable persona);

/* Errors every provider raises. */
extern NSErrorDomain const NekoAskErrorDomain;
typedef NS_ERROR_ENUM(NekoAskErrorDomain, NekoAskErrors) {
	NekoAskErrorNotConfigured = 1,
	NekoAskErrorTimedOut,
	NekoAskErrorNoAnswer,
	NekoAskErrorTransport,
	NekoAskErrorNoShortcut       /*!< the named Shortcut does not exist */
};

NS_ASSUME_NONNULL_END
