#import "NekoPlugins.h"
#import "NekoPlugin.h"

NSString * const NekoPluginsEnabledKey = @"NekoPluginsEnabled";
NSString * const NekoPluginsDirectoryKey = @"NekoPluginsDirectory";
NSString * const NekoPluginsDidChangeNotification = @"NekoPluginsDidChange";

/* Which bundled plugins have already been put in place, and at which version, so
   that a newer app can replace an older copy without switching anything back on
   that somebody switched off. */
static NSString * const NekoPluginsSeededKey = @"NekoPluginsSeeded";

@implementation NekoPlugins

+ (NekoPlugins *)sharedPlugins
{
	static NekoPlugins *shared = nil;
	if(shared == nil)
		shared = [[NekoPlugins alloc] init];
	return shared;
}

- (id)init
{
	if((self = [super init]) != nil) {
		plugins = [[NSMutableArray alloc] init];
		[self reload];
	}
	return self;
}

- (void)dealloc
{
	[plugins release];
	[super dealloc];
}

- (NSURL *)directory
{
	NSArray *support = NSSearchPathForDirectoriesInDomains(
		NSApplicationSupportDirectory, NSUserDomainMask, YES);
	NSString *path = [[[support firstObject] stringByAppendingPathComponent:@"Neko"]
		stringByAppendingPathComponent:@"Plugins"];
	/* Somewhere else, if a harness said so — the same seam Memory and Models
	   already have, and for the same reason: a test binary run straight out of
	   the bundle does not resolve to the sandboxed container, so without this it
	   sees no plugins at all and every rung that needs one reads as standing
	   aside. tests/reach.m counted two of them unreachable before this existed. */
	NSString *elsewhere = [[NSUserDefaults standardUserDefaults]
		stringForKey:NekoPluginsDirectoryKey];
	if([elsewhere length] > 0)
		path = [elsewhere stringByExpandingTildeInPath];
	[[NSFileManager defaultManager] createDirectoryAtPath:path
	                         withIntermediateDirectories:YES
	                                          attributes:nil
	                                               error:NULL];
	return [NSURL fileURLWithPath:path];
}

/* Read straight out of the bundle. Nothing is copied, nothing is enabled: these
   are folders somebody may choose to add, in the one place a downloaded app can
   keep them where they cannot be edited. */
- (NSURL *)examplesDirectory
{
	NSString *path = [[[NSBundle mainBundle] resourcePath]
		stringByAppendingPathComponent:@"Examples"];
	if(![[NSFileManager defaultManager] fileExistsAtPath:path])
		return nil;
	return [NSURL fileURLWithPath:path];
}

- (NSArray *)examples
{
	NSURL *folder = [self examplesDirectory];
	if(folder == nil)
		return [NSArray array];
	NSMutableArray *found = [NSMutableArray array];
	NSEnumerator *e = [[[NSFileManager defaultManager]
		contentsOfDirectoryAtPath:[folder path] error:NULL] objectEnumerator];
	NSString *name;
	while((name = [e nextObject]) != nil)
		if([[name pathExtension] isEqualToString:@"nekoplugin"])
			[found addObject:[folder URLByAppendingPathComponent:name]];
	return found;
}

#pragma mark What is there

- (void)reload
{
	[plugins removeAllObjects];
	NSFileManager *files = [NSFileManager defaultManager];
	NSArray *inside = [[files contentsOfDirectoryAtPath:[[self directory] path] error:NULL]
		sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	NSEnumerator *e = [inside objectEnumerator];
	NSString *name;
	while((name = [e nextObject]) != nil) {
		if(![name hasSuffix:@".nekoplugin"])
			continue;
		NekoPlugin *plugin = [[[NekoPlugin alloc] initWithFolder:
			[[self directory] URLByAppendingPathComponent:name]] autorelease];
		/* Two plugins claiming the same identifier: the first one wins and the
		   second says why it is not being used, rather than one of them
		   silently shadowing the other. */
		if([self pluginWithIdentifier:[plugin identifier]] != nil)
			continue;
		[plugins addObject:plugin];
	}
}

- (NSArray *)all
{
	return [NSArray arrayWithArray:plugins];
}

- (NekoPlugin *)pluginWithIdentifier:(NSString *)identifier
{
	for (NekoPlugin *plugin in plugins) {
		if([[plugin identifier] isEqualToString:identifier]) {
			return plugin;
		}
	}
	return nil;
}

- (NSArray *)enabled
{
	NSMutableArray *on = [NSMutableArray array];
	for (NekoPlugin *plugin in plugins) {
		if ([plugin isUsable] && [self isEnabled:plugin]) {
			[on addObject:plugin];
		}
	}
	return on;
}

#pragma mark The switch

- (BOOL)isEnabled:(NekoPlugin *)plugin
{
	NSArray *on = [[NSUserDefaults standardUserDefaults]
		arrayForKey:NekoPluginsEnabledKey];
	return [on containsObject:[plugin identifier]];
}

- (void)setEnabled:(BOOL)enabled for:(NekoPlugin *)plugin
{
	/* A refused plugin cannot be switched on at all: the panel disables its
	   switch, and this is the second door. */
	if(enabled && ![plugin isUsable])
		return;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSMutableArray *on = [NSMutableArray arrayWithArray:
		[defaults arrayForKey:NekoPluginsEnabledKey]];
	[on removeObject:[plugin identifier]];
	if(enabled)
		[on addObject:[plugin identifier]];
	[defaults setObject:on forKey:NekoPluginsEnabledKey];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:NekoPluginsDidChangeNotification object:self];
}

#pragma mark Arriving and leaving

- (NSString *)installFrom:(NSURL *)chosen
{
	if(![[chosen pathExtension] isEqualToString:@"nekoplugin"])
		return NSLocalizedString(@"A plugin is a folder whose name ends in .nekoplugin.", @"A plugin is a folder whose name ends in .nekoplugin.");

	/* Read before it is copied: a manifest that cannot be used should be refused
	   where somebody is looking at a panel, not later in a list. */
	NekoPlugin *reading = [[[NekoPlugin alloc] initWithFolder:chosen] autorelease];
	if(![reading isUsable])
		return [reading refusal];
	if([self pluginWithIdentifier:[reading identifier]] != nil)
		return [NSString stringWithFormat:
			NSLocalizedString(@"“%@” is already installed.", @"\"%@\" is already installed."), [reading name]];

	NSURL *destination = [[self directory]
		URLByAppendingPathComponent:[chosen lastPathComponent]];
	NSFileManager *files = [NSFileManager defaultManager];
	[files removeItemAtURL:destination error:NULL];
	NSError *problem = nil;
	if(![files copyItemAtURL:chosen toURL:destination error:&problem])
		return [problem localizedDescription]
			?: NSLocalizedString(@"It could not be copied in.", @"It could not be copied in.");

	[self reload];
	/* Left switched off. Arriving is not the same as being on. */
	[[NSNotificationCenter defaultCenter]
		postNotificationName:NekoPluginsDidChangeNotification object:self];
	return nil;
}

- (void)remove:(NekoPlugin *)plugin
{
	[self setEnabled:NO for:plugin];
	[[NSFileManager defaultManager] removeItemAtURL:[plugin folder] error:NULL];
	[self reload];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:NekoPluginsDidChangeNotification object:self];
}

#pragma mark The ones that ship with the app

- (NSURL *)bundledDirectory
{
	NSString *path = [[NSBundle mainBundle] pathForResource:@"Plugins" ofType:nil];
	return [path length] > 0 ? [NSURL fileURLWithPath:path] : nil;
}

- (BOOL)isBundled:(NekoPlugin *)plugin
{
	NSURL *inside = [self bundledDirectory];
	if(inside == nil)
		return NO;
	return [[NSFileManager defaultManager] fileExistsAtPath:
		[[inside URLByAppendingPathComponent:[[plugin folder] lastPathComponent]] path]];
}

- (void)seedFromBundle
{
	NSURL *inside = [self bundledDirectory];
	if(inside == nil)
		return;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary *seeded = [NSMutableDictionary dictionaryWithDictionary:
		[defaults dictionaryForKey:NekoPluginsSeededKey]];
	NSFileManager *files = [NSFileManager defaultManager];
	NSArray *names = [files contentsOfDirectoryAtPath:[inside path] error:NULL];
	NSEnumerator *e = [names objectEnumerator];
	NSString *name;
	BOOL changed = NO;

	while((name = [e nextObject]) != nil) {
		if(![name hasSuffix:@".nekoplugin"])
			continue;
		NekoPlugin *shipped = [[[NekoPlugin alloc] initWithFolder:
			[inside URLByAppendingPathComponent:name]] autorelease];
		if(![shipped isUsable]) {
			/* The app shipping a plugin it refuses is a bug in the app, and a
			   silent one would be the worst kind. */
			NSLog(@"Neko: the plugin shipped as %@ was refused — %@", name, [shipped refusal]);
			continue;
		}

		NSString *already = [seeded objectForKey:[shipped identifier]];
		BOOL firstTime = (already == nil);
		NSURL *destination = [[self directory] URLByAppendingPathComponent:name];
		BOOL there = [files fileExistsAtPath:[destination path]];
		BOOL newer = !firstTime
			&& [[shipped version] compare:already options:NSNumericSearch] == NSOrderedDescending;

		if(there && !newer && !firstTime)
			continue;              /* the copy in place is the one to use */

		[files removeItemAtURL:destination error:NULL];
		if(![files copyItemAtURL:[shipped folder] toURL:destination error:NULL])
			continue;
		[seeded setObject:[shipped version] forKey:[shipped identifier]];
		changed = YES;

		if(!firstTime)
			continue;              /* an update never touches the switch */

		/* The one exception, and only the first time this plugin has ever been
		   seen: switched on, because these are the feeds the app has always
		   had. */
		[self reload];
		NekoPlugin *installed = [self pluginWithIdentifier:[shipped identifier]];
		if(installed != nil)
			[self setEnabled:YES for:installed];
	}

	if(!changed)
		return;
	[defaults setObject:seeded forKey:NekoPluginsSeededKey];
	[self reload];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:NekoPluginsDidChangeNotification object:self];
}

#pragma mark What they add

- (NSArray *)feeds
{
	NSMutableArray *all = [NSMutableArray array];
	NSEnumerator *e = [[self enabled] objectEnumerator];
	NekoPlugin *plugin;
	while((plugin = [e nextObject]) != nil) {
		NSEnumerator *f = [[plugin feeds] objectEnumerator];
		NSDictionary *feed;
		while((feed = [f nextObject]) != nil) {
			NSMutableDictionary *one = [NSMutableDictionary dictionaryWithDictionary:feed];
			/* Whose it is, so the panel and the credits can say so. */
			[one setObject:[plugin identifier] forKey:@"Plugin"];
			[all addObject:one];
		}
	}
	return all;
}

@end
