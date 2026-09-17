#import "NekoPainter.h"
#import "NekoModelStore.h"
#import "NekoAnswerProvider.h"

NSString * const NekoDrawEnabledKey = @"NekoDrawEnabled";
NSString * const NekoDrawModelKey   = @"NekoDrawModel";
NSString * const NekoDrawStepsKey   = @"NekoDrawSteps";
NSString * const NekoDrawSizeKey    = @"NekoDrawSize";

#define NekoPainterLocalized(text) NSLocalizedString(text, nil)

@implementation NekoPainter

+ (void)initialize
{
	if(self != [NekoPainter class])
		return;
	[[NSUserDefaults standardUserDefaults] registerDefaults:
		[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithBool:NO], NekoDrawEnabledKey,
			[NSNumber numberWithInt:14], NekoDrawStepsKey,
			[NSNumber numberWithInt:512], NekoDrawSizeKey, nil]];
}

+ (NekoPainter *)sharedPainter
{
	static NekoPainter *shared = nil;
	if(shared == nil)
		shared = [[NekoPainter alloc] init];
	return shared;
}

- (void)dealloc
{
	[self cancel];
	[scratch release];
	[super dealloc];
}

#pragma mark What it needs

- (NSString *)helperPath
{
	NSString *path = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"neko-paint"];
	if(path == nil)
		return nil;
	return [[NSFileManager defaultManager] isExecutableFileAtPath:path] ? path : nil;
}

/* Whichever of them somebody chose, and the first when nobody has. Not
   -firstObject any more: there is more than one now, and this used to be the
   only thing deciding which was used. */
- (NekoLocalModel *)model
{
	NekoModelStore *store = [NekoModelStore sharedStore];
	NSString *chosen = [[NSUserDefaults standardUserDefaults]
		stringForKey:NekoDrawModelKey];
	NSEnumerator *e = [[store pictureCatalogue] objectEnumerator];
	NekoLocalModel *each;
	while((each = [e nextObject]) != nil)
		if([[each identifier] isEqualToString:chosen])
			return each;
	return [[store pictureCatalogue] firstObject];
}

- (NSURL *)modelURL
{
	return [[NekoModelStore sharedStore]
		installedURLForIdentifier:[[self model] identifier]];
}

- (BOOL)isReady
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:NekoDrawEnabledKey]
		&& [self helperPath] != nil
		&& [self modelURL] != nil;
}

- (NSString *)hint
{
	if([self helperPath] == nil)
		return NekoPainterLocalized(@"This build has no drawing program in it.");
	if([self modelURL] == nil)
		return NekoPainterLocalized(@"Download the picture model first.");
	if(![[NSUserDefaults standardUserDefaults] boolForKey:NekoDrawEnabledKey])
		return NekoPainterLocalized(@"Drawing is switched off.");
	return nil;
}

#pragma mark Drawing

- (BOOL)isDrawing
{
	return task != nil && [task isRunning];
}

- (void)cancel
{
	if(task != nil && [task isRunning])
		[task terminate];
	[task release];
	task = nil;
}

- (void)draw:(NSString *)prompt
  completion:(void (^)(NSImage *picture, NSError *error))completion
{
	NSString *helper = [self helperPath];
	NSURL *model = [self modelURL];
	if(helper == nil || model == nil || [prompt length] == 0) {
		completion(nil, [NSError errorWithDomain:NekoAskErrorDomain
		                                    code:NekoAskErrorNotConfigured
		                                userInfo:nil]);
		return;
	}
	[self cancel];

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NekoLocalModel *chosen = [self model];
	int steps = (int)[defaults integerForKey:NekoDrawStepsKey];
	int side = (int)[defaults integerForKey:NekoDrawSizeKey];
	if(steps < 1) steps = [chosen drawSteps] > 0 ? [chosen drawSteps] : 14;
	if(side < 128) side = [chosen drawSide] > 0 ? [chosen drawSide] : 512;
	/* The guidance is the model's and not somebody's to set: it is not a taste,
	   it is what the checkpoint was distilled for. A turbo model at seven draws
	   mush, and there is no reason anybody would want that. */
	CGFloat guidance = [chosen drawGuidance] > 0.0 ? [chosen drawGuidance] : 7.0;

	[scratch release];
	scratch = [[NSTemporaryDirectory() stringByAppendingPathComponent:
		[NSString stringWithFormat:@"neko-drawing-%u.png", arc4random()]] retain];

	NSArray *arguments = [NSArray arrayWithObjects:
		@"-M", @"img_gen",
		@"-m", [model path],
		@"-p", prompt,
		@"-o", scratch,
		@"--steps", [NSString stringWithFormat:@"%d", steps],
		@"-W", [NSString stringWithFormat:@"%d", side],
		@"-H", [NSString stringWithFormat:@"%d", side],
		@"--sampling-method", @"euler_a",
		@"--cfg-scale", [NSString stringWithFormat:@"%.1f", guidance],
		/* A pet's picture, not a print: a fixed seed would draw the same
		   Colosseum every time it was asked. */
		@"-s", [NSString stringWithFormat:@"%u", arc4random_uniform(1000000)],
		@"--diffusion-fa", nil];

	task = [[NSTask alloc] init];
	[task setLaunchPath:helper];
	[task setArguments:arguments];
	[task setStandardOutput:[NSPipe pipe]];
	[task setStandardError:[NSPipe pipe]];

	void (^done)(NSImage *, NSError *) = Block_copy(completion);
	NSString *file = [[scratch copy] autorelease];

	[task setTerminationHandler:^(NSTask *finished) {
		NSImage *picture = nil;
		if([finished terminationStatus] == 0)
			picture = [[[NSImage alloc] initWithContentsOfFile:file] autorelease];
		NSError *problem = picture != nil ? nil :
			[NSError errorWithDomain:NekoAskErrorDomain
			                    code:NekoAskErrorNoAnswer
			                userInfo:[NSDictionary dictionaryWithObject:
				NekoPainterLocalized(@"The drawing did not come out.")
				                                                 forKey:NSLocalizedDescriptionKey]];
		dispatch_async(dispatch_get_main_queue(), ^{
			done(picture, problem);
			Block_release(done);
			[[NSFileManager defaultManager] removeItemAtPath:file error:NULL];
		});
	}];

	NS_DURING
		[task launch];
	NS_HANDLER
		[self cancel];
		completion(nil, [NSError errorWithDomain:NekoAskErrorDomain
		                                    code:NekoAskErrorTransport
		                                userInfo:nil]);
		Block_release(done);
	NS_ENDHANDLER
}

@end
