/* NekoWeb */

#import <Cocoa/Cocoa.h>

/*! BOOL: may the cat look something up. Off until asked for. */
extern NSString * const NekoWebEnabledKey;

/*! What a model may ask for, and the only thing it may ask for. */
@interface NekoWebSource : NSObject
{
	NSString *identifier;        /* "ansa" — the word a model is allowed to say */
	NSString *name;              /* "ANSA" */
	NSString *detail;            /* "ultima ora, in italiano" */
	NSString *address;
	BOOL prominent;              /* named in the instructions, not only known */
}
- (id)initWithIdentifier:(NSString *)anIdentifier
                    name:(NSString *)aName
                  detail:(NSString *)aDetail
                 address:(NSString *)anAddress
               prominent:(BOOL)isProminent;
- (NSString *)identifier;
- (NSString *)name;
- (NSString *)detail;
- (NSURL *)url;
- (BOOL)isProminent;
@end

/*! Headlines, from a list somebody else cannot add to.

   The dangerous version of this feature is the obvious one: let the model name a
   web address and fetch it. Then a sentence on a page — or in a headline, or in
   a document somebody sent — can send the cat anywhere, and text nobody in this
   room wrote decides what gets downloaded. So the model does not name addresses.
   It names one of the entries below, by a word from a fixed list, and anything
   else is refused before a connection is opened.

   What comes back is treated the same way as text read from the screen: quoted
   data, never instructions, and an answer built on it may not perform anything.
   That last rule lives in NekoAsk and has a test of its own.

   The request carries nothing: no question, no account, no cookies, no history —
   an ephemeral session, one GET, eight seconds. What ANSA can see is that
   somebody fetched a public feed. */
@interface NekoWeb : NSObject
{
	NSURLSession *session;
}

+ (NekoWeb *)sharedWeb;
- (BOOL)isEnabled;

/*! The list, which is now whatever the enabled plugins provide — the app's own
   two dozen feeds included, since they ship as a plugin. Closed in the sense that
   matters: a model may name a word from it and can never name an address. */
+ (NSArray<NekoWebSource *> *)sources;
+ (NekoWebSource *)sourceNamed:(NSString *)identifier;

/*! The line of names a model is shown — the handful worth naming, not all of
   them: an instruction that lists two dozen words costs a small model more than
   the choice is worth, and the app recognises the rest by itself. */
+ (NSString *)namesForInstructions;
+ (BOOL)looksLikeALook:(NSString *)line;
+ (NSString *)wantedIn:(NSString *)line;      /* what came after the marker */

/*! What the question itself asks for, before any model is consulted: an entry
   from the list, "weather \<place\>", or nil when it is not that kind of question.

   Measured, and the reason this exists: asked "leggi le ultime notizie su
   ansa.it", a 4B model on this Mac answered "Oggi a Milano è stato annunciato il
   nuovo piano per la mobilità sostenibile" — an invented headline, delivered
   with confidence. A small model cannot be relied on to admit it does not know,
   so the app decides this one and the model never gets the chance. */
+ (NSString *)wantedFor:(NSString *)question;

/*! The feed for wherever this Mac is, or nil when nobody has said where that is.
   ANSA publishes one per Italian region and all twenty were fetched before this
   went in; outside Italy there is nothing local to offer yet, and the cat says
   so rather than guessing. */
+ (NekoWebSource *)localSource;

/*! Up to eight headlines, each a short line of its own. */
- (void)headlinesFrom:(NekoWebSource *)source
           completion:(void (^)(NSArray *headlines, NSError *error))done;

/*! Today and tomorrow, from open-meteo, which needs no key and no account.
   3B Meteo publishes no feed — every address it used to have is a 404 — so the
   cat says where its numbers come from rather than pretending. */
- (void)weatherFor:(NSString *)place
        completion:(void (^)(NSString *summary, NSError *error))done;

/*! The fetching itself, shared with the routes a plugin adds: the same ephemeral
   session, the same eight seconds, the same request that carries nothing. A
   plugin never gets either of these — it declares an address in its manifest and
   the application does the asking. */
- (void)get:(NSURL *)url completion:(void (^)(NSData *body, NSError *error))done;
- (NSArray *)headlinesInFeed:(NSData *)body;

/*! What goes into the second prompt: the lines, marked as somebody else's
   writing. */
+ (NSString *)blockFrom:(NSString *)what lines:(NSArray<NSString*> *)lines;

/*! And what to show when there is no model worth handing it to. */
+ (NSString *)plainList:(NSArray<NSString*> *)lines from:(NekoWebSource *)source;

@end
