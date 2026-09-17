/* NekoBrains */

#import <Cocoa/Cocoa.h>
#import "NekoAnswerProvider.h"

/*! Which engine says the things nobody asked for.

   Two separate questions live here, and they used to be answered by one setting.

   A question asked out loud can go anywhere the user likes, remote engines
   included: they asked it, they know where it went. But everything the cat says
   on its own — a remark about the day, a curious question, and in time a diary
   and the reflections drawn from it — is different on both counts. It is not
   solicited, so it has to be good enough to be worth an interruption; and it is
   about the person rather than from them, so it stays on the Mac. A promise that
   the diary never leaves this machine cannot survive an exception, so the rule
   lives in code: this class will not return a remote provider, whatever the
   preferences say.

   "Good enough" is measured rather than assumed. Apple's on-device model carries
   the instructions this design needs; a 1.5B GGUF demonstrably does not — given
   the same three blocks it answered every question, including the time of day,
   with a request to draw a picture. So a local model qualifies at roughly two
   gigabytes and up, and below that the cat keeps its written-in lines and says
   less, which the Suggestions tab states rather than leaving to be discovered. */
@interface NekoBrains : NSObject

/*! The best engine on this Mac for unprompted speech, or nil when none is good
   enough. Never a remote one. */
+ (id<NekoAnswerProvider>)bestOnDeviceProvider;

/*! Whether anything at all qualifies. */
+ (BOOL)hasSomethingWorthHearing;

/*! Whether a given provider keeps what it is told on this Mac. The memory is
   offered to a question only when the answer is yes: a diary that goes to a
   remote service on the days somebody picked ChatGPT is not a diary that stays
   on the Mac. */
+ (BOOL)staysOnThisMac:(id<NekoAnswerProvider>)provider;

/*! What to show in the preferences: the name of the engine that will speak, or
   why nothing will. */
+ (NSString *)describeChoice;

/*! A local model at or above this many bytes is considered able to hold a long
   instruction. */
+ (long long)capableModelBytes;

/*! The most capable model actually on the disk, or nil when the largest one there
   is still too small. Not necessarily the one chosen for questions: someone may
   ask questions of a small fast model and still have a capable one downloaded. */
+ (id)biggestInstalledModel;

@end
