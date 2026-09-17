/* NekoModelStore */

#import <Cocoa/Cocoa.h>

/*! Whether this Mac can actually run a given model.

   Added because the catalogue grew a 27B, and that is the first entry somebody
   can *fetch* and then not *load*: sixteen gigabytes arrive over an hour and
   then llama.cpp cannot map them beside everything else running. Nothing here
   used to look, so the only warning was a sentence in a row somebody may not
   read. */
typedef NS_ENUM(int, NekoModelFit) {
	NekoModelFitsWell,        /*!< room to spare */
	NekoModelFitsTightly,     /*!< it will load, and the Mac will feel it */
	NekoModelWillNotLoad      /*!< not on this machine */
};

/*! One downloadable model. */
@interface NekoLocalModel : NSObject
{
	NSString *identifier;
	NSString *name;
	NSString *detail;
	NSURL *url;
	long long expectedBytes;
	BOOL thinks;
	int drawSteps;
	CGFloat drawGuidance;
	int drawSide;
}
/*! Whether this model writes its notes before it answers.

   A required argument and not a setter, on purpose: a catalogue entry added
   without deciding this is exactly how Qwen3.5 4B got in. Its URL was checked,
   its bytes were checked, its licence was checked, and nobody asked what it
   **writes** — which is a `<think>` block, and it went in the bubble with the
   persona quoted back inside it. NekoLocalProvider takes it out now; this says
   which ones it will be taking it out of, so the preferences can say so too. */
@property (readonly) BOOL thinks;

/*! What it takes to answer with, in bytes: the weights plus what llama.cpp wants
   beside them for the context and its own buffers. Not the same as the download,
   which is only the weights. */
- (long long)memoryNeeded;

/*! And whether that fits here. Read from hw.memsize each time rather than kept:
   the answer changes when somebody plugs in a different Mac's disk, and it costs
   nothing to ask. */
- (NekoModelFit)fitOnThisMac;

/*! One sentence for the row, or nil when there is nothing to warn about. */
- (NSString *)memoryWarning;

- (id)initWithIdentifier:(NSString *)anIdentifier
                    name:(NSString *)aName
                  detail:(NSString *)aDetail
                     url:(NSURL *)aURL
                   bytes:(long long)bytes
                  thinks:(BOOL)thinksOutLoud;

/*! The same thing for a model that draws, and the three extra arguments are
   required for the reason `thinks` is: a picture model added without them is a
   picture model drawn with somebody else's recipe.

   The turbo checkpoints are distilled to draw in one to four steps with the
   guidance turned off, and asked for fourteen steps at a guidance of seven —
   which is what this application passed, and what suits SD 1.5 — they come back
   as mush. The recipe belongs to the model, so it travels with it. */
- (id)initWithIdentifier:(NSString *)anIdentifier
                    name:(NSString *)aName
                  detail:(NSString *)aDetail
                     url:(NSURL *)aURL
                   bytes:(long long)bytes
                   steps:(int)steps
                guidance:(CGFloat)guidance
                    side:(int)side;

/* How this one wants to be drawn with. Meaningless for a model that answers in
   words, where they are zero. */
@property (readonly) int drawSteps;
@property (readonly) CGFloat drawGuidance;
@property (readonly) int drawSide;
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) NSString *name;
@property (readonly, copy) NSString *detail;        /*!< "468 MB, 4-bit" and so on */
@property (readonly, retain) NSURL *url;
@property (readonly) long long expectedBytes;
@end


/*! Keeps the local models: what can be had, what is on disk, and the download in
   between.

   Nothing here shells out to anything. The files live in the app's own
   Application Support folder, inside the sandbox container, and are fetched
   straight over HTTPS — no package manager, no Python, no daemon to install
   first. */
@interface NekoModelStore : NSObject
{
	NSURLSession *session;
	NSURLSessionDownloadTask *task;
	NekoLocalModel *downloading;
	double fraction;
	void (^progressBlock)(double);
	void (^completionBlock)(NSURL *, NSError *);
}

/*! Where the models are, when they are not where they live.

   Not a preference and not in any window, and here for the same reason
   NekoMemoryDirectoryKey is: a harness runs unsandboxed and looks in
   ~/Library/Application Support, while the application looks inside its
   container, so the check that matters most cannot see the file it needs.

   That cost something real. The arm of tests/think.m that asks every installed
   model a question and refuses any answer carrying a reasoning tag — the one
   check that would have caught a `<think>` block reaching a speech bubble —
   found nothing to ask, because the only model on the machine was in the app's
   container. It reported that honestly and it still measured nothing. */
extern NSString * const NekoModelsDirectoryKey;

/*! How much memory this Mac has, when a harness needs it to be a different Mac.
   Bytes. Ignored when zero or unset, which is every real launch. */
extern NSString * const NekoModelMemoryKey;

+ (NekoModelStore *)sharedStore;

/*! What can be downloaded, in ascending size. */
- (NSArray<NekoLocalModel*> *)catalogue;

/*! The ones that draw rather than write. Kept apart from the others in every
   sense — their own folder, their own list — so that the housekeeping button on
   the Local model tab cannot sweep away a picture model it does not recognise. */
- (NSArray *)pictureCatalogue;

- (NekoLocalModel *)modelWithIdentifier:(NSString *)identifier;

/* Where they are kept, created on demand. */
- (NSURL *)modelsDirectory;
- (NSURL *)picturesDirectory;

/*! `nil` when that one is not on disk. */
- (NSURL *)installedURLForIdentifier:(NSString *)identifier;

/*! A file that is there but far short of its published size: an interrupted
   download, which reads as a broken model rather than a missing one. */
- (BOOL)isIncomplete:(NSString *)identifier;
- (long long)installedBytesForIdentifier:(NSString *)identifier;
- (NSArray<NSString*> *)installedIdentifiers;
- (BOOL)removeIdentifier:(NSString *)identifier;

/*! Housekeeping: what is downloaded besides the one in use, what it costs, and
   one call to be rid of it — strays that are not in the catalogue included. */
- (NSArray<NSString*> *)identifiersOtherThan:(NSString *)keep;
- (long long)installedBytesOtherThan:(NSString *)keep;
- (long long)totalInstalledBytes;
- (NSUInteger)removeAllExcept:(NSString *)keep;

/* One download at a time; asking for a second cancels the first. Progress is
   0 to 1, and both blocks arrive on the main thread. */
/*! What this Mac has, and what is left for a model after the system and whatever
   else is open. Both in bytes. */
+ (long long)memoryOnThisMac;
+ (long long)memoryForAModel;

/*! Room on the disk the models live on, and whether this one would fit with the
   headroom a download needs. */
- (long long)freeDiskBytes;
- (BOOL)hasRoomOnDiskFor:(NekoLocalModel *)model;

/*! One sentence about the disk, or `nil`. Only ever asked before a download —
   a model already on the disk has already spent the space. */
- (NSString *)diskWarningFor:(NekoLocalModel *)model;

- (void)downloadModel:(NekoLocalModel *)model
             progress:(void (^)(double fraction))progress
           completion:(void (^)(NSURL *file, NSError *error))completion;
- (void)cancelDownload;
@property (readonly, getter=isDownloading) BOOL downloading;
@property (readonly) double fraction;
@property (readonly, retain) NekoLocalModel *downloadingModel;

@end
