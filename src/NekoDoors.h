/* NekoDoors */

#import <Cocoa/Cocoa.h>

/*! The ways in, from the rest of the Mac.

   Until now this application had exactly one door — its own hotkey — which made
   it the only thing on the Mac that could not be reached the way everything else
   is reached. The asymmetry was stark once seen: Neko **runs the user's
   Shortcuts**, and nothing in the operating system could run Neko.

   **App Intents is the answer Apple would give, and it cannot be built here.**
   Checked rather than assumed: the metadata a Shortcuts action is discovered
   through is produced by `appintentsmetadataprocessor`, which ships inside Xcode
   and not in the Command Line Tools, and this project builds with the Command
   Line Tools by design — one shell script, no project file. Swift code declaring
   an intent would compile and nothing would ever find it. That is a toolchain
   fact and it is written down in docs/others.md with what it would take.

   So: the two doors that need no toolchain anybody has to install, and that reach
   most of the same places.

   **A Services entry.** "Ask Neko about this" appears in the Services menu and in
   the right-click menu of selected text in every application on the Mac. It is
   the better door of the two and it costs a plist entry: the selection is
   somebody choosing words on purpose, which is exactly the consent this
   application asks for everywhere else.

   **A URL.** `neko://ask?q=…`, which Shortcuts can open, and so can a script, a
   terminal, or another application. This one is deliberately **not** the same
   thing as asking: it fills the typed line and brings it up, and a person presses
   return. A URL can come from a web page, and a web page is the one place this
   application has never taken instructions from — so the door opens onto the
   line, where somebody is standing, rather than onto the engine. */
@interface NekoDoors : NSObject

/*! Called once at startup; registers the services provider. */
+ (void)open;

/*! "Ask Neko about this", from the Services menu of any application. */
- (void)askAboutSelection:(NSPasteboard *)board
                 userData:(NSString *)data
                    error:(NSString **)problem;

/*! What a neko:// URL asks for, or `nil`. Its own method so a test can measure the
   parsing without opening anything. */
+ (NSString *)questionInURL:(NSURL *)url;

@end
