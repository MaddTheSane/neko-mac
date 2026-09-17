#import "NekoShortcutProvider.h"

/* Long enough for a model to answer, short enough that a broken Shortcut does
   not leave the cat staring into space. */
/* A Shortcut can be a chain of actions ending in a model, so it gets longer
   than the direct providers — but the clipboard is watched more closely, since
   the wait ends the moment it changes. */
static const NSTimeInterval NekoShortcutTimeout = 10.0;
static const NSTimeInterval NekoShortcutPollInterval = 0.08;

@implementation NekoShortcutProvider

- (id)initWithShortcutName:(NSString *)name
{
	if((self = [super init]) != nil)
		shortcutName = [(name ?: @"Ask Neko") copy];
	return self;
}

- (void)dealloc
{
	[self cancel];
}

@synthesize shortcutName;

- (NSString *)name
{
	return NSLocalizedString(@"A Shortcut", nil);
}

- (BOOL)isConfigured
{
	/* Whether the Shortcut exists cannot be asked without running it, so the
	   name being set is as far as this can go. */
	return [shortcutName length] > 0;
}

- (NSString *)configurationHint
{
	return [self isConfigured] ? nil
		: NSLocalizedString(@"Name the Shortcut that answers", nil);
}

#pragma mark What the user actually has

+ (NSArray<NSString*> *)availableShortcutNames
{
	static NSArray *cached = nil;
	static NSDate *asked = nil;
	/* The list is a process launch; a few seconds of memory is plenty. */
	if(cached != nil && [asked timeIntervalSinceNow] > -5.0)
		return cached;

	NSTask *task = [[NSTask alloc] init];
	[task setLaunchPath:@"/usr/bin/shortcuts"];
	[task setArguments:[NSArray arrayWithObject:@"list"]];
	NSPipe *output = [NSPipe pipe];
	[task setStandardOutput:output];
	[task setStandardError:[NSPipe pipe]];

	NSData *data = nil;
	@try {
		[task launch];
		data = [[output fileHandleForReading] readDataToEndOfFile];
		[task waitUntilExit];
	} @catch (NSException *problem) {
		return nil;              /* no Shortcuts, or not allowed to ask */
	}
	if([task terminationStatus] != 0)
		return nil;

	NSString *text = [[NSString alloc] initWithData:data
										   encoding:NSUTF8StringEncoding];
	NSMutableArray *names = [NSMutableArray array];
	NSEnumerator *e = [[text componentsSeparatedByString:@"\n"] objectEnumerator];
	for(NSString *line in e) {
		NSString *name = [line stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if([name length] > 0)
			[names addObject:name];
	}

	cached = [names copy];
	asked = [NSDate date];
	return cached;
}

- (BOOL)shortcutExists
{
	NSArray *names = [NekoShortcutProvider availableShortcutNames];
	if(names == nil)
		return YES;              /* cannot tell: let it try */
	for(NSString *name in names)
		if([name caseInsensitiveCompare:shortcutName] == NSOrderedSame)
			return YES;
	return NO;
}

#pragma mark Asking

- (void)askQuestion:(NSString *)question
       instructions:(NSString *)instructions
         completion:(void (^)(NSString *answer, NSError *error))completion
{
	[self cancel];

	if(![self isConfigured]) {
		completion(nil, [NSError errorWithDomain:NekoAskErrorDomain
		                                    code:NekoAskErrorNotConfigured
		                                userInfo:nil]);
		return;
	}

	/* Asking for a Shortcut that is not there used to mean twelve seconds of
	   waiting followed by a vague apology, while Shortcuts complained on its
	   own behalf. Say it at once, and say which name failed. */
	if(![self shortcutExists]) {
		completion(nil, [NSError errorWithDomain:NekoAskErrorDomain
		                                    code:NekoAskErrorNoShortcut
		                                userInfo:[NSDictionary dictionaryWithObject:shortcutName
		                                                                    forKey:@"name"]]);
		return;
	}

	NSPasteboard *board = [NSPasteboard generalPasteboard];
	saved = [self contentsOfPasteboard:board];
	baseline = [board changeCount];
	pending = [completion copy];
	deadline = [NSDate dateWithTimeIntervalSinceNow:NekoShortcutTimeout];

	/* The Shortcut owns its own prompt, so who is answering has to travel
	   inside the question. */
	NSString *asked = [instructions length] > 0
		? [NSString stringWithFormat:@"%@\n\n%@", instructions, question]
		: question;
	if(![self launchShortcutWithURL:[self urlForQuestion:asked]]) {
		[self finishWithAnswer:nil
		                 error:[NSError errorWithDomain:NekoAskErrorDomain
		                                           code:NekoAskErrorTransport
		                                       userInfo:nil]];
		return;
	}

	poll = [NSTimer scheduledTimerWithTimeInterval:NekoShortcutPollInterval
											target:self
			selector:@selector(checkClipboard:)
			userInfo:nil
			 repeats:YES];
}

- (NSURL *)urlForQuestion:(NSString *)question
{
	NSCharacterSet *allowed = [NSCharacterSet URLQueryAllowedCharacterSet];
	NSString *name = [shortcutName stringByAddingPercentEncodingWithAllowedCharacters:allowed];
	NSString *text = [(question ?: @"") stringByAddingPercentEncodingWithAllowedCharacters:allowed];
	/* The ampersands have to survive as separators, so the pieces are encoded
	   and the URL assembled, not the other way round. */
	return [NSURL URLWithString:[NSString stringWithFormat:
		@"shortcuts://run-shortcut?name=%@&input=text&text=%@", name, text]];
}

- (BOOL)launchShortcutWithURL:(NSURL *)url
{
	return url != nil && [[NSWorkspace sharedWorkspace] openURL:url];
}

/* The Shortcut is done when it has put something new on the clipboard. */
- (void)checkClipboard:(NSTimer *)timer
{
	NSPasteboard *board = [NSPasteboard generalPasteboard];
	if([board changeCount] != baseline) {
		NSString *answer = [board stringForType:NSPasteboardTypeString];
		[self restorePasteboard:board];
		if([answer length] > 0)
			[self finishWithAnswer:answer error:nil];
		else
			[self finishWithAnswer:nil
			                 error:[NSError errorWithDomain:NekoAskErrorDomain
			                                           code:NekoAskErrorNoAnswer
			                                       userInfo:nil]];
		return;
	}

	if([deadline timeIntervalSinceNow] <= 0.0) {
		[self finishWithAnswer:nil
		                 error:[NSError errorWithDomain:NekoAskErrorDomain
		                                           code:NekoAskErrorTimedOut
		                                       userInfo:nil]];
	}
}

- (void)finishWithAnswer:(NSString *)answer error:(NSError *)error
{
	void (^completion)(NSString *, NSError *) = pending;
	pending = NULL;
	[self stopPolling];
	if(completion != NULL) {
		completion(answer, error);
		completion = nil;
	}
}

- (void)cancel
{
	if(pending != NULL) {
		pending = NULL;
	}
	[self stopPolling];
}

- (void)stopPolling
{
	[poll invalidate];
	poll = nil;
	deadline = nil;
	saved = nil;
}

#pragma mark Leaving the clipboard as it was found

- (NSArray<NSPasteboardItem*> *)contentsOfPasteboard:(NSPasteboard *)board
{
	NSMutableArray *items = [NSMutableArray array];
	for(NSPasteboardItem *item in [board pasteboardItems]) {
		NSPasteboardItem *copy = [[NSPasteboardItem alloc] init];
		for(NSPasteboardType type in item.types) {
			NSData *data = [item dataForType:type];
			if(data != nil)
				[copy setData:data forType:type];
		}
		[items addObject:copy];
	}
	return items;
}

- (void)restorePasteboard:(NSPasteboard *)board
{
	[board clearContents];
	if([saved count] > 0)
		[board writeObjects:saved];
	baseline = [board changeCount];
}

@end
