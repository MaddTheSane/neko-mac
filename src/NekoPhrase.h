/* NekoPhrase */

#import <Cocoa/Cocoa.h>

/*! Hearing a phrase inside a sentence.

   Shared by the two things a plugin can ask to be told about — a verb, which does
   something, and a route, which fetches something — because they hear the same
   way and it was measured once: whole words only, so "metti" is in "metti Taylor
   Swift" and not in "mettiamo che sia lunedì"; the argument is whatever follows,
   cut from what was actually said rather than from the lowercased copy the
   matching runs on, so a search gets "Taylor Swift" and not "taylor swift". */
@interface NekoPhrase : NSObject

+ (BOOL)phrase:(NSString *)phrase
            in:(NSString *)lowered
          said:(NSString *)original
      argument:(NSString **)argument;

@end
