#import "NekoFolderAccess.h"

/* One default per folder, holding the bookmark. */
static NSString *NekoBookmarkKeyFor(NSString *key)
{
	return [@"NekoFolder-" stringByAppendingString:key];
}

@implementation NekoFolderAccess

+ (NekoFolderAccess *)sharedAccess
{
	static NekoFolderAccess *shared = nil;
	if(shared == nil)
		shared = [[NekoFolderAccess alloc] init];
	return shared;
}

+ (NSArray *)folderKeys
{
	return @[@"desktop", @"documents", @"downloads",
		@"pictures", @"music", @"movies"];
}

+ (BOOL)isFolderKey:(NSString *)key
{
	return [[self folderKeys] containsObject:[key lowercaseString]];
}

/*! Where the folder is for a person, which is not where it is for the sandbox:
   the container has its own empty Desktop, and that is never what anyone means.
 
 This won't work if the user directory is somewhere else! */
- (NSURL *)realFolderForKey:(NSString *)key
{
	static NSDictionary<NSString*,NSString*> *const names =
	@{@"desktop": @"Desktop", @"documents": @"Documents",
	  @"downloads": @"Downloads", @"pictures": @"Pictures",
	  @"music": @"Music", @"movies": @"Movies"};
	NSString *name = names[[key lowercaseString]];
	if(name == nil)
		return nil;
	/* NSHomeDirectory is the container inside the sandbox, so the real home is
	   taken from the login name instead. */
	NSString *home = [@"/Users" stringByAppendingPathComponent:NSUserName()];
	return [NSURL fileURLWithPath:[home stringByAppendingPathComponent:name]];
}

- (NSString *)displayNameForKey:(NSString *)key
{
	NSURL *folder = [self realFolderForKey:key];
	NSString *shown = nil;
	
	if([folder getResourceValue:&shown forKey:NSURLLocalizedNameKey error:NULL]) {
		return [shown length] > 0 ? shown : key;
	}
	return key;
}

#pragma mark Remembering

- (NSURL *)resolveBookmarkFor:(NSString *)key stale:(BOOL *)stale
{
	NSData *bookmark = [[NSUserDefaults standardUserDefaults]
		dataForKey:NekoBookmarkKeyFor(key)];
	if(bookmark == nil)
		return nil;
	BOOL wasStale = NO;
	NSError *problem = nil;
	NSURL *url = [NSURL URLByResolvingBookmarkData:bookmark
	                                       options:NSURLBookmarkResolutionWithSecurityScope
	                                 relativeToURL:nil
	                           bookmarkDataIsStale:&wasStale
	                                         error:&problem];
	if(stale != NULL)
		*stale = wasStale;
	return url;
}

- (BOOL)hasAccessToFolderKey:(NSString *)key
{
	return [self resolveBookmarkFor:key stale:NULL] != nil;
}

- (NSArray *)allowedKeys
{
	NSMutableArray *allowed = [NSMutableArray array];
	for(NSString *key in [NekoFolderAccess folderKeys])
		if([self hasAccessToFolderKey:key])
			[allowed addObject:key];
	return allowed;
}

- (void)forgetFolderKey:(NSString *)key
{
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:NekoBookmarkKeyFor(key)];
}

#pragma mark Asking

- (NSString *)refusalForChoosingURL:(NSURL *)chosen insteadOfFolderKey:(NSString *)key
{
	NSURL *folder = [self realFolderForKey:key];
	if(chosen == nil || folder == nil)
		return NSLocalizedString(@"Nothing was chosen.", @"the folder handover, when the answer is no");
	if([[[chosen path] lastPathComponent] isEqualToString:[[folder path] lastPathComponent]])
		return nil;
	return [NSString stringWithFormat:
		NSLocalizedString(@"That is “%@”, and I asked for your %@ folder. I can only be given the one I asked for.", @"That is “%@”, and I asked for your %@ folder. I can only be given the one I asked for."),
		[[NSFileManager defaultManager] displayNameAtPath:[chosen path]],
		[self displayNameForKey:key]];
}

- (BOOL)requestAccessToFolderKey:(NSString *)key
{
	return [self requestAccessToFolderKey:key saying:NULL];
}

- (BOOL)requestAccessToFolderKey:(NSString *)key saying:(NSString **)problem
{
	if(problem != NULL)
		*problem = nil;
	if(![NekoFolderAccess isFolderKey:key])
		return NO;
	if([self hasAccessToFolderKey:key])
		return YES;

	NSURL *folder = [self realFolderForKey:key];
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel setCanChooseFiles:NO];
	[panel setCanChooseDirectories:YES];
	[panel setAllowsMultipleSelection:NO];
	[panel setCanCreateDirectories:NO];
	[panel setDirectoryURL:folder];
	[panel setPrompt:NSLocalizedString(@"Allow", nil)];
	[panel setMessage:[NSString stringWithFormat:
		NSLocalizedString(@"Choose your %@ folder so Neko can work in it. It is the only way in: nothing else can grant this.", nil),
		[self displayNameForKey:key]]];

	[NSApp activateIgnoringOtherApps:YES];
	if([panel runModal] != NSModalResponseOK)
		return NO;

	NSURL *chosen = [[panel URLs] firstObject];
	/* The panel is where the sandbox hands over a folder, but it hands over
	   whichever one was picked: a Documents bookmark stored under "desktop"
	   would be a lie the rest of the code would believe. Said out loud rather
	   than refused quietly — from where somebody is standing, a folder chosen and
	   then ignored is the application doing nothing. */
	NSString *wrongOne = [self refusalForChoosingURL:chosen insteadOfFolderKey:key];
	if(wrongOne != nil) {
		if(problem != NULL)
			*problem = wrongOne;
		return NO;
	}

	NSError *failure = nil;
	NSData *bookmark = [chosen bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
	            includingResourceValuesForKeys:nil
	                             relativeToURL:nil
	                                     error:&failure];
	if(bookmark == nil) {
		if(problem != NULL)
			*problem = [NSString stringWithFormat:
				NSLocalizedString(@"macOS did not hand your %@ folder over: %@", @"macOS did not hand your %@ folder over: %@"),
				[self displayNameForKey:key],
				[failure localizedDescription] ?: NSLocalizedString(@"no reason given", @"no reason given")];
		return NO;
	}
	[[NSUserDefaults standardUserDefaults] setObject:bookmark
	                                          forKey:NekoBookmarkKeyFor(key)];
	return YES;
}

#pragma mark Using

- (NSURL *)beginUsingFolderKey:(NSString *)key
{
	BOOL stale = NO;
	NSURL *url = [self resolveBookmarkFor:key stale:&stale];
	if(url == nil)
		return nil;
	if(stale)
		[self forgetFolderKey:key];        /* it will be asked for again, honestly */
	return [url startAccessingSecurityScopedResource] ? url : nil;
}

- (void)doneWithURL:(NSURL *)url
{
	[url stopAccessingSecurityScopedResource];
}

@end
