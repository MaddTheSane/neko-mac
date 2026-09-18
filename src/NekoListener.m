#import "NekoListener.h"
#import "NekoAnswerProvider.h"
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>

/* The felt cost of the whole feature was here: after you stop talking, nothing
   happens until this expires. A second and a half still tolerates a pause for
   thought, and the recogniser usually declares the sentence finished on its own
   before it runs out. */
static const NSTimeInterval NekoSilenceTimeout = 1.5;
static const NSTimeInterval NekoListeningLimit = 15.0;

@implementation NekoListener

+ (BOOL)isAvailable
{
	return NSClassFromString(@"SFSpeechRecognizer") != Nil;
}

+ (NSInteger)authorizationStatus
{
	if(![self isAvailable])
		return 1;                /* as good as denied */
	if(@available(macOS 10.15, *))
		return (NSInteger)[SFSpeechRecognizer authorizationStatus];
	return 1;
}

+ (void)requestAuthorization:(void (^)(BOOL granted))completion
{
	if(![self isAvailable]) {
		completion(NO);
		return;
	}
	if(@available(macOS 10.15, *)) {
		[SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
			dispatch_async(dispatch_get_main_queue(), ^{
				completion(status == SFSpeechRecognizerAuthorizationStatusAuthorized);
			});
		}];
	} else {
		completion(NO);
	}
}

- (void)dealloc
{
	[self cancel];
}

- (BOOL)isListening
{
	return engine != nil;
}

- (BOOL)isOnDevice
{
	return onDevice;
}

#pragma mark Listening

- (BOOL)startListeningWithLocale:(NSLocale *)locale
                          report:(void (^)(NSString *text, BOOL final, NSError *error))block
{
	return [self startListeningWithLocale:locale
	                            patience:NekoListeningLimit
	                              report:block];
}

- (BOOL)startListeningWithLocale:(NSLocale *)locale
                        patience:(NSTimeInterval)seconds
                          report:(void (^)(NSString *text, BOOL final, NSError *error))block
{
	if(![NekoListener isAvailable] || [self isListening])
		return NO;

	if(@available(macOS 10.15, *)) {
		SFSpeechRecognizer *speech = [[SFSpeechRecognizer alloc] initWithLocale:locale];
		if(speech == nil || ![speech isAvailable]) {
			return NO;
		}
		recognizer = speech;

		SFSpeechAudioBufferRecognitionRequest *audioRequest =
			[[SFSpeechAudioBufferRecognitionRequest alloc] init];
		[audioRequest setShouldReportPartialResults:YES];
		/* Keeping it on the Mac when the language allows: the preferences say
		   which of the two is happening. */
		onDevice = [speech supportsOnDeviceRecognition];
		if(onDevice)
			[audioRequest setRequiresOnDeviceRecognition:YES];
		request = audioRequest;

		report = [block copy];
		heard = nil;

		AVAudioEngine *audio = [[AVAudioEngine alloc] init];
		engine = audio;
		AVAudioInputNode *input = [audio inputNode];
		AVAudioFormat *format = [input outputFormatForBus:0];
		/* Both halves of "usable", because the second one cost a day. A default
		   input that has gone away — a display waking, a headset leaving —
		   hands back a format with a sane sample rate and **no channels**, and
		   -installTapOnBus: does not return an error for that. It raises. The
		   unified log for the failure is quoted in tests/deaf.m. */
		if([format sampleRate] <= 0.0 || [format channelCount] == 0) {
			[self cancel];
			return NO;
		}

		NSError *error = nil;
		@try {
			[input installTapOnBus:0 bufferSize:1024 format:format
			                block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
				[self->request appendAudioPCMBuffer:buffer];
			}];
			[audio prepare];
		}
		@catch(NSException *raised) {
			/* A raise from CoreAudio is a failure to start like any other, and
			   every caller of this method is written to read a BOOL. */
			NSLog(@"Neko: the microphone would not open — %@", [raised reason]);
			[self cancel];
			return NO;
		}

		if(![audio startAndReturnError:&error]) {
			void (^failed)(NSString *, BOOL, NSError *) = report;
			report = NULL;
			[self cancel];
			if(failed != NULL) {
				failed(nil, YES, error);
				failed = nil;
			}
			return NO;
		}

		task = [speech recognitionTaskWithRequest:audioRequest
		                            resultHandler:^(SFSpeechRecognitionResult *result,
		                                            NSError *taskError) {
			[self handleResult:result error:taskError];
		}];

		[self restartSilenceTimer:seconds];
		return YES;
	}
	return NO;
}

- (void)handleResult:(id)result error:(NSError *)error
{
	if(report == NULL)
		return;

	if(@available(macOS 10.15, *)) {
		SFSpeechRecognitionResult *recognised = result;
		if(recognised != nil) {
			heard = [[[recognised bestTranscription] formattedString] copy];
			BOOL final = [recognised isFinal];
			report(heard, final, nil);
			if(final) {
				[self cancel];
				return;
			}
			/* Words are still coming: reset the patience. */
			[self restartSilenceTimer:NekoSilenceTimeout];
			return;
		}
	}

	if(error != nil) {
		void (^failed)(NSString *, BOOL, NSError *) = report;
		report = NULL;
		NSString *partial = [heard copy];
		[self cancel];
		if(failed != NULL) {
			/* Something was understood before it broke: that counts. */
			if([partial length] > 0)
				failed(partial, YES, nil);
			else
				failed(nil, YES, error);
			failed = nil;
		}
	}
}

- (void)restartSilenceTimer:(NSTimeInterval)seconds
{
	[silence invalidate];
	silence = [NSTimer scheduledTimerWithTimeInterval:seconds
	                                          target:self
	                                        selector:@selector(silenceExpired:)
	                                        userInfo:nil
	                                         repeats:NO];
}

- (void)silenceExpired:(NSTimer *)timer
{
	silence = nil;
	[self stop];
}

- (void)stop
{
	if(![self isListening])
		return;

	if(@available(macOS 10.15, *))
		[(SFSpeechAudioBufferRecognitionRequest *)request endAudio];

	[[(AVAudioEngine *)engine inputNode] removeTapOnBus:0];
	[(AVAudioEngine *)engine stop];

	/* Nothing was understood at all: say so now rather than hanging. */
	if([heard length] == 0 && report != NULL) {
		void (^failed)(NSString *, BOOL, NSError *) = report;
		report = NULL;
		[self cancel];
		failed(nil, YES, [NSError errorWithDomain:NekoAskErrorDomain
		                                     code:NekoAskErrorNoAnswer
		                                 userInfo:nil]);
		failed = nil;
	}
}

- (void)cancel
{
	[silence invalidate];
	silence = nil;

	if(engine != nil) {
		[[engine inputNode] removeTapOnBus:0];
		[engine stop];
		engine = nil;
	}
	if(task != nil) {
		if(@available(macOS 10.15, *))
			[task cancel];
		task = nil;
	}
	request = nil;
	recognizer = nil;
	if(report != NULL) {
		report = NULL;
	}
}

@end
