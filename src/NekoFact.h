/* NekoFact */

#import <Cocoa/Cocoa.h>

/*! Things about you that the cat was told, and keeps.

   The diary already grows durable lines, but it grows them the slow way: a
   reflection over yesterday, once a day, written by whatever engine is best on
   this Mac. Checked in `NekoMemory reflectIfDue`, that means two things nobody
   would guess from the outside — a fact said this morning is invisible until
   tomorrow, and on a Mac with no local engine and no Apple Intelligence it is
   invisible **for ever**, because the reflection returns early when there is
   nothing to think with.

   So this is the fast half, and it is the half the rest of this application is
   built on: **the words are recognised in code, and no model is asked.**

   Three things, all of them said in so many words rather than guessed at:

   - *"Ricordati che il venerdì stacco prima"* — told to keep something.
   - *"Mi chiamo Nicolò"* — the one fact that changes how everything else reads.
   - *"Dimentica quello che ti ho detto sul venerdì"* — told to let it go.

   What it deliberately does **not** do is infer. A pet that decides for itself
   what about you is worth writing down is a different and worse thing than one
   that writes down what you told it to, and the difference is visible from the
   outside: everything in here can be traced to a sentence somebody said on
   purpose. "Sono stanco" is not a fact about somebody, and neither is anything
   else this does not recognise.

   Kept as plain text beside the diary, one line each with the day it was said,
   in the same folder the preferences will open in the Finder — because a file
   about a person that they cannot read is not honest, whatever it contains. */
@interface NekoFact : NSObject

/*! What the sentence asks for, or nil when it asks for none of this.
   The dictionary carries What ("il venerdì stacco prima"), Kind ("keep",
   "forget", "name"), and Sentence, which is what the cat says back. */
+ (NSDictionary *)wantedFor:(NSString *)question;

/*! Does it, and answers with the sentence to say. */
+ (NSString *)act:(NSDictionary *)wanted;

/*! Everything it has been told, oldest first, without the dates. */
+ (NSArray<NSString*> *)all;

/*! For the preferences, and for the tests. */
+ (void)forgetEverything;

@end
