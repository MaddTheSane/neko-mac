#import "NekoAppleProvider.h"
#import "Neko-Swift.h"

@implementation NekoAppleProvider

+ (BOOL)isSupported
{
	return [NekoAppleModel isAvailable];
}

- (id)model
{
	if(model == nil) {
		model = [[NekoAppleModel alloc] init];
	}
	return model;
}

- (void)dealloc
{
	[model cancel];
	[model release];
	[super dealloc];
}

- (NSString *)name
{
	return NSLocalizedString(@"Apple Intelligence, on this Mac", nil);
}

- (BOOL)isConfigured
{
	return [NekoAppleProvider isSupported];
}

- (NSString *)configurationHint
{
	if([self isConfigured])
		return nil;
	Class bridge = NSClassFromString(@"NekoAppleModel");
	NSString *reason = bridge != Nil ? [bridge unavailableReason] : nil;
	return reason ?: NSLocalizedString(@"Needs macOS 26 or newer", nil);
}

- (void)askQuestion:(NSString *)question
       instructions:(NSString *)instructions
         completion:(void (^)(NSString *answer, NSError *error))completion
{
	if(![self isConfigured]) {
		completion(nil, [NSError errorWithDomain:NekoAskErrorDomain
		                                    code:NekoAskErrorNotConfigured
		                                userInfo:nil]);
		return;
	}

	[[self model] ask:question
	     instructions:instructions
	       completion:^(NSString *answer, NSString *failure) {
		if([answer length] > 0) {
			completion(answer, nil);
			return;
		}
		completion(nil, [NSError errorWithDomain:NekoAskErrorDomain
		                                    code:NekoAskErrorNoAnswer
		                                userInfo:failure != nil
			? [NSDictionary dictionaryWithObject:failure forKey:NSLocalizedDescriptionKey]
			: nil]);
	}];
}

- (void)askQuestion:(NSString *)question
       instructions:(NSString *)instructions
            partial:(void (^)(NSString *sofar))partial
         completion:(void (^)(NSString *answer, NSError *error))completion
{
	if(![self isConfigured]) {
		completion(nil, [NSError errorWithDomain:NekoAskErrorDomain
		                                    code:NekoAskErrorNotConfigured
		                                userInfo:nil]);
		return;
	}

	[[self model] askStreaming:question
	              instructions:instructions
	                   partial:partial
	                completion:^(NSString *answer, NSString *failure) {
		if([answer length] > 0) {
			completion(answer, nil);
			return;
		}
		completion(nil, [NSError errorWithDomain:NekoAskErrorDomain
		                                    code:NekoAskErrorNoAnswer
		                                userInfo:failure != nil
			? [NSDictionary dictionaryWithObject:failure forKey:NSLocalizedDescriptionKey]
			: nil]);
	}];
}

- (void)cancel
{
	[model cancel];
}

@end
