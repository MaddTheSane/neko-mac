/* NekoAsk */

#import <Cocoa/Cocoa.h>
#import "NekoAnswerProvider.h"

@class NekoHotKey, NekoListener, NekoBubble, NekoLine;
@class NekoShortcutProvider, NekoModelProvider, NekoAppleProvider;
@class NekoOpenAIProvider, NekoLocalProvider;

/* NSUserDefaults keys */
extern NSString * const NekoAskEnabledKey;
extern NSString * const NekoAskHotKeyCodeKey;
extern NSString * const NekoAskHotKeyModifiersKey;
extern NSString * const NekoAskProviderKey;      /* apple, openai, model, shortcut */
extern NSString * const NekoAskShortcutNameKey;
extern NSString * const NekoAskSpeakKey;
extern NSString * const NekoAskFollowUpKey;      /* keep listening after speaking */
extern NSString * const NekoAskTempoKey;         /* let a short answer take a moment */

/*! When the cat last said something nobody asked for. Kept in the defaults so a
   restart does not hand it a fresh tongue. */
extern NSString * const NekoLastUnpromptedKey;

/*! Ask the cat a question.

   The keystroke starts listening, what you said becomes text, the text goes to
   whichever provider is configured, and the answer appears in a bubble beside
   the cat. While all that happens the cat stops chasing the pointer: being asked
   something is more important than the cursor.

   Nothing is captured until the keystroke, and the microphone closes as soon as
   the sentence ends. */
@interface NekoAsk : NSObject
{
	NekoHotKey *hotKey;
	NekoListener *listener;
	NekoBubble *bubble;
	NekoLine *typedLine;         /*!< the typed half of the conversation */
	id voice;                    /*!< AVSpeechSynthesizer, kept so it can be cut off */
	BOOL beatPending;            /*!< a reply to wait for, once the voice is done */
	BOOL saidUnasked;            /*!< what is on screen, nobody asked for */
	BOOL fromTheWeb;             /*!< this answer was built on somebody else's words */
	BOOL heardSomething;         /*!< it has visibly noticed this sentence starting */
	NSString *pendingRemark;     /*!< said once the cat has turned to say it */
	NSString *pendingAnswer;     /*!< held for a beat, so it does not arrive instantly */
	BOOL turnedForRemark;        /*!< one turn per remark, however far it moved */
	BOOL beatRan;                /*!< and something was listening for a reply */
	NSString *askingAbout;       /*!< the question now in flight */
	NSString *lastQuestion;      /*!< the turn before this one, so "it" resolves */
	NSString *lastAnswer;
	NSDate *lastTurn;
	/*! And the two before that, because a third turn is not rare. Counted from
	   this Mac's own diary, timestamps only: of fourteen runs of questions inside
	   three minutes of each other, six reached a third turn and two reached a
	   fifth. Carrying one turn meant the first thing somebody said was gone by
	   the time they had said three. */
	NSMutableArray *turns;
	NekoShortcutProvider *shortcutProvider;
	NekoModelProvider *modelProvider;
	NekoAppleProvider *appleProvider;
	NekoOpenAIProvider *openaiProvider;
	NekoLocalProvider *localProvider;
	int phase;
	NSDate *lastDrawn;           /*!< throttles the streaming redraw */
	NSTimer *thinking;
	BOOL drawing;                /* the spinner is an hourglass, not a paw */           /* the animation while it waits */
	NSString *thinkingQuestion;
	unsigned thinkingTick;
	BOOL hotKeyFailed;
}

+ (NekoAsk *)sharedAsk;
@property (class, readonly, retain) NekoAsk *sharedAsk;

/*! Re-reads the preferences: on or off, the keystroke, which provider. */
- (void)applySettings;

@property (readonly, getter=isEnabled) BOOL enabled;
@property (readonly, getter=isBusy) BOOL busy;

/*! The keystroke as the preferences should show it, and whether registering it
   failed because something else already owns it. */
@property (readonly, copy) NSString *hotKeyDisplayName;
@property (readonly) BOOL hotKeyUnavailable;

@property (readonly, assign) id<NekoAnswerProvider> provider;
@property (readonly, retain) NekoModelProvider *modelProvider;   /*!< the preferences hold its key */
@property (readonly, retain) NekoOpenAIProvider *openaiProvider;

/*! Starts a question, or abandons the one in progress. Held rather than tapped,
   the same keystroke opens a line to type in instead. */
- (IBAction)toggle:(id)sender;
- (IBAction)hotKeyLetGo:(id)sender;

/*! Opens the line to type in, whether or not the microphone works. */
- (void)typeALine;

/*! After the cat has spoken: the microphone stays open for a few seconds so a
   reply needs no keystroke, with the bubble saying so while it lasts. Off when
   the switch in the preferences is off, and never when speech has not already
   been allowed — the cat does not ask for the microphone on its own account. */
- (void)keepListening;
@property (readonly, getter=isWaitingForReply) BOOL waitingForReply;

/*! How long a finished answer waits before it is shown.

   Response delays scaled to the weight of a reply raise perceived humanness,
   social presence and satisfaction in chat — and the spinner this app already
   has is the typing indicator that made waiting tolerable in those studies. It
   cuts the other way for anything factual: asked the time, fast *is* the answer.
   Nothing is delayed that was already on screen, and nothing longer than a
   sentence or two, because those streamed in as they arrived. Zero when the
   switch is off. */
- (NSTimeInterval)tempoFor:(NSString *)text;

/*! The turn just before this one, as it goes into the next prompt, and how it
   gets there. Empty once a few minutes have passed. */
- (NSString *)threadForPrompt;
- (void)rememberQuestion:(NSString *)question answer:(NSString *)answer;

/*! A plugin's verb, read back before anything happens. */
- (void)proposeVerb:(NSDictionary *)verb;

/*! What a plugin's route fetched, quoted to a model as somebody else's words. */
- (void)followRoute:(NSDictionary *)route;

/*! The whole of asking, from a question that is already text: what the typed line
   and the microphone both end in, and what the Services entry uses. */
- (void)ask:(NSString *)question;

/*! A question that arrived from somewhere other than this application — a URL
   another program opened. It is read back and waits for a yes, like every other
   thing here that came from outside: a URL can be on a web page, and a web page
   is the one place this application has never taken instructions from. */
- (void)proposeQuestion:(NSString *)question;

/*! An appointment, read back in full — the day in words, the hours, the title —
   before anything is written. Read back and not simply done, unlike the timer:
   this one lands in a calendar, where a wrong entry outlives the mistake. */
- (void)proposeAppointment:(NSDictionary *)appointment;

/*! The two halves either side of a plugin having a look at the words: the second
   is what actually asks, and what actually says. */
- (void)askAfterPlugins:(NSString *)question;
- (void)sayAfterPlugins:(NSString *)text;

/*! Everything that would be sent with the next question. Public because it is
   the only way to check what a follow-up actually asks. */
- (NSString *)instructionsForAsking;

/*! Goes and looks something up: a name from NekoWeb's list, or "weather <place>".
   Verbatim when the app itself decided to look, because then the headlines are
   what was asked for; through the model when the model asked, because then they
   are context for a question. */
- (void)lookUp:(NSString *)wanted verbatim:(BOOL)asItIs;

/*! Two seams, so that the moment after the cat speaks can be tested on a machine
   with no microphone and no permission to use one: whether speech has already
   been allowed, and starting the listener. The tests override these; nothing
   else does. */
@property (readonly) BOOL speechAlreadyAllowed;
- (BOOL)startListeningForReplyWithPatience:(NSTimeInterval)seconds;

/*! The cat notices a sentence starting rather than waiting for it to end. Called
   from the listener as soon as there are words, and once per sentence: in human
   conversation the gap between turns runs about a tenth of a second while the
   reply takes six times that to plan, and what fills it is the listener
   reacting. */
- (void)acknowledgeHearing:(NSString *)heard;

/*! What the microphone reports during those few seconds. Called by the listener,
   and by the tests, which have no microphone. */
- (void)replyHeard:(NSString *)text final:(BOOL)final error:(NSError *)error;

/*! For the cat's own remarks, which nobody asked for. NO while it is listening,
   thinking, answering or already saying something: an interruption of an
   interruption is worse than a missed suggestion. */
- (BOOL)canSpeakUnprompted;

/*! Seconds since the last unasked remark of any kind, and whether the quiet
   period from the Suggestions tab has passed. Both count suggestions and
   curious questions together: they are all interruptions to whoever is
   working. */
+ (NSTimeInterval)secondsSinceSpokeUnprompted;
+ (BOOL)mayInterruptNow;

/*! Whether a bubble is on screen right now. The cat stays where it is while one
   is: reading something that walks away is worse than waiting for it. */
@property (readonly, getter=isSpeaking) BOOL speaking;

/*! Says something in the bubble without any question having been asked, and
   holds the cat still while it does. */
- (void)sayUnprompted:(NSString *)text;

/*! Shows a picture beside the cat, for the preferences' own test button. */
- (void)showDrawing:(NSImage *)picture near:(id)panel;

@end
