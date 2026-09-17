/* NekoModelProvider */

#import <Cocoa/Cocoa.h>
#import "NekoAnswerProvider.h"

/*! Asks Claude directly, over HTTPS, with a key the user pastes once.

   The key lives in the Keychain, never in the preferences file. Answers are
   asked for short on purpose: they have to fit in a speech bubble beside a
   32 point cat. */
@interface NekoModelProvider : NSObject <NekoAnswerProvider>
{
	NSURLSessionDataTask *task;
	void (^pending)(NSString *, NSError *);
	id stream;                   /*!< a NekoStream while one is in flight */
}

/*! Stored in the Keychain. Pass nil to forget it. */
- (BOOL)setApiKey:(NSString *)key;
- (BOOL)hasApiKey;
+ (NSString *)keychainAccount;

/*! Which model to ask. Defaults to Claude Opus 5. */
- (NSString *)model;

@end
