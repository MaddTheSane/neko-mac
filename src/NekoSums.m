#import "NekoSums.h"
#import "NekoWhen.h"
#import <math.h>

static NSLocale *NekoSumsLocale(void)
{
	NSString *code = [[[NSBundle mainBundle] preferredLocalizations] firstObject];
	return [NSLocale localeWithLocaleIdentifier:code ?: @"en"];
}

#pragma mark A number, written the way the language writes it

static NSString *NekoNumberWritten(double value)
{
	NSNumberFormatter *formatter = [[[NSNumberFormatter alloc] init] autorelease];
	[formatter setLocale:NekoSumsLocale()];
	[formatter setNumberStyle:NSNumberFormatterDecimalStyle];
	[formatter setMaximumFractionDigits:6];
	/* Whole answers stay whole: 1081, not 1.081,000. */
	[formatter setMinimumFractionDigits:0];
	return [formatter stringFromNumber:[NSNumber numberWithDouble:value]];
}

#pragma mark The parser

/* Written by hand rather than handed to NSExpression, for the reason in the
   header: NSExpression answers 7/2 with 3. Ordinary precedence, parentheses,
   a right-associative power, and a unary minus. Anything it cannot read sets
   `failed`, and a failed sum is a sum this says nothing about. */
typedef struct {
	const unichar *chars;
	NSUInteger length;
	NSUInteger at;
	BOOL failed;
} NekoSum;

static double NekoSumExpression(NekoSum *scan);

static void NekoSumSkipSpace(NekoSum *scan)
{
	while(scan->at < scan->length && scan->chars[scan->at] == ' ')
		scan->at++;
}

static double NekoSumPrimary(NekoSum *scan)
{
	NekoSumSkipSpace(scan);
	if(scan->at >= scan->length) {
		scan->failed = YES;
		return 0.0;
	}
	if(scan->chars[scan->at] == '(') {
		scan->at++;
		double inside = NekoSumExpression(scan);
		NekoSumSkipSpace(scan);
		if(scan->at >= scan->length || scan->chars[scan->at] != ')') {
			scan->failed = YES;
			return 0.0;
		}
		scan->at++;
		return inside;
	}

	NSUInteger start = scan->at;
	while(scan->at < scan->length &&
	      ((scan->chars[scan->at] >= '0' && scan->chars[scan->at] <= '9') ||
	       scan->chars[scan->at] == '.'))
		scan->at++;
	if(scan->at == start) {
		scan->failed = YES;
		return 0.0;
	}
	NSString *digits = [NSString stringWithCharacters:scan->chars + start
	                                           length:scan->at - start];
	/* Read with a fixed locale: the comma has already become a point, and
	   -doubleValue would read "3.5" as 3 where the language uses a comma. */
	NSNumberFormatter *plain = [[[NSNumberFormatter alloc] init] autorelease];
	[plain setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
	[plain setNumberStyle:NSNumberFormatterDecimalStyle];
	NSNumber *read = [plain numberFromString:digits];
	if(read == nil) {
		scan->failed = YES;
		return 0.0;
	}
	return [read doubleValue];
}

static double NekoSumUnary(NekoSum *scan)
{
	NekoSumSkipSpace(scan);
	if(scan->at < scan->length && scan->chars[scan->at] == '-') {
		scan->at++;
		return -NekoSumUnary(scan);
	}
	if(scan->at < scan->length && scan->chars[scan->at] == '+') {
		scan->at++;
		return NekoSumUnary(scan);
	}
	return NekoSumPrimary(scan);
}

static double NekoSumPower(NekoSum *scan)
{
	double left = NekoSumUnary(scan);
	NekoSumSkipSpace(scan);
	if(scan->at < scan->length && scan->chars[scan->at] == '^') {
		scan->at++;
		double right = NekoSumPower(scan);       /* right associative */
		return pow(left, right);
	}
	return left;
}

static double NekoSumTerm(NekoSum *scan)
{
	double left = NekoSumPower(scan);
	for(;;) {
		NekoSumSkipSpace(scan);
		if(scan->at >= scan->length)
			return left;
		unichar sign = scan->chars[scan->at];
		if(sign != '*' && sign != '/')
			return left;
		scan->at++;
		double right = NekoSumPower(scan);
		if(sign == '*') {
			left = left * right;
		} else {
			/* Nothing is said rather than infinity being said. */
			if(right == 0.0) {
				scan->failed = YES;
				return 0.0;
			}
			left = left / right;
		}
	}
}

static double NekoSumExpression(NekoSum *scan)
{
	double left = NekoSumTerm(scan);
	for(;;) {
		NekoSumSkipSpace(scan);
		if(scan->at >= scan->length)
			return left;
		unichar sign = scan->chars[scan->at];
		if(sign != '+' && sign != '-')
			return left;
		scan->at++;
		double right = NekoSumTerm(scan);
		left = (sign == '+') ? left + right : left - right;
	}
}

/* The whole string, or nothing. A sum that parses halfway is not a sum. */
static BOOL NekoSumEvaluate(NSString *text, double *answer)
{
	NSUInteger length = [text length];
	if(length == 0 || length > 200)
		return NO;
	unichar *chars = malloc(sizeof(unichar) * length);
	[text getCharacters:chars range:NSMakeRange(0, length)];
	NekoSum scan = { chars, length, 0, NO };
	double value = NekoSumExpression(&scan);
	NekoSumSkipSpace(&scan);
	BOOL whole = !scan.failed && scan.at == length;
	free(chars);
	if(!whole || !isfinite(value))
		return NO;
	*answer = value;
	return YES;
}

#pragma mark Turning a sentence into something the parser can read

static NSString *NekoReplacingWholeWords(NSString *text, NSDictionary<NSString*,NSString*> *swaps)
{
	NSMutableString *out = [NSMutableString stringWithString:text];
	/* Longest first, so "elevato a" beats "a" and "per cento" beats "per". */
	NSArray *keys = [[swaps allKeys] sortedArrayUsingComparator:
		^NSComparisonResult(NSString *a, NSString *b) {
			if([b length] > [a length]) return NSOrderedDescending;
			if([b length] < [a length]) return NSOrderedAscending;
			return NSOrderedSame;
		}];
	for(NSString *word in keys) {
		NSString *pattern = [NSString stringWithFormat:@"(?<![\\p{L}\\p{N}])%@(?![\\p{L}\\p{N}])",
			[NSRegularExpression escapedPatternForString:word]];
		NSRegularExpression *regex = [NSRegularExpression
			regularExpressionWithPattern:pattern options:0 error:NULL];
		if(regex == nil)
			continue;
		[regex replaceMatchesInString:out options:0
		                        range:NSMakeRange(0, [out length])
		                 withTemplate:[swaps objectForKey:word]];
	}
	return out;
}

static NSString *NekoRegexReplace(NSString *text, NSString *pattern, NSString *with)
{
	NSRegularExpression *regex = [NSRegularExpression
		regularExpressionWithPattern:pattern options:0 error:NULL];
	if(regex == nil)
		return text;
	return [regex stringByReplacingMatchesInString:text options:0
	                                         range:NSMakeRange(0, [text length])
	                                  withTemplate:with];
}

/* The words four languages use for the four operations, and the numbers up to
   twelve — the same table the timer reads, so "quanto fa sette per otto" works
   and is not a second list to keep in step. */
static NSString *NekoAsArithmetic(NSString *lowered)
{
	static NSDictionary *operators = nil;
	if(operators == nil)
		operators = [[NSDictionary dictionaryWithObjectsAndKeys:
			@"+", @"più", @"+", @"piu", @"+", @"plus", @"+", @"más", @"+", @"mas",
			@"-", @"meno", @"-", @"minus", @"-", @"moins", @"-", @"menos",
			@"*", @"per", @"*", @"times", @"*", @"por", @"*", @"fois",
			@"*", @"moltiplicato", @"*", @"multiplied", @"*", @"x", @"*", @"×",
			@"/", @"diviso", @"/", @"divided", @"/", @"dividido", @"/", @"divisé",
			@"/", @"divise", @"/", @"÷",
			@"^", @"elevato", @"^", @"alla", @"^", @"al quadrato",
			nil] retain];

	NSString *text = lowered;

	/* A percentage of something, before anything else: the "di" in "il 18% di
	   240" is a multiplication and nothing else in this table would say so. */
	text = NekoReplacingWholeWords(text, [NSDictionary dictionaryWithObjectsAndKeys:
		@"%", @"per cento", @"%", @"percento", @"%", @"percent",
		@"%", @"por ciento", @"%", @"pour cent", nil]);
	text = NekoRegexReplace(text,
		@"(\\d+(?:[.,]\\d+)?)\\s*%\\s*(?:di|dei|del|della|dello|of|de|du|des)\\b",
		@"($1/100)*");

	/* The articles, which "quanto fa il 18% di 240" leaves behind and which would
	   otherwise make a perfectly good sum look like a sentence. */
	text = NekoReplacingWholeWords(text, [NSDictionary dictionaryWithObjectsAndKeys:
		@"", @"il", @"", @"lo", @"", @"la", @"", @"i", @"", @"gli", @"", @"le",
		@"", @"the", @"", @"el", @"", @"los", @"", @"las", @"", @"les",
		nil]);

	text = NekoReplacingWholeWords(text, operators);

	/* Written numbers, then the decimal comma, then the digit grouping a
	   language writes with a point — in that order, since each undoes the
	   ambiguity the next one would otherwise inherit. */
	NSMutableDictionary *numbers = [NSMutableDictionary dictionary];
	for(NSString *one in [NekoWhen writtenNumbers]) {
		/* "a" and "an" are articles far more often than they are one. */
		if([one isEqualToString:@"a"] || [one isEqualToString:@"an"] ||
		   [one isEqualToString:@"un"] || [one isEqualToString:@"una"] ||
		   [one isEqualToString:@"une"] || [one isEqualToString:@"uno"])
			continue;
		[numbers setObject:[[NekoWhen writtenNumbers] objectForKey:one] forKey:one];
	}
	NSMutableDictionary *asText = [NSMutableDictionary dictionary];
	for(NSString *one in numbers)
		[asText setObject:[[numbers objectForKey:one] stringValue] forKey:one];
	text = NekoReplacingWholeWords(text, asText);

	text = NekoRegexReplace(text, @"(\\d),(\\d)", @"$1.$2");
	text = NekoRegexReplace(text, @"(\\d)\\.(\\d\\d\\d)(?![\\d])", @"$1$2");

	/* Everything that is not a sum, gone — and then the check that nothing that
	   mattered was among it. */
	text = [text stringByTrimmingCharactersInSet:
		[NSCharacterSet characterSetWithCharactersInString:@" ?!.=\t\n"]];
	return text;
}

static BOOL NekoLooksLikeASum(NSString *text)
{
	static NSCharacterSet *allowed = nil;
	if(allowed == nil)
		allowed = [[NSCharacterSet characterSetWithCharactersInString:
			@"0123456789.+-*/^() "] retain];
	if([text length] == 0)
		return NO;
	if([[text stringByTrimmingCharactersInSet:allowed] length] > 0)
		return NO;
	/* A bare number is not a question. */
	NSCharacterSet *operators = [NSCharacterSet
		characterSetWithCharactersInString:@"+-*/^"];
	return [text rangeOfCharacterFromSet:operators].location != NSNotFound;
}

#pragma mark Units

/*! Word, unit, and what kind of thing it measures — two units of different kinds
   are a sentence this says nothing about. The words are whole words, longest
   first when they overlap, so "chilometri" is never read as "metri". */
static NSArray *NekoKnownUnits(void)
{
	static NSArray *units = nil;
	if(units != nil)
		return units;

	NSMutableArray *all = [[NSMutableArray alloc] init];
	void (^add)(NSString *, NSString *, NSUnit *) =
		^(NSString *kind, NSString *words, NSUnit *unit) {
		NSArray *seperated = [words componentsSeparatedByString:@","];
		for(NSString *word in seperated)
			[all addObject:@[word, kind, unit]];
	};

	add(@"length", @"chilometri,chilometro,kilometri,kilometers,kilometres,km",
		[NSUnitLength kilometers]);
	add(@"length", @"centimetri,centimetro,centimeters,cm", [NSUnitLength centimeters]);
	add(@"length", @"millimetri,millimetro,millimeters,mm", [NSUnitLength millimeters]);
	add(@"length", @"metri,metro,meters,metres,mètres", [NSUnitLength meters]);
	add(@"length", @"miglia,miglio,miles,mile,mi", [NSUnitLength miles]);
	add(@"length", @"piedi,piede,feet,foot,ft", [NSUnitLength feet]);
	add(@"length", @"pollici,pollice,inches,inch", [NSUnitLength inches]);
	add(@"length", @"iarde,iarda,yards,yard", [NSUnitLength yards]);

	add(@"mass", @"chilogrammi,chilogrammo,chili,chilo,kilos,kilograms,kg",
		[NSUnitMass kilograms]);
	add(@"mass", @"grammi,grammo,grams,gram,g", [NSUnitMass grams]);
	add(@"mass", @"libbre,libbra,pounds,pound,lbs,lb", [NSUnitMass poundsMass]);
	add(@"mass", @"once,oncia,ounces,ounce,oz", [NSUnitMass ounces]);
	add(@"mass", @"tonnellate,tonnellata,tonnes,tons,ton", [NSUnitMass metricTons]);

	add(@"temperature", @"fahrenheit,°f", [NSUnitTemperature fahrenheit]);
	add(@"temperature", @"kelvin", [NSUnitTemperature kelvin]);
	add(@"temperature", @"celsius,centigradi,gradi,grado,°c",
		[NSUnitTemperature celsius]);

	add(@"volume", @"millilitri,millilitro,millilitres,milliliters,ml",
		[NSUnitVolume milliliters]);
	add(@"volume", @"litri,litro,litres,liters,liter,litre", [NSUnitVolume liters]);
	add(@"volume", @"galloni,gallone,gallons,gallon", [NSUnitVolume gallons]);
	add(@"volume", @"pinte,pinta,pints,pint", [NSUnitVolume pints]);
	add(@"volume", @"tazze,cups,cup", [NSUnitVolume cups]);

	add(@"duration", @"secondi,secondo,seconds,second,segundos",
		[NSUnitDuration seconds]);
	add(@"duration", @"minuti,minuto,minutes,minute,minutos", [NSUnitDuration minutes]);
	add(@"duration", @"ore,ora,hours,hour,heures,horas", [NSUnitDuration hours]);

	add(@"speed", @"km/h,kmh,chilometri orari", [NSUnitSpeed kilometersPerHour]);
	add(@"speed", @"mph,miglia orarie", [NSUnitSpeed milesPerHour]);
	add(@"speed", @"nodi,knots", [NSUnitSpeed knots]);
	add(@"speed", @"m/s", [NSUnitSpeed metersPerSecond]);

	add(@"storage", @"gigabyte,gb", [NSUnitInformationStorage gigabytes]);
	add(@"storage", @"megabyte,mb", [NSUnitInformationStorage megabytes]);
	add(@"storage", @"terabyte,tb", [NSUnitInformationStorage terabytes]);
	add(@"storage", @"kilobyte,chilobyte,kb", [NSUnitInformationStorage kilobytes]);
	add(@"storage", @"byte", [NSUnitInformationStorage bytes]);

	[all sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
		NSUInteger left = [[a objectAtIndex:0] length];
		NSUInteger right = [[b objectAtIndex:0] length];
		if(left > right) return NSOrderedAscending;
		if(left < right) return NSOrderedDescending;
		return NSOrderedSame;
	}];
	units = [all copy];
	[all release];
	return units;
}

static BOOL NekoWholeWordAt(NSString *text, NSRange found)
{
	NSCharacterSet *letters = [NSCharacterSet alphanumericCharacterSet];
	if(found.location > 0 &&
	   [letters characterIsMember:[text characterAtIndex:found.location - 1]])
		return NO;
	NSUInteger after = NSMaxRange(found);
	if(after < [text length] && [letters characterIsMember:[text characterAtIndex:after]])
		return NO;
	return YES;
}

@implementation NekoSums

#pragma mark Conversion

+ (NSString *)conversionIn:(NSString *)lowered
{
	/* Exactly one number. Two would be a sentence about something else. */
	NSRegularExpression *digits = [NSRegularExpression
		regularExpressionWithPattern:@"\\d+(?:[.,]\\d+)?" options:0 error:NULL];
	NSArray *found = [digits matchesInString:lowered options:0
	                                   range:NSMakeRange(0, [lowered length])];
	if([found count] != 1)
		return nil;
	NSRange numberAt = [[found objectAtIndex:0] range];
	double amount = [[[lowered substringWithRange:numberAt]
		stringByReplacingOccurrencesOfString:@"," withString:@"."] doubleValue];

	/* Every unit word in the sentence, longest first and never overlapping one
	   already claimed. */
	NSMutableArray *seen = [NSMutableArray array];
	NSMutableIndexSet *taken = [NSMutableIndexSet indexSet];
	[taken addIndexesInRange:numberAt];
	for(NSArray *entry in NekoKnownUnits()) {
		NSString *word = [entry objectAtIndex:0];
		NSRange search = NSMakeRange(0, [lowered length]);
		for(;;) {
			NSRange at = [lowered rangeOfString:word options:0 range:search];
			if(at.location == NSNotFound)
				break;
			search = NSMakeRange(NSMaxRange(at), [lowered length] - NSMaxRange(at));
			if(!NekoWholeWordAt(lowered, at))
				continue;
			if([taken containsIndexesInRange:at] ||
			   [taken intersectsIndexesInRange:at])
				continue;
			[taken addIndexesInRange:at];
			[seen addObject:[NSArray arrayWithObjects:
				[NSNumber numberWithUnsignedInteger:at.location],
				[entry objectAtIndex:1], [entry objectAtIndex:2], nil]];
		}
	}
	if([seen count] != 2)
		return nil;

	[seen sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
		return [[a objectAtIndex:0] compare:[b objectAtIndex:0]];
	}];
	NSArray *first = [seen objectAtIndex:0], *second = [seen objectAtIndex:1];
	if(![[first objectAtIndex:1] isEqualToString:[second objectAtIndex:1]])
		return nil;                    /* litres into kilometres */

	/* The unit the number belongs to is the one that comes after it — "5 miglia
	   in km" and "quanti km sono 5 miglia" are the same sentence read this way. */
	NSArray *from = second, *into = first;
	if([[first objectAtIndex:0] unsignedIntegerValue] > numberAt.location) {
		from = first;
		into = second;
	}
	NSUnit *fromUnit = [from objectAtIndex:2], *intoUnit = [into objectAtIndex:2];
	if(fromUnit == intoUnit)
		return nil;

	NSMeasurement *said = [[[NSMeasurement alloc] initWithDoubleValue:amount
	                                                            unit:fromUnit] autorelease];
	NSMeasurement *answer = [said measurementByConvertingToUnit:intoUnit];

	NSMeasurementFormatter *formatter = [[[NSMeasurementFormatter alloc] init] autorelease];
	[formatter setLocale:NekoSumsLocale()];
	[formatter setUnitOptions:NSMeasurementFormatterUnitOptionsProvidedUnit];
	[formatter setUnitStyle:NSFormattingUnitStyleMedium];
	[[formatter numberFormatter] setMaximumFractionDigits:4];

	/* Said with an equals sign rather than in a sentence, the same shape the
	   arithmetic uses: it is checkable at a glance and it has no grammar to get
	   wrong in four languages. */
	return [NSString stringWithFormat:@"%@ = %@",
		[formatter stringFromMeasurement:said],
		[formatter stringFromMeasurement:answer]];
}

#pragma mark Arithmetic

+ (NSString *)sumIn:(NSString *)lowered
{
	/* The phrase that asks, when there is one. A sum can also arrive on its own
	   — "12*7" is not a sentence about anything else — so this is not required. */
	NSArray *triggers = @[
		@"quanto fa", @"quanto fanno", @"quanto è", @"quanto e'", @"quant'è",
		@"quanto viene", @"calcola", @"calcolami",
		@"how much is", @"what is", @"what's", @"calculate", @"work out",
		@"combien font", @"combien fait", @"calcule",
		@"cuánto es", @"cuanto es", @"cuánto son", @"cuanto son", @"calcula"];
	NSString *text = lowered;
	for(NSString *trigger in triggers) {
		NSRange at = [text rangeOfString:trigger];
		if(at.location == NSNotFound)
			continue;
		text = [text substringFromIndex:NSMaxRange(at)];
		break;
	}

	NSString *sum = NekoAsArithmetic(text);
	if(!NekoLooksLikeASum(sum))
		return nil;
	double answer = 0.0;
	if(!NekoSumEvaluate(sum, &answer))
		return nil;

	/* Said back with the sum in it, because a number on its own cannot be
	   checked and this one can be wrong about what it heard rather than about
	   the arithmetic. */
	NSString *shown = [[sum stringByReplacingOccurrencesOfString:@"*" withString:@"×"]
		stringByReplacingOccurrencesOfString:@"/" withString:@"÷"];
	/* One space around every operator, whatever the sentence had: "18%di240"
	   and "18 % di 240" arrive here as the same string and should read as it. */
	shown = NekoRegexReplace(shown, @"\\s*([+\\-×÷^])\\s*", @" $1 ");
	shown = NekoRegexReplace(shown, @"\\s+", @" ");
	return [NSString stringWithFormat:@"%@ = %@",
		[shown stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceCharacterSet]], NekoNumberWritten(answer)];
}

#pragma mark

+ (NSString *)wantedFor:(NSString *)question
{
	NSString *lowered = [question lowercaseString];
	NSString *answer = [self conversionIn:lowered];
	if(answer != nil)
		return answer;
	return [self sumIn:lowered];
}

@end
