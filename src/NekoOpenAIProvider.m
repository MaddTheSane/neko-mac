#import "NekoOpenAIProvider.h"
#import "NekoStream.h"
#import "NekoKeychain.h"

static NSString * const NekoOpenAIModelKey = @"NekoAskOpenAIModel";
static NSString * const NekoOpenAIAccount = @"openai-api-key";
/* Whatever the account can use; this one is only a starting point. */
static NSString * const NekoOpenAIDefaultModel = @"gpt-4o";
static const NSTimeInterval NekoOpenAITimeout = 8.0;

@implementation NekoOpenAIProvider

- (void)dealloc
{
	[self cancel];
}

+ (NSString *)keychainAccount
{
	return NekoOpenAIAccount;
}

- (NSString *)name
{
	return NSLocalizedString(@"ChatGPT", nil);
}

- (NSString *)model
{
	NSString *model = [[NSUserDefaults standardUserDefaults] stringForKey:NekoOpenAIModelKey];
	return [model length] > 0 ? model : NekoOpenAIDefaultModel;
}

- (BOOL)setApiKey:(NSString *)key
{
	return [NekoKeychain setSecret:key forAccount:NekoOpenAIAccount];
}

- (BOOL)hasApiKey
{
	return [NekoKeychain hasSecretForAccount:NekoOpenAIAccount];
}

- (BOOL)isConfigured
{
	return [self hasApiKey];
}

- (NSString *)configurationHint
{
	return [self isConfigured] ? nil : NSLocalizedString(@"Paste an API key", nil);
}

#pragma mark Asking

- (void)askQuestion:(NSString *)question
       instructions:(NSString *)instructions
         completion:(void (^)(NSString *answer, NSError *error))completion
{
	[self cancel];

	NSString *key = [NekoKeychain secretForAccount:NekoOpenAIAccount];
	if([key length] == 0) {
		completion(nil, [NSError errorWithDomain:NekoAskErrorDomain
		                                    code:NekoAskErrorNotConfigured
		                                userInfo:nil]);
		return;
	}

	/* No token ceiling on purpose: the parameter that carries one was renamed
	   between model generations, and the instructions already ask for two
	   sentences. */
	NSArray *messages = [NSArray arrayWithObjects:
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"system", @"role", instructions, @"content", nil],
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"user", @"role", question, @"content", nil], nil];
	NSDictionary *body = [NSDictionary dictionaryWithObjectsAndKeys:
		[self model], @"model", messages, @"messages", nil];

	NSError *encoding = nil;
	NSData *payload = [NSJSONSerialization dataWithJSONObject:body options:0 error:&encoding];
	if(payload == nil) {
		completion(nil, encoding);
		return;
	}

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
		[NSURL URLWithString:@"https://api.openai.com/v1/chat/completions"]];
	[request setHTTPMethod:@"POST"];
	[request setValue:@"application/json" forHTTPHeaderField:@"content-type"];
	[request setValue:[NSString stringWithFormat:@"Bearer %@", key]
	   forHTTPHeaderField:@"authorization"];
	[request setHTTPBody:payload];
	[request setTimeoutInterval:NekoOpenAITimeout];

	pending = [completion copy];
	task = [[NSURLSession sharedSession] dataTaskWithRequest:request
										   completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		   dispatch_async(dispatch_get_main_queue(), ^{
			   [self handleData:data response:response error:error];
		   });
	   }];
	[task resume];
}

/* The same question, answered a few words at a time. ChatGPT sends
   {"choices":[{"delta":{"content":"..."}}]} per event and closes with [DONE];
   everything else about reading that is in NekoStream and is shared with Claude. */
- (void)askQuestion:(NSString *)question
       instructions:(NSString *)instructions
            partial:(void (^)(NSString *sofar))partial
         completion:(void (^)(NSString *answer, NSError *error))completion
{
	[self cancel];

	NSString *key = [NekoKeychain secretForAccount:NekoOpenAIAccount];
	if([key length] == 0) {
		completion(nil, [NSError errorWithDomain:NekoAskErrorDomain
		                                    code:NekoAskErrorNotConfigured
		                                userInfo:nil]);
		return;
	}

	NSArray *messages = [NSArray arrayWithObjects:
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"system", @"role", instructions, @"content", nil],
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"user", @"role", question, @"content", nil], nil];
	NSDictionary *body = [NSDictionary dictionaryWithObjectsAndKeys:
		[self model], @"model", messages, @"messages",
		[NSNumber numberWithBool:YES], @"stream", nil];

	NSData *payload = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
	if(payload == nil) {
		[self askQuestion:question instructions:instructions completion:completion];
		return;
	}

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
		[NSURL URLWithString:@"https://api.openai.com/v1/chat/completions"]];
	[request setHTTPMethod:@"POST"];
	[request setValue:@"application/json" forHTTPHeaderField:@"content-type"];
	[request setValue:@"text/event-stream" forHTTPHeaderField:@"accept"];
	[request setValue:[NSString stringWithFormat:@"Bearer %@", key]
	   forHTTPHeaderField:@"authorization"];
	[request setHTTPBody:payload];

	stream = [[NekoStream alloc] initWithRequest:request
	                                     timeout:NekoOpenAITimeout
	                                        text:^NSString *(NSDictionary *event) {
		return [[[[event objectForKey:@"choices"] lastObject]
			objectForKey:@"delta"] objectForKey:@"content"];
	}
	                                     partial:partial
	                                  completion:^(NSString *answer, NSError *error) {
		stream = nil;
		completion(answer, error);
	}];
	[stream start];
}

- (void)handleData:(NSData *)data response:(NSURLResponse *)response error:(NSError *)error
{
	void (^completion)(NSString *, NSError *) = pending;
	pending = NULL;
	task = nil;
	if(completion == NULL)
		return;                  /* cancelled while in flight */

	if(error != nil) {
		completion(nil, error);
		return;
	}

	NSDictionary *json = [NSJSONSerialization JSONObjectWithData:(data ?: [NSData data])
	                                                     options:0 error:NULL];
	NSInteger status = [(NSHTTPURLResponse *)response statusCode];
	if(status != 200) {
		NSString *detail = [[json objectForKey:@"error"] objectForKey:@"message"];
		completion(nil, [NSError errorWithDomain:NekoAskErrorDomain
		                                    code:NekoAskErrorTransport
		                                userInfo:detail != nil
			? [NSDictionary dictionaryWithObject:detail forKey:NSLocalizedDescriptionKey]
			: nil]);
		return;
	}

	NSString *answer = [[[[json objectForKey:@"choices"] lastObject]
		objectForKey:@"message"] objectForKey:@"content"];
	if([answer length] > 0)
		completion(answer, nil);
	else
		completion(nil, [NSError errorWithDomain:NekoAskErrorDomain
		                                    code:NekoAskErrorNoAnswer
		                                userInfo:nil]);
}

- (void)cancel
{
	[stream cancel];
	stream = nil;
	[task cancel];
	task = nil;
	if(pending != NULL) {
		pending = NULL;
	}
}

@end
