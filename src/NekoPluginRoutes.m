#import "NekoPluginRoutes.h"
#import "NekoPlugins.h"
#import "NekoPlugin.h"
#import "NekoPhrase.h"
#import "NekoWeb.h"

/* What a route may hand back, before any of it is quoted to anybody. Eight lines
   because that is what a feed gives, and 1200 characters because the whole
   instruction block a small model is given is about that again — a route that
   answers with a novel would push the character out of the prompt. */
static const NSUInteger NekoRouteMostLines = 8;
static const NSUInteger NekoRouteMostCharacters = 1200;

@implementation NekoPluginRoutes

+ (BOOL)anythingListens
{
	NSEnumerator *e = [[[NekoPlugins sharedPlugins] enabled] objectEnumerator];
	NekoPlugin *plugin;
	while((plugin = [e nextObject]) != nil)
		if([[plugin routes] count] > 0)
			return YES;
	return NO;
}

+ (NSDictionary *)matchFor:(NSString *)question
{
	NSString *said = [question lowercaseString];
	NSDictionary *best = nil;
	NSString *bestPhrase = nil;
	NSString *bestArgument = nil;

	NSEnumerator *plugins = [[[NekoPlugins sharedPlugins] enabled] objectEnumerator];
	NekoPlugin *plugin;
	while((plugin = [plugins nextObject]) != nil) {
		NSEnumerator *e = [[plugin routes] objectEnumerator];
		NSDictionary *route;
		while((route = [e nextObject]) != nil) {
			NSEnumerator *p = [[route objectForKey:@"Phrases"] objectEnumerator];
			NSString *phrase;
			while((phrase = [p nextObject]) != nil) {
				NSString *argument = nil;
				if(![NekoPhrase phrase:[phrase lowercaseString] in:said
				                  said:question argument:&argument])
					continue;
				if(bestPhrase != nil && [phrase length] <= [bestPhrase length])
					continue;
				/* An address with a %@ in it has nothing to ask for without one. */
				NSString *where = [route objectForKey:@"Url"];
				if([where rangeOfString:@"%@"].location != NSNotFound
				   && [argument length] == 0)
					continue;
				best = route;
				bestPhrase = phrase;
				bestArgument = argument;
			}
		}
	}

	if(best == nil)
		return nil;
	NSMutableDictionary *matched = [NSMutableDictionary dictionaryWithDictionary:best];
	[matched setObject:(bestArgument ?: @"") forKey:@"Argument"];
	return matched;
}

#pragma mark Going and looking

/* Whatever came back, as lines. A feed if it parses as one — which is what most
   of these will be — and otherwise the text with its tags taken out, capped.
   Nothing here tries to be clever about JSON: a route that wants to be understood
   publishes something a person could read. */
/* The field names a JSON answer is read out of. A closed list rather than
   cleverness: an API that wants to be understood puts its prose under one of
   these, and anything else is left alone rather than guessed at.

   Measured on Wikipedia's own summary, which is one 1,948-byte line of JSON and
   the shape most public APIs answer in — with this it comes out as three
   readable lines and without it as nothing at all. */
static NSSet *NekoRouteFieldsWorthReading(void)
{
	static NSSet *fields = nil;
	if(fields == nil)
		fields = [[NSSet setWithArray:[NSArray arrayWithObjects:
			@"title", @"name", @"description", @"summary", @"extract",
			@"abstract", @"text", @"content", @"answer", @"value", nil]] retain];
	return fields;
}

static void NekoReadJSON(id thing, NSMutableArray *into, NSUInteger depth)
{
	if(depth > 4 || [into count] >= NekoRouteMostLines)
		return;
	if([thing isKindOfClass:[NSDictionary class]]) {
		NSEnumerator *k = [thing keyEnumerator];
		NSString *key;
		while((key = [k nextObject]) != nil) {
			id value = [thing objectForKey:key];
			if([value isKindOfClass:[NSString class]]
			   && [NekoRouteFieldsWorthReading() containsObject:[key lowercaseString]]) {
				NSString *said = [value stringByTrimmingCharactersInSet:
					[NSCharacterSet whitespaceAndNewlineCharacterSet]];
				if([said length] > 0 && [into count] < NekoRouteMostLines)
					[into addObject:[NSString stringWithFormat:@"%@: %@", key, said]];
			}
			else if([value isKindOfClass:[NSDictionary class]]
			        || [value isKindOfClass:[NSArray class]])
				NekoReadJSON(value, into, depth + 1);
		}
	}
	else if([thing isKindOfClass:[NSArray class]]) {
		NSEnumerator *e = [thing objectEnumerator];
		id one;
		while((one = [e nextObject]) != nil)
			NekoReadJSON(one, into, depth + 1);
	}
}

+ (NSArray<NSString*> *)linesIn:(NSData *)body
{
	NSArray *headlines = [[NekoWeb sharedWeb] headlinesInFeed:body];
	if([headlines count] > 0)
		return headlines;

	/* Then JSON, which is what most things that answer a question answer in. */
	id parsed = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
	if(parsed != nil) {
		NSMutableArray *said = [NSMutableArray array];
		NekoReadJSON(parsed, said, 0);
		if([said count] > 0)
			return said;
	}

	NSString *text = [[[NSString alloc] initWithData:body
	                                        encoding:NSUTF8StringEncoding] autorelease];
	if([text length] == 0)
		return [NSArray array];
	if([text length] > NekoRouteMostCharacters * 8)
		text = [text substringToIndex:NekoRouteMostCharacters * 8];

	/* Tags out, entities left alone: this is quoted as somebody's words and not
	   rendered, so a stray &amp; is somebody's stray &amp;. */
	NSMutableString *plain = [NSMutableString stringWithString:text];
	NSRange open = [plain rangeOfString:@"<"];
	while(open.location != NSNotFound) {
		NSRange close = [plain rangeOfString:@">"
		                             options:0
		                               range:NSMakeRange(open.location,
		                                   [plain length] - open.location)];
		if(close.location == NSNotFound)
			break;
		[plain deleteCharactersInRange:NSMakeRange(open.location,
			NSMaxRange(close) - open.location)];
		open = [plain rangeOfString:@"<"];
	}

	NSMutableArray *lines = [NSMutableArray array];
	NSUInteger spent = 0;
	NSEnumerator *e = [[plain componentsSeparatedByCharactersInSet:
		[NSCharacterSet newlineCharacterSet]] objectEnumerator];
	NSString *one;
	while((one = [e nextObject]) != nil && [lines count] < NekoRouteMostLines) {
		NSString *trimmed = [one stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if([trimmed length] == 0)
			continue;
		if(spent + [trimmed length] > NekoRouteMostCharacters) {
			/* Cut rather than dropped. A body that is one line longer than the
			   whole budget used to come back as nothing at all, which is how a
			   route that answers in a single long line looked unreachable. */
			NSUInteger room = NekoRouteMostCharacters > spent
				? NekoRouteMostCharacters - spent : 0;
			if(room > 40)
				[lines addObject:[trimmed substringToIndex:room]];
			break;
		}
		[lines addObject:trimmed];
		spent += [trimmed length];
	}
	return lines;
}

+ (void)fetch:(NSDictionary *)route
   completion:(void (^)(NSArray<NSString*> *lines, NSError *error))done
{
	/* Asked again at the moment of fetching and not at the moment of matching: a
	   plugin switched off in between has to count. */
	NekoPlugin *plugin = [[NekoPlugins sharedPlugins]
		pluginWithIdentifier:[route objectForKey:@"Plugin"]];
	if(plugin == nil || ![plugin isUsable] || ![plugin wantsNetwork]
	   || ![[NekoPlugins sharedPlugins] isEnabled:plugin]) {
		done([NSArray array], nil);
		return;
	}

	NSString *address = [route objectForKey:@"Url"];
	if(![[address lowercaseString] hasPrefix:@"https://"]) {
		done([NSArray array], nil);         /* checked twice, as everything is */
		return;
	}
	if([address rangeOfString:@"%@"].location != NSNotFound) {
		NSString *escaped = [[route objectForKey:@"Argument"] ?: @""
			stringByAddingPercentEncodingWithAllowedCharacters:
				[NSCharacterSet URLQueryAllowedCharacterSet]];
		address = [NSString stringWithFormat:address, escaped ?: @""];
	}
	NSURL *url = [NSURL URLWithString:address];
	if(url == nil || ![[[url scheme] lowercaseString] isEqualToString:@"https"]) {
		done([NSArray array], nil);
		return;
	}

	[[NekoWeb sharedWeb] get:url completion:^(NSData *body, NSError *error) {
		if(body == nil) {
			done(nil, error);
			return;
		}
		done([self linesIn:body], nil);
	}];
}

@end
