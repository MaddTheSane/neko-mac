/* NekoFolderAccess */

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/*! Which of your folders the cat has been shown, and how it remembers.

   The app is sandboxed, and measured from a signed build it cannot read the
   Desktop or write to Documents: that is the sandbox doing its job. The way in
   that does not involve giving it up is the one macOS provides — you pick the
   folder yourself, once, in a panel, and the app keeps a security-scoped
   bookmark to it. Nothing else opens that door: not a setting, not a model, not
   a sentence somebody typed into a window.

   Six folders can ever be asked for, and no others. */
@interface NekoFolderAccess : NSObject

+ (NekoFolderAccess *)sharedAccess;
@property (readonly, class) NekoFolderAccess *sharedAccess;

/* "desktop", "documents", "downloads", "pictures", "music", "movies". */
+ (NSArray<NSString*> *)folderKeys;
@property (readonly, class, copy) NSArray<NSString*> *folderKeys;
+ (BOOL)isFolderKey:(NSString *)key;

/*! The Finder's name for it, for anything the user reads. */
- (NSString *)displayNameForKey:(NSString *)key;

/*! Whether a bookmark exists and still resolves. */
- (BOOL)hasAccessToFolderKey:(NSString *)key;
- (NSArray<NSString*> *)allowedKeys;

/*! Opens the standard panel at that folder and keeps a bookmark if the user
   agrees. Returns whether access is now available. Must be called on the main
   thread: it puts up a panel. */
- (BOOL)requestAccessToFolderKey:(NSString *)key;

/*! The same, and it says why when the answer is no — except when the answer is
   somebody pressing Cancel, which is not a failure and gets no sentence. Picking
   the wrong folder used to be refused in silence in all three places that ask,
   which is indistinguishable from a button that does nothing. */
- (BOOL)requestAccessToFolderKey:(NSString *)key saying:(NSString *_Nullable __autoreleasing *_Nullable)problem;

/*! Why a chosen folder is not the one that was asked for, or `nil` when it is. Its
   own method so that the sentence can be measured without driving a panel the
   system owns. */
- (NSString *)refusalForChoosingURL:(NSURL *)chosen insteadOfFolderKey:(NSString *)key;

/*! The folder, with access started. Balance every non-nil answer with
   `-doneWithURL:`, or the sandbox will run out of scoped resources. */
- (NSURL * _Nullable)beginUsingFolderKey:(NSString *)key;
- (void)doneWithURL:(NSURL *)url;

/*! Forgets a folder, which is the only way back out. */
- (void)forgetFolderKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
