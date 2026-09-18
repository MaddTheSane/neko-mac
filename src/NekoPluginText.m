#import "NekoPluginText.h"
#import "NekoPlugins.h"
#import "NekoPlugin.h"
#import "NekoShortcutProvider.h"
#import "NekoAction.h"
#import "NekoWeb.h"

/* Long enough for a Shortcut that thinks, short enough that a conversation does
   not visibly wait for one. */
static const NSTimeInterval NekoPluginTextPatience = 8.0;
/* A transformation is a rewording, not a document. */
static const NSUInteger NekoPluginTextMost = 2000;

@implementation NekoPluginText

+ (NekoPlugin *)firstProcessing:(BOOL)inward
{
	NSEnumerator *e = [[[NekoPlugins sharedPlugins] enabled] objectEnumerator];
	NekoPlugin *plugin;
	while((plugin = [e nextObject]) != nil)
		if([plugin text] != nil && [plugin processesTextGoing:inward]
		   && [[plugin textShortcut] length] > 0)
			return plugin;
	return nil;
}

+ (BOOL)anythingProcesses:(BOOL)inward
{
	return [self firstProcessing:inward] != nil;
}

/* The one thing a plugin may not do with its output. Thrown away whole rather
   than cleaned: a plugin that returns a marker is not making a mistake about
   punctuation, and the honest response to it is to ignore the plugin for this
   turn and say so in the log. */
+ (BOOL)wouldAccept:(NSString *)result
{
	return [self isAcceptable:result from:nil];
}

+ (BOOL)isAcceptable:(NSString *)result from:(NekoPlugin *)plugin
{
	if([result length] == 0)
		return NO;
	if([result length] > NekoPluginTextMost) {
		NSLog(@"Neko: %@ returned %lu characters of text; ignored",
			[plugin identifier], (unsigned long)[result length]);
		return NO;
	}
	/* Anywhere in the text, not only at the front. The app's own routing only
	   looks at the first word, so a marker in the middle of a sentence would not
	   become a deed — but a plugin writing one is a plugin reaching for something
	   it was not given, and the useful response is to ignore the whole
	   transformation rather than to reason about where it put it. */
	NSString *shouted = [NekoWithoutMarkdown(result) uppercaseString];
	NSArray *markers = [NSArray arrayWithObjects:@"ACTION:", @"IMAGE:", @"LOOK:", nil];
	NSEnumerator *e = [markers objectEnumerator];
	NSString *marker;
	while((marker = [e nextObject]) != nil)
		if([shouted rangeOfString:marker].location != NSNotFound) {
			NSLog(@"Neko: %@ returned a marker; the whole transformation is ignored",
				[plugin identifier]);
			return NO;
		}
	return YES;
}

+ (void)pass:(NSString *)text
      inward:(BOOL)inward
  completion:(void (^)(NSString *result, NSString *pluginName))done
{
	NekoPlugin *plugin = [self firstProcessing:inward];
	if(plugin == nil || [text length] == 0) {
		done(text, nil);
		return;
	}

	NekoShortcutProvider *runner = [[NekoShortcutProvider alloc]
									initWithShortcutName:[plugin textShortcut]];
	if(![runner shortcutExists]) {
		NSLog(@"Neko: %@ names the Shortcut “%@”, which is not there",
			[plugin identifier], [plugin textShortcut]);
		done(text, nil);
		return;
	}

	/* Retained for the length of the call: the provider owns a timer and a
	   clipboard it has to put back. */
	NSString *original = [text copy];
	NSString *named = [[plugin name] copy];
	__block BOOL answered = NO;

	/* No instructions: a text plugin is handed the words and nothing about the
	   conversation they came from. */
	[runner askQuestion:original instructions:@""
	        completion:^(NSString *result, NSError *error) {
		if(answered)
			return;
		answered = YES;
		NSString *clean = [result stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		BOOL good = (error == nil) && [self isAcceptable:clean from:plugin];
		done(good ? clean : original, good ? named : nil);
	}];

	/* The provider has its own deadline, and this is the one that guarantees the
	   conversation moves on even if it never calls back at all. */
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
			(int64_t)((NekoPluginTextPatience + 1.0) * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{
		if(answered)
			return;
		answered = YES;
		[runner cancel];
		NSLog(@"Neko: %@ took too long; the text is unchanged", [plugin identifier]);
		done(original, nil);
	});
}

@end
