/* NekoUnseen */

#import <Cocoa/Cocoa.h>

/*! "Quanto vale Apple in borsa adesso?"

   Stage 6 of docs/personality-roadmap.md, and it was not planned: stage 3 found
   it while measuring something else. Asked twenty things it has no way to know,
   the **shipped** prompt refused 34 of 80 and answered the rest — and the answers
   are these:

       quanto vale Apple in borsa adesso?  →  "Attualmente, il 2 settembre 2026,
                                               Apple vale 278,43 dollari per
                                               azione."
       chi mi ha scritto stamattina?       →  "Oggi, il 2 settembre 2026, nessuno
                                               mi ha scritto."
       il mio codice compila?              →  "No, il codice non si esegue."
       quanti messaggi non letti ho?       →  "Non vedo messaggi non letti nel
                                               programma Google Chat."

   An invented share price with today's date on it, and three assertions about
   somebody's mail, code and messages that nothing in front of the model could
   support. The facts block **already** tells it to decline what is not on the
   list; it cannot tell *not on the list* from *not in the world*.

   **Three prompts have now failed at this**, all recorded in that roadmap: a
   sentence forbidding it to go along with a false premise denied 15 of 20 *true*
   premises; a character that would "rather say you do not know" declined to name
   the capital of Australia; and naming the domain instead of the verb kept the
   error and lost half the gain. A sentence can make a small model agree or
   disagree. It cannot give it a way to tell the difference.

   So this is the mechanism, in the shape that has worked five times here —
   `NekoWeb`, `NekoTimer`, `NekoClock`, `NekoSums`, `NekoAppointment`,
   `NekoRecord`: a closed list of phrases, matched before any engine, answered in
   one honest sentence with nothing to invent with.

   **It is a floor, not a gate**, and that is why it runs last. Everything above
   it in the chain may legitimately know the answer: the news when feeds are on, a
   plugin's route for a share price, `NekoRecord` for what somebody wrote in their
   own diary, and a folder somebody handed over in a panel — which is why the
   question about files stands aside the moment `NekoFolderAccess` has been
   granted anything. This never claims blindness where the application can see.

   And it says **what** it cannot see rather than that the thing is unknowable.
   *"Non posso vedere la tua posta"* is true and checkable; *"non lo so"* is what
   the model says about the capital of Australia. That distinction is the whole
   defect, and in code it is free. */
@interface NekoUnseen : NSObject

/*! The honest sentence, or nil when the question is not one of these. */
+ (NSString *)wantedFor:(NSString *)question;

@end
