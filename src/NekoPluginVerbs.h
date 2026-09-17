/* NekoPluginVerbs */

#import <Cocoa/Cocoa.h>

@class NekoPlugin;

/*! Phrases a plugin asked to hear, matched by the app and never by a model.

   The reasoning is the one the news feeds measured the hard way: asked to read a
   feed, a 4B model invented a headline about Milan, and a 1.5B repeated the
   question back. So intent is recognised here, in code, before any engine is
   consulted — the same place "che notizie ci sono" is recognised.

   What a verb may do is two things, both of which the app could already do and
   neither of which needs a new permission: open an address from a closed list of
   schemes, or run one of the user's own Shortcuts. And it happens only after the
   deed has been read back and somebody has said yes. */
@interface NekoPluginVerbs : NSObject

/*! `NO` when nothing enabled declares a verb, which costs nothing to ask. */
+ (BOOL)anythingListens;

/*! Whether any of that is a command for Music or Spotify — which is what decides
   whether the Permissions tab has anything to ask macOS for. */
+ (BOOL)anythingCommandsAPlayer;

/*! The best match for what somebody said, or nil. Longest phrase wins, so
   "alza il volume" beats "alza". The dictionary returned carries the verb's own
   keys plus:

       Plugin      the plugin's identifier, for the read-back
       Argument    what followed the phrase, trimmed — may be empty
       Sentence    the Confirm line with the argument in it, ready to show */
+ (NSDictionary *)matchFor:(NSString *)question;

/*! Opens the address or runs the Shortcut. Returns NO — and changes nothing — when
   the plugin is gone, when its switch went off between the question and the yes,
   or when the address turns out not to be one Neko will open. */
+ (BOOL)perform:(NSDictionary *)verb;

/*! The same, with the sentence to say when it could not. "That did not work" is
   true and useless: the one thing that goes wrong here is a Shortcut somebody has
   not made yet, and the app knows its name. */
+ (BOOL)perform:(NSDictionary *)verb saying:(NSString **)problem;

@end
