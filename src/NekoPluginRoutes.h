/* NekoPluginRoutes */

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/*! The half of the plugin interface that answers.

   A plugin can *be* things — feeds, characters, translations, a text filter — and
   since 2.6 it can *do* things, through a verb. It could not **answer**. A route
   is that: a list of phrases, one https address, and the name of whoever wrote
   what comes back.

   It is the mechanism `NekoWeb wantedFor:` already is, generalised — and it is
   deliberately the narrowest generalisation that is still useful:

   - **The plugin does not write a rule.** No pattern, no regular expression, no
     guess handed to a model. It lists words, and the application matches them the
     way it matches a verb: whole words, longest phrase first.
   - **One address, and it is https.** The plugin cannot name it at fetch time and
     nothing that comes back can change where the next one goes — which is the
     rule that keeps a headline from sending the cat somewhere.
   - **The request carries nothing**: the same ephemeral session as the feeds, one
     GET, eight seconds, no cookies, no question, no account.
   - **What comes back is somebody else's words.** It is quoted to a model under
     the name the route declared, and an answer built on it may not perform
     anything — the rule `tests/screen.m` fails on if it is ever broken, and
     `tests/route.m` stages a reply with `ACTION: open-app Terminal` inside it.

   A route decides what a question is *about*, which is the judgement this
   application has always kept for itself. This is why it is a list of phrases and
   not an intent: the plugin says which words it would like to hear, and the
   application still decides. */
@interface NekoPluginRoutes : NSObject

/*! Is any enabled plugin listening for anything at all. */
+ (BOOL)anythingListens;

/*! The route whose phrase is in the question, with what followed it, or nil. */
+ (NSDictionary *_Nullable)matchFor:(NSString *)question;

/*! Fetches what the route asks for and hands back lines of somebody else's text.
   Empty on any failure — a route that cannot be reached is a question answered
   without it, not a question refused. */
+ (void)fetch:(NSDictionary<NSString*,NSString*> *)route
   completion:(void (^)(NSArray<NSString*> * _Nullable lines, NSError * _Nullable error))done NS_SWIFT_ASYNC(2);

@end

NS_ASSUME_NONNULL_END
