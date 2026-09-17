/* NekoShortcutProvider */

#import <Cocoa/Cocoa.h>
#import "NekoAnswerProvider.h"

/*! Hands the question to a Shortcut the user owns and reads back what it put on
   the clipboard.

   The Shortcut is where the intelligence lives, and it is the user's choice:
   Apple Intelligence's "Use Model" action, which can escalate to ChatGPT, a
   ChatGPT action, or anything else that ends in text. Nothing here talks to a
   model, holds a key, or opens a socket.

   The clipboard is the return channel because it is the only one that costs no
   permission: a file would mean a folder the user has to grant. Whatever was on
   the clipboard before is put back afterwards. */
@interface NekoShortcutProvider : NSObject <NekoAnswerProvider>
{
	NSString *shortcutName;
	NSTimer *poll;
	NSInteger baseline;          /*!< clipboard change count before running */
	NSArray<NSPasteboardItem*> *saved;             /*!< what was on the clipboard, to put back */
	NSDate *deadline;
	void (^pending)(NSString *, NSError *);
}

- (id)initWithShortcutName:(NSString *)name;
@property (readonly, copy) NSString *shortcutName;

/*! Every Shortcut the user has, by name, or nil when they cannot be listed.
   Asked of /usr/bin/shortcuts, which works inside the sandbox. */
+ (NSArray<NSString*> *)availableShortcutNames;

/*! Whether the named one is among them. YES when the list is unavailable, so a
   working setup is never blocked by a failed check. */
- (BOOL)shortcutExists;

/*! The URL that runs the Shortcut with the question as its input. */
- (NSURL *)urlForQuestion:(NSString *)question;

/*! Hands that URL to the system. Separated out so a test can stand in for
   Shortcuts without a Shortcut being installed. */
- (BOOL)launchShortcutWithURL:(NSURL *)url;

@end
