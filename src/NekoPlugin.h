/* NekoPlugin */

#import <Cocoa/Cocoa.h>

/* The interface version this build understands. A plugin declaring a higher one
   is refused rather than half-read: a manifest key nobody has implemented yet is
   a promise the app cannot keep. */
extern const NSInteger NekoPluginInterface;

/* One plugin folder, read but never run.

   A plugin is a folder with a manifest and some files. The manifest is the whole
   of the contract: what it says it extends is what it may be asked, and nothing
   else about it is consulted. A plugin that did not declare Feeds cannot add a
   feed however many feed addresses its files contain.

   Nothing here loads code. The app is sandboxed and holds a microphone, a
   location, folders somebody handed over by name and a diary about their working
   life; code inside this process would inherit all of it, and the entitlement
   that makes such loading possible is the one that would make the sandbox
   decorative. So a plugin is data, or — later, and only if something needs it —
   a separate process. See docs/plugins.md. */
@interface NekoPlugin : NSObject
{
	NSURL *folder;
	NSDictionary *manifest;
	NSString *refusal;           /* why it may not be used, or nil */
	NSDictionary *strings;       /* its own translations, loaded once */
}

/* Reads the manifest and checks it. Never nil: a plugin that cannot be used is
   still shown in the list, with the sentence that says why. */
- (id)initWithFolder:(NSURL *)aFolder;

- (NSURL *)folder;
- (NSString *)identifier;
- (NSString *)name;
- (NSString *)version;
- (NSString *)author;
- (NSString *)summary;

/* nil when it is usable; otherwise one sentence, for the panel. */
- (NSString *)refusal;
- (BOOL)isUsable;

/* What it declared, already checked against what it wants. */
- (NSArray *)feeds;              /* NSDictionary each: Identifier, Name, Detail, Address */
- (BOOL)wantsNetwork;
- (BOOL)wantsToOpenThings;
- (BOOL)wantsShortcuts;

/* "players": the right to send one of a closed list of commands to Music or to
   Spotify. Not the right to script them — the scripts are the app's. */
- (BOOL)wantsToControlPlayers;

/* The schemes a verb may open, and the only ones. */
+ (NSArray *)openableSchemes;

/* Verbs: phrases the plugin wants to hear, and what to do about them.

   Each is a dictionary with Identifier, Phrases, Confirm, and exactly one of Url
   or Shortcut. The app matches the phrases itself, reads the deed back, and waits
   for a yes — a verb that declares no confirmation is refused, because every deed
   in this app is read back before it happens. */
- (NSArray *)verbs;

/* Phrases it would like to be told about, each with one https address to fetch
   and the name of whoever wrote what comes back. */
- (NSArray *)routes;

/* Character folders the plugin ships, as absolute paths. A character is images
   and a manifest, so this needs nothing but disk. */
- (NSArray *)characterPaths;

/* One of the plugin's own strings, in the language the app is running in.

   Looked up in the plugin's own `<lang>.lproj/plugin.strings` first, then in the
   app's tables — which is how the feeds that ship with the app keep their
   translations — and otherwise handed back as it came. A plugin that ships
   English only will say English things; that is its author's business, and the
   app's four languages are not a reason to refuse it. */
- (NSString *)localized:(NSString *)key;

/* Text processing, done by running one of the user's own Shortcuts — never a
   program of the plugin's own. nil when it does not process text. */
- (NSDictionary *)text;
- (NSString *)textShortcut;

/* Every Shortcut of yours this plugin needs, verbs and text together, in the
   order they were declared. Which of them exist is not asked here: a manifest is
   read, and Shortcuts are somebody's own business. */
- (NSArray<NSString*> *)shortcutsItNeeds;
- (BOOL)processesTextGoing:(BOOL)inward;   /* YES for what you said, NO for the answer */

/* "2 feeds", "nothing yet" — the line under its name in the panel. */
- (NSString *)describeWhatItAdds;

@end
