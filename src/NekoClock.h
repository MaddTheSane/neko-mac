/* NekoClock */

#import <Cocoa/Cocoa.h>

/*! "Quanti giorni mancano a venerdì?"

   Answered here rather than by a model, and the reason was measured rather than
   assumed — because the obvious version of the claim is **already false in this
   application**. `NekoFactsNow` has handed every engine the time, the date and
   the day of the week since 2.4, so a model here does not have to invent the
   date: it is told it.

   What it does with it is another matter. `tests/sums.m` asked three models on
   this Mac — Qwen2.5 1.5B, Gemma 3 4B, Qwen3 4B — the same date questions with
   that block in front of them, on Monday 31 August 2026:

       how many days to Friday   (4)    → 2, 2, 1
       how long to 25 December   (116)  → "due settimane", 31, 170
       what day is the day after tomorrow → wrong on two of the three

   **One of nine right**, and every wrong one said plainly, in a whole sentence,
   with no sign that it was a guess. That is the signature of arithmetic done by
   something that cannot count: the facts are there and the subtraction is not.

   So this does the subtraction, and does nothing else. `NSCalendar` knows how
   many days there are between two dates, across a month end and a leap year and
   the hour the clocks change, and it is right every time for nothing.

   **What it refuses to do**, which is the half that takes the work: decide that
   a sentence was a question about a date. Three things are required — a phrase
   that asks, a tail that parses, and a target in the future — and the failure
   that matters is not a missed question but an answer to one nobody asked.

   And one measured trap, worth writing down because it produced a confident
   wrong answer in the first draft: `NSDataDetector`, handed *"al 3 marzo"*,
   returns **today at noon** and reports that it used the whole phrase. Handed
   *"3 marzo"* it returns the right day. The Italian preposition poisons it. So
   the tail is stripped of its articles and prepositions before the detector sees
   it, and a result that lands in the past is thrown away. */
@interface NekoClock : NSObject

/* What to say, or nil when the sentence was not one of these. */
+ (NSString *)wantedFor:(NSString *)question;

@end
