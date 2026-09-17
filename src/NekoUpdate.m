#import "NekoUpdate.h"
#import "NekoController.h"
#import "NekoAsk.h"

NSString * const NekoUpdateCheckKey = @"NekoUpdateCheck";
NSString * const NekoUpdateDidChangeNotification = @"NekoUpdateDidChange";


/* Where the releases are. One address, and it is this project's own. */
static NSString * const NekoUpdateFeed =
	@"https://api.github.com/repos/nicolorisitano82/neko-mac/releases/latest";

/* Once a day. A pet that asks a server every hour is a pet with a habit. */
static const NSTimeInterval NekoUpdateEvery = 24.0 * 3600.0;

static NSString * const NekoUpdateAskedKey = @"NekoUpdateLastChecked";
static NSString * const NekoUpdateSaidKey  = @"NekoUpdateAnnounced";

@implementation NekoUpdate

+ (NekoUpdate *)sharedUpdate
{
	static NekoUpdate *shared = nil;
	if(shared == nil)
		shared = [[NekoUpdate alloc] init];
	return shared;
}

+ (void)initialize
{
	if(self != [NekoUpdate class])
		return;
	[[NSUserDefaults standardUserDefaults] registerDefaults:
		[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
		                           forKey:NekoUpdateCheckKey]];
}

- (id)init
{
	if((self = [super init]) != nil) {
		NSURLSessionConfiguration *configuration =
			[NSURLSessionConfiguration defaultSessionConfiguration];
		[configuration setTimeoutIntervalForRequest:20.0];
		session = [[NSURLSession sessionWithConfiguration:configuration] retain];
	}
	return self;
}

#pragma mark Version numbers

+ (NSString *)runningVersion
{
	return [[[NSBundle mainBundle] infoDictionary]
		objectForKey:@"CFBundleShortVersionString"] ?: @"0";
}

/* By the numbers between the dots, not by NSNumericSearch on the whole string:
   that reads "2.9" against "2.13" correctly and "2.9" against "2.9.1" wrongly,
   because a missing part is not a zero to a string comparison. */
+ (BOOL)version:(NSString *)candidate isNewerThan:(NSString *)current
{
	if([candidate length] == 0)
		return NO;
	NSCharacterSet *strip = [NSCharacterSet characterSetWithCharactersInString:@"vV "];
	NSArray *theirs = [[candidate stringByTrimmingCharactersInSet:strip]
		componentsSeparatedByString:@"."];
	NSArray *ours = [[(current ?: @"0") stringByTrimmingCharactersInSet:strip]
		componentsSeparatedByString:@"."];
	NSUInteger parts = MAX([theirs count], [ours count]), i;
	for(i = 0; i < parts; i++) {
		NSInteger a = i < [theirs count]
			? [[theirs objectAtIndex:i] integerValue] : 0;
		NSInteger b = i < [ours count]
			? [[ours objectAtIndex:i] integerValue] : 0;
		if(a != b)
			return a > b;
	}
	return NO;                     /* the same version is not a newer one */
}

#pragma mark Asking

- (BOOL)isChecking { return checking; }
- (BOOL)isDownloading { return task != nil; }
- (double)fraction { return fraction; }
- (NSString *)availableVersion { return version; }

- (NSString *)menuTitle
{
	if([self isDownloading])
		return [NSString stringWithFormat:
			NSLocalizedString(@"Downloading %.0f%%…", @"Downloading %.0f%%…"), fraction * 100.0];
	if([version length] == 0)
		return nil;
	return [NSString stringWithFormat:
		NSLocalizedString(@"Version %@ is out…", @"Version %@ is out…"), version];
}

- (void)checkQuietly
{
	if(![[NSUserDefaults standardUserDefaults] boolForKey:NekoUpdateCheckKey])
		return;
	NSDate *last = [[NSUserDefaults standardUserDefaults] objectForKey:NekoUpdateAskedKey];
	if([last isKindOfClass:[NSDate class]]
	   && -[last timeIntervalSinceNow] < NekoUpdateEvery)
		return;
	[self ask:NO];
}

- (void)checkAloud
{
	[self ask:YES];
}

- (void)ask:(BOOL)outLoud
{
	if(checking)
		return;
	checking = YES;
	[[NSNotificationCenter defaultCenter]
		postNotificationName:NekoUpdateDidChangeNotification object:self];

	NSMutableURLRequest *request = [NSMutableURLRequest
		requestWithURL:[NSURL URLWithString:NekoUpdateFeed]];
	/* GitHub wants to know what is asking; it is told the application and
	   nothing else. */
	[request setValue:[NSString stringWithFormat:@"Neko/%@",
		[NekoUpdate runningVersion]] forHTTPHeaderField:@"User-Agent"];
	[request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];

	[[session dataTaskWithRequest:request
	           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self heard:data error:error outLoud:outLoud];
		});
	}] resume];
}

+ (NSDictionary *)releaseFrom:(NSData *)json
{
	NSDictionary *release = nil;
	if([json length] > 0)
		release = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];
	if(![release isKindOfClass:[NSDictionary class]])
		return nil;

	NSString *tag = [release objectForKey:@"tag_name"];
	if(![tag isKindOfClass:[NSString class]])
		return nil;
	if(![self version:tag isNewerThan:[self runningVersion]])
		return nil;

	/* The disk image, and only that: a release carries source archives too and
	   they are not what anybody wants here. */
	NSString *where = nil;
	long long size = 0;
	NSEnumerator *e = [[release objectForKey:@"assets"] objectEnumerator];
	NSDictionary *asset;
	while((asset = [e nextObject]) != nil) {
		if(![asset isKindOfClass:[NSDictionary class]])
			continue;
		NSString *name = [asset objectForKey:@"name"];
		if(![name isKindOfClass:[NSString class]]
		   || ![[name pathExtension] isEqualToString:@"dmg"])
			continue;
		NSString *address = [asset objectForKey:@"browser_download_url"];
		if([address isKindOfClass:[NSString class]]) {
			where = address;
			size = [[asset objectForKey:@"size"] longLongValue];
		}
		break;
	}
	if([where length] == 0)
		return nil;              /* a release with nothing to install */

	NSCharacterSet *strip = [NSCharacterSet characterSetWithCharactersInString:@"vV "];
	NSString *page = [release objectForKey:@"html_url"];
	NSMutableDictionary *found = [NSMutableDictionary dictionary];
	[found setObject:[tag stringByTrimmingCharactersInSet:strip] forKey:@"Version"];
	[found setObject:[NSURL URLWithString:where] forKey:@"Download"];
	[found setObject:[NSNumber numberWithLongLong:size] forKey:@"Bytes"];
	if([page isKindOfClass:[NSString class]])
		[found setObject:page forKey:@"Notes"];
	return found;
}

- (void)heard:(NSData *)data error:(NSError *)error outLoud:(BOOL)outLoud
{
	checking = NO;
	[[NSUserDefaults standardUserDefaults] setObject:[NSDate date]
	                                         forKey:NekoUpdateAskedKey];

	NSDictionary *found = [NekoUpdate releaseFrom:data];

	if(found == nil) {
		[version release]; version = nil;
		[download release]; download = nil;
		[notes release]; notes = nil;
		if(outLoud)
			[self say:[data length] > 0
				? [NSString stringWithFormat:
					NSLocalizedString(@"This is the newest one: %@.", @"This is the newest one: %@."),
					[NekoUpdate runningVersion]]
				: NSLocalizedString(@"I could not ask about new versions just now.", @"I could not ask about new versions just now.")];
		[[NSNotificationCenter defaultCenter]
			postNotificationName:NekoUpdateDidChangeNotification object:self];
		return;
	}

	[version release];
	version = [[found objectForKey:@"Version"] copy];
	[download release];
	download = [[found objectForKey:@"Download"] retain];
	[notes release];
	notes = [[found objectForKey:@"Notes"] copy];
	bytes = [[found objectForKey:@"Bytes"] longLongValue];

	[[NSNotificationCenter defaultCenter]
		postNotificationName:NekoUpdateDidChangeNotification object:self];

	/* Said out loud once per version, ever. The menu carries it after that: a
	   cat that mentions the same release every morning is a cat with a nag. */
	NSString *already = [[NSUserDefaults standardUserDefaults]
		stringForKey:NekoUpdateSaidKey];
	if(outLoud || ![already isEqualToString:version]) {
		[[NSUserDefaults standardUserDefaults] setObject:version
		                                         forKey:NekoUpdateSaidKey];
		[self say:[NSString stringWithFormat:
			NSLocalizedString(@"There is a %@ now. It is in my menu when you want it.", @"There is a %@ now. It is in my menu when you want it."),
			version]];
	}
}

/* Through the bubble when it may speak, and to the log either way, because the
   menu is the part that does not depend on a rate rule. */
- (void)say:(NSString *)text
{
	NSLog(@"Neko: %@", text);
	[[NekoAsk sharedAsk] sayUnprompted:text];
}

#pragma mark The two questions

- (NSString *)sizeSaid
{
	if(bytes <= 0)
		return @"";
	return [NSString stringWithFormat:@" (%.0f MB)", (double)bytes / 1.0e6];
}

- (void)offerIt:(id)sender
{
	if([self isDownloading]) {
		[self showProgress];
		return;
	}
	if([version length] == 0) {
		[self checkAloud];
		return;
	}

	[NSApp activateIgnoringOtherApps:YES];
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:[NSString stringWithFormat:
		NSLocalizedString(@"Neko %@ is out.", @"Neko %@ is out."), version]];
	/* One literal, on one line. A key split across string literals can never
	   match an entry in Localizable.strings, and tests/docs.m says so now. */
	[alert setInformativeText:[NSString stringWithFormat:
		NSLocalizedString(@"Shall I download the disk image%@? Installing it is yours to do: I open it and quit, and you drag Neko into Applications the way you did the first time.", @"Shall I download the disk image%@? Installing it is yours to do: I open it and quit, and you drag Neko into Applications the way you did the first time."),
		[self sizeSaid]]];
	[alert addButtonWithTitle:NSLocalizedString(@"Download", @"Download")];
	[alert addButtonWithTitle:NSLocalizedString(@"Not now", @"Not now")];
	if([notes length] > 0)
		[alert addButtonWithTitle:NSLocalizedString(@"What changed", @"What changed")];

	NSModalResponse answer = [alert runModal];
	if(answer == NSAlertThirdButtonReturn) {
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:notes]];
		return;
	}
	if(answer != NSAlertFirstButtonReturn)
		return;

	[self startDownload];
}

#pragma mark The download

- (NSURL *)folder
{
	NSArray *support = NSSearchPathForDirectoriesInDomains(
		NSApplicationSupportDirectory, NSUserDomainMask, YES);
	NSString *path = [[[support firstObject] stringByAppendingPathComponent:@"Neko"]
		stringByAppendingPathComponent:@"Updates"];
	[[NSFileManager defaultManager] createDirectoryAtPath:path
	                         withIntermediateDirectories:YES
	                                          attributes:nil error:NULL];
	return [NSURL fileURLWithPath:path];
}

- (void)startDownload
{
	if(task != nil || download == nil)
		return;
	fraction = 0.0;

	NSURL *destination = [[self folder] URLByAppendingPathComponent:
		[NSString stringWithFormat:@"Neko-%@.dmg", version]];

	task = [[session downloadTaskWithURL:download
	          completionHandler:^(NSURL *temporary, NSURLResponse *response, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self arrivedAt:temporary destination:destination error:error];
		});
	}] retain];
	[task resume];

	[self showProgress];
	/* Polled rather than delegated, the same way the model download does it:
	   a delegate whose only job is to forward two numbers is a class nobody
	   needs. */
	[self performSelector:@selector(tick) withObject:nil afterDelay:0.2];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:NekoUpdateDidChangeNotification object:self];
}

- (void)tick
{
	if(task == nil)
		return;
	long long got = [task countOfBytesReceived];
	long long total = [task countOfBytesExpectedToReceive];
	if(total <= 0)
		total = bytes;
	if(total > 0)
		fraction = MIN(1.0, (double)got / (double)total);

	[bar setDoubleValue:fraction * 100.0];
	[progressLabel setStringValue:[NSString localizedStringWithFormat:
		NSLocalizedString(@"%.0f MB of %.0f MB", @"%.0f MB of %.0f MB"),
		(double)got / 1.0e6, (double)total / 1.0e6]];

	[self performSelector:@selector(tick) withObject:nil afterDelay:0.2];
}

- (void)cancel:(id)sender
{
	[task cancel];
	[task release];
	task = nil;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
	                                        selector:@selector(tick) object:nil];
	[self hideProgress];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:NekoUpdateDidChangeNotification object:self];
}

- (void)arrivedAt:(NSURL *)temporary
      destination:(NSURL *)destination
            error:(NSError *)error
{
	BOOL cancelled = task == nil;
	[task release];
	task = nil;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
	                                        selector:@selector(tick) object:nil];
	[self hideProgress];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:NekoUpdateDidChangeNotification object:self];
	if(cancelled)
		return;

	if(temporary == nil || error != nil) {
		[self say:NSLocalizedString(@"The download did not finish.", @"The download did not finish.")];
		return;
	}

	NSFileManager *files = [NSFileManager defaultManager];
	[files removeItemAtURL:destination error:NULL];
	if(![files moveItemAtURL:temporary toURL:destination error:NULL]) {
		[self say:NSLocalizedString(@"The download did not finish.", @"The download did not finish.")];
		return;
	}

	[self askAboutOpening:destination];
}

#pragma mark The second question, and the way out

- (void)askAboutOpening:(NSURL *)image
{
	[NSApp activateIgnoringOtherApps:YES];
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:[NSString stringWithFormat:
		NSLocalizedString(@"Neko %@ is downloaded.", @"Neko %@ is downloaded."), version]];
	[alert setInformativeText:NSLocalizedString(@"Shall I open it and quit? Then drag Neko into Applications, replacing the one that is there, and start it again. I close first so that the copy you are replacing is not the copy that is running.", @"Shall I open it and quit? Then drag Neko into Applications, replacing the one that is there, and start it again. I close first so that the copy you are replacing is not the copy that is running.")];
	[alert addButtonWithTitle:NSLocalizedString(@"Open it and quit", @"Open it and quit")];
	[alert addButtonWithTitle:NSLocalizedString(@"Later", @"Later")];

	if([alert runModal] != NSAlertFirstButtonReturn) {
		[self say:[NSString stringWithFormat:
			NSLocalizedString(@"It is in %@ when you want it.", @"It is in %@ when you want it."),
			[[image URLByDeletingLastPathComponent] path]]];
		return;
	}

	if(![[NSWorkspace sharedWorkspace] openURL:image]) {
		/* If the image cannot be opened — the one step in this whole sequence
		   that could not be measured without a person, because it depends on
		   another process being handed access to a file inside this one's
		   container — then at least show where it is instead of leaving somebody
		   with a download they cannot find. */
		[[NSWorkspace sharedWorkspace] selectFile:[image path]
		                 inFileViewerRootedAtPath:@""];
		[self say:NSLocalizedString(@"I could not open the disk image.", @"I could not open the disk image.")];
		return;
	}
	/* A moment for the image to be mounted by somebody else's process before
	   this one stops existing. */
	[self performSelector:@selector(goAway) withObject:nil afterDelay:2.5];
}

- (void)goAway
{
	[NSApp terminate:nil];
}

#pragma mark The bar

- (void)showProgress
{
	if(progressPanel == nil) {
		progressPanel = [[NSPanel alloc] initWithContentRect:
			NSMakeRect(0.0, 0.0, 360.0, 108.0)
			                                       styleMask:NSWindowStyleMaskTitled
			                                                | NSWindowStyleMaskClosable
			                                         backing:NSBackingStoreBuffered
			                                           defer:NO];
		[progressPanel setTitle:NSLocalizedString(@"Downloading Neko", @"Downloading Neko")];
		[progressPanel setReleasedWhenClosed:NO];
		[progressPanel center];

		NSView *content = [progressPanel contentView];

		bar = [[NSProgressIndicator alloc] initWithFrame:
			NSMakeRect(20.0, 62.0, 320.0, 16.0)];
		[bar setStyle:NSProgressIndicatorStyleBar];
		[bar setIndeterminate:NO];
		[bar setMinValue:0.0];
		[bar setMaxValue:100.0];
		[content addSubview:bar];

		progressLabel = [[NSTextField alloc] initWithFrame:
			NSMakeRect(20.0, 36.0, 320.0, 18.0)];
		[progressLabel setBezeled:NO];
		[progressLabel setDrawsBackground:NO];
		[progressLabel setEditable:NO];
		[progressLabel setSelectable:NO];
		[progressLabel setFont:[NSFont systemFontOfSize:11.0]];
		[progressLabel setTextColor:[NSColor secondaryLabelColor]];
		[progressLabel setStringValue:@""];
		[content addSubview:progressLabel];

		NSButton *stop = [[[NSButton alloc] initWithFrame:
			NSMakeRect(250.0, 8.0, 92.0, 24.0)] autorelease];
		[stop setBezelStyle:NSBezelStyleRounded];
		[stop setTitle:NSLocalizedString(@"Stop", @"Stop")];
		[stop setTarget:self];
		[stop setAction:@selector(cancel:)];
		[content addSubview:stop];
	}
	[NSApp activateIgnoringOtherApps:YES];
	[progressPanel makeKeyAndOrderFront:nil];
}

- (void)hideProgress
{
	[progressPanel orderOut:nil];
}

@end
