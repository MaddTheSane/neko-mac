#import "NekoPluginVerbs.h"
#import "NekoPhrase.h"
#import "NekoPlugins.h"
#import "NekoPlugin.h"
#import "NekoShortcutProvider.h"
#import "NekoPlayer.h"

@implementation NekoPluginVerbs

+ (BOOL)anythingListens
{
	NSEnumerator *e = [[[NekoPlugins sharedPlugins] enabled] objectEnumerator];
	NekoPlugin *plugin;
	while((plugin = [e nextObject]) != nil)
		if([[plugin verbs] count] > 0)
			return YES;
	return NO;
}

+ (BOOL)anythingCommandsAPlayer
{
	NSEnumerator *e = [[[NekoPlugins sharedPlugins] enabled] objectEnumerator];
	NekoPlugin *plugin;
	while((plugin = [e nextObject]) != nil) {
		if(![plugin wantsToControlPlayers])
			continue;
		NSEnumerator *v = [[plugin verbs] objectEnumerator];
		NSDictionary *verb;
		while((verb = [v nextObject]) != nil)
			if([[verb objectForKey:@"Player"] length] > 0)
				return YES;
	}
	return NO;
}

+ (NSDictionary *)matchFor:(NSString *)question
{
	NSString *said = [question lowercaseString];
	NSDictionary *best = nil;
	NSString *bestArgument = nil;
	NSString *bestPhrase = nil;
	NekoPlugin *bestPlugin = nil;

	NSEnumerator *plugins = [[[NekoPlugins sharedPlugins] enabled] objectEnumerator];
	NekoPlugin *plugin;
	while((plugin = [plugins nextObject]) != nil) {
		NSEnumerator *e = [[plugin verbs] objectEnumerator];
		NSDictionary *verb;
		while((verb = [e nextObject]) != nil) {
			NSEnumerator *p = [[verb objectForKey:@"Phrases"] objectEnumerator];
			NSString *phrase;
			while((phrase = [p nextObject]) != nil) {
				NSString *argument = nil;
				if(![NekoPhrase phrase:[phrase lowercaseString] in:said
				                  said:question argument:&argument])
					continue;
				/* Longest phrase wins: "alza il volume" beats "alza". */
				if(bestPhrase != nil && [phrase length] <= [bestPhrase length])
					continue;
				/* A verb that needs words is not a match without them: "metti"
				   on its own is not a request for a particular song, and the
				   read-back would say so — "Metto “” in Musica?". A verb that
				   needs none is complete as it stands, and "alza il volume" is the
				   whole sentence.
				   Which it is, is decided by the sentence the person will be shown
				   rather than by the door behind it: a Shortcut can want the words
				   just as much as an address can. (This is where the volume verbs
				   were lost. The test was on Url alone, and rangeOfString: sent to
				   a nil address answers {0, 0} — 0 is not NSNotFound, so every
				   Shortcut verb said with nothing after it looked like an address
				   waiting for a word.) */
				NSString *address = [verb objectForKey:@"Url"];
				NSString *readBack = [verb objectForKey:@"Confirm"];
				BOOL needsWords =
					([address length] > 0
					 && [address rangeOfString:@"%@"].location != NSNotFound)
					|| ([readBack length] > 0
					    && [readBack rangeOfString:@"%@"].location != NSNotFound);
				if(needsWords && [argument length] == 0)
					continue;
				best = verb;
				bestPhrase = phrase;
				bestArgument = argument;
				bestPlugin = plugin;
			}
		}
	}

	if(best == nil)
		return nil;

	NSMutableDictionary *matched = [NSMutableDictionary dictionaryWithDictionary:best];
	[matched setObject:[bestPlugin identifier] forKey:@"Plugin"];
	[matched setObject:(bestArgument ?: @"") forKey:@"Argument"];

	/* The sentence somebody is about to be shown. A Confirm line with a %@ in it
	   gets the argument; one without is used as it is. */
	NSString *confirm = [best objectForKey:@"Confirm"];
	NSString *sentence = [confirm rangeOfString:@"%@"].location != NSNotFound
		? [NSString stringWithFormat:confirm, bestArgument ?: @""]
		: confirm;
	[matched setObject:sentence forKey:@"Sentence"];
	return matched;
}

#pragma mark Doing it

+ (BOOL)perform:(NSDictionary *)verb
{
	return [self perform:verb saying:NULL];
}

+ (BOOL)perform:(NSDictionary *)verb saying:(NSString **)problem
{
	/* Asked again at the moment of doing, not at the moment of matching: a switch
	   turned off between the question and the yes has to count. */
	NekoPlugin *plugin = [[NekoPlugins sharedPlugins]
		pluginWithIdentifier:[verb objectForKey:@"Plugin"]];
	if(plugin == nil || ![plugin isUsable]
	   || ![[NekoPlugins sharedPlugins] isEnabled:plugin])
		return NO;

	NSString *argument = [verb objectForKey:@"Argument"] ?: @"";
	NSString *address = [verb objectForKey:@"Url"];
	if([address length] > 0) {
		if(![plugin wantsToOpenThings])
			return NO;
		BOOL allowed = NO;
		NSEnumerator *s = [[NekoPlugin openableSchemes] objectEnumerator];
		NSString *scheme;
		while((scheme = [s nextObject]) != nil)
			if([[address lowercaseString] hasPrefix:scheme])
				allowed = YES;
		if(!allowed)
			return NO;           /* checked twice: once on reading, once on doing */

		NSString *filled = address;
		if([address rangeOfString:@"%@"].location != NSNotFound) {
			NSString *escaped = [argument stringByAddingPercentEncodingWithAllowedCharacters:
				[NSCharacterSet URLQueryAllowedCharacterSet]];
			filled = [NSString stringWithFormat:address, escaped ?: @""];
		}
		NSURL *url = [NSURL URLWithString:filled];
		return url != nil && [[NSWorkspace sharedWorkspace] openURL:url];
	}

	/* Music and Spotify, spoken to directly: the reason 2.6's volume verbs needed
	   a Shortcut nobody had made. The plugin named a player and a command; the
	   script that carries it out is the app's own. */
	NSString *player = [verb objectForKey:@"Player"];
	NSString *command = [verb objectForKey:@"Command"];
	if([player length] > 0 && [command length] > 0) {
		if(![plugin wantsToControlPlayers])
			return NO;
		if(![NekoPlayer knows:player] || ![NekoPlayer knowsCommand:command])
			return NO;              /* checked twice: on reading, and on doing */
		return [NekoPlayer perform:command on:player with:argument saying:problem];
	}

	NSString *shortcut = [verb objectForKey:@"Shortcut"];
	if([shortcut length] == 0 || ![plugin wantsShortcuts])
		return NO;

	/* Their own Shortcut, handed the rest of the sentence. Nothing is read back
	   from it: a verb does something, it does not answer. */
	NekoShortcutProvider *runner = [[[NekoShortcutProvider alloc]
		initWithShortcutName:shortcut] autorelease];
	if(![runner shortcutExists]) {
		/* The one failure somebody can do something about, so it is said by name
		   rather than as "that did not work". */
		if(problem != NULL)
			*problem = [NSString stringWithFormat:
				NSLocalizedString(@"You have no Shortcut called “%@”. The plugin says how to make it.", @"You have no Shortcut called \"%@\". The plugin says how to make it."),
				shortcut];
		return NO;
	}
	return [runner launchShortcutWithURL:[runner urlForQuestion:argument]];
}

@end
