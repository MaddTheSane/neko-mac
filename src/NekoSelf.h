/* NekoSelf */

#import <Cocoa/Cocoa.h>

/*! "Dove sei?" — "Da quanto sei qui?" — "Da quanto non ci parliamo?"

   The first piece of docs/self.md, and that document's argument is why it looks
   like this rather than like a prompt.

   **What the field calls self-awareness is the wrong self for a cat.** The
   careful instrument there is the Situational Awareness Dataset — three aspects,
   seven categories, sixteen tasks, over 13,000 questions, sixteen models — and
   every one of its categories is about knowing you are a language model, knowing
   whether you are being tested, recognising your own output. A small pixel cat
   exists in order not to know any of that.

   What it should know is where it lives, what happened before, and what time it
   is. That turns out to be **unstudied as self**: the 2026 work on agents and
   screens is about *acting* on them — pixel grounding, 3.5 million annotated
   desktop elements — and asks nothing about what an agent knows of its own
   situation.

   **And the constructive half is the opposite of how the request sounds.** On
   the largest temporal benchmark, putting events in order sits below 30% across
   24 models, and the same model that reliably retrieves a date loses half its
   accuracy the moment two times must be related. This application measured the
   same thing on its own doorstep: three local models, the date and day already
   in the prompt, **one of nine** date questions right. So a sense of time is
   achievable precisely because it has to be **computed**: every fact here is a
   subtraction over a timestamp or a rectangle, and no engine is asked anything.

   Four things it can say about itself, all of them checkable by the person who
   hears them:

       where it is       which screen, where on it, and where the Mac is
       how long it has   the day the two of you met, stamped once and kept
       how long quiet    since they last asked it anything
       and the middle    of that: how many days, said as days

   **Deliberately not in the prompt.** These facts are answered in code and are
   not added to the block a model is given. Two reasons, both from measurement:
   the block is already a thousand characters and a longer prompt measurably
   makes a small model worse; and Völkel's second factor for conversational
   agents — the one named *Dysfunctional* — has **egocentric** and **conceited**
   in its top twenty descriptors, so a cat handed its own biography every time it
   is asked anything is a cat that will start talking about itself. If remarks
   should ever draw on this, that is an experiment with a negative table, not a
   line added to a prompt.

   What it must never do is claim to feel any of it. A self-model is buildable
   and testable; whether anything is experienced is not currently answerable by
   anybody — see docs/self.md §5 — and `NekoSense` already refuses a remark that
   claims a feeling it does not have. */
@interface NekoSelf : NSObject

/*! What to say, or nil when the sentence was not asking. */
+ (NSString *)wantedFor:(NSString *)question;

/* The pieces, exposed so a harness can check them without a window. */

/*! Where the cat is: which screen, and where on it. */
+ (NSString *)whereItIs;                /* nil when there is no panel yet */

/*! Where the **Mac** is, which is a different question and answered in two
   tiers, both of them NekoPlace's and neither of them sent anywhere.

   The town, when somebody has pressed the button for it: measured, at the
   accuracy macOS calls reduced, and kept as a word rather than a coordinate.

   Otherwise the country the **time zone** implies, which costs nothing and
   needs nobody's permission — and the sentence says *somewhere in* rather than
   naming a place, because a time zone is a deduction about a country and not a
   position. A cat that said "sono a Roma" to everyone in Italy would be wrong
   about almost all of them. */
+ (NSString *)whereTheMacIs;            /* nil when even the time zone says nothing */
+ (NSInteger)daysHere;
+ (NSString *)howLongSinceHeard;        /* nil when nothing was ever heard */

/*! And the mirror of it: how long since the cat itself said something unprompted.
   The stamp is NekoAsk's, kept in the defaults so that quitting is not a way of
   resetting the quiet period — which means it is also the one number here that
   survives the application being closed and opened again. */
+ (NSString *)howLongSinceSpoke;        /* nil when it has never spoken */

@end
