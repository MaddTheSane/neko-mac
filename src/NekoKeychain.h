/* NekoKeychain */

#import <Cocoa/Cocoa.h>

/*! API keys live here, never in the preferences file. One account per provider,
   so switching between them does not lose either key. */
@interface NekoKeychain : NSObject

+ (BOOL)setSecret:(NSString *)secret forAccount:(NSString *)account;
+ (NSString *)secretForAccount:(NSString *)account;
+ (BOOL)hasSecretForAccount:(NSString *)account;

@end
