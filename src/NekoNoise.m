#import "NekoNoise.h"

/*! Eight taps: the correlation reaches about 2^8 values back, which for pauses of
   a second or two is a couple of minutes of memory. More than that and the cat
   would have moods measured in hours. */
static const unsigned NekoNoiseTaps = 8;

/*! Adding eight uniform draws together narrows the result towards the middle —
   the central limit doing what it does — and a cat whose pauses are all nearly
   average is not what any of this is for. The values are stretched back out
   around the centre; the factor was measured rather than guessed (see
   tests/noise.m: it puts the spread within a tenth of the flat draw's while
   keeping the slope). */
static const double NekoNoiseStretch = 2.4;

@implementation NekoNoise

+ (NekoNoise *)sharedNoise
{
	static NekoNoise *shared = nil;
	if(shared == nil)
		shared = [[NekoNoise alloc] initWithSeed:0];
	return shared;
}

- (id)initWithSeed:(unsigned long)aSeed
{
	if((self = [super init]) != nil) {
		taps = NekoNoiseTaps;
		seed = aSeed != 0 ? aSeed : ((unsigned long)arc4random() | 1UL);
		counter = 0;
		unsigned i;
		for(i = 0; i < taps; i++)
			rows[i] = [self uniform];
	}
	return self;
}

/*! Its own generator, so that the same seed gives the same afternoon twice.
   Numerical Recipes' constants; nothing here needs cryptography. */
- (double)uniform
{
	seed = seed * 1664525UL + 1013904223UL;
	return (double)((seed >> 16) & 0xFFFF) / 65536.0;
}

- (double)next
{
	/* Which rows are redrawn is decided by the bits that changed when the
	   counter advanced: row 0 every call, row 1 every second, row 2 every
	   fourth, and so on. That is the whole trick. */
	unsigned before = counter;
	counter++;
	unsigned changed = before ^ counter;

	double sum = 0.0;
	unsigned i;
	for(i = 0; i < taps; i++) {
		if(changed & (1u << i))
			rows[i] = [self uniform];
		sum += rows[i];
	}

	double value = (sum / (double)taps - 0.5) * NekoNoiseStretch + 0.5;
	if(value < 0.0)
		value = 0.0;
	if(value > 0.999999)
		value = 0.999999;
	return value;
}

- (unsigned)nextBelow:(unsigned)span
{
	if(span == 0)
		return 0;
	return (unsigned)([self next] * (double)span);
}

- (double)nextScale
{
	return 0.6 + 0.8 * [self next];
}

@end
