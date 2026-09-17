/* NekoOpenAIProvider */

#import <Cocoa/Cocoa.h>
#import "NekoAnswerProvider.h"

/*! ChatGPT, asked directly with a key of the user's own.

   Apple's own ChatGPT integration cannot be reached from another application —
   it answers inside Siri and the writing tools, never to a program — so the
   choices are this, or a Shortcut that ends in a ChatGPT action. */
@interface NekoOpenAIProvider : NSObject <NekoAnswerProvider>
{
	NSURLSessionDataTask *task;
	void (^pending)(NSString *, NSError *);
	id stream;                   /* a NekoStream while one is in flight */
}

+ (NSString *)keychainAccount;
- (BOOL)setApiKey:(NSString *)key;
- (BOOL)hasApiKey;
- (NSString *)model;

@end
