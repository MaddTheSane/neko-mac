/* NekoVoice */

#import <Cocoa/Cocoa.h>

/* When the cat was last seen, so that "again" and "a while" mean something. */
extern NSString * const NekoVoiceLastSeenKey;
extern NSString * const NekoVoiceGreetedKey;

/*! How it sounds, rather than what it says.

   Three things, and none of them touches the facts. A mood that drifts with the
   hour and the day, so that the same question asked on Monday morning and on
   Friday night does not come back in the same words. An opening that knows the
   history — the first time today, the first time in a week, one o'clock in the
   morning. And the pass that takes the assistant out of the assistant: no
   compliment before the answer, no second sentence that says the first one
   again.

   The last of those is the one with evidence behind it. Models are trained to
   agree and to flatter — "great question" before the answer, a closing sentence
   restating the opening one — and it reads as machinery every time. The
   instructions ask for none of it; this is what happens when they are ignored,
   which is often enough to be worth code. */
@interface NekoVoice : NSObject

/*! One line for the prompt: what sort of a mood it is in, and a turn of phrase
   to lean on. Deterministic from the date, so it holds still for hours at a
   time rather than changing between two questions. */
+ (NSString *)moodNow;
+ (NSString *)moodAt:(NSDate *)when;

/*! Something to say when it appears, or nil, which is most of the time. Written
   in rather than generated: this is the first thing said after a launch, and it
   has to work before any engine is ready — or without one at all. */
+ (NSString *)openingIfDue;
+ (NSString *)openingFor:(NSDate *)when lastSeen:(NSDate *)before;

/*! Whether a line claims an inner state in the first person — "mi sento solo",
   "I feel ignored".

   Machines are unnerving in proportion to the *experience* people ascribe to
   them, more than to how they look: a thing that seems to feel is the uncanny
   direction, and a pet that says it feels neglected is also a manipulation. The
   cat may go quiet, sit differently, look away; it does not report feelings it
   does not have. Identity is not a feeling — "sono un gatto di pixel" is fine. */
+ (BOOL)claimsAFeeling:(NSString *)line;

/*! Takes the compliment off the front and the restatement off the end. Returns
   the line unchanged when there is neither, which is most of the time. */
+ (NSString *)withoutFlattery:(NSString *)line;

/*! Whether a line is nothing but agreement — "certo!", "ottima domanda" — with
   no answer attached to it. */
+ (BOOL)isNothingButFlattery:(NSString *)line;

/*! Whether the second sentence says the first one again. */
+ (BOOL)saysItTwice:(NSString *)line;

@end
