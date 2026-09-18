/* NekoSums */

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/*! "Quanto fa 47 per 23" and "quanti litri sono due galloni".

   The same measurement that justifies `NekoClock` — `tests/sums.m`, three models
   on this Mac — says something less obvious about these two, and the two halves
   deserve to be told apart rather than lumped together as "a model cannot do
   maths":

       47 × 23        Qwen3 4B: 1081 ✓   Gemma 3 4B: "Quindici"   1.5B: "circa 2.04"
       1234 + 5678    all three: 6912 ✓
       18% of 240     all three: 43,2 ✓
       2 gallons → l  4,54 · 0,845 · 7,5      (the right answer is 7,57)
       5 miles → km   "circa 8" · 7.6 · "circa 8"

   So **plain arithmetic is mostly right on a four billion parameter model and
   unreliable below it**, and **conversion is unreliable everywhere**: a model
   asked for a conversion factor recalls a plausible one — 4,54 is a real number,
   it is the litres in an imperial gallon — and states it without hedging. That is
   the worse failure of the two, because it is right-shaped.

   Doing both here is not really a question of accuracy anyway. It costs a
   millisecond instead of a second, it needs no engine at all, and it cannot be
   wrong. `NSMeasurement` holds the conversion factors that ship with the
   operating system, and the arithmetic is a hundred lines of parser.

   **Not `NSExpression`**, which was the first thing tried and was measured
   rather than trusted: it answers `7/2` with **3** and `1/0` with **0**, both
   silently. A calculator that quietly does integer division is worse than none.

   **What it refuses**, again the half that is the work: a sentence that is not
   entirely a sum. Everything after the phrase that asks has to parse — every
   character of it — or this says nothing and lets somebody who can guess do the
   guessing. "Quanto fa male" is not a multiplication. */
@interface NekoSums : NSObject

/*! What to say, or nil. */
+ (NSString * _Nullable)wantedFor:(NSString *)question;

@end

NS_ASSUME_NONNULL_END
