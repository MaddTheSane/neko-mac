/* NekoAdvisor */

#import <Cocoa/Cocoa.h>

/*! NSUserDefaults key: the last thing the cat suggested, so a relaunch does not
   repeat it word for word. */
extern NSString * const NekoSuggestLastKey;

/*! The cat looking over your shoulder.

   It runs only in the roaming behaviour — a cat that chases the cursor has its
   attention elsewhere, and one living on the Dock is already busy — and only
   when the switch in the preferences is on.

   What it knows is deliberately shallow and needs no permission at all: which
   application is in front, how long you have been in it, how often you have been
   switching, whether you are at the keyboard, and the time of day. Window titles
   are read only if this Mac has already granted screen recording to Neko for
   some other reason; the permission is never asked for. Nothing is read from
   inside your documents, and nothing is stored beyond the last line it said. */
@interface NekoAdvisor : NSObject
{
	NSTimer *heartbeat;
	NSDate *lastSpoke;
	NSString *lastSubject;       /*!< the app the last suggestion was about */
	BOOL waiting;                /*!< a suggestion is being written */
}

+ (NekoAdvisor *)sharedAdvisor;
@property (class, readonly, retain) NekoAdvisor *sharedAdvisor;

/*! `YES` while an engine is writing a suggestion. The cat stands still for it:
   wandering off mid-thought and then speaking from the far side of the desk
   reads as two unrelated events. */
@property (readonly, getter=isThinking) BOOL thinking;

/*! Reads the settings and starts or stops accordingly. Safe to call often. */
- (void)applySettings;

/*! Everything that would be sent, as plain text, for the preferences to show
   before anyone switches this on. */
- (NSString *)context;

/*! Asks now, whatever the timers think, and reports what came back. The
   preferences use it so the feature can be tried once rather than waited for. */
- (void)suggestNow:(void (^)(NSString *line, NSError *error))report;

@end
