/* NekoTimer */

#import <Cocoa/Cocoa.h>

extern NSNotificationName const NekoTimerDidChangeNotification;

/*! "Metti un timer di dieci minuti."

   The one utility on the list in docs/utilities.md where this application is
   genuinely better than the system it runs on: a bubble that follows you across
   Spaces, delivered by something that walks over and sits down to say it. There is
   no public way to set the Clock's timer, and there does not need to be one.

   **Recognised in code, never by a model.** The duration comes from `NekoWhen`,
   which is a table; the question is looked at before any engine is consulted, on
   the same rails as the news and the verbs. A model asked to set a timer sets it
   for a plausible-sounding number.

   **It says what it understood, and it does not ask.** Every deed in this
   application is read back and waits for a yes, and this one deliberately is not:
   a timer touches nothing, outlives nothing, and a yes-or-no in front of it is
   friction in the one place somebody is in a hurry. What it does instead is answer
   with the time it will land — *"Dieci minuti: te lo dico alle 17:29"* — which is
   the same information a confirmation would carry, arriving sooner. If that is
   wrong, the menu cancels it in one click.

   **One at a time.** Two would need a list, and a list needs a window.

   **It does not survive being quit**, and says so if asked to: a desktop pet that
   is not running cannot remind anybody of anything, and a notification that
   outlives the application would be a different promise than the one on the tin. */
@interface NekoTimer : NSObject
{
	NSTimer *ticking;
	NSDate *landsAt;
	NSTimeInterval asked;
	NSUInteger putOff;             /*!< how often the moment has been a bad one */
}

+ (NekoTimer *)sharedTimer;
@property (readonly, class, retain) NekoTimer *sharedTimer;

/*! How long the question asks for, or 0 when it is not asking for a timer. A
   duration on its own is not enough: "ho dormito otto ore" is not a request. */
+ (NSTimeInterval)wantedFor:(NSString *)question;

/*! Starts it, replacing whatever was running, and answers the sentence to say. */
- (NSString *)startFor:(NSTimeInterval)seconds;

- (BOOL)isRunning;
- (NSTimeInterval)secondsLeft;
@property (readonly, getter=isRunning) BOOL running;
@property (readonly, nonatomic) NSTimeInterval secondsLeft;

/* For the menu: "Timer — 4 minuti" while one runs, nil when none does. */
- (NSString *)menuTitle;
@property (readonly, copy) NSString *menuTitle;
- (void)cancel;

@end
