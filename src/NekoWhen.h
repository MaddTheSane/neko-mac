/* NekoWhen */

#import <Cocoa/Cocoa.h>

/*! How long "fra dieci minuti" is.

   `NSDataDetector` parses absolute dates out of ordinary sentences in all four of
   this application's languages, for nothing, with no model and no permission:
   *"domani alle 15"* arrives as a date. Measured on this Mac before any of this
   was written, it parses **none** of these:

       metti un timer di 10 minuti · ricordamelo fra 20 minuti · svegliami tra
       un'ora · fra un'ora e mezza · tra un quarto d'ora · tra mezz'ora · 90
       secondi · set a timer for 10 minutes · remind me in 20 minutes · in half an
       hour · in an hour and a half · dans 20 minutes · en media hora

   So this is the small, closed, testable piece that was missing. It is deliberately
   not clever: a number, a unit, and the handful of words four languages use for a
   half and a quarter. Everything it does not recognise is nothing, which is the
   right answer far more often than a guess would be — the failure that matters is
   not a missed timer, it is a timer nobody asked for. */
@interface NekoWhen : NSObject

/*! How many seconds the sentence asks for, or 0 when it does not ask for any.
   "Un'ora e mezza" is 5400; "quanto fa sette per otto" is 0. */
+ (NSTimeInterval)secondsIn:(NSString *)said;

/*! The same, said back in the language of the application: "dieci minuti",
   "un'ora e mezza". For the sentence somebody is shown before anything starts. */
+ (NSString *)describe:(NSTimeInterval)seconds;

/*! When a timer set now would land, as somebody would read it off a clock. */
+ (NSString *)clockTimeIn:(NSTimeInterval)seconds;

/*! The numbers written out, in the four languages. Shared with NekoSums so that
   "quanto fa sette per otto" and "fra sette minuti" read the same list rather
   than two lists that drift apart. */
+ (NSDictionary *)writtenNumbers;

@end
