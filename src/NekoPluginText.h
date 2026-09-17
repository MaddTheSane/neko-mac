/* NekoPluginText */

#import <Cocoa/Cocoa.h>

/*! Passing text through a plugin, on its way in or on its way out.

   The mechanism is one of the user's own Shortcuts, and that is the whole reason
   this is allowed: the Shortcut is theirs, nothing new runs inside this app, and
   the plugin names a Shortcut rather than a program.

   Four rules, and they are the interesting part:

   1. **It can change words and nothing else.** Whatever comes back is text that
      will be shown or asked. It cannot become a deed: if the returned text
      carries one of the app's markers — ACTION:, IMAGE:, LOOK: — the whole
      transformation is thrown away rather than cleaned up, because a plugin
      reaching for a marker is a plugin doing something it was not given.
   2. **It never blocks the conversation.** A Shortcut that is slow, missing or
      broken means the original text, unchanged, after the timeout.
   3. **It sees the words and nothing around them.** Not the diary, not the
      instructions, not what the cat noticed, not where you are.
   4. **What you said is what is remembered.** The diary records the words that
      were spoken; the transformed version is what the engine is asked. */
@interface NekoPluginText : NSObject

/*! `NO` when nothing is enabled that processes text in this direction, which is the
   usual case and costs nothing. */
+ (BOOL)anythingProcesses:(BOOL)inward;

/* Hands the text to the first enabled plugin that processes this direction, and
   calls back on the main thread with what came back — or with the text exactly as
   it was given, which is what happens on a timeout, a refusal, an empty answer or
   a marker. */
/* Whether a transformation would be used at all: empty, too long, or carrying
   one of the app's markers means the original text stands. Public because it is
   the invariant worth testing directly. */
+ (BOOL)wouldAccept:(NSString *)result;

+ (void)pass:(NSString *)text
      inward:(BOOL)inward
  completion:(void (^)(NSString *result, NSString *pluginName))done;

@end
