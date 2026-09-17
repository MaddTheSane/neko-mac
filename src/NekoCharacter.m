#import "NekoCharacter.h"
#import "NekoPlugins.h"
#import "NekoPlugin.h"

/* Manifest key of every state, indexed by NekoState. */
static NSString * const NekoStateKeys[NekoStateCount] = {
	@"stop", @"jare", @"kaki", @"akubi", @"sleep", @"awake",
	@"u_move", @"d_move", @"l_move", @"r_move",
	@"ul_move", @"ur_move", @"dl_move", @"dr_move",
	@"u_togi", @"d_togi", @"l_togi", @"r_togi"
};

/* State to borrow the frames from when a manifest does not describe one.
   Diagonals fall back to the nearest cardinal, everything else eventually
   reaches "stop", which every character must provide. */
static const NekoState NekoStateFallbacks[NekoStateCount] = {
	NekoStateStop,   /* stop, the root of every chain */
	NekoStateStop,   /* jare */
	NekoStateStop,   /* kaki */
	NekoStateStop,   /* akubi */
	NekoStateStop,   /* sleep */
	NekoStateStop,   /* awake */
	NekoStateStop,   /* u_move */
	NekoStateStop,   /* d_move */
	NekoStateStop,   /* l_move */
	NekoStateStop,   /* r_move */
	NekoStateLMove,  /* ul_move */
	NekoStateRMove,  /* ur_move */
	NekoStateLMove,  /* dl_move */
	NekoStateRMove,  /* dr_move */
	NekoStateKaki,   /* u_togi */
	NekoStateKaki,   /* d_togi */
	NekoStateKaki,   /* l_togi */
	NekoStateKaki    /* r_togi */
};

static NSString * const NekoCharacterExtension = @"nekochar";
static NSString * const NekoCharacterDirectory = @"Characters";

@implementation NekoCharacter

#pragma mark Discovery

static NSArray *NekoCharacterCache = nil;

/* The ones inside the app, and then the ones enabled plugins ship. The app's own
   win a collision: a plugin cannot replace Neko with something else called
   "neko", it can only add. */
+ (NSArray<NekoCharacter*> *)availableCharacters
{
	if(NekoCharacterCache != nil)
		return NekoCharacterCache;

	NSMutableArray *characters = [NSMutableArray array];
	NSMutableSet *taken = [NSMutableSet set];

	NSString *root = [[[NSBundle mainBundle] resourcePath]
		stringByAppendingPathComponent:NekoCharacterDirectory];
	for (NSString *entry in [[NSFileManager defaultManager]
							 contentsOfDirectoryAtPath:root error:NULL]) {
		if(![[entry pathExtension] isEqualToString:NekoCharacterExtension])
			continue;
		NekoCharacter *character = [[NekoCharacter alloc]
									initWithPath:[root stringByAppendingPathComponent:entry]];
		if(character == nil || [taken containsObject:[character identifier]])
			continue;
		[taken addObject:[character identifier]];
		[characters addObject:character];
	}

	for(NekoPlugin *plugin in [[NekoPlugins sharedPlugins] enabled]) {
		for(NSString *path in [plugin characterPaths]) {
			NekoCharacter *character = [[NekoCharacter alloc]
				initWithPath:path];
			if(character == nil || [taken containsObject:[character identifier]])
				continue;
			[taken addObject:[character identifier]];
			[characters addObject:character];
		}
	}

	[characters sortUsingSelector:@selector(compareByName:)];
	NekoCharacterCache = [characters copy];
	return NekoCharacterCache;
}

/* Switching a plugin on or off changes who is available, and the list is
   cached — so it is thrown away rather than left saying yesterday's answer. */
+ (void)forgetTheList
{
	NekoCharacterCache = nil;
}

+ (NekoCharacter *)characterWithIdentifier:(NSString *)theIdentifier
{
	NSArray *characters = [self availableCharacters];
	for(NekoCharacter *character in characters) {
		if([[character identifier] isEqualToString:theIdentifier]) {
			return character;
		}
	}
	return ([characters count] > 0) ? [characters objectAtIndex:0] : nil;
}

- (NSComparisonResult)compareByName:(NekoCharacter *)other
{
	return [[self name] caseInsensitiveCompare:[other name]];
}

#pragma mark Loading

- (id)initWithPath:(NSString *)path
{
	if((self = [super init]) == nil)
		return nil;

	NSString *manifestPath = [path stringByAppendingPathComponent:@"character.plist"];
	NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfFile:manifestPath];
	if(manifest == nil) {
		NSLog(@"Neko: %@ has no readable character.plist", path);
		return nil;
	}

	identifier = [[manifest objectForKey:@"Identifier"] copy];
	if(identifier == nil)
		identifier = [[[path lastPathComponent] stringByDeletingPathExtension] copy];
	name = [[manifest objectForKey:@"Name"] copy];
	if(name == nil)
		name = [identifier copy];
	persona = [[manifest objectForKey:@"Persona"] copy];

	CGFloat width = [[manifest objectForKey:@"SpriteWidth"] doubleValue];
	CGFloat height = [[manifest objectForKey:@"SpriteHeight"] doubleValue];
	spriteSize = NSMakeSize(width > 0.0 ? width : 32.0,
	                        height > 0.0 ? height : 32.0);

	NSDictionary *states = [manifest objectForKey:@"States"];
	int i;
	for(i = 0; i < NekoStateCount; i++) {
		NSDictionary *state = [states objectForKey:NekoStateKeys[i]];
		frames[i] = [self imagesInDirectory:path
								  fileNames:[state objectForKey:@"Frames"]];
		unsigned ticks = [[state objectForKey:@"TicksPerFrame"] unsignedIntValue];
		ticksPerFrame[i] = (ticks > 0) ? ticks : 1;
	}

	if([frames[NekoStateStop] count] == 0) {
		NSLog(@"Neko: %@ describes no usable \"stop\" state", path);
		return nil;
	}
	return self;
}

- (NSArray<NSImage*> *)imagesInDirectory:(NSString *)path fileNames:(NSArray<NSString*> *)fileNames
{
	NSMutableArray *images = [NSMutableArray array];
	for(NSString *fileName in fileNames) {
		NSString *file = [path stringByAppendingPathComponent:fileName];
		NSImage *image = [[NSImage alloc] initWithContentsOfFile:file];
		if(image == nil) {
			NSLog(@"Neko: cannot load frame %@", file);
			continue;
		}
		[images addObject:image];
	}
	return images;
}

- (void)dealloc
{
	int i;
	for(i = 0; i < NekoStateCount; i++)
		frames[i] = nil;
}

#pragma mark Accessors

@synthesize identifier;
@synthesize name;

- (NSString *)persona
{
	if([persona length] > 0)
		return persona;
	return [NSString stringWithFormat:
		NSLocalizedString(@"a small pixel-art cat named %@", nil), name];
}

@synthesize spriteSize;

/* Walks the fallback chain until a described state turns up. */
- (NekoState)resolvedState:(NekoState)state
{
	int hops;
	for(hops = 0; hops < NekoStateCount; hops++) {
		if(state < 0 || state >= NekoStateCount)
			return NekoStateStop;
		if([frames[state] count] > 0)
			return state;
		state = NekoStateFallbacks[state];
	}
	return NekoStateStop;
}

- (NSArray *)framesForState:(NekoState)state
{
	return frames[[self resolvedState:state]];
}

- (unsigned)ticksPerFrameForState:(NekoState)state
{
	return ticksPerFrame[[self resolvedState:state]];
}

/*! Template rendering keeps the menu bar icon readable in both appearances, but
   it throws colour away. That suits the classic two colour sprites and ruins
   the colourful ones, so only greyscale frames become templates. */
- (BOOL)isGreyscale:(NSImage *)image
{
	NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:[image TIFFRepresentation]];
	if(rep == nil)
		return NO;
	NSInteger x, y;
	for(y = 0; y < [rep pixelsHigh]; y++) {
		for(x = 0; x < [rep pixelsWide]; x++) {
			NSColor *colour = [[rep colorAtX:x y:y]
				colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
			if(colour == nil || [colour alphaComponent] == 0.0)
				continue;
			CGFloat r = [colour redComponent];
			CGFloat g = [colour greenComponent];
			CGFloat b = [colour blueComponent];
			if(fabs(r - g) > 0.02 || fabs(g - b) > 0.02)
				return NO;
		}
	}
	return YES;
}

- (NSImage *)menuBarImage
{
	NSImage *frame = [[self framesForState:NekoStateStop] objectAtIndex:0];
	NSImage *image = [frame copy];
	[image setSize:NSMakeSize(18.0f, 18.0f)];
	[image setTemplate:[self isGreyscale:frame]];
	return image;
}

@end
