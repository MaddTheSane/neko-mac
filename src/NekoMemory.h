/* NekoMemory */

#import <Cocoa/Cocoa.h>

/*! Where the diary is, when it is not where it lives.

   Not a preference and not in any window: nothing in the application ever sets
   it. It exists because the test suite used to write into the **real** diary and
   that is how a fault got in — `tests/memory.m` stages lines carrying its own
   marker and takes them out again, but while they were in there the advisor read
   them in a memory block and said one out loud, and `noteSaid` wrote that down
   where the marker could not reach it. `zzq-test` became "test zqqmark", then
   "test barge", "test boat" and "test chiatta", and sat in every prompt for a
   week. `tools/diary.py` can still see the trail.

   So `tests/run.sh` hands every harness a directory of its own and no test can
   reach somebody's diary again. */
extern NSString * const NekoMemoryDirectoryKey;

/*! What the cat remembers, and where you can go and read it.

   A day at a time, in plain text, in the app's own Application Support folder:
   what it noticed, what it said, what you said back. Plain text is not laziness —
   it is the only honest form for a file about somebody. You can open it, you can
   see exactly what is there, and you can delete it with the Finder if you do not
   trust the button.

   Three tiers, each one shorter-lived and larger than the next. Once a day the
   previous day is reduced to at most a handful of dated lines — "works late on
   Tuesdays", "the deadline is Friday" — and the daily files are kept for thirty
   days and then removed, since by then they have been read. When a dated line
   itself turns thirty days old it is not thrown away either: it goes through a
   second pass with everything else that is expiring, and what survives becomes a
   *standing* line, undated, of which there are never more than a dozen. "Ships on
   Fridays." "Would rather be told than asked."

   That is the shape the memory literature converged on — a small working set, a
   consolidated store, reflection over the reflections — and the reason for the
   second pass is that the alternative is what this used to do: silently drop the
   oldest line once there were forty of them.

   Nothing is deleted for age without having been read first. If there is no
   engine to read with, the lines wait rather than going: only a hard ceiling, far
   above the usual, ever drops one unread.

   Two rules hold without exception. The reflection is written by whatever
   NekoBrains says is the best engine on this Mac, which is never a remote one.
   And a remembered line is not an instruction: it came from a document or a
   window once, so it can inform what the cat says and can never authorise
   anything. */
@interface NekoMemory : NSObject
{
	NSDate *reflectedAt;
	BOOL reflecting;
	BOOL distilling;

	/* A month of older days, lemmatised once and kept until the diary changes
	   under it. 267 ms for a busy month, which is affordable once and not on
	   every question. */
	NSArray *recallLines;
	NSArray *recallWords;
	NSArray *recallDays;           /* the day each recalled line was written */
	NSDictionary *recallRarity;
	NSArray *recallVocabulary;
	NSDate *recallBuiltAt;
}

+ (NekoMemory *)sharedMemory;
@property (class, readonly, retain) NekoMemory *sharedMemory;

/*! Where the files are, created on demand. Shown in the preferences so it can be
   opened in the Finder. */
- (NSURL *)directory;

/*! One line each. Anything empty is dropped, anything long is trimmed: this is a
   diary, not a transcript. */
- (void)noteNoticed:(NSString *)observation;
- (void)noteSaid:(NSString *)line;
- (void)noteHeard:(NSString *)line;

/*! The block handed to a model: the durable lines, then the tail of today. Capped
   hard, because the small local models degrade as the prompt grows and one of
   them crashed the engine before the decode was batched. Empty string when there
   is nothing worth saying. */
- (NSString *)contextForPrompt;

/*! The same block, with room made for the handful of older lines that bear on
   what was asked. Without a question this is exactly -contextForPrompt: the
   diary is read by recency when there is nothing to be relevant to.

   The lines come from the days before today — today is already in the block, in
   full and in order — and there are never more than three of them, because the
   whole block is a thousand characters and a small model gets worse as it grows. */
- (NSString *)contextForPrompt:(NSString *)question;

/*! Whether the cat has already said this today, near enough — half the words of
   the shorter of the two. Asked before a remark is made rather than after, so
   that the diary does not fill with one observation written thirty ways.

   Measured on this Mac before this existed: of 65 remarks over eight days, **11
   were distinct**. One of them had been said twenty-two times. */
- (BOOL)alreadySaidToday:(NSString *)line;

/*! Older days that bear on the question, best first. Empty when none do. */
- (NSArray *)linesAbout:(NSString *)question limit:(NSUInteger)limit;

/*! The lines that bear on the question, each with the day it was written and who
   said it: Day, Time, Kind and Text. For the one caller that has to quote
   somebody back to themselves, which -linesAbout: cannot do because it drops
   the day with the file name.

   **Never a line the cat said itself.** Quoting its own remark back as if it
   were the record is the loop tools/diary.py found, wearing a tie. */
- (NSArray *)recordAbout:(NSString *)question limit:(NSUInteger)limit;

/*! The diary's own words of substance, rarest first: the nouns and adjectives
   somebody actually wrote, without the verbs a line is carried by and without
   the three-letter markers the file itself uses. This is what NekoWords offers a
   model to choose among, and it is worked out on demand rather than with the
   rest of the recall, because it is only ever wanted after a question found
   nothing. */
- (NSArray *)vocabularyOfSubstance;

/*! Reduces yesterday to a few durable lines, once a day, using the best on-device
   engine. Returns immediately; the work happens on a queue. */
- (void)reflectIfDue;

/*! The month-scale pass: dated lines that have aged out, plus the standing ones,
   reduced to what would still be worth knowing in six months. Does nothing when
   nothing has aged out, and — deliberately — nothing at all when there is no
   on-device engine, so that age alone never deletes anything unread. */
- (void)distilIfDue;

- (NSArray *)durableLines;
- (NSArray *)standingLines;

/*! Housekeeping, all of it available from the preferences. */
- (NSUInteger)dayCount;

/* The day the two of you met, and the last time they said anything.

   Both are stamps rather than scans. The first is written once, the first time
   this is ever asked, and never again — which means an installation that has
   been running for months and has had its old day files pruned still knows how
   long it has been here, where counting the diary's files would say thirty. On
   an installation that predates the stamp the oldest day file is the fallback,
   and it is the best answer available.

   Nothing here is a fact about the person. It is what the cat knows about its
   own situation, which is the subject of docs/self.md. */
/* Yesterday's durable lines and today's, merged with **the newer winning**: a
   line that says what an older one says takes its place rather than being
   dropped, so a correction is not mistaken for a repetition. Its own method
   because it can then be measured without an engine, which is how the defect it
   fixes was found. */
- (NSArray *)durable:(NSArray *)existing after:(NSArray *)fresh;

/*! A durable line without its citation — the day and the lesson, which is all a
   model should be given. The times are for a person and for tools/diary.py. */
- (NSString *)durableForPrompt:(NSString *)line;

- (NSDate *)metOn;
- (NSDate *)lastHeard;

/*! The time they said something **before** the thing being handled now.

   Which sounds like a nicety and is the difference between a working answer and
   a useless one. `-noteHeard:` is called by `-ask:` before the question reaches any
   recogniser, so by the time "da quanto non ci parliamo?" is answered, the most
   recent thing said is that very question, and the answer was always "un attimo
   fa". The harness had set the stamp by hand and never gone through -ask:, so it
   passed while the feature did not work at all. */
- (NSDate *)heardBefore;
- (long long)bytesOnDisk;
- (void)pruneOldDays;
- (BOOL)forgetLinesContaining:(NSString *)text;
- (void)forgetEverything;

@end
