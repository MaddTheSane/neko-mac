#import "NekoAction.h"
#import "NekoAnswerProvider.h"
#import "NekoFolderAccess.h"

NSString * const NekoActionsEnabledKey = @"NekoActionsEnabled";

static NSString * const NekoActionMarker = @"ACTION:";

@interface NekoAction ()
@property (readwrite, copy) NSString *verb;
@property (readwrite, copy) NSString *target;
@property (readwrite, retain) NSURL *resolved;
@property (readwrite, copy) NSString *extra;
@property (readwrite, copy) NSString *other;
@end

@implementation NekoAction

/*! Small models bold what they think is important, so "\*\*ACTION: open-app
   TextEdit\*\*" arrives and used to be read as a sentence. The markers are looked
   for after the decoration is taken off. */
NSString *NekoWithoutMarkdown(NSString *line)
{
	NSString *plain = [line stringByReplacingOccurrencesOfString:@"*" withString:@""];
	plain = [plain stringByReplacingOccurrencesOfString:@"`" withString:@""];
	plain = [plain stringByReplacingOccurrencesOfString:@"#" withString:@""];
	return [plain stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (BOOL)looksLikeAnAction:(NSString *)line
{
	return [[NekoWithoutMarkdown(line) uppercaseString] hasPrefix:NekoActionMarker];
}

#pragma mark Finding what was named

/* "photoshop" is not what the bundle is called: it is "Adobe Photoshop 2025".
   Everything installed is looked at once and the closest name that contains
   what was asked for wins, shortest first so "Safari" does not lose to
   "Safari Technology Preview". */
+ (NSURL *)applicationNamed:(NSString *)name
{
	if([name length] == 0)
		return nil;

	NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
	NSString *direct = [workspace fullPathForApplication:name];
	if(direct != nil)
		return [NSURL fileURLWithPath:direct];

	NSArray *folders = @[@"/Applications",
		@"/Applications/Utilities", @"/System/Applications",
		@"/System/Applications/Utilities",
		[NSHomeDirectory() stringByAppendingPathComponent:@"Applications"]];
	NSFileManager *files = [NSFileManager defaultManager];
	NSString *wanted = [name lowercaseString];
	NSString *best = nil;

	for (NSString *folder in folders) {
		NSEnumerator *inside = [[files contentsOfDirectoryAtPath:folder error:NULL]
			objectEnumerator];
		for (NSString *entry in inside) {
			if(![[entry pathExtension] isEqualToString:@"app"])
				continue;
			NSString *path = [folder stringByAppendingPathComponent:entry];
			/* Both names: the bundle on disk is Preview.app and the Finder calls
			   it Anteprima, and someone speaking Italian will say the second. */
			NSString *plain = [[entry stringByDeletingPathExtension] lowercaseString];
			NSString *shown = [[[files displayNameAtPath:path]
				stringByDeletingPathExtension] lowercaseString];
			BOOL matches = [plain rangeOfString:wanted].location != NSNotFound
			            || [wanted rangeOfString:plain].location != NSNotFound
			            || ([shown length] > 0
			                && ([shown rangeOfString:wanted].location != NSNotFound
			                    || [wanted rangeOfString:shown].location != NSNotFound));
			if(!matches)
				continue;
			if(best == nil || [entry length] < [[best lastPathComponent] length])
				best = path;
		}
	}
	return best != nil ? [NSURL fileURLWithPath:best] : nil;
}

+ (NSURL *)folderNamed:(NSString *)name
{
	static NSDictionary<NSString*,NSNumber*> *const known
	= @{@"desktop": @(NSDesktopDirectory),
		@"documents": @(NSDocumentDirectory),
		@"downloads": @(NSDownloadsDirectory),
		@"movies": @(NSMoviesDirectory),
		@"music": @(NSMusicDirectory),
		@"pictures": @(NSPicturesDirectory)};
	NSNumber *which = [known objectForKey:[name lowercaseString]];
	if(which == nil)
		return nil;
	/* The real folder, not the sandbox's copy: this is handed to LaunchServices
	   to open in the Finder, which is allowed even where reading is not. */
	NSURL *path = [NSURL fileURLWithPath:
				   [NSHomeDirectory() stringByAppendingPathComponent:
					[[name lowercaseString] capitalizedString]]];
	NSArray *inside = [[NSFileManager defaultManager] URLsForDirectory:
					   [which unsignedIntegerValue] inDomains:NSUserDomainMask];
	if([inside count] > 0)
		path = [inside firstObject];
	return path;
}

#pragma mark Reading the line

+ (NekoAction *)actionFromLine:(NSString *)line
{
	if(![self looksLikeAnAction:line])
		return nil;

	NSString *body = NekoWithoutMarkdown(line);
	NSRange colon = [body rangeOfString:@":"];
	if(colon.location == NSNotFound)
		return nil;
	body = [[body substringFromIndex:NSMaxRange(colon)]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSRange newline = [body rangeOfString:@"\n"];
	if(newline.location != NSNotFound)
		body = [body substringToIndex:newline.location];

	NSRange space = [body rangeOfString:@" "];
	if(space.location == NSNotFound)
		return nil;                 /* "ACTION: cannot" ends up here too */
	NSString *word = [[body substringToIndex:space.location] lowercaseString];
	NSString *rest = [[body substringFromIndex:NSMaxRange(space)]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if([rest length] == 0)
		return nil;

	if([word isEqualToString:@"cannot"])
		return nil;                 /* the app's own words, not the model's */

	NekoAction *action = [[NekoAction alloc] init];
	action.verb = word;

	if([word isEqualToString:@"open-app"]) {
		action.resolved = [NekoAction applicationNamed:rest];
		action.target = rest;
		return action.resolved != nil ? action : nil;
	}
	if([word isEqualToString:@"open-url"]) {
		NSString *address = rest;
		/* "in Chrome" at the end names the browser. */
		NSRange in_ = [[rest lowercaseString] rangeOfString:@" in "
		                                          options:NSBackwardsSearch];
		if(in_.location != NSNotFound) {
			address = [[rest substringToIndex:in_.location]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			NSString *browser = [[rest substringFromIndex:NSMaxRange(in_)]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			action.resolved = [NekoAction applicationNamed:browser];
			action.extra = browser;
			if(action.resolved == nil)
				return nil;
		}
		if([address rangeOfString:@"://"].location == NSNotFound)
			address = [@"https://" stringByAppendingString:address];
		NSURL *url = [NSURL URLWithString:address];
		NSString *scheme = [[url scheme] lowercaseString];
		/* Only the two schemes anyone means when they say "open": no file://,
		   no custom scheme a model has invented. */
		if(url == nil || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]))
			return nil;
		action.target = [url absoluteString];
		return action;
	}
	if([word isEqualToString:@"open-folder"]) {
		action.resolved = [NekoAction folderNamed:rest];
		action.target = rest;
		return action.resolved != nil ? action : nil;
	}
	if([word isEqualToString:@"run-shortcut"]) {
		action.target = rest;
		return action;
	}
	if([word isEqualToString:@"copy"] || [word isEqualToString:@"move"]) {
		/* "pippo.txt from desktop to documents", and nothing more elaborate:
		   no paths, no wildcards, no folders of its own choosing. */
		NSRange from = [[rest lowercaseString] rangeOfString:@" from "];
		NSRange to = [[rest lowercaseString] rangeOfString:@" to " options:NSBackwardsSearch];
		if(from.location == NSNotFound || to.location == NSNotFound
		   || to.location < NSMaxRange(from))
			return nil;
		NSString *file = [[rest substringToIndex:from.location]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		NSString *source = [[[rest substringWithRange:NSMakeRange(NSMaxRange(from),
			to.location - NSMaxRange(from))]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
		NSString *destination = [[[rest substringFromIndex:NSMaxRange(to)]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];

		if([file length] == 0 || [file rangeOfString:@"/"].location != NSNotFound
		   || [file rangeOfString:@"*"].location != NSNotFound
		   || [file rangeOfString:@".."].location != NSNotFound)
			return nil;              /* a name, not a path and not a pattern */
		if(![NekoFolderAccess isFolderKey:source] || ![NekoFolderAccess isFolderKey:destination])
			return nil;
		if([source isEqualToString:destination])
			return nil;

		action.target = file;
		action.extra = source;
		action.resolved = nil;
		action.other = destination;
		return action;
	}
	return nil;                     /* an unknown verb is refused, not guessed */
}

@synthesize verb;
@synthesize target;
@synthesize resolved;
@synthesize extra;
@synthesize other;

- (NSArray *)needsFolders
{
	if(!([verb isEqualToString:@"copy"] || [verb isEqualToString:@"move"]))
		return [NSArray array];
	NekoFolderAccess *access = [NekoFolderAccess sharedAccess];
	NSMutableArray *missing = [NSMutableArray array];
	if(![access hasAccessToFolderKey:extra])
		[missing addObject:extra];
	if(![access hasAccessToFolderKey:other])
		[missing addObject:other];
	return missing;
}

/* The file as it is actually spelled on disk. "pippo" is asked for, "Pippo.txt"
   is there, and two files called "pippo.txt" and "pippo.md" mean the cat has to
   ask rather than choose. */
- (NSString *)fileInFolderURL:(NSURL *)folder isAmbiguous:(BOOL *)ambiguous
{
	NSArray *entries = [[NSFileManager defaultManager]
		contentsOfDirectoryAtPath:[folder path] error:NULL];
	NSString *wanted = [target lowercaseString];
	NSMutableArray *exact = [NSMutableArray array];
	NSMutableArray *stem = [NSMutableArray array];
	for(NSString *entry in entries) {
		if([entry hasPrefix:@"."])
			continue;
		NSString *plain = [entry lowercaseString];
		if([plain isEqualToString:wanted])
			[exact addObject:entry];
		else if([[plain stringByDeletingPathExtension] isEqualToString:wanted])
			[stem addObject:entry];
	}
	NSArray *found = [exact count] > 0 ? exact : stem;
	if(ambiguous != NULL)
		*ambiguous = [found count] > 1;
	return [found count] == 1 ? [found firstObject] : nil;
}

/* Never over the top of something else: "pippo.txt" becomes "pippo 2.txt". */
- (NSURL *)freeNameInFolderURL:(NSURL *)folder forName:(NSString *)name
{
	NSFileManager *files = [NSFileManager defaultManager];
	NSURL *candidate = [folder URLByAppendingPathComponent:name];
	if(![files fileExistsAtPath:[candidate path]])
		return candidate;
	NSString *stem = [name stringByDeletingPathExtension];
	NSString *extension = [name pathExtension];
	unsigned n;
	for(n = 2; n < 1000; n++) {
		NSString *tried = [NSString stringWithFormat:@"%@ %u", stem, n];
		if([extension length] > 0)
			tried = [tried stringByAppendingPathExtension:extension];
		candidate = [folder URLByAppendingPathComponent:tried];
		if(![files fileExistsAtPath:[candidate path]])
			return candidate;
	}
	return nil;
}

- (NSString *)summary
{
	if([verb isEqualToString:@"open-app"])
		return [NSString stringWithFormat:NSLocalizedString(@"Open %@?", @"Open %@?"),
			[[[resolved lastPathComponent] stringByDeletingPathExtension] ?: target
				stringByReplacingOccurrencesOfString:@".app" withString:@""]];
	if([verb isEqualToString:@"open-url"])
		return extra != nil
			? [NSString stringWithFormat:NSLocalizedString(@"Open %@ in %@?", @"Open %@ in %@?"), target, extra]
			: [NSString stringWithFormat:NSLocalizedString(@"Open %@?", @"Open %@?"), target];
	if([verb isEqualToString:@"open-folder"]) {
		/* The Finder's own name for it, so an Italian is asked about "Documenti"
		   rather than about the English word the model happened to write. */
		NSString *shown = [[NSFileManager defaultManager] displayNameAtPath:[resolved path]];
		return [NSString stringWithFormat:NSLocalizedString(@"Open the %@ folder?", @"Open the %@ folder?"),
			[shown length] > 0 ? shown : target];
	}
	if([verb isEqualToString:@"run-shortcut"])
		return [NSString stringWithFormat:NSLocalizedString(@"Run your shortcut “%@”?", @"Run your shortcut “%@”?"), target];

	NekoFolderAccess *access = [NekoFolderAccess sharedAccess];
	if([verb isEqualToString:@"copy"])
		return [NSString stringWithFormat:NSLocalizedString(@"Copy “%@” from %@ to %@?", @"Copy “%@” from %@ to %@?"),
			target, [access displayNameForKey:extra], [access displayNameForKey:other]];
	if([verb isEqualToString:@"move"])
		return [NSString stringWithFormat:NSLocalizedString(@"Move “%@” from %@ to %@?", @"Move “%@” from %@ to %@?"),
			target, [access displayNameForKey:extra], [access displayNameForKey:other]];
	return nil;
}

#pragma mark Doing it

- (BOOL)perform:(NSError **)error
{
	NSWorkspace *workspace = [NSWorkspace sharedWorkspace];

	if([verb isEqualToString:@"open-app"] || [verb isEqualToString:@"open-folder"])
		return [workspace openURL:resolved];

	if([verb isEqualToString:@"open-url"]) {
		NSURL *url = [NSURL URLWithString:target];
		if(resolved == nil)
			return [workspace openURL:url];
		return [workspace openURLs:[NSArray arrayWithObject:url]
		      withApplicationAtURL:resolved
		                   options:NSWorkspaceLaunchDefault
		             configuration:[NSDictionary dictionary]
		                     error:error] != nil;
	}

	if([verb isEqualToString:@"copy"] || [verb isEqualToString:@"move"])
		return [self moveOrCopy:error];

	if([verb isEqualToString:@"run-shortcut"]) {
		NSTask *task = [[NSTask alloc] init];
		[task setLaunchPath:@"/usr/bin/shortcuts"];
		[task setArguments:@[@"run", target]];
		@try {
			[task launch];
		} @catch(NSException *raised) {
			if(error != NULL)
				*error = [NSError errorWithDomain:NekoAskErrorDomain
											 code:NekoAskErrorTransport
										 userInfo:nil];
			return NO;
		}
		return YES;
	}
	return NO;
}

/* One file, between two folders you handed over yourself. Nothing is
   overwritten, nothing is deleted, and a name that matches two files is a
   question rather than a guess. */
- (BOOL)moveOrCopy:(NSError **)error
{
	NekoFolderAccess *access = [NekoFolderAccess sharedAccess];
	NSURL *from = [access beginUsingFolderKey:extra];
	NSURL *to = [access beginUsingFolderKey:other];
	BOOL done = NO;
	NSString *complaint = nil;

	if(from == nil || to == nil) {
		complaint = NSLocalizedString(@"I have not been shown that folder.", @"I have not been shown that folder.");
	} else {
		BOOL ambiguous = NO;
		NSString *name = [self fileInFolderURL:from isAmbiguous:&ambiguous];
		if(ambiguous)
			complaint = [NSString stringWithFormat:
				NSLocalizedString(@"There is more than one “%@” there.", @"There is more than one \"%@\" there."), target];
		else if(name == nil)
			complaint = [NSString stringWithFormat:
				NSLocalizedString(@"I cannot find “%@” there.", @"I cannot find \"%@\" there."), target];
		else {
			NSURL *source = [from URLByAppendingPathComponent:name];
			NSNumber *directory = nil;
			[source getResourceValue:&directory forKey:NSURLIsDirectoryKey error:NULL];
			if([directory boolValue]) {
				complaint = NSLocalizedString(@"That is a folder, and I only carry files.", @"That is a folder, and I only carry files.");
			} else {
				NSURL *destination = [self freeNameInFolderURL:to forName:name];
				NSError *problem = nil;
				NSFileManager *files = [NSFileManager defaultManager];
				done = [verb isEqualToString:@"move"]
					? [files moveItemAtURL:source toURL:destination error:&problem]
					: [files copyItemAtURL:source toURL:destination error:&problem];
				if(!done)
					complaint = [problem localizedDescription];
			}
		}
	}

	if(from != nil) [access doneWithURL:from];
	if(to != nil) [access doneWithURL:to];
	if(!done && error != NULL)
		*error = [NSError errorWithDomain:NekoAskErrorDomain
		                             code:NekoAskErrorTransport
		                         userInfo:complaint != nil
				  ? @{NSLocalizedDescriptionKey: complaint}
			: nil];
	return done;
}

@end
