/* NekoUpdate */

#import <Cocoa/Cocoa.h>

extern NSString * const NekoUpdateCheckKey;          /* the switch, on by default */
extern NSNotificationName const NekoUpdateDidChangeNotification;

/* Telling you a new version exists, and then getting out of the way.

   This application goes out as an **unsigned** disk image, which decides the
   shape of everything here. A signed application can replace its own bundle and
   relaunch; an unsigned one that tried would hand you a copy Gatekeeper refuses
   to open, having already thrown away the copy that worked. So this does not
   install anything, ever:

       1. it asks GitHub, once a day, what the newest release is;
       2. if that is newer than this, it says so — in the cat's menu, and once
          out loud;
       3. it asks whether to download, with the size, before fetching anything;
       4. it downloads with a progress bar, and can be cancelled;
       5. it asks again before doing anything with the file;
       6. and then it opens the disk image and quits, so that the copy you are
          about to drag across is not the copy that is running.

   **The installation is yours.** Drag Neko into Applications, the way you did
   the first time. That is one step more than a self-updater and it is the step
   that makes the other five safe.

   What the check reveals, stated plainly rather than buried: one HTTPS request
   to api.github.com, carrying no diary, no question, and nothing about you
   except what any web request carries — your address, and the fact that
   something asked. It sends no identifier of its own. The switch is in the Pet
   tab and turns the whole thing off; it is on by default because an unsigned
   application that cannot tell you it is out of date is worse than one that
   asks a public API for a version number.

   And what it does **not** promise: this checks a version number, not a
   signature. The assurances are TLS and the address it asks, and after that it
   is a disk image you look at yourself before dragging anything. Nothing here
   verifies the download, because nothing here could — an unsigned build has
   nothing to verify against. */
@interface NekoUpdate : NSObject
{
	NSURLSession *session;
	NSURLSessionDownloadTask *task;
	NSString *version;             /* the newer one, or nil */
	NSString *notes;               /* the release page */
	NSURL *download;
	long long bytes;
	double fraction;
	BOOL checking;

	NSPanel *progressPanel;
	NSProgressIndicator *bar;
	NSTextField *progressLabel;
}

+ (NekoUpdate *)sharedUpdate;

/* Asked once a day at most, and silent when there is nothing to say. */
- (void)checkQuietly;

/* Asked because somebody pressed the button, which says something either way. */
- (void)checkAloud;

- (BOOL)isChecking;
- (BOOL)isDownloading;
- (double)fraction;

/* The newer version's number, or nil when there is none. */
- (NSString *)availableVersion;

/* What the cat's menu says while one is waiting, or nil. */
- (NSString *)menuTitle;

/* The two questions, the download, and the hand-over. */
- (void)offerIt:(id)sender;

/* Whether one version string is newer than another, by the numbers between the
   dots: 2.13 is newer than 2.9 and than 2.12.1, and "v2.13" is 2.13. */
+ (BOOL)version:(NSString *)candidate isNewerThan:(NSString *)current;

/* This build, from Info.plist. */
+ (NSString *)runningVersion;

/* What a GitHub release answer amounts to: Version, Bytes, Download and Notes,
   or nil when it is not a release, has no disk image in it, or is not newer than
   this build. Separate from the request so that it can be measured against a
   staged answer instead of against the network. */
+ (NSDictionary *)releaseFrom:(NSData *)json;

@end
