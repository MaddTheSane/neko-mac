/* NekoPlace */

#import <Cocoa/Cocoa.h>
@class CLLocationManager;

/* What is remembered between launches: a town and a region, never coordinates. */
extern NSString * const NekoPlaceTownKey;
extern NSString * const NekoPlaceRegionKey;
extern NSString * const NekoPlaceAskedKey;   /* the day it last looked */

/*! Posted when the town, the region or the permission changes. macOS answers a
   location request when somebody answers a dialog, which is long after the
   button was pressed, so whatever is on screen has to be told rather than
   guessing. */
extern NSString * const NekoPlaceDidChangeNotification;

/*! Roughly where this Mac is, and nothing finer than that.

   Two tiers, and the first needs no permission at all: the time zone says which
   country somebody is in, which is enough to know that "the news" means an
   Italian wire rather than a British one.

   The second tier is the town, and it is worth a permission because it is what
   makes "che tempo fa" answerable without naming a city and "che notizie ci
   sono qui" mean anything. It is asked for only when somebody presses the button
   for it, one fix at a time, at the accuracy macOS calls reduced — a few
   kilometres, which is a town and not a street.

   What is kept is the *name* of the town and of the region, in the defaults, as
   text. The coordinates are used to look those two up and then dropped: there is
   nowhere in this app where a latitude would be useful, and a file with somebody's
   latitude in it is a different kind of file. Nothing is sent anywhere — the
   lookup is Apple's, on the system; the weather asks open-meteo for a town by
   name, which is what a person would have typed. */
@interface NekoPlace : NSObject
{
	CLLocationManager *manager;  /* CLLocationManager, kept for its lifetime */
	void (^report)(NSString *town, NSString *region);
	BOOL looking;                /* a request is in flight */
	BOOL waitingForPermission;   /* the dialog is up, or ought to be */
}

+ (NekoPlace *)sharedPlace;

/* NO on a Mac without CoreLocation, or with location services switched off for
   everything. */
+ (BOOL)isAvailable;

/* 0 undetermined, 1 denied, 2 restricted, 3 authorised. Reading it prompts
   nobody. */
+ (NSInteger)authorizationStatus;

/* The town and the region as they were last looked up, or nil. Free: no
   permission, no network, no waiting. */
- (NSString *)town;
- (NSString *)region;

/* The country from the time zone: "IT" for Europe/Rome. Costs nothing and needs
   nobody's permission, which is why it is the fallback for everything. */
- (NSString *)country;

/* Asks macOS for one position, turns it into a town and a region, keeps those
   two words and forgets the rest. Calls back on the main thread, with nils when
   it could not or may not. Does nothing more than once a day. */
- (void)findOut:(void (^)(NSString *town, NSString *region))done;

/* The same, ignoring the once-a-day rule. What a button does: somebody asking is
   not the app pestering the system. */
- (void)lookAgain:(void (^)(NSString *town, NSString *region))done;

/* Whether it is worth calling: something to gain and permission to try. */
- (BOOL)mayLook;

/* Forgets the town and the region. */
- (void)forget;

/* Two seams, so that the order these things happen in can be tested without a
   dialog appearing on somebody's screen — asking for permission for real is not
   something a test may do, since a refusal can only be undone in System
   Settings. The tests override these; nothing else does. */
- (NSInteger)permission;     /* defaults to +authorizationStatus */
- (CLLocationManager *)manager;/* the CLLocationManager, kept for its lifetime */

@end
