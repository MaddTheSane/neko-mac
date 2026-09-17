/* NekoPlugins */

#import <Cocoa/Cocoa.h>

@class NekoPlugin;

/* Which ones are switched on. An identifier not in this list is never read,
   never asked and never run: disabling is not a flag a plugin can see, it is the
   app not consulting it. */
extern NSString * const NekoPluginsEnabledKey;

/* Where the folders are, when a harness needs them somewhere else. A test binary
   run out of the bundle does not resolve to the sandboxed container. */
extern NSString * const NekoPluginsDirectoryKey;

/* Posted when one is added, removed, enabled or disabled. */
extern NSNotificationName const NekoPluginsDidChangeNotification;

/* The folder of plugins, and what may be done with them.

   They live inside the app's container, because the app is sandboxed and that is
   where it can actually read. That has a consequence worth saying out loud: a
   plugin cannot be installed by dragging it into a folder in the Finder the way a
   character can. So installing is a panel — the same NSOpenPanel handover the
   folder access already uses — and this class is what does the copying. */
@interface NekoPlugins : NSObject
{
	NSMutableArray *plugins;
}

+ (NekoPlugins *)sharedPlugins;

- (NSURL *)directory;

/* The examples inside the bundle, if any shipped: read-only, never seeded, and
   there so that Add… has somewhere to point. */
- (NSURL *)examplesDirectory;
- (NSArray<NekoPlugin*> *)examples;

/* Everything installed, refused ones included: a plugin that cannot be used is
   still shown, with the sentence saying why. */
- (NSArray<NekoPlugin*> *)all;
- (NSArray<NekoPlugin*> *)enabled;            /* usable and switched on */
- (NekoPlugin *)pluginWithIdentifier:(NSString *)identifier;

- (void)reload;

- (BOOL)isEnabled:(NekoPlugin *)plugin;
- (void)setEnabled:(BOOL)enabled for:(NekoPlugin *)plugin;

/* Copies a folder in and leaves it switched off: arriving is not the same as
   being on. Returns nil on success, or the sentence that says what was wrong. */
- (NSString *)installFrom:(NSURL *)chosen;

/* The folder, its switch, and anything it was remembered by. */
- (void)remove:(NekoPlugin *)plugin;

/* Every feed every enabled plugin adds, as NekoWeb wants them. */
- (NSArray *)feeds;

/* Copies the plugins that ship inside the app into the container, and switches
   them on the first time each one arrives.

   That last part is the one exception to "arriving is not the same as being on",
   and it is deliberate: a plugin that ships with the app is not a folder somebody
   downloaded, and the news feeds it carries are the ones the app has always had.
   Arriving switched off would mean the news simply stopped working on the day
   they moved out of the code.

   Switched on once, and never again. Somebody who turns one off finds it still
   off after the next launch, and after the next update — that is the whole point
   of the switch. */
- (void)seedFromBundle;

/* Ships with the app: it can be switched off, and it cannot be removed, because
   removing it would only mean it came back at the next launch. */
- (BOOL)isBundled:(NekoPlugin *)plugin;

@end
