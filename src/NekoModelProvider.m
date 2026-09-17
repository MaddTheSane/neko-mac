#import "NekoModelProvider.h"
#import "NekoStream.h"
#import "NekoKeychain.h"

static NSString * const NekoModelKey = @"NekoAskModel";
static NSString * const NekoKeychainAccount = @"anthropic-api-key";

static NSString * const NekoDefaultModel = @"claude-opus-5";
/* Eight seconds: long enough for a sentence over the network, short enough
   that a stuck request does not leave the cat staring. */
static const NSTimeInterval NekoModelTimeout = 8.0;

@implementation NekoModelProvider

- (void)dealloc
{
	[self cancel];
	[super dealloc];
}

- (NSString *)name
{
	return NSLocalizedString(@"Claude", nil);
}

- (NSString *)model
{
	NSString *model = [[NSUserDefaults standardUserDefaults] stringForKey:NekoModelKey];
	return [model length] > 0 ? model : NekoDefaultModel;
}

- (BOOL)isConfigured
{
	return [self hasApiKey];
}

- (NSString *)configurationHint
{
	return [self isConfigured] ? nil : NSLocalizedString(@"Paste an API key", nil);
}

#pragma mark The key, in the Keychain

+ (NSString *)keychainAccount
{
	return NekoKeychainAccount;
}

- (BOOL)setApiKey:(NSString *)key
{
	return [NekoKeychain setSecret:key forAccount:NekoKeychainAccount];
}

- (NSString *)apiKey
{
	return [NekoKeychain secretForAccount:NekoKeychainAccount];
}

- (BOOL)hasApiKey
{
	return [NekoKeychain hasSecretForAccount:NekoKeychainAccount];
}

#pragma mark Asking

- (void)askQuestion:(NSString *)question
       instructions:(NSString *)instructions
         completion:(void (^)(NSString *answer, NSError *error))completion
{
	[self cancel];

	NSString *key = [self apiKey];
	if([key length] == 0) {
		completion(nil, [NSError errorWithDomain:NekoAskErrorDomain
		                                    code:NekoAskErrorNotConfigured
		                                userInfo:nil]);
		return;
	}

	NSDictionary *body = [NSDictionary dictionaryWithObjectsAndKeys:
		[self model], @"model",
		@400, @"max_tokens",   /* a bubble, not an essay */
		instructions, @"system",
		[NSDictionary dictionaryWithObjectsAndKeys:@"low", @"effort", nil], @"output_config",
		@"default", @"fallbacks",
		[NSArray arrayWithObject:
			[NSDictionary dictionaryWithObjectsAndKeys:
				@"user", @"role", question, @"content", nil]], @"messages",
		nil];

	NSError *encoding = nil;
	NSData *payload = [NSJSONSerialization dataWithJSONObject:body options:0 error:&encoding];
	if(payload == nil) {
		completion(nil, encoding);
		return;
	}

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
		[NSURL URLWithString:@"https://api.anthropic.com/v1/messages"]];
	[request setHTTPMethod:@"POST"];
	[request setValue:@"application/json" forHTTPHeaderField:@"content-type"];
	[request setValue:key forHTTPHeaderField:@"x-api-key"];
	[request setValue:@"2023-06-01" forHTTPHeaderField:@"anthropic-version"];
	/* Server-side fallbacks: a refused question is answered by another model
	   rather than coming back empty. */
	[request setValue:@"server-side-fallback-2026-07-01" forHTTPHeaderField:@"anthropic-beta"];
	[request setHTTPBody:payload];
	[request setTimeoutInterval:NekoModelTimeout];

	pending = Block_copy(completion);
	task = [[[NSURLSession sharedSession] dataTaskWithRequest:request
	         completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self handleData:data response:response error:error];
		});
	}] retain];
	[task resume];
}

/* The same question, a few words at a time. Claude sends one event per delta and
   the text sits at delta.text; the rest of reading a stream is in NekoStream and
   is shared with ChatGPT, whose events put it somewhere else entirely. */
- (void)askQuestion:(NSString *)question
       instructions:(NSString *)instructions
            partial:(void (^)(NSString *sofar))partial
         completion:(void (^)(NSString *answer, NSError *error))completion
{
	[self cancel];

	NSString *key = [self apiKey];
	if([key length] == 0) {
		completion(nil, [NSError errorWithDomain:NekoAskErrorDomain
		                                    code:NekoAskErrorNotConfigured
		                                userInfo:nil]);
		return;
	}

	NSDictionary *body = [NSDictionary dictionaryWithObjectsAndKeys:
		[self model], @"model",
		@400, @"max_tokens",
		instructions, @"system",
		[NSDictionary dictionaryWithObjectsAndKeys:@"low", @"effort", nil], @"output_config",
		@"default", @"fallbacks",
		[NSNumber numberWithBool:YES], @"stream",
		[NSArray arrayWithObject:
			[NSDictionary dictionaryWithObjectsAndKeys:
				@"user", @"role", question, @"content", nil]], @"messages",
		nil];

	NSData *payload = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
	if(payload == nil) {
		[self askQuestion:question instructions:instructions completion:completion];
		return;
	}

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
		[NSURL URLWithString:@"https://api.anthropic.com/v1/messages"]];
	[request setHTTPMethod:@"POST"];
	[request setValue:@"application/json" forHTTPHeaderField:@"content-type"];
	[request setValue:@"text/event-stream" forHTTPHeaderField:@"accept"];
	[request setValue:key forHTTPHeaderField:@"x-api-key"];
	[request setValue:@"2023-06-01" forHTTPHeaderField:@"anthropic-version"];
	[request setValue:@"server-side-fallback-2026-07-01" forHTTPHeaderField:@"anthropic-beta"];
	[request setHTTPBody:payload];

	stream = [[NekoStream alloc] initWithRequest:request
	                                     timeout:NekoModelTimeout
	                                        text:^NSString *(NSDictionary *event) {
		NSDictionary *delta = [event objectForKey:@"delta"];
		if(![delta isKindOfClass:[NSDictionary class]])
			return nil;
		return [delta objectForKey:@"text"];
	}
	                                     partial:partial
	                                  completion:^(NSString *answer, NSError *error) {
		[stream release];
		stream = nil;
		completion(answer, error);
	}];
	[stream start];
}

- (void)handleData:(NSData *)data response:(NSURLResponse *)response error:(NSError *)error
{
	void (^completion)(NSString *, NSError *) = pending;
	pending = NULL;
	[task release];
	task = nil;
	if(completion == NULL)
		return;                  /* cancelled while in flight */

	if(error != nil) {
		completion(nil, error);
		Block_release(completion);
		return;
	}

	NSInteger status = [(NSHTTPURLResponse *)response statusCode];
	NSDictionary *json = [NSJSONSerialization JSONObjectWithData:(data ?: [NSData data])
	                                                     options:0
	                                                       error:NULL];
	if(status != 200) {
		NSString *detail = [[json objectForKey:@"error"] objectForKey:@"message"];
		completion(nil, [NSError errorWithDomain:NekoAskErrorDomain
		                                    code:NekoAskErrorTransport
		                                userInfo:detail != nil
			? [NSDictionary dictionaryWithObject:detail forKey:NSLocalizedDescriptionKey]
			: nil]);
		Block_release(completion);
		return;
	}

	/* The answer is the text blocks, joined. A refusal arrives as a 200 with no
	   text at all, which is why stop_reason is worth looking at. */
	NSMutableString *answer = [NSMutableString string];
	NSEnumerator *e = [[json objectForKey:@"content"] objectEnumerator];
	for(NSDictionary *block in e) {
		if(![[block objectForKey:@"type"] isEqualToString:@"text"])
			continue;
		NSString *text = [block objectForKey:@"text"];
		if([text length] == 0)
			continue;
		if([answer length] > 0)
			[answer appendString:@"\n"];
		[answer appendString:text];
	}

	if([answer length] == 0) {
		/* A refusal comes back as a 200 with no text; either way there is
		   nothing for the cat to say. */
		completion(nil, [NSError errorWithDomain:NekoAskErrorDomain
		                                    code:NekoAskErrorNoAnswer
		                                userInfo:nil]);
	} else {
		completion(answer, nil);
	}
	Block_release(completion);
}

- (void)cancel
{
	[stream cancel];
	[stream release];
	stream = nil;
	[task cancel];
	[task release];
	task = nil;
	if(pending != NULL) {
		Block_release(pending);
		pending = NULL;
	}
}

@end
