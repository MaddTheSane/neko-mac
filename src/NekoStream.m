#import "NekoStream.h"
#import "NekoAsk.h"

@implementation NekoStream

- (id)initWithRequest:(NSURLRequest *)request
              timeout:(NSTimeInterval)seconds
                 text:(NSString *(^)(NSDictionary *event))text
              partial:(void (^)(NSString *sofar))partial
           completion:(void (^)(NSString *answer, NSError *error))completion
{
	if((self = [super init]) != nil) {
		pending = [[NSMutableData alloc] init];
		answer = [[NSMutableString alloc] init];
		status = 200;
		textOf = [text copy];
		onPartial = partial != nil ? [partial copy] : NULL;
		onDone = [completion copy];

		NSURLSessionConfiguration *how =
			[NSURLSessionConfiguration ephemeralSessionConfiguration];
		[how setTimeoutIntervalForRequest:seconds];
		session = [NSURLSession sessionWithConfiguration:how
												delegate:self
										   delegateQueue:nil];
		task = [session dataTaskWithRequest:request];
	}
	return self;
}

- (void)start { [task resume]; }

- (void)cancel
{
	finished = YES;
	[task cancel];
	[session invalidateAndCancel];
}

- (NSString *)sofar { return [answer copy]; }

#pragma mark Reading it

/* One line at a time, because a chunk from the network stops wherever it stops —
   halfway through a word, halfway through a line, or between the two characters
   of a newline. Anything that is not a data: line is a comment or a keep-alive
   and is meant to be ignored. */
- (void)consume:(NSData *)chunk
{
	if([chunk length] > 0)
		[pending appendData:chunk];

	while(YES) {
		const char *bytes = (const char *)[pending bytes];
		NSUInteger length = [pending length], i, breakAt = NSNotFound;
		for(i = 0; i < length; i++)
			if(bytes[i] == '\n') { breakAt = i; break; }
		if(breakAt == NSNotFound)
			break;

		NSData *lineData = [pending subdataWithRange:NSMakeRange(0, breakAt)];
		[pending replaceBytesInRange:NSMakeRange(0, breakAt + 1) withBytes:NULL length:0];

		NSString *line = [[NSString alloc] initWithData:lineData
											   encoding:NSUTF8StringEncoding];
		line = [line stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if(![line hasPrefix:@"data:"])
			continue;

		NSString *payload = [[line substringFromIndex:5]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if([payload isEqualToString:@"[DONE]"] || [payload length] == 0)
			continue;

		NSDictionary *event = [NSJSONSerialization JSONObjectWithData:
			[payload dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
		if(![event isKindOfClass:[NSDictionary class]])
			continue;

		NSString *more = textOf != NULL ? textOf(event) : nil;
		if([more length] == 0)
			continue;
		[answer appendString:more];
		if(onPartial != NULL)
			onPartial([answer copy]);
	}
}

#pragma mark What the session tells us

- (void)URLSession:(NSURLSession *)which
          dataTask:(NSURLSessionDataTask *)aTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))decide
{
	status = [(NSHTTPURLResponse *)response statusCode];
	if(status != 200 && errorBody == nil)
		errorBody = [[NSMutableData alloc] init];
	decide(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)which
          dataTask:(NSURLSessionDataTask *)aTask
    didReceiveData:(NSData *)data
{
	/* A status that is not 200 does not arrive as events; it arrives as one JSON
	   object saying what went wrong, and it is worth reading rather than
	   reporting "no answer". */
	if(status != 200) {
		[errorBody appendData:data];
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		if(!self->finished)
			[self consume:data];
	});
}

- (void)URLSession:(NSURLSession *)which
              task:(NSURLSessionTask *)aTask
didCompleteWithError:(NSError *)error
{
	dispatch_async(dispatch_get_main_queue(), ^{
		if(self->finished)
			return;
		self->finished = YES;

		void (^done)(NSString *, NSError *) = self->onDone;
		self->onDone = NULL;
		if(done == NULL)
			return;

		if(self->status != 200) {
			NSDictionary *said = [NSJSONSerialization JSONObjectWithData:
				(self->errorBody ?: [NSData data]) options:0 error:NULL];
			NSString *detail = [[said objectForKey:@"error"] objectForKey:@"message"];
			done(nil, [NSError errorWithDomain:NekoAskErrorDomain
			                              code:NekoAskErrorTransport
			                          userInfo:[detail length] > 0
				? [NSDictionary dictionaryWithObject:detail
				                              forKey:NSLocalizedDescriptionKey]
				: nil]);
		}
		else if(error != nil && [self->answer length] == 0)
			done(nil, error);
		else
			done([self->answer copy], nil);
		[self->session finishTasksAndInvalidate];
	});
}

@end
