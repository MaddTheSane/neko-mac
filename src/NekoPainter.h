/* NekoPainter */

#import <Cocoa/Cocoa.h>
#import "NekoModelStore.h"

/* NSUserDefaults keys */
extern NSString * const NekoDrawEnabledKey;   /*!< BOOL, may the cat draw at all */
extern NSString * const NekoDrawModelKey;     /*!< which of the picture models to draw with */
extern NSString * const NekoDrawStepsKey;     /*!< denoising steps, quality against time */
extern NSString * const NekoDrawSizeKey;      /*!< square side in pixels */

/*! Draws what it is asked for, here, on this Mac's GPU.

   Deliberately a separate program rather than a linked library. Stable
   Diffusion is reached through stable-diffusion.cpp, which carries its own copy
   of ggml, and the app already has one inside llama.cpp: linked together they
   would be two definitions of every ggml symbol. A helper in the bundle also
   means a model that wanders off into a gigabyte of memory, or crashes, takes
   nothing of the cat with it.

   Nothing here reaches the network. The prompt goes to a process on this
   machine and a PNG comes back. */
@interface NekoPainter : NSObject
{
	NSTask *task;
	NSString *scratch;
}

+ (NekoPainter *)sharedPainter;

/*! The switch, the helper and a model on disk, all three. */
- (BOOL)isReady;

/*! Why it is not, for the preferences to show. nil when it is. */
- (NSString *)hint;

/*! Where the helper is, or nil in a build without one. */
- (NSString *)helperPath;
- (NSURL *)modelURL;

/*! Which of the picture models is drawing: whichever somebody chose in the
   preferences, and the first when nobody has. Public because the preferences ask
   it rather than working it out again — the two of them disagreeing about which
   model is in use is exactly the bug that -firstObject in two files invited. */
- (NekoLocalModel *)model;

/*! Draws, then hands back the picture on the main thread. Slow by the standards
   of everything else here: tens of seconds is normal, which is why the cat says
   something first and the picture arrives later. */
- (void)draw:(NSString *)prompt
  completion:(void (^)(NSImage *picture, NSError *error))completion;

- (BOOL)isDrawing;
@property (readonly, getter=isDrawing) BOOL drawing;
- (void)cancel;

@end
