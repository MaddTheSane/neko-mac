#import "NekoPlugin.h"
#import "NekoPlayer.h"

const NSInteger NekoPluginInterface = 1;

/* A plugin may not smuggle a marker into anything the app shows or hands to a
   model: those three words are how this app's own code says "do something", and
   they belong to the app. */
static NSString * const NekoPluginMarkers[] = { @"ACTION:", @"IMAGE:", @"LOOK:", nil };

@implementation NekoPlugin

- (id)initWithFolder:(NSURL *)aFolder
{
	if((self = [super init]) != nil) {
		folder = [aFolder retain];
		[self read];
	}
	return self;
}

- (void)dealloc
{
	[folder release];
	[manifest release];
	[strings release];
	[refusal release];
	[super dealloc];
}

- (NSURL *)folder     { return folder; }
- (NSString *)refusal { return refusal; }
- (BOOL)isUsable      { return refusal == nil; }

- (NSString *)identifier
{
	return [manifest objectForKey:@"Identifier"]
		?: [[folder lastPathComponent] stringByDeletingPathExtension];
}

- (NSString *)name
{
	return [self localized:([manifest objectForKey:@"Name"] ?: [self identifier])];
}

- (NSString *)version { return [manifest objectForKey:@"Version"] ?: @"?"; }
- (NSString *)author  { return [manifest objectForKey:@"Author"] ?: @""; }
- (NSString *)summary { return [self localized:([manifest objectForKey:@"Summary"] ?: @"")]; }

- (BOOL)wants:(NSString *)what
{
	NSArray *wants = [manifest objectForKey:@"Wants"];
	return [wants isKindOfClass:[NSArray class]] && [wants containsObject:what];
}

- (BOOL)wantsNetwork      { return [self wants:@"network"]; }
- (BOOL)wantsToOpenThings { return [self wants:@"open"]; }
- (BOOL)wantsShortcuts    { return [self wants:@"shortcuts"]; }
- (BOOL)wantsToControlPlayers { return [self wants:@"players"]; }

#pragma mark Reading it

/* Every refusal is a sentence somebody can act on, not a code. The panel shows
   it under the plugin's name and the plugin stays in the list: a plugin that
   vanished on being refused would be a plugin nobody could fix. */
- (void)refuse:(NSString *)why
{
	if(refusal != nil)
		return;                  /* the first reason is the useful one */
	refusal = [why copy];
}

- (BOOL)carriesAMarker:(NSString *)text
{
	NSUInteger i;
	for(i = 0; NekoPluginMarkers[i] != nil; i++)
		if([[text uppercaseString] rangeOfString:NekoPluginMarkers[i]].location != NSNotFound)
			return YES;
	return NO;
}

- (void)read
{
	NSURL *plist = [folder URLByAppendingPathComponent:@"plugin.plist"];
	NSDictionary *read = [NSDictionary dictionaryWithContentsOfURL:plist];
	if(![read isKindOfClass:[NSDictionary class]]) {
		[self refuse:NSLocalizedString(@"There is no readable plugin.plist inside it.", @"There is no readable plugin.plist inside it.")];
		return;
	}
	manifest = [read retain];

	NSString *identifier = [manifest objectForKey:@"Identifier"];
	if([identifier length] == 0 || [identifier rangeOfString:@"."].location == NSNotFound) {
		[self refuse:NSLocalizedString(@"Its Identifier is missing or is not of the form com.example.thing.", @"Its Identifier is missing or is not of the form com.example.thing.")];
		return;
	}
	if([[manifest objectForKey:@"Name"] length] == 0) {
		[self refuse:NSLocalizedString(@"It has no Name to show.", @"It has no Name to show.")];
		return;
	}

	NSInteger declared = [[manifest objectForKey:@"Interface"] integerValue];
	if(declared <= 0) {
		[self refuse:NSLocalizedString(@"It does not say which plugin interface it was written for.", @"It does not say which plugin interface it was written for.")];
		return;
	}
	if(declared > NekoPluginInterface) {
		[self refuse:[NSString stringWithFormat:
			NSLocalizedString(@"It was written for a newer version of Neko’s plugin interface (%ld; this one understands %ld).", @"It was written for a newer version of Neko’s plugin interface (%ld; this one understands %ld)."),
			(long)declared, (long)NekoPluginInterface]];
		return;
	}

	NSString *minimum = [manifest objectForKey:@"MinimumApp"];
	NSString *ours = [[[NSBundle mainBundle] infoDictionary]
		objectForKey:@"CFBundleShortVersionString"] ?: @"0";
	if([minimum length] > 0
	   && [ours compare:minimum options:NSNumericSearch] == NSOrderedAscending) {
		[self refuse:[NSString stringWithFormat:
			NSLocalizedString(@"It needs Neko %@ or newer, and this is %@.", @"It needs Neko %@ or newer, and this is %@."), minimum, ours]];
		return;
	}

	if([self carriesAMarker:[self summary]]) {
		[self refuse:NSLocalizedString(@"Its summary contains one of Neko’s own markers, which a plugin may not write.", @"Its summary contains one of Neko’s own markers, which a plugin may not write.")];
		return;
	}

	[self readExtensions];
}

/* Only the keys this interface knows about. An unknown one is refused rather
   than ignored: ignoring it would mean the plugin believes it is doing something
   it is not. */
- (void)readExtensions
{
	NSDictionary *extends = [manifest objectForKey:@"Extends"];
	if(extends != nil && ![extends isKindOfClass:[NSDictionary class]]) {
		[self refuse:NSLocalizedString(@"Its Extends section is not a dictionary.", @"Its Extends section is not a dictionary.")];
		return;
	}

	NSArray *known = @[@"Feeds", @"Text", @"Characters",
		@"Verbs", @"Routes"];
	for(NSString *key in extends)
		if(![known containsObject:key]) {
			[self refuse:[NSString stringWithFormat:
				NSLocalizedString(@"It extends “%@”, which this version of Neko does not offer yet.", @"It extends “%@”, which this version of Neko does not offer yet."), key]];
			return;
		}

	[self checkFeeds:[extends objectForKey:@"Feeds"]];
	[self checkText:[extends objectForKey:@"Text"]];
	[self checkCharacters:[extends objectForKey:@"Characters"]];
	[self checkVerbs:[extends objectForKey:@"Verbs"]];
	[self checkRoutes:[extends objectForKey:@"Routes"]];
	[self checkStrings];
}

/* Characters a plugin ships. Named one by one rather than found by scanning the
   folder, for the same reason as everything else here: the manifest is the
   contract, and a folder that appears after it was written is not part of it. */
- (void)checkCharacters:(NSArray *)characters
{
	if(characters == nil)
		return;
	if(![characters isKindOfClass:[NSArray class]]) {
		[self refuse:NSLocalizedString(@"Its Characters section is not a list.", @"Its Characters section is not a list.")];
		return;
	}

	NSFileManager *files = [NSFileManager defaultManager];
	NSEnumerator *e = [characters objectEnumerator];
	NSString *name;
	while((name = [e nextObject]) != nil) {
		if(![name isKindOfClass:[NSString class]]
		   || ![[name pathExtension] isEqualToString:@"nekochar"]) {
			[self refuse:NSLocalizedString(@"Each of its characters has to be the name of a folder ending in .nekochar.", @"Each of its characters has to be the name of a folder ending in .nekochar.")];
			return;
		}
		NSString *inside = [[folder path] stringByAppendingPathComponent:name];
		if(![files fileExistsAtPath:inside]) {
			[self refuse:[NSString stringWithFormat:
				NSLocalizedString(@"It says it ships the character “%@”, and that folder is not inside it.", @"It says it ships the character “%@”, and that folder is not inside it."), name]];
			return;
		}
		NSDictionary *manifestOfCharacter = [NSDictionary dictionaryWithContentsOfFile:
			[inside stringByAppendingPathComponent:@"character.plist"]];
		NSString *word = [manifestOfCharacter objectForKey:@"Identifier"];
		if([word length] == 0) {
			[self refuse:[NSString stringWithFormat:
				NSLocalizedString(@"The character “%@” has no readable character.plist with an Identifier in it.", @"The character “%@” has no readable character.plist with an Identifier in it."), name]];
			return;
		}
		if([word rangeOfCharacterFromSet:
				[[NSCharacterSet alphanumericCharacterSet] invertedSet]].location != NSNotFound) {
			[self refuse:[NSString stringWithFormat:
				NSLocalizedString(@"The character identifier “%@” has punctuation or spaces in it; it has to be one plain word.", @"The character identifier “%@” has punctuation or spaces in it; it has to be one plain word."), word]];
			return;
		}
	}
}

/* The schemes a verb may open. A closed list, and the reasoning is the same as
   for the feeds: if a plugin could name any scheme, a phrase somebody says would
   be able to reach anything on the Mac that registers one — including the one
   that runs Shortcuts, which would hide behind an address what the Shortcut field
   shows in the panel. */
+ (NSArray *)openableSchemes
{
	return @[@"https:", @"spotify:", @"music:", @"itms:",
		@"itmss:", @"mailto:"];
}

/* Phrases the plugin wants to hear, and what it wants fetched when it hears one.

   A route is the one thing here that decides what a question is *about*, which is
   the judgement this application has always kept for itself — so the shape is
   deliberately narrow. A closed list of phrases, one https address, and what comes
   back is quoted to a model as somebody else's words and can never become an
   action. A plugin does not get to write a pattern, a regular expression, or a
   rule; it gets to say which words it would like to be told about. */
- (void)checkRoutes:(NSArray *)routes
{
	if(routes == nil)
		return;
	if(![routes isKindOfClass:[NSArray class]]) {
		[self refuse:NSLocalizedString(@"Its Routes section is not a list.", @"Its Routes section is not a list.")];
		return;
	}

	NSMutableSet *taken = [NSMutableSet set];
	NSEnumerator *e = [routes objectEnumerator];
	NSDictionary *route;
	while((route = [e nextObject]) != nil) {
		if(![route isKindOfClass:[NSDictionary class]]) {
			[self refuse:NSLocalizedString(@"One of its routes is not a dictionary.", @"One of its routes is not a dictionary.")];
			return;
		}
		NSString *word = [route objectForKey:@"Identifier"];
		if([word length] == 0 || [taken containsObject:word]) {
			[self refuse:NSLocalizedString(@"Each of its routes needs its own Identifier.", @"Each of its routes needs its own Identifier.")];
			return;
		}
		[taken addObject:word];

		NSArray *phrases = [route objectForKey:@"Phrases"];
		if(![phrases isKindOfClass:[NSArray class]] || [phrases count] == 0) {
			[self refuse:[NSString stringWithFormat:
				NSLocalizedString(@"The route “%@” lists no Phrases to listen for.", @"The route “%@” lists no Phrases to listen for."), word]];
			return;
		}
		NSEnumerator *p = [phrases objectEnumerator];
		NSString *phrase;
		while((phrase = [p nextObject]) != nil) {
			if(![phrase isKindOfClass:[NSString class]] || [phrase length] < 3) {
				[self refuse:[NSString stringWithFormat:
					NSLocalizedString(@"The route “%@” has a phrase too short to match on; three letters at least.", @"The route “%@” has a phrase too short to match on; three letters at least."), word]];
				return;
			}
			if([self carriesAMarker:phrase]) {
				[self refuse:NSLocalizedString(@"One of its routes carries one of Neko’s own markers in a phrase.", @"One of its routes carries one of Neko’s own markers in a phrase.")];
				return;
			}
		}

		/* Whose words these are. It is shown to the person and given to the model
		   as the name on the quotation, so a route without one is a route whose
		   answer nobody can weigh. */
		NSString *says = [route objectForKey:@"Says"];
		if([says length] == 0) {
			[self refuse:[NSString stringWithFormat:
				NSLocalizedString(@"The route “%@” does not say whose words it fetches.", @"The route “%@” does not say whose words it fetches."), word]];
			return;
		}
		if([self carriesAMarker:says] || [self carriesAMarker:
		        ([route objectForKey:@"Summary"] ?: @"")]) {
			[self refuse:NSLocalizedString(@"One of its routes carries one of Neko’s own markers in what it says about itself.", @"One of its routes carries one of Neko’s own markers in what it says about itself.")];
			return;
		}

		if([route objectForKey:@"Program"] != nil) {
			[self refuse:NSLocalizedString(@"One of its routes wants to run a program of its own, which this version does not allow.", @"One of its routes wants to run a program of its own, which this version does not allow.")];
			return;
		}

		NSString *address = [route objectForKey:@"Url"];
		if([address length] == 0
		   || ![[address lowercaseString] hasPrefix:@"https://"]) {
			[self refuse:[NSString stringWithFormat:
				NSLocalizedString(@"The route “%@” needs an https address to fetch.", @"The route “%@” needs an https address to fetch."), word]];
			return;
		}
	}

	if([routes count] > 0 && ![self wantsNetwork]) {
		[self refuse:NSLocalizedString(@"It adds routes without asking for the network, so nothing could be fetched.", @"It adds routes without asking for the network, so nothing could be fetched.")];
		return;
	}
}

/* Phrases the plugin wants to hear, and what it wants done. */
- (void)checkVerbs:(NSArray *)verbs
{
	if(verbs == nil)
		return;
	if(![verbs isKindOfClass:[NSArray class]]) {
		[self refuse:NSLocalizedString(@"Its Verbs section is not a list.", @"Its Verbs section is not a list.")];
		return;
	}

	NSMutableSet *taken = [NSMutableSet set];
	NSEnumerator *e = [verbs objectEnumerator];
	NSDictionary *verb;
	while((verb = [e nextObject]) != nil) {
		if(![verb isKindOfClass:[NSDictionary class]]) {
			[self refuse:NSLocalizedString(@"One of its verbs is not a dictionary.", @"One of its verbs is not a dictionary.")];
			return;
		}
		NSString *word = [verb objectForKey:@"Identifier"];
		if([word length] == 0 || [taken containsObject:word]) {
			[self refuse:NSLocalizedString(@"Each of its verbs needs its own Identifier.", @"Each of its verbs needs its own Identifier.")];
			return;
		}
		[taken addObject:word];

		NSArray *phrases = [verb objectForKey:@"Phrases"];
		if(![phrases isKindOfClass:[NSArray class]] || [phrases count] == 0) {
			[self refuse:[NSString stringWithFormat:
				NSLocalizedString(@"The verb “%@” lists no Phrases to listen for.", @"The verb “%@” lists no Phrases to listen for."), word]];
			return;
		}
		NSEnumerator *p = [phrases objectEnumerator];
		NSString *phrase;
		while((phrase = [p nextObject]) != nil) {
			if(![phrase isKindOfClass:[NSString class]] || [phrase length] < 3) {
				[self refuse:[NSString stringWithFormat:
					NSLocalizedString(@"The verb “%@” has a phrase too short to match on; three letters at least.", @"The verb “%@” has a phrase too short to match on; three letters at least."), word]];
				return;
			}
			if([self carriesAMarker:phrase]) {
				[self refuse:NSLocalizedString(@"One of its verbs carries one of Neko’s own markers in a phrase.", @"One of its verbs carries one of Neko’s own markers in a phrase.")];
				return;
			}
		}

		/* The read-back. Every deed in this app is shown before it happens, and a
		   verb that skips it would be the one exception — so it is refused. */
		NSString *confirm = [verb objectForKey:@"Confirm"];
		if([confirm length] == 0) {
			[self refuse:[NSString stringWithFormat:
				NSLocalizedString(@"The verb “%@” has no Confirm sentence, and nothing here happens without being read back first.", @"The verb “%@” has no Confirm sentence, and nothing here happens without being read back first."), word]];
			return;
		}
		if([self carriesAMarker:confirm]) {
			[self refuse:NSLocalizedString(@"One of its verbs carries one of Neko’s own markers in its Confirm sentence.", @"One of its verbs carries one of Neko’s own markers in its Confirm sentence.")];
			return;
		}

		/* Exactly one door of three: an address, a Shortcut of yours, or a
		   command sent to Music or Spotify. A verb that could do two things is a
		   verb whose read-back sentence is a lie. */
		NSString *address = [verb objectForKey:@"Url"];
		NSString *shortcut = [verb objectForKey:@"Shortcut"];
		NSString *player = [verb objectForKey:@"Player"];
		NSString *command = [verb objectForKey:@"Command"];
		int doors = ([address length] > 0 ? 1 : 0) + ([shortcut length] > 0 ? 1 : 0)
			+ ([player length] > 0 || [command length] > 0 ? 1 : 0);
		if(doors != 1) {
			[self refuse:[NSString stringWithFormat:
				NSLocalizedString(@"The verb “%@” needs exactly one of Url, Shortcut, or Player and Command.", @"The verb “%@” needs exactly one of Url, Shortcut, or Player and Command."), word]];
			return;
		}
		if([verb objectForKey:@"Program"] != nil || [verb objectForKey:@"Executable"] != nil) {
			[self refuse:NSLocalizedString(@"One of its verbs wants to run a program of its own, which this version does not allow.", @"One of its verbs wants to run a program of its own, which this version does not allow.")];
			return;
		}
		/* Refused rather than ignored, which is the rule everywhere in this file.
		   Nothing reads these keys, so a plugin carrying one is either mistaken
		   about what it can do or hoping the next version will read it. Both are
		   better answered now. */
		if([verb objectForKey:@"Script"] != nil || [verb objectForKey:@"AppleScript"] != nil) {
			[self refuse:NSLocalizedString(@"One of its verbs carries a script of its own. Neko sends its own commands to Music and Spotify and never anybody else’s.", @"One of its verbs carries a script of its own. Neko sends its own commands to Music and Spotify and never anybody else’s.")];
			return;
		}

		if([address length] > 0) {
			BOOL allowed = NO;
			NSEnumerator *s = [[NekoPlugin openableSchemes] objectEnumerator];
			NSString *scheme;
			while((scheme = [s nextObject]) != nil)
				if([[address lowercaseString] hasPrefix:scheme])
					allowed = YES;
			if(!allowed) {
				[self refuse:[NSString stringWithFormat:
					NSLocalizedString(@"The verb “%@” opens an address Neko will not open; allowed are https, spotify, music, itms and mailto.", @"The verb “%@” opens an address Neko will not open; allowed are https, spotify, music, itms and mailto."), word]];
				return;
			}
			if(![self wantsToOpenThings]) {
				[self refuse:NSLocalizedString(@"It has verbs that open an address without asking to open things.", @"It has verbs that open an address without asking to open things.")];
				return;
			}
		} else if([shortcut length] > 0) {
			if(![self wantsShortcuts]) {
				[self refuse:NSLocalizedString(@"It has verbs that run one of your Shortcuts without asking to.", @"It has verbs that run one of your Shortcuts without asking to.")];
				return;
			}
		} else {
			/* Two closed lists, and nothing else gets through. A plugin names a
			   player and a command; the script that carries it out lives in the
			   app, in one file, where it can be read. */
			if([player length] == 0 || [command length] == 0) {
				[self refuse:[NSString stringWithFormat:
					NSLocalizedString(@"The verb “%@” needs both a Player and a Command.", @"The verb “%@” needs both a Player and a Command."), word]];
				return;
			}
			if(![NekoPlayer knows:player]) {
				[self refuse:[NSString stringWithFormat:
					NSLocalizedString(@"The verb “%@” names the player “%@”, and Neko only knows music and spotify.", @"The verb “%@” names the player “%@”, and Neko only knows music and spotify."), word, player]];
				return;
			}
			if(![NekoPlayer knowsCommand:command]) {
				[self refuse:[NSString stringWithFormat:
					NSLocalizedString(@"The verb “%@” asks for “%@”, which is not one of the commands Neko can send.", @"The verb “%@” asks for “%@”, which is not one of the commands Neko can send."), word, command]];
				return;
			}
			if(![self wantsToControlPlayers]) {
				[self refuse:NSLocalizedString(@"It has verbs that command Music or Spotify without asking to.", @"It has verbs that command Music or Spotify without asking to.")];
				return;
			}
		}
	}
}

/* A language folder that cannot be read is an authoring mistake, and a silent
   fallback would leave the author believing their translations work. */
- (void)checkStrings
{
	NSFileManager *files = [NSFileManager defaultManager];
	NSEnumerator *e = [[files contentsOfDirectoryAtPath:[folder path] error:NULL]
		objectEnumerator];
	NSString *entry;
	while((entry = [e nextObject]) != nil) {
		if(![[entry pathExtension] isEqualToString:@"lproj"])
			continue;
		NSString *table = [[[folder path] stringByAppendingPathComponent:entry]
			stringByAppendingPathComponent:@"plugin.strings"];
		if(![files fileExistsAtPath:table])
			continue;
		if([NSDictionary dictionaryWithContentsOfFile:table] == nil) {
			[self refuse:[NSString stringWithFormat:
				NSLocalizedString(@"Its %@ translations cannot be read; plugin.strings has to be a property list.", @"Its %@ translations cannot be read; plugin.strings has to be a property list."), entry]];
			return;
		}
	}
}

/* Text processing: the plugin is handed what somebody said, or what the cat is
   about to say, and hands something back.

   It is done by running one of the user's own Shortcuts, which is the whole of
   why it is allowed at all: the Shortcut is theirs, they wrote it or installed
   it, and nothing new runs inside this app. A plugin names a Shortcut; it cannot
   name a program. */
- (void)checkText:(NSDictionary *)text
{
	if(text == nil)
		return;
	if(![text isKindOfClass:[NSDictionary class]]) {
		[self refuse:NSLocalizedString(@"Its Text section is not a dictionary.", @"Its Text section is not a dictionary.")];
		return;
	}

	NSString *shortcut = [text objectForKey:@"Shortcut"];
	if([shortcut length] == 0) {
		[self refuse:NSLocalizedString(@"It processes text without naming a Shortcut to do it with.", @"It processes text without naming a Shortcut to do it with.")];
		return;
	}
	if([text objectForKey:@"Program"] != nil || [text objectForKey:@"Executable"] != nil) {
		[self refuse:NSLocalizedString(@"It wants to process text with a program of its own, which this version does not allow — only one of your own Shortcuts.", @"It wants to process text with a program of its own, which this version does not allow — only one of your own Shortcuts.")];
		return;
	}

	NSString *direction = [[text objectForKey:@"Direction"] lowercaseString];
	NSArray *allowed = [NSArray arrayWithObjects:@"in", @"out", @"both", nil];
	if(![allowed containsObject:direction ?: @""]) {
		[self refuse:NSLocalizedString(@"Its Text section has to say Direction: in, out or both.", @"Its Text section has to say Direction: in, out or both.")];
		return;
	}
}

- (void)checkFeeds:(NSArray *)feeds
{
	if(feeds == nil)
		return;
	if(![feeds isKindOfClass:[NSArray class]]) {
		[self refuse:NSLocalizedString(@"Its Feeds section is not a list.", @"Its Feeds section is not a list.")];
		return;
	}
	if(![self wantsNetwork]) {
		[self refuse:NSLocalizedString(@"It adds feeds without asking for the network, so nothing could be fetched.", @"It adds feeds without asking for the network, so nothing could be fetched.")];
		return;
	}

	NSEnumerator *e = [feeds objectEnumerator];
	NSDictionary *feed;
	while((feed = [e nextObject]) != nil) {
		if(![feed isKindOfClass:[NSDictionary class]]) {
			[self refuse:NSLocalizedString(@"One of its feeds is not a dictionary.", @"One of its feeds is not a dictionary.")];
			return;
		}
		NSString *word = [feed objectForKey:@"Identifier"];
		NSString *address = [feed objectForKey:@"Address"];
		if([word length] == 0 || [[feed objectForKey:@"Name"] length] == 0) {
			[self refuse:NSLocalizedString(@"One of its feeds has no Identifier or no Name.", @"One of its feeds has no Identifier or no Name.")];
			return;
		}
		/* The word a question is matched against, and one the app already uses
		   would quietly shadow a built-in source. */
		if([word rangeOfCharacterFromSet:
				[[NSCharacterSet alphanumericCharacterSet] invertedSet]].location != NSNotFound) {
			[self refuse:[NSString stringWithFormat:
				NSLocalizedString(@"The feed word “%@” has punctuation or spaces in it; it has to be one plain word.", @"The feed word “%@” has punctuation or spaces in it; it has to be one plain word."), word]];
			return;
		}
		if(![[address lowercaseString] hasPrefix:@"https://"]) {
			[self refuse:[NSString stringWithFormat:
				NSLocalizedString(@"The feed “%@” is not an https address.", @"The feed “%@” is not an https address."), word]];
			return;
		}
		if([self carriesAMarker:[feed objectForKey:@"Name"]]
		   || [self carriesAMarker:([feed objectForKey:@"Detail"] ?: @"")]) {
			[self refuse:NSLocalizedString(@"One of its feeds carries one of Neko’s own markers in its name.", @"One of its feeds carries one of Neko’s own markers in its name.")];
			return;
		}
	}
}

- (NSArray *)feeds
{
	if(![self isUsable])
		return [NSArray array];
	NSArray *feeds = [[manifest objectForKey:@"Extends"] objectForKey:@"Feeds"];
	if(![feeds isKindOfClass:[NSArray class]])
		return [NSArray array];

	/* A detail is looked up as a string key before it is used. For the plugin
	   that ships with the app that means its descriptions stay translated —
	   they are the same keys the code used to hold — and for anybody else's
	   plugin the string simply passes through, which is right: the app has no
	   translations for words it has never seen. */
	NSMutableArray *localized = [NSMutableArray array];
	NSEnumerator *e = [feeds objectEnumerator];
	NSDictionary *feed;
	while((feed = [e nextObject]) != nil) {
		NSMutableDictionary *one = [NSMutableDictionary dictionaryWithDictionary:feed];
		NSString *detail = [feed objectForKey:@"Detail"];
		if([detail length] > 0)
			[one setObject:[self localized:detail] forKey:@"Detail"];
		NSString *shown = [feed objectForKey:@"Name"];
		if([shown length] > 0)
			[one setObject:[self localized:shown] forKey:@"Name"];
		[localized addObject:one];
	}
	return localized;
}

- (NSArray *)routes
{
	if(![self isUsable])
		return [NSArray array];
	NSArray *routes = [[manifest objectForKey:@"Extends"] objectForKey:@"Routes"];
	if(![routes isKindOfClass:[NSArray class]])
		return [NSArray array];

	NSMutableArray *localized = [NSMutableArray array];
	NSEnumerator *e = [routes objectEnumerator];
	NSDictionary *route;
	while((route = [e nextObject]) != nil) {
		NSMutableDictionary *one = [NSMutableDictionary dictionaryWithDictionary:route];
		NSString *says = [route objectForKey:@"Says"];
		if([says length] > 0)
			[one setObject:[self localized:says] forKey:@"Says"];
		NSString *summary = [route objectForKey:@"Summary"];
		if([summary length] > 0)
			[one setObject:[self localized:summary] forKey:@"Summary"];
		[one setObject:[self identifier] forKey:@"Plugin"];
		[localized addObject:one];
	}
	return localized;
}

- (NSArray *)verbs
{
	if(![self isUsable])
		return [NSArray array];
	NSArray *verbs = [[manifest objectForKey:@"Extends"] objectForKey:@"Verbs"];
	if(![verbs isKindOfClass:[NSArray class]])
		return [NSArray array];

	/* The two sentences a person reads go through the plugin's own translations
	   first, like everything else it shows. */
	NSMutableArray *localized = [NSMutableArray array];
	NSEnumerator *e = [verbs objectEnumerator];
	NSDictionary *verb;
	while((verb = [e nextObject]) != nil) {
		NSMutableDictionary *one = [NSMutableDictionary dictionaryWithDictionary:verb];
		NSString *confirm = [verb objectForKey:@"Confirm"];
		if([confirm length] > 0)
			[one setObject:[self localized:confirm] forKey:@"Confirm"];
		NSString *summary = [verb objectForKey:@"Summary"];
		if([summary length] > 0)
			[one setObject:[self localized:summary] forKey:@"Summary"];
		[localized addObject:one];
	}
	return localized;
}

- (NSArray<NSString*> *)shortcutsItNeeds
{
	NSMutableArray *names = [NSMutableArray array];
	NSEnumerator *e = [[self verbs] objectEnumerator];
	NSDictionary *verb;
	while((verb = [e nextObject]) != nil) {
		NSString *name = [verb objectForKey:@"Shortcut"];
		if([name length] > 0 && ![names containsObject:name])
			[names addObject:name];
	}
	NSString *text = [self textShortcut];
	if([text length] > 0 && ![names containsObject:text])
		[names addObject:text];
	return names;
}

- (NSArray *)characterPaths
{
	if(![self isUsable])
		return [NSArray array];
	NSArray *named = [[manifest objectForKey:@"Extends"] objectForKey:@"Characters"];
	if(![named isKindOfClass:[NSArray class]])
		return [NSArray array];
	NSMutableArray *paths = [NSMutableArray array];
	NSEnumerator *e = [named objectEnumerator];
	NSString *name;
	while((name = [e nextObject]) != nil)
		[paths addObject:[[folder path] stringByAppendingPathComponent:name]];
	return paths;
}

/* The plugin's own strings, for the language the app is running in. Loaded once,
   and only if it ships any. */
- (NSDictionary *)strings
{
	if(strings != nil)
		return strings;

	NSFileManager *files = [NSFileManager defaultManager];
	NSEnumerator *e = [[[NSBundle mainBundle] preferredLocalizations] objectEnumerator];
	NSString *language;
	while((language = [e nextObject]) != nil) {
		NSString *code = [language length] > 2 ? [language substringToIndex:2] : language;
		NSEnumerator *tries = [[NSArray arrayWithObjects:language, code, nil] objectEnumerator];
		NSString *attempt;
		while((attempt = [tries nextObject]) != nil) {
			NSString *path = [[[folder path] stringByAppendingPathComponent:
				[attempt stringByAppendingPathExtension:@"lproj"]]
				stringByAppendingPathComponent:@"plugin.strings"];
			if(![files fileExistsAtPath:path])
				continue;
			NSDictionary *read = [NSDictionary dictionaryWithContentsOfFile:path];
			if(read != nil) {
				strings = [read retain];
				return strings;
			}
		}
	}
	strings = [[NSDictionary dictionary] retain];   /* asked, and there is none */
	return strings;
}

- (NSString *)localized:(NSString *)key
{
	if([key length] == 0)
		return key;
	NSString *mine = [[self strings] objectForKey:key];
	if([mine length] > 0)
		return mine;
	/* The app's own tables next: that is how the feeds shipped inside the app
	   keep their translations without shipping a strings file of their own. */
	return NSLocalizedString(key, nil);
}

- (NSDictionary *)text
{
	if(![self isUsable])
		return nil;
	NSDictionary *text = [[manifest objectForKey:@"Extends"] objectForKey:@"Text"];
	return [text isKindOfClass:[NSDictionary class]] ? text : nil;
}

- (NSString *)textShortcut
{
	return [[self text] objectForKey:@"Shortcut"];
}

- (BOOL)processesTextGoing:(BOOL)inward
{
	NSString *direction = [[[self text] objectForKey:@"Direction"] lowercaseString];
	if([direction isEqualToString:@"both"])
		return YES;
	return [direction isEqualToString:(inward ? @"in" : @"out")];
}

- (NSString *)describeWhatItAdds
{
	NSMutableArray *parts = [NSMutableArray array];
	NSUInteger feeds = [[self feeds] count];
	if(feeds == 1)
		[parts addObject:NSLocalizedString(@"1 feed", @"1 feed")];
	else if(feeds > 1)
		[parts addObject:[NSString localizedStringWithFormat:
			NSLocalizedString(@"%lu feeds", @"%lu feeds"), (unsigned long)feeds]];

	/* Named, not counted. Somebody who switches on a plugin that ships characters
	   is then looking for them in a menu of forty-seven, and "3 characters" does
	   not help with that — which is exactly what happened the first time one was
	   installed. */
	NSMutableArray *characterNames = [NSMutableArray array];
	NSEnumerator *where = [[self characterPaths] objectEnumerator];
	NSString *path;
	while((path = [where nextObject]) != nil) {
		NSDictionary *its = [NSDictionary dictionaryWithContentsOfFile:
			[path stringByAppendingPathComponent:@"character.plist"]];
		NSString *called = [its objectForKey:@"Name"];
		if([called length] > 0)
			[characterNames addObject:called];
	}
	if([characterNames count] > 0 && [characterNames count] <= 6) {
		[parts addObject:[NSString stringWithFormat:
			NSLocalizedString(@"the characters %@, in the Character menu", @"the characters %@, in the Character menu"),
			[characterNames componentsJoinedByString:@", "]]];
	}
	else {

	NSUInteger characters = [[self characterPaths] count];
	if(characters == 1)
		[parts addObject:NSLocalizedString(@"1 character", @"1 character")];
	else if(characters > 1)
		[parts addObject:[NSString localizedStringWithFormat:
			NSLocalizedString(@"%lu characters", @"%lu characters"), (unsigned long)characters]];
	}

	NSUInteger verbs = [[self verbs] count];
	if(verbs == 1)
		[parts addObject:NSLocalizedString(@"1 phrase it listens for", @"1 phrase it listens for")];
	else if(verbs > 1)
		[parts addObject:[NSString localizedStringWithFormat:
			NSLocalizedString(@"%lu phrases it listens for", @"%lu phrases it listens for"), (unsigned long)verbs]];

	NSUInteger routes = [[self routes] count];
	if(routes == 1)
		[parts addObject:NSLocalizedString(@"1 question it goes and looks up", @"1 question it goes and looks up")];
	else if(routes > 1)
		[parts addObject:[NSString localizedStringWithFormat:
			NSLocalizedString(@"%lu questions it goes and looks up", @"%lu questions it goes and looks up"),
			(unsigned long)routes]];

	/* The one thing about a route that a feed never does. The application's own
	   requests carry no question at all; a route with a %@ in its address carries
	   part of what somebody said to whoever owns that address, because that is
	   what looking something up is. It is said here, in the window where somebody
	   decides whether to trust the folder they just added. */
	NSMutableSet *hosts = [NSMutableSet set];
	NSEnumerator *r = [[self routes] objectEnumerator];
	NSDictionary *route;
	while((route = [r nextObject]) != nil) {
		NSString *address = [route objectForKey:@"Url"];
		if([address rangeOfString:@"%@"].location == NSNotFound)
			continue;
		NSString *host = [[NSURL URLWithString:
			[address stringByReplacingOccurrencesOfString:@"%@" withString:@"x"]] host];
		if([host length] > 0)
			[hosts addObject:host];
	}
	if([hosts count] > 0)
		[parts addObject:[NSString localizedStringWithFormat:
			NSLocalizedString(@"sends part of what you say to %@", @"sends part of what you say to %@"),
			[[[hosts allObjects] sortedArrayUsingSelector:@selector(compare:)]
				componentsJoinedByString:@", "]]];

	if([self text] != nil) {
		NSString *which = [self processesTextGoing:YES]
			? ([self processesTextGoing:NO]
				? NSLocalizedString(@"what you say and what it answers", @"what you say and what it answers")
				: NSLocalizedString(@"what you say", @"what you say"))
			: NSLocalizedString(@"what it answers", @"what it answers");
		[parts addObject:[NSString stringWithFormat:
			NSLocalizedString(@"passes %@ through your Shortcut “%@”", @"passes %@ through your Shortcut “%@”"),
			which, [self textShortcut]]];
	}

	if([parts count] == 0)
		return NSLocalizedString(@"nothing this version of Neko can use yet", @"nothing this version of Neko can use yet");
	return [parts componentsJoinedByString:NSLocalizedString(@", and ", @"noun joiner")];
}

@end
