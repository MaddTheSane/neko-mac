/* NekoAction */

#import <Cocoa/Cocoa.h>

/*! BOOL: may a spoken request turn into something happening. Off until asked. */
extern NSString * const NekoActionsEnabledKey;

/* A line with the asterisks and backticks a small model likes to add taken off. */
extern NSString *NekoWithoutMarkdown(NSString *line);

/*! One thing the cat is allowed to do, parsed out of a model's answer.

   The list of verbs is closed and short, and anything that does not match it
   exactly is refused rather than interpreted. There is no shell here, no
   arbitrary path, no wildcard, nothing that deletes or overwrites: this round
   opens applications, addresses and folders, and runs a Shortcut you wrote
   yourself — which is the escape hatch for everything else, because a Shortcut
   is your own code that you authorised, not something a model invented.

   The second round adds copying and moving a file between your own folders,
   which the sandbox will not allow until you have handed the folder over in a
   panel: `needsFolders` says which ones are still missing so they can be asked
   for. Nothing here overwrites — a name already taken is given a number — and
   nothing here deletes.

   Nothing is ever performed without being shown first. `summary` is what the
   bubble says before the *Yes*, in the language the app is running in. */
@interface NekoAction : NSObject
{
	NSString *verb;
	NSString *target;
	NSString *extra;         /*!< the browser for open-url, otherwise nil */
	NSURL *resolved;         /*!< the application or folder it worked out */
	NSString *other;         /*!< the destination folder, for copy and move */
}

/*! `nil` when the line is not an action, the verb is unknown, or what it names
   cannot be found on this Mac. */
+ (NekoAction *)actionFromLine:(NSString *)line;

/*! Whether a line even claims to be one, so that a refusal can be explained
   rather than silently turning into a sentence. */
+ (BOOL)looksLikeAnAction:(NSString *)line;

@property (readonly, copy) NSString *verb;
@property (readonly, copy) NSString *target;

/*! The folder keys this needs and does not have yet, in order. Empty when it can
   go ahead. */
- (NSArray<NSString*> *)needsFolders;

/* "Apro Photoshop." — what the confirmation asks about. */
- (NSString *)summary;

/* Does it. Returns NO and fills in the error when the system refuses. */
- (BOOL)perform:(NSError **)error;

@end
