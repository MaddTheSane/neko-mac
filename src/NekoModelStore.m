#import "NekoModelStore.h"
#import "NekoAnswerProvider.h"

NSString * const NekoModelsDirectoryKey = @"NekoModelsDirectory";
NSString * const NekoModelMemoryKey = @"NekoModelMemory";

#pragma mark Whether this Mac can run it

/* The weights are memory-mapped, so what a model costs to answer with is close
   to its file size — plus the context, the KV cache and llama.cpp's own buffers,
   which at the short context this application asks for come to something under
   a gigabyte and a half. Rounded up rather than down: the failure this guards
   against is somebody being told yes and finding out no. */
static const long long NekoModelWorkingSet = 1500LL * 1000LL * 1000LL;

/* And what the rest of the Mac needs while that happens. Four gigabytes is the
   system, the window server, a browser with a few tabs and whatever somebody was
   already doing — which is the state a model actually gets loaded in, not an
   idle machine. */
static const long long NekoModelLeaveForTheMac = 4000LL * 1000LL * 1000LL;


@implementation NekoLocalModel

- (id)initWithIdentifier:(NSString *)anIdentifier
                    name:(NSString *)aName
                  detail:(NSString *)aDetail
                     url:(NSURL *)aURL
                   bytes:(long long)bytes
                  thinks:(BOOL)thinksOutLoud
{
	if((self = [super init]) != nil) {
		thinks = thinksOutLoud;
		identifier = [anIdentifier copy];
		name = [aName copy];
		detail = [aDetail copy];
		url = [aURL retain];
		expectedBytes = bytes;
	}
	return self;
}

- (id)initWithIdentifier:(NSString *)anIdentifier
                    name:(NSString *)aName
                  detail:(NSString *)aDetail
                     url:(NSURL *)aURL
                   bytes:(long long)bytes
                   steps:(int)steps
                guidance:(CGFloat)guidance
                    side:(int)side
{
	if((self = [self initWithIdentifier:anIdentifier name:aName detail:aDetail
	                                url:aURL bytes:bytes thinks:NO]) != nil) {
		drawSteps = steps;
		drawGuidance = guidance;
		drawSide = side;
	}
	return self;
}

- (int)drawSteps       { return drawSteps; }
- (CGFloat)drawGuidance  { return drawGuidance; }
- (int)drawSide        { return drawSide; }

- (void)dealloc
{
	[identifier release];
	[name release];
	[detail release];
	[url release];
	[super dealloc];
}

@synthesize identifier;
@synthesize name;
@synthesize detail;
@synthesize url;
@synthesize expectedBytes;
@synthesize thinks;

- (long long)memoryNeeded
{
	return expectedBytes + NekoModelWorkingSet;
}

- (NekoModelFit)fitOnThisMac
{
	long long room = [NekoModelStore memoryForAModel];
	long long needed = [self memoryNeeded];
	if(needed > room)
		return NekoModelWillNotLoad;
	/* Inside the room but against the ceiling: it loads, and then the Mac spends
	   the day swapping. Worth saying out loud rather than discovering. */
	if(needed > (room * 4LL) / 5LL)
		return NekoModelFitsTightly;
	return NekoModelFitsWell;
}

- (NSString *)memoryWarning
{
	double needed = (double)[self memoryNeeded] / 1e9;
	double here = (double)[NekoModelStore memoryOnThisMac] / 1e9;
	switch([self fitOnThisMac]) {
		case NekoModelWillNotLoad:
			return [NSString stringWithFormat:
				NSLocalizedString(@"Needs about %.0f GB of memory. This Mac has %.0f GB.", nil),
				needed, here];
		case NekoModelFitsTightly:
			return [NSString stringWithFormat:
				NSLocalizedString(@"Fits barely: %.0f GB of %.0f GB. The Mac will feel it.", nil),
				needed, here];
		case NekoModelFitsWell:
		default:
			return nil;
	}
}

@end


@implementation NekoModelStore

+ (NekoModelStore *)sharedStore
{
	static NekoModelStore *shared = nil;
	if(shared == nil)
		shared = [[NekoModelStore alloc] init];
	return shared;
}

- (id)init
{
	if((self = [super init]) != nil) {
		NSURLSessionConfiguration *configuration =
			[NSURLSessionConfiguration defaultSessionConfiguration];
		/* Hundreds of megabytes over a possibly slow line: no request timeout,
		   but give up if nothing arrives for a minute. */
		[configuration setTimeoutIntervalForRequest:60.0];
		[configuration setTimeoutIntervalForResource:0.0];
		session = [[NSURLSession sessionWithConfiguration:configuration] retain];
	}
	return self;
}

#pragma mark What can be had

- (NSArray *)catalogue
{
	static NSArray *cached = nil;
	if(cached != nil)
		return cached;

	/* Instruction-tuned models in GGUF, the format the engine reads, ordered by
	   size. The descriptions are what they actually do: the half-billion one was
	   asked for the capital of Italy and answered "Italie, la capitale d'Italia,
	   è Roma", which is the sort of thing worth warning about rather than
	   dressing up. Sizes are the published ones, used to show progress before
	   the server says how long the file is.

	   **Why the list stops at four billion parameters.** The newest Qwen is
	   `Qwen3.8-Flash-Next`, and it was asked for rather than guessed at. Its
	   own files answer: the four-bit build is 111 GB across four pieces, and
	   the smallest one-bit build is 72 GB across three. Nothing here can
	   download a model in pieces, and nothing sold as a laptop can hold one.
	   So the most recent thing that fits is Qwen3.5 4B, which is the last
	   entry, and the big one is left out rather than listed and unusable. */
	cached = [[NSArray alloc] initWithObjects:
		[[[NekoLocalModel alloc]
			initWithIdentifier:@"qwen2.5-0.5b-instruct-q4"
			              name:@"Qwen2.5 0.5B Instruct"
			            detail:NSLocalizedString(@"468 MB — answers in a blink, and gets simple facts wrong", nil)
			               url:[NSURL URLWithString:@"https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"]
			             bytes:491544576LL
			            thinks:NO] autorelease],
		[[[NekoLocalModel alloc]
			initWithIdentifier:@"qwen2.5-1.5b-instruct-q4"
			              name:@"Qwen2.5 1.5B Instruct"
			            detail:NSLocalizedString(@"1.0 GB — the smallest one worth believing", nil)
			               url:[NSURL URLWithString:@"https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"]
			             bytes:1117320192LL
			            thinks:NO] autorelease],
		[[[NekoLocalModel alloc]
			initWithIdentifier:@"llama-3.2-3b-instruct-q4"
			              name:@"Llama 3.2 3B Instruct"
			            detail:NSLocalizedString(@"1.9 GB — good in several languages, a second or two to answer", nil)
			               url:[NSURL URLWithString:@"https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"]
			             bytes:2019377696LL
			            thinks:NO] autorelease],
		[[[NekoLocalModel alloc]
			initWithIdentifier:@"qwen2.5-3b-instruct-q4"
			              name:@"Qwen2.5 3B Instruct"
			            detail:NSLocalizedString(@"2.0 GB — right and brief, and a year older than the two below", nil)
			               url:[NSURL URLWithString:@"https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf"]
			             bytes:2104521312LL
			            thinks:NO] autorelease],
		[[[NekoLocalModel alloc]
			initWithIdentifier:@"qwen3-1.7b-q8"
			              name:@"Qwen3 1.7B"
			            detail:NSLocalizedString(@"1.7 GB — newer than the 1.5B and better at holding to an instruction", nil)
			               url:[NSURL URLWithString:@"https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q8_0.gguf"]
			             bytes:1834426016LL
			            thinks:YES] autorelease],
		[[[NekoLocalModel alloc]
			initWithIdentifier:@"gemma-3-4b-it-q4"
			              name:@"Gemma 3 4B"
			            detail:NSLocalizedString(@"2.3 GB — the best of these outside English", nil)
			               url:[NSURL URLWithString:@"https://huggingface.co/ggml-org/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf"]
			             bytes:2489757856LL
			            thinks:NO] autorelease],
		[[[NekoLocalModel alloc]
			initWithIdentifier:@"qwen3-4b-instruct-q4"
			              name:@"Qwen3 4B Instruct"
			            detail:NSLocalizedString(@"2.3 GB — follows a brief better than anything above it", nil)
			               url:[NSURL URLWithString:@"https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf"]
			             bytes:2497281120LL
			            thinks:NO] autorelease],
		[[[NekoLocalModel alloc]
			initWithIdentifier:@"qwen3.5-4b-q4"
			              name:@"Qwen3.5 4B"
			            detail:NSLocalizedString(@"2.7 GB — the most recent, and it reasons at such length that it often never reaches the answer", nil)
			               url:[NSURL URLWithString:@"https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf"]
			             bytes:2740937888LL
			            thinks:YES] autorelease],
		/* A different order of thing from everything above, and the catalogue
		   has to say so rather than let somebody find out after a ten-gigabyte
		   download. These are 27B: six to ten times the size of the rest, and
		   the first entries here that a Mac can *fetch* and then not *run* —
		   nothing in this application checks how much memory there is, so the
		   only warning is the sentence in the row.

		   Two of them because one is not a choice. The smaller trades accuracy
		   for fitting on a 16 GB machine; the larger is the usual quality point
		   and wants the memory of a bigger one.

		   Both are vision-language models upstream. Neko asks them for text and
		   never ships the projector alongside, so they run as text models, which
		   is all NekoLocalProvider wants of them. */
		[[[NekoLocalModel alloc]
			initWithIdentifier:@"qwen3.8-27b-q2"
			              name:@"Qwen3.8 27B (smaller)"
			            detail:NSLocalizedString(@"9.8 GB — a 27B, several times the size of anything above it", nil)
			               url:[NSURL URLWithString:@"https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-UD-Q2_K_XL.gguf"]
			             bytes:9828981664LL
			            thinks:YES] autorelease],
		[[[NekoLocalModel alloc]
			initWithIdentifier:@"qwen3.8-27b-q4"
			              name:@"Qwen3.8 27B"
			            detail:NSLocalizedString(@"16.5 GB — the same 27B, kept whole", nil)
			               url:[NSURL URLWithString:@"https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-UD-Q4_K_M.gguf"]
			             bytes:16464440224LL
			            thinks:YES] autorelease],
		nil];
	return cached;
}

- (NekoLocalModel *)modelWithIdentifier:(NSString *)identifier
{
	NSEnumerator *pictures = [[self pictureCatalogue] objectEnumerator];
	NekoLocalModel *picture;
	while((picture = [pictures nextObject]) != nil)
		if([[picture identifier] isEqualToString:identifier])
			return picture;
	NSEnumerator *e = [[self catalogue] objectEnumerator];
	NekoLocalModel *model;
	while((model = [e nextObject]) != nil)
		if([[model identifier] isEqualToString:identifier])
			return model;
	return nil;
}

#pragma mark What is on disk

/* One picture model, because the choice here is not really a choice: Stable
   Diffusion 1.5 quantised to 8 bits is the smallest thing that draws a
   recognisable Colosseum, and the alternatives are either the same model a
   hundred megabytes lighter or four times the size. */
- (NSArray *)pictureCatalogue
{
	static NSArray *cached = nil;
	if(cached != nil)
		return cached;
	/* Four to choose between, in the order somebody would try them: the one that
	   has always been here first, then the two that draw in a quarter of the
	   time, then the one that draws bigger and slower.

	   Every URL was fetched and every size read from the response rather than
	   typed, and the licence of each was looked at — which is why two of these
	   rows mention one. The steps and the guidance are the model's own: asked for
	   SD 1.5's fourteen at a guidance of seven, a turbo checkpoint returns
	   mush. */
	cached = [[NSArray alloc] initWithObjects:
		[[[NekoLocalModel alloc]
			initWithIdentifier:@"sd15-q8"
			              name:@"Stable Diffusion 1.5"
			            detail:NSLocalizedString(@"1.6 GB — 512 pixels in about fifteen seconds. The one this app has always drawn with", nil)
			               url:[NSURL URLWithString:@"https://huggingface.co/second-state/stable-diffusion-v1-5-GGUF/resolve/main/stable-diffusion-v1-5-pruned-emaonly-Q8_0.gguf"]
			             bytes:1717986918LL
			             steps:14
			          guidance:7.0f
			              side:512] autorelease],
		[[[NekoLocalModel alloc]
			initWithIdentifier:@"sd-turbo-q8"
			              name:@"SD-Turbo"
			            detail:NSLocalizedString(@"2.0 GB — draws in four steps instead of fourteen, so a few seconds rather than fifteen. Stability AI Community licence", nil)
			               url:[NSURL URLWithString:@"https://huggingface.co/Green-Sky/SD-Turbo-GGUF/resolve/main/sd_turbo-f16-q8_0.gguf"]
			             bytes:2023745376LL
			             steps:4
			          guidance:1.0f
			              side:512] autorelease],
		[[[NekoLocalModel alloc]
			initWithIdentifier:@"sd21-q8"
			              name:@"Stable Diffusion 2.1"
			            detail:NSLocalizedString(@"2.0 GB — 768 pixels, and steadier with hands and faces than 1.5", nil)
			               url:[NSURL URLWithString:@"https://huggingface.co/second-state/stable-diffusion-2-1-GGUF/resolve/main/v2-1_768-nonema-pruned-Q8_0.gguf"]
			             bytes:2014680768LL
			             steps:20
			          guidance:7.0f
			              side:768] autorelease],
		[[[NekoLocalModel alloc]
			initWithIdentifier:@"sdxl-turbo-q8"
			              name:@"SDXL-Turbo"
			            detail:NSLocalizedString(@"4.1 GB — the best-looking of these, in four steps. Non-commercial licence only", nil)
			               url:[NSURL URLWithString:@"https://huggingface.co/OlegSkutte/sdxl-turbo-GGUF/resolve/main/sd_xl_turbo_1.0.q8_0.gguf"]
			             bytes:4098988672LL
			             steps:4
			          guidance:1.0f
			              side:512] autorelease], nil];
	return cached;
}

- (BOOL)isPicture:(NSString *)identifier
{
	NSEnumerator *e = [[self pictureCatalogue] objectEnumerator];
	NekoLocalModel *model;
	while((model = [e nextObject]) != nil)
		if([[model identifier] isEqualToString:identifier])
			return YES;
	return NO;
}

- (NSURL *)picturesDirectory
{
	NSArray *support = NSSearchPathForDirectoriesInDomains(
		NSApplicationSupportDirectory, NSUserDomainMask, YES);
	NSString *path = [[[support firstObject] stringByAppendingPathComponent:@"Neko"]
		stringByAppendingPathComponent:@"Images"];
	[[NSFileManager defaultManager] createDirectoryAtPath:path
	                         withIntermediateDirectories:YES
	                                          attributes:nil
	                                               error:NULL];
	return [NSURL fileURLWithPath:path];
}

- (NSURL *)modelsDirectory
{
	NSArray *support = NSSearchPathForDirectoriesInDomains(
		NSApplicationSupportDirectory, NSUserDomainMask, YES);
	NSString *path = [[[support firstObject] stringByAppendingPathComponent:@"Neko"]
		stringByAppendingPathComponent:@"Models"];
	/* Somewhere else, if a harness said so. See NekoModelStore.h for what not
	   having this cost. */
	NSString *elsewhere = [[NSUserDefaults standardUserDefaults]
		stringForKey:NekoModelsDirectoryKey];
	if([elsewhere length] > 0)
		path = [elsewhere stringByExpandingTildeInPath];
	[[NSFileManager defaultManager] createDirectoryAtPath:path
	                         withIntermediateDirectories:YES
	                                          attributes:nil
	                                               error:NULL];
	return [NSURL fileURLWithPath:path];
}

- (NSURL *)fileURLForIdentifier:(NSString *)identifier
{
	NSURL *directory = [self isPicture:identifier] ? [self picturesDirectory]
	                                               : [self modelsDirectory];
	return [directory URLByAppendingPathComponent:
		[identifier stringByAppendingPathExtension:@"gguf"]];
}

/* An interrupted download leaves a file that exists and cannot be read: two of
   them, at half and at a seventh of their size, answered every question with
   "that model file could not be read". A file more than a tenth short of what
   the catalogue says is treated as not there, which is what it is. */
- (BOOL)looksComplete:(NSString *)identifier at:(NSURL *)file
{
	NekoLocalModel *model = [self modelWithIdentifier:identifier];
	long long expected = [model expectedBytes];
	if(expected <= 0)
		return YES;
	long long actual = (long long)[[[NSFileManager defaultManager]
		attributesOfItemAtPath:[file path] error:NULL] fileSize];
	return actual >= (expected / 10) * 9;
}

- (NSURL *)installedURLForIdentifier:(NSString *)identifier
{
	NSURL *file = [self fileURLForIdentifier:identifier];
	if(![[NSFileManager defaultManager] fileExistsAtPath:[file path]])
		return nil;
	return [self looksComplete:identifier at:file] ? file : nil;
}

/* There, but too small to be usable: the difference between "download this" and
   "that download did not finish". */
- (BOOL)isIncomplete:(NSString *)identifier
{
	NSURL *file = [self fileURLForIdentifier:identifier];
	if(![[NSFileManager defaultManager] fileExistsAtPath:[file path]])
		return NO;
	return ![self looksComplete:identifier at:file];
}

- (long long)installedBytesForIdentifier:(NSString *)identifier
{
	NSDictionary *attributes = [[NSFileManager defaultManager]
		attributesOfItemAtPath:[[self fileURLForIdentifier:identifier] path] error:NULL];
	return [[attributes objectForKey:NSFileSize] longLongValue];
}

- (NSArray *)installedIdentifiers
{
	NSMutableArray *found = [NSMutableArray array];
	NSEnumerator *e = [[self catalogue] objectEnumerator];
	NekoLocalModel *model;
	while((model = [e nextObject]) != nil)
		if([self installedURLForIdentifier:[model identifier]] != nil)
			[found addObject:[model identifier]];
	return found;
}

/* Everything downloaded that is not the one in use, and what it costs. Models
   are hundreds of megabytes each: trying two and forgetting is easy, and a
   gigabyte quietly parked in Application Support is not obvious from anywhere
   else. */
- (NSArray *)identifiersOtherThan:(NSString *)keep
{
	NSMutableArray *others = [NSMutableArray array];
	NSEnumerator *e = [[self installedIdentifiers] objectEnumerator];
	NSString *identifier;
	while((identifier = [e nextObject]) != nil)
		if(![identifier isEqualToString:keep])
			[others addObject:identifier];
	return others;
}

- (long long)installedBytesOtherThan:(NSString *)keep
{
	long long total = 0;
	NSEnumerator *e = [[self identifiersOtherThan:keep] objectEnumerator];
	NSString *identifier;
	while((identifier = [e nextObject]) != nil)
		total += [self installedBytesForIdentifier:identifier];
	return total;
}

- (long long)totalInstalledBytes
{
	long long total = 0;
	NSEnumerator *e = [[self installedIdentifiers] objectEnumerator];
	NSString *identifier;
	while((identifier = [e nextObject]) != nil)
		total += [self installedBytesForIdentifier:identifier];
	return total;
}

/* Returns how many went. Also sweeps away anything left in the folder that is
   not in the catalogue at all — a half finished download from an older version,
   or a model dropped by hand. */
- (NSUInteger)removeAllExcept:(NSString *)keep
{
	NSUInteger removed = 0;
	NSEnumerator *e = [[self identifiersOtherThan:keep] objectEnumerator];
	NSString *identifier;
	while((identifier = [e nextObject]) != nil)
		if([self removeIdentifier:identifier])
			removed++;

	NSArray *known = [[self catalogue] valueForKey:@"identifier"];
	NSArray *contents = [[NSFileManager defaultManager]
		contentsOfDirectoryAtPath:[[self modelsDirectory] path] error:NULL];
	NSEnumerator *files = [contents objectEnumerator];
	NSString *file;
	while((file = [files nextObject]) != nil) {
		NSString *stem = [file stringByDeletingPathExtension];
		if([known containsObject:stem] || [stem isEqualToString:keep])
			continue;
		NSURL *stray = [[self modelsDirectory] URLByAppendingPathComponent:file];
		if([[NSFileManager defaultManager] removeItemAtURL:stray error:NULL])
			removed++;
	}
	return removed;
}

- (BOOL)removeIdentifier:(NSString *)identifier
{
	NSURL *file = [self installedURLForIdentifier:identifier];
	if(file == nil)
		return YES;
	return [[NSFileManager defaultManager] removeItemAtURL:file error:NULL];
}

#pragma mark Fetching one

- (BOOL)isDownloading
{
	return task != nil;
}

@synthesize fraction;

@synthesize downloadingModel = downloading;

+ (long long)memoryOnThisMac
{
	/* A different Mac, when a harness said so — the same seam the directories
	   have, and needed for the same reason: the case that matters is a 16 GB
	   machine, and the machine this was written on has thirty-nine. Without it
	   the only verdict ever exercised is the one that happens to be true here,
	   which is how a check ends up proving nothing. */
	long long pretend = (long long)[[NSUserDefaults standardUserDefaults]
		integerForKey:NekoModelMemoryKey];
	if(pretend > 0)
		return pretend;
	return (long long)[[NSProcessInfo processInfo] physicalMemory];
}

+ (long long)memoryForAModel
{
	long long all = [self memoryOnThisMac];
	long long left = all - NekoModelLeaveForTheMac;
	return left > 0 ? left : 0;
}

- (long long)freeDiskBytes
{
	NSDictionary *room = [[NSFileManager defaultManager]
		attributesOfFileSystemForPath:[[self modelsDirectory] path] error:NULL];
	NSNumber *free = [room objectForKey:NSFileSystemFreeSize];
	return free != nil ? (long long)[free unsignedLongLongValue] : 0LL;
}

- (BOOL)hasRoomOnDiskFor:(NekoLocalModel *)model
{
	/* The download is written before it is moved into place, so the disk needs
	   the file and a little room to breathe rather than exactly the file. */
	long long wanted = [model expectedBytes] + 1000LL * 1000LL * 1000LL;
	return [self freeDiskBytes] >= wanted;
}

- (NSString *)diskWarningFor:(NekoLocalModel *)model
{
	if([self hasRoomOnDiskFor:model])
		return nil;
	return [NSString stringWithFormat:
		NSLocalizedString(@"No room on the disk: needs %.1f GB, %.1f GB free.", nil),
		(double)[model expectedBytes] / 1e9, (double)[self freeDiskBytes] / 1e9];
}

- (void)downloadModel:(NekoLocalModel *)model
             progress:(void (^)(double))progress
           completion:(void (^)(NSURL *, NSError *))completion
{
	[self cancelDownload];

	downloading = [model retain];
	fraction = 0.0;
	progressBlock = Block_copy(progress);
	completionBlock = Block_copy(completion);

	NSURL *destination = [self fileURLForIdentifier:[model identifier]];
	long long expected = [model expectedBytes];

	task = [[session downloadTaskWithURL:[model url]
	          completionHandler:^(NSURL *temporary, NSURLResponse *response, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self finishedAt:temporary destination:destination
			         response:response error:error];
		});
	}] retain];

	/* The task reports its own progress; polling it keeps this free of a
	   delegate whose only job would be to forward two numbers. */
	[self performSelector:@selector(reportProgress:)
	           withObject:[NSNumber numberWithLongLong:expected]
	           afterDelay:0.25];
	[task resume];
}

- (void)reportProgress:(NSNumber *)expected
{
	if(task == nil)
		return;

	long long written = [task countOfBytesReceived];
	long long total = [task countOfBytesExpectedToReceive];
	if(total <= 0)
		total = [expected longLongValue];      /* before the server says */
	if(total > 0)
		fraction = MIN(1.0, (double)written / (double)total);
	if(progressBlock != NULL)
		progressBlock(fraction);

	[self performSelector:@selector(reportProgress:) withObject:expected afterDelay:0.25];
}

- (void)finishedAt:(NSURL *)temporary
       destination:(NSURL *)destination
          response:(NSURLResponse *)response
             error:(NSError *)error
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self
	                                        selector:@selector(reportProgress:)
	                                          object:nil];
	void (^completion)(NSURL *, NSError *) = completionBlock;
	completionBlock = NULL;

	[task release];
	task = nil;
	[downloading release];
	downloading = nil;
	if(progressBlock != NULL) {
		Block_release(progressBlock);
		progressBlock = NULL;
	}

	NSError *problem = error;
	if(problem == nil) {
		NSInteger status = [(NSHTTPURLResponse *)response statusCode];
		if(status != 200)
			problem = [NSError errorWithDomain:NekoAskErrorDomain
			                             code:NekoAskErrorTransport
			                         userInfo:[NSDictionary dictionaryWithObject:
				[NSString stringWithFormat:@"HTTP %ld", (long)status]
				                                                        forKey:NSLocalizedDescriptionKey]];
	}

	if(problem == nil) {
		/* Replace rather than merge: a half written model is worse than none. */
		[[NSFileManager defaultManager] removeItemAtURL:destination error:NULL];
		if(![[NSFileManager defaultManager] moveItemAtURL:temporary
		                                           toURL:destination
		                                           error:&problem])
			destination = nil;
	}

	if(completion != NULL) {
		completion(problem == nil ? destination : nil, problem);
		Block_release(completion);
	}
}

- (void)cancelDownload
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self
	                                        selector:@selector(reportProgress:)
	                                          object:nil];
	[task cancel];
	[task release];
	task = nil;
	[downloading release];
	downloading = nil;
	fraction = 0.0;
	if(progressBlock != NULL) {
		Block_release(progressBlock);
		progressBlock = NULL;
	}
	if(completionBlock != NULL) {
		Block_release(completionBlock);
		completionBlock = NULL;
	}
}

@end
