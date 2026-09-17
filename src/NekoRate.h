/* NekoRate */

#import <Cocoa/Cocoa.h>
#import "NekoDesktop.h"

/* NSUserDefaults keys. The pace is remembered across launches: it is learned
   from how somebody reacts, and quitting the app is not a reason to forget what
   it learned about them. */
extern NSString * const NekoRateTargetKey;      /* remarks a day it aims at */
extern NSString * const NekoRateDayKey;         /* the day the counts belong to */
extern NSString * const NekoRateSaidKey;
extern NSString * const NekoRateAnsweredKey;
extern NSString * const NekoRateIgnoredKey;
extern NSString * const NekoRateDismissedKey;
extern NSString * const NekoRateActiveKey;      /* seconds at the Mac today */

/*! How often the cat may speak unasked, as a budget for the day rather than a
   timer.

   A colleague says something eight to fifteen times a day; a notification says
   it every time a timer expires. The difference is not the average — it is that
   a colleague notices when nobody is listening. So this keeps three things: how
   many remarks today, how they landed, and how much of the day has actually
   been spent at the Mac.

   From those come two answers. Whether it may speak at all right now: not before
   the interval in the preferences, never more than the day's budget, and never
   two in a row far ahead of the day's pace. And how good a moment it has to
   wait for: a wide seam in the work when the day is on pace, a small gap when it
   is behind, which is what lets the rate rise on a quiet day without dropping
   the rule that a remark has to land somewhere.

   The pace itself moves. A remark answered is worth one more a day; one that was
   let go is worth one fewer; one clicked away is worth two, because that is
   somebody saying no rather than somebody being busy. It never goes above
   fifteen — the top of the band a colleague occupies — and never below four,
   which is what consistently being ignored ought to earn. */
@interface NekoRate : NSObject
{
	NSDate *lastAccrual;         /*!< when the time at the Mac was last counted */
}

+ (NekoRate *)sharedRate;
@property (class, readonly, retain) NekoRate *sharedRate;

/* The two questions the advisor and the antics ask. */
- (BOOL)mayInterruptNow;
- (NekoBreakpoint)seamNeeded;

/* What happened to the remarks. Neutral is a real answer: with nothing
   listening for a reply there is no way to tell being ignored from being
   agreed with, and guessing would move the pace on no evidence. */
- (void)noteSaid;
- (void)noteAnswered;
- (void)noteIgnored;
- (void)noteDismissed;

/* Today, and the pace. */
- (double)target;
- (NSUInteger)saidToday;
- (NSUInteger)answeredToday;
- (NSTimeInterval)activeToday;
- (double)expectedByNow;
- (NSTimeInterval)gap;           /* the shortest it will leave between remarks */
- (NSString *)describeToday;

/*! Back to the middle of the band, for someone who wants to start again. */
- (void)forgetPace;

/*! Seams, so that a day can be replayed in a second: what time it is, how long
   since the last remark, whether somebody is at the Mac, and what the
   preferences say. The tests override these; nothing else does. */
- (NSDate *)now;
- (NSTimeInterval)secondsSinceLastRemark;
- (BOOL)atTheMac;
- (NSTimeInterval)floorFromPreferences;

@end
