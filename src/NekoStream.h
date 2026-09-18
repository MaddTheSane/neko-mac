/* NekoStream */

#import <Cocoa/Cocoa.h>

/*! An answer that arrives a few words at a time.

   Both remote engines can send one — ChatGPT and Claude both speak
   server-sent events — and neither of them did, which is backwards: they are the
   two slowest engines in the application, because they are the two that go over
   a network, and they were the two that made somebody wait for the whole answer
   before showing any of it. The local ones, which are quickest to first word,
   were already streaming.

   The two formats differ only in where the text sits inside each event, so that
   is the one thing a caller supplies. Everything else — buffering half-arrived
   lines, ignoring the keep-alives, noticing a status that is not 200 and reading
   the error out of the body instead — is here and is the same for both.

   The parsing is deliberately separable from the network: -consume: takes bytes
   as though they had arrived, which is how tests/stream.m measures a split
   mid-word, a split mid-line, and an error body without spending anybody's
   money on an API call. */
@interface NekoStream : NSObject <NSURLSessionDataDelegate>
{
	NSURLSession *session;
	NSURLSessionDataTask *task;
	NSMutableData *pending;        /* bytes that are not yet a whole line */
	NSMutableString *answer;
	NSMutableData *errorBody;      /* when the status was not 200 */
	NSInteger status;

	NSString *(^textOf)(NSDictionary *event);
	void (^onPartial)(NSString *sofar);
	void (^onDone)(NSString *answer, NSError *error);
	BOOL finished;
}

- (id)initWithRequest:(NSURLRequest *)request
              timeout:(NSTimeInterval)seconds
                 text:(NSString *(^)(NSDictionary *event))text
              partial:(void (^)(NSString *sofar))partial
           completion:(void (^)(NSString *answer, NSError *error))completion;

- (void)start;
- (void)cancel;

/*! Bytes as if they had arrived, and what has been understood of them so far. */
- (void)consume:(NSData *)chunk;
- (NSString *)sofar;

@end
