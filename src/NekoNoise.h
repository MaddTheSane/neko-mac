/* NekoNoise */

#import <Cocoa/Cocoa.h>

/*! Timing that drifts instead of scattering.

   Everything the cat waits for was drawn from a flat distribution: each pause
   independent of the last, every value as likely as every other. It reads as a
   metronome with the beats moved about, which is what the source comment on the
   roaming rest was reaching for and not quite getting.

   Natural variation is not flat. Procedural animation built on 1/f — pink —
   noise is judged natural in perceptual studies, while the same motion with no
   jitter, or with white jitter, is picked as the least natural of the three. The
   difference is not the range of the values, it is that neighbouring values are
   related: a slow afternoon stays slow for a while, and then it does not.

   Voss-McCartney: a handful of random walks, each redrawn half as often as the
   one before it, added together. Twenty lines, no allocation, and its own
   generator so that a test can replay the same sequence twice. */
@interface NekoNoise : NSObject
{
	double rows[10];
	unsigned taps;               /*!< how many of those rows are in use */
	unsigned counter;
	unsigned long seed;
}

/*! One shared stream: the cat has one sense of time, not one per feature. */
@property (class, readonly, retain) NekoNoise *sharedNoise;

/*! A stream that can be replayed. Seed 0 asks for an unpredictable one. */
- (instancetype)initWithSeed:(unsigned long)aSeed;

/*! The next value, 0 to 1, correlated with the last one. */
- (double)next;

/*! The same, as a whole number below span — the shape of the calls this
   replaces. */
- (unsigned)nextBelow:(unsigned)span;

/*! Around one, for scaling a duration: 0.6 to 1.4, averaging 1. */
- (double)nextScale;

@end
