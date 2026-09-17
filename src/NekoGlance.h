/* NekoGlance */

#import <Cocoa/Cocoa.h>

extern NSNotificationName const NekoGlanceDidChangeNotification;

/*! Reading the screen, granted for a stretch of time rather than for ever.

   Taken from the Convai desktop pet by way of docs/others-2.md, designed in
   docs/one-look.md, and argued with in docs/one-look-roadmap.md — which is worth
   reading first, because the analysis contradicted the design twice and the
   experiment contradicted itself once.

   **What it replaces.** `NekoReadTextKey` was a switch: on until somebody
   remembered it. Everything else in this application asks per use — a folder is
   chosen in a panel, a deed is read back and waits, a verb re-checks its plugin
   at the moment of doing — and the screen, the most sensitive thing it can touch,
   was the one place with a standing grant. That is not a hole; it is a switch
   somebody set on purpose. But a permission you have to remember to revoke is one
   careful people decline permanently, which left the feature off for exactly the
   people this is built for.

   So: *"guarda per dieci minuti"*, or the menu, and it looks for that long and
   then stops on its own and says so. The time left is in the menu, one click
   ends it, and it never survives a quit — the same three properties `NekoTimer`
   has, for the same reasons.

   **What it does not change.** A password field is still refused, secure keyboard
   entry still silences it entirely, only a few hundred characters are taken, and
   what is read never leaves this Mac: everything that reads the desktop summary
   asks NekoBrains for an engine that stays here, and tests/screen.m fails if a
   new reader ever forgets.

   **And what the experiment said it is worth**, since a header should not oversell
   what it guards: with ten staged desktops asked twice, the remarks used what was
   read one or two times in ten. Those one or two were the only remarks in the run
   that knowing the minutes could not have produced. */
@interface NekoGlance : NSObject
{
	NSTimer *ticking;
	NSDate *until;
}

+ (NekoGlance *)sharedGlance;

/* How long the question asks it to look for, or 0 when it is not asking. */
+ (NSTimeInterval)wantedFor:(NSString *)question;

/* Starts it, replacing any stretch already running, and answers what to say. */
- (NSString *)lookFor:(NSTimeInterval)seconds;

/* The whole of what the rest of the application asks: may it read right now. */
- (BOOL)isLooking;
- (NSTimeInterval)secondsLeft;

/* For the menu: "Sto guardando — 4 minuti" while it runs, nil when it does not. */
- (NSString *)menuTitle;
- (void)stop;

/* What the menu item starts when nobody said how long. */
+ (NSTimeInterval)defaultStretch;

@end
