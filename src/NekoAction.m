#import "NekoAction.h"
#import "NekoAnswerProvider.h"
#import "NekoFolderAccess.h"

NSString * const NekoActionsEnabledKey = @"NekoActionsEnabled";

#define NekoActionLocalized(text) NSLocalizedString(text, nil)

static NSString * const NekoActionMarker = @"ACTION:";

@implementation NekoAction

/* Small models bold what they think is important, so "**ACTION: open-app
   TextEdit**" arrives and used to be read as a sentence. The markers are looked
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
	NSDictionary *known = [NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithUnsignedInteger:NSDesktopDirectory], @"desktop",
		[NSNumber numberWithUnsignedInteger:NSDocumentDirectory], @"documents",
		[NSNumber numberWithUnsignedInteger:NSDownloadsDirectory], @"downloads",
		[NSNumber numberWithUnsignedInteger:NSMoviesDirectory], @"movies",
		[NSNumber numberWithUnsignedInteger:NSMusicDirectory], @"music",
		[NSNumber numberWithUnsignedInteger:NSPicturesDirectory], @"pictures", nil];
	NSNumber *which = [known objectForKey:[name lowercaseString]];
	if(which == nil)
		return nil;
	/* The real folder, not the sandbox's copy: this is handed to LaunchServices
	   to open in the Finder, which is allowed even where reading is not. */
	NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:
		[[name lowercaseString] capitalizedString]];
	NSArray *inside = NSSearchPathForDirectoriesInDomains(
		[which unsignedIntegerValue], NSUserDomainMask, YES);
	if([inside count] > 0)
		path = [inside firstObject];
	return [NSURL fileURLWithPath:path];
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

	NekoAction *action = [[[NekoAction alloc] init] autorelease];
	action->verb = [word retain];

	if([word isEqualToString:@"open-app"]) {
		action->resolved = [[NekoAction applicationNamed:rest] retain];
		action->target = [rest retain];
		return action->resolved != nil ? action : nil;
	}
	if([word isEqualToString:@"open-url"]) {
		NSString *address = rest;
		/* "in Chrome" at the end names the browser. */
		NSRange in = [[rest lowercaseString] rangeOfString:@" in "
		                                          options:NSBackwardsSearch];
		if(in.location != NSNotFound) {
			address = [[rest substringToIndex:in.location]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			NSString *browser = [[rest substringFromIndex:NSMaxRange(in)]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			action->resolved = [[NekoAction applicationNamed:browser] retain];
			action->extra = [browser retain];
			if(action->resolved == nil)
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
		action->target = [[url absoluteString] retain];
		return action;
	}
	if([word isEqualToString:@"open-folder"]) {
		action->resolved = [[NekoAction folderNamed:rest] retain];
		action->target = [rest retain];
		return action->resolved != nil ? action : nil;
	}
	if([word isEqualToString:@"run-shortcut"]) {
		action->target = [rest retain];
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

		action->target = [file retain];
		action->extra = [source retain];
		action->resolved = nil;
		action->other = [destination retain];
		return action;
	}
	return nil;                     /* an unknown verb is refused, not guessed */
}

- (void)dealloc
{
	[other release];
	[verb release];
	[target release];
	[extra release];
	[resolved release];
	[super dealloc];
}

- (NSString *)verb { return verb; }
- (NSString *)target { return target; }

- (NSArray *)needsFolders
{
	if(!([verb isEqualToString:@"copy"] || [verb isEqualToString:@"move"]))
		return [NSArray array];
	NekoFolderAccess *access = [NekoFolderAccess sharedAccess];
	NSMutableArray *missing = [NSMutableArray array];
	if(![access hasAccessTo:extra])
		[missing addObject:extra];
	if(![access hasAccessTo:other])
		[missing addObject:other];
	return missing;
}

/* The file as it is actually spelled on disk. "pippo" is asked for, "Pippo.txt"
   is there, and two files called "pippo.txt" and "pippo.md" mean the cat has to
   ask rather than choose. */
- (NSString *)fileIn:(NSURL *)folder ambiguous:(BOOL *)ambiguous
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
- (NSURL *)freeNameIn:(NSURL *)folder for:(NSString *)name
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
		return [NSString stringWithFormat:NekoActionLocalized(@"Open %@?"),
			[[[resolved lastPathComponent] stringByDeletingPathExtension] ?: target
				stringByReplacingOccurrencesOfString:@".app" withString:@""]];
	if([verb isEqualToString:@"open-url"])
		return extra != nil
			? [NSString stringWithFormat:NekoActionLocalized(@"Open %@ in %@?"), target, extra]
			: [NSString stringWithFormat:NekoActionLocalized(@"Open %@?"), target];
	if([verb isEqualToString:@"open-folder"]) {
		/* The Finder's own name for it, so an Italian is asked about "Documenti"
		   rather than about the English word the model happened to write. */
		NSString *shown = [[NSFileManager defaultManager] displayNameAtPath:[resolved path]];
		return [NSString stringWithFormat:NekoActionLocalized(@"Open the %@ folder?"),
			[shown length] > 0 ? shown : target];
	}
	if([verb isEqualToString:@"run-shortcut"])
		return [NSString stringWithFormat:NekoActionLocalized(@"Run your shortcut “%@”?"), target];

	NekoFolderAccess *access = [NekoFolderAccess sharedAccess];
	if([verb isEqualToString:@"copy"])
		return [NSString stringWithFormat:NekoActionLocalized(@"Copy “%@” from %@ to %@?"),
			target, [access displayNameFor:extra], [access displayNameFor:other]];
	if([verb isEqualToString:@"move"])
		return [NSString stringWithFormat:NekoActionLocalized(@"Move “%@” from %@ to %@?"),
			target, [access displayNameFor:extra], [access displayNameFor:other]];
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
		NSTask *task = [[[NSTask alloc] init] autorelease];
		[task setLaunchPath:@"/usr/bin/shortcuts"];
		[task setArguments:[NSArray arrayWithObjects:@"run", target, nil]];
		NS_DURING
			[task launch];
		NS_HANDLER
			if(error != NULL)
				*error = [NSError errorWithDomain:NekoAskErrorDomain
				                             code:NekoAskErrorTransport
				                         userInfo:nil];
			return NO;
		NS_ENDHANDLER
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
	NSURL *from = [access beginUsing:extra];
	NSURL *to = [access beginUsing:other];
	BOOL done = NO;
	NSString *complaint = nil;

	if(from == nil || to == nil) {
		complaint = NekoActionLocalized(@"I have not been shown that folder.");
	} else {
		BOOL ambiguous = NO;
		NSString *name = [self fileIn:from ambiguous:&ambiguous];
		if(ambiguous)
			complaint = [NSString stringWithFormat:
				NekoActionLocalized(@"There is more than one “%@” there."), target];
		else if(name == nil)
			complaint = [NSString stringWithFormat:
				NekoActionLocalized(@"I cannot find “%@” there."), target];
		else {
			NSURL *source = [from URLByAppendingPathComponent:name];
			NSNumber *directory = nil;
			[source getResourceValue:&directory forKey:NSURLIsDirectoryKey error:NULL];
			if([directory boolValue]) {
				complaint = NekoActionLocalized(@"That is a folder, and I only carry files.");
			} else {
				NSURL *destination = [self freeNameIn:to for:name];
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

	if(from != nil) [access doneWith:from];
	if(to != nil) [access doneWith:to];
	if(!done && error != NULL)
		*error = [NSError errorWithDomain:NekoAskErrorDomain
		                             code:NekoAskErrorTransport
		                         userInfo:complaint != nil
			? [NSDictionary dictionaryWithObject:complaint forKey:NSLocalizedDescriptionKey]
			: nil];
	return done;
}

@end
