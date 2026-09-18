#import "NekoWakeWord.h"
#import "NekoAsk.h"
#import "NekoController.h"
#import "NekoListener.h"
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>

NSString * const NekoWakeWordKey = @"NekoWakeWord";

/* Speech ends a recognition task of its own accord after about a minute, so it
   is rebuilt before that rather than after. */
static const NSTimeInterval NekoWakeRenewal = 50.0;

/* One wake a second at most, so a sentence containing the name twice is one
   wake, not two. */
static const NSTimeInterval NekoWakeCooldown = 1.5;

/* What a recogniser makes of a cat called Neko. A dictation engine has never
   heard of the cat and writes down the nearest word it knows, which in Italian
   is usually "neco" or "necco" and in English "nico". */
static NSString * const NekoWakeSpellings[] = {
	@"neko", @"neco", @"necco", @"nekko", @"nico", @"niko", nil
};

@implementation NekoWakeWord

+ (NekoWakeWord *)sharedWakeWord
{
	static NekoWakeWord *shared = nil;
	if(shared == nil)
		shared = [[NekoWakeWord alloc] init];
	return shared;
}

+ (BOOL)isAvailable
{
	if(![NekoListener isAvailable])
		return NO;
	if(@available(macOS 10.15, *)) {
		SFSpeechRecognizer *speech = [[SFSpeechRecognizer alloc]
									  initWithLocale:[NSLocale currentLocale]];
		return speech != nil && [speech isAvailable]
			&& [speech supportsOnDeviceRecognition];
	}
	return NO;
}

+ (NSString *)unavailableReason
{
	if(![NekoListener isAvailable])
		return NSLocalizedString(@"This Mac has no speech recognition.", nil);
	if([NekoListener authorizationStatus] == 1 || [NekoListener authorizationStatus] == 2)
		return NSLocalizedString(@"Speech recognition is refused for Neko. The Permissions tab has the way back.", nil);
	if(![self isAvailable])
		return NSLocalizedString(@"This Mac cannot recognise your language without sending the audio to a server, and an always-open microphone is not something to send anywhere.", nil);
	return nil;
}

#pragma mark The name

/* Accents off, case off, punctuation to spaces, so that "Neko!" and "nekò" and
   "neko," are all the same three syllables. */
+ (NSString *)plainly:(NSString *)text
{
	NSString *folded = [text stringByFoldingWithOptions:
		(NSDiacriticInsensitiveSearch | NSCaseInsensitiveSearch)
		                                          locale:[NSLocale currentLocale]];
	NSMutableString *plain = [NSMutableString stringWithString:@" "];
	NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
	NSUInteger i;
	for(i = 0; i < [folded length]; i++) {
		unichar c = [folded characterAtIndex:i];
		[plain appendString:[letters characterIsMember:c]
			? [NSString stringWithCharacters:&c length:1] : @" "];
	}
	[plain appendString:@" "];
	return plain;
}

+ (BOOL)textNamesTheCat:(NSString *)text
{
	if([text length] == 0)
		return NO;
	NSString *plain = [self plainly:text];
	NSUInteger i;
	for(i = 0; NekoWakeSpellings[i] != nil; i++) {
		NSString *word = [NSString stringWithFormat:@" %@ ", NekoWakeSpellings[i]];
		if([plain rangeOfString:word].location != NSNotFound)
			return YES;
	}
	return NO;
}

#pragma mark Running

- (BOOL)isListening
{
	return running;
}

/* Whether the recogniser has said anything at all lately: listening and hearing
   are not the same thing, and only one of them can be seen from outside. */
- (BOOL)isHearing
{
	return running && lastResult != nil && -[lastResult timeIntervalSinceNow] < 30.0;
}

- (BOOL)shouldRun
{
	NekoController *controller = [NekoController sharedController];
	return [[NSUserDefaults standardUserDefaults] boolForKey:NekoWakeWordKey]
		&& [[NekoAsk sharedAsk] isEnabled]
		&& ![controller isPaused]
		&& [NekoWakeWord isAvailable];
}

- (void)applySettings
{
	if(![self shouldRun]) {
		[self stop];
		return;
	}

	/* Speech has to be allowed before any of this does anything at all. Without
	   asking, the recogniser accepts a task, returns no results, and the cat
	   simply never hears its name — which is what happened: the permission had
	   never been requested because the keystroke, which is where it used to be
	   asked for, had never been used. */
	NSInteger status = [NekoListener authorizationStatus];
	if(status == 3) {
		[self start];
		return;
	}
	if(status != 0)
		return;                    /* refused: the permissions tab says so */

	if(asking)
		return;
	asking = YES;
	[NekoListener requestAuthorization:^(BOOL granted) {
		self->asking = NO;
		if(granted)
			[self start];
	}];
}

- (void)start
{
	if(running)
		return;
	if(@available(macOS 10.15, *)) {
		SFSpeechRecognizer *speech = [[SFSpeechRecognizer alloc]
			initWithLocale:[NSLocale currentLocale]];
		if(speech == nil || ![speech isAvailable] || ![speech supportsOnDeviceRecognition]) {
			return;
		}
		recognizer = speech;

		AVAudioEngine *audio = [[AVAudioEngine alloc] init];
		engine = audio;
		AVAudioInputNode *input = [audio inputNode];
		AVAudioFormat *format = [input outputFormatForBus:0];
		/* The same two guards as NekoListener, and this is the path that runs
		   unattended: a default input that has gone away gives a sane sample
		   rate and no channels, and -installTapOnBus: raises rather than
		   returning. See tests/deaf.m. */
		if([format sampleRate] <= 0.0 || [format channelCount] == 0) {
			[self stop];
			return;
		}

		NSError *problem = nil;
		@try {
			/* The tap outlives each recognition task: only the request
			   underneath it is swapped, every fifty seconds. */
			[input installTapOnBus:0 bufferSize:2048 format:format
			                block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
				SFSpeechAudioBufferRecognitionRequest *current = self->request;
				if(current != nil)
					[current appendAudioPCMBuffer:buffer];
			}];
			[audio prepare];
		}
		@catch(NSException *raised) {
			NSLog(@"Neko: the wake word could not open the microphone — %@",
				[raised reason]);
			[self stop];
			return;
		}

		if(![audio startAndReturnError:&problem]) {
			[self stop];
			return;
		}

		running = YES;
		lastResult = [NSDate date];
		[self beginTask];
		renewal = [NSTimer scheduledTimerWithTimeInterval:NekoWakeRenewal
		                                          target:self
		                                        selector:@selector(renew:)
		                                        userInfo:nil
		                                         repeats:YES];
		watchdog = [NSTimer scheduledTimerWithTimeInterval:5.0
		                                           target:self
		                                         selector:@selector(checkAlive:)
		                                         userInfo:nil
		                                          repeats:YES];
	}
}

- (void)beginTask
{
	if(@available(macOS 10.15, *)) {
		SFSpeechAudioBufferRecognitionRequest *audioRequest =
			[[SFSpeechAudioBufferRecognitionRequest alloc] init];
		[audioRequest setShouldReportPartialResults:YES];
		[audioRequest setRequiresOnDeviceRecognition:YES];
		request = audioRequest;

		task = [recognizer
				recognitionTaskWithRequest:audioRequest
						  resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
			 if(result != nil) {
				 self->lastResult = [NSDate date];
				 [self heard:[[result bestTranscription] formattedString]];
			 }
			 /* A final result means this task is over and the audio after it goes
				nowhere. That, not the error case, is what made the cat deaf for
				stretches: Speech decides a sentence has ended, and without a new
				task the next "Neko" is heard by nobody. */
			 if(self->running && (error != nil || (result != nil && [result isFinal])))
				 [self performSelectorOnMainThread:@selector(renewNow)
										withObject:nil waitUntilDone:NO];
		 }];
	}
}

- (void)endTask
{
	if(@available(macOS 10.15, *)) {
		[request endAudio];
		[task cancel];
	}
	request = nil;
	task = nil;
}

- (void)renewNow
{
	[self renew:nil];
}

/* The new request is put in place before the old task is told to stop, so the
   tap is never appending to nothing: a gap here is a word missed. */
- (void)renew:(NSTimer *)timer
{
	if(!running)
		return;
	id oldRequest = request;
	id oldTask = task;
	request = nil;
	task = nil;
	[self beginTask];

	if(@available(macOS 10.15, *)) {
		[(SFSpeechAudioBufferRecognitionRequest *)oldRequest endAudio];
		[(SFSpeechRecognitionTask *)oldTask cancel];
	}

	lastResult = [NSDate date];
}

/* A task can also stop saying anything at all without ever finishing. Twenty
   seconds of silence from the recogniser — not from the room — and it is
   rebuilt. */
- (void)checkAlive:(NSTimer *)timer
{
	if(!running || lastResult == nil)
		return;
	if(-[lastResult timeIntervalSinceNow] > 20.0)
		[self renew:nil];
}

- (void)stop
{
	[renewal invalidate];
	renewal = nil;
	[watchdog invalidate];
	watchdog = nil;
	[resume invalidate];
	resume = nil;
	if(@available(macOS 10.15, *)) {
		[engine stop];
		[[engine inputNode] removeTapOnBus:0];
	}
	[self endTask];
	engine = nil;
	recognizer = nil;
	running = NO;
}

#pragma mark Hearing it

- (void)heard:(NSString *)text
{
	if(!running || ![NekoWakeWord textNamesTheCat:text])
		return;
	if(lastHeard != nil && -[lastHeard timeIntervalSinceNow] < NekoWakeCooldown)
		return;
	lastHeard = [NSDate date];

	NekoAsk *ask = [NekoAsk sharedAsk];
	if([ask isBusy] || [ask isSpeaking])
		return;

	/* The microphone cannot be held by two things at once, and the cat is about
	   to want it: stop, hand over, and pick it up again when the conversation is
	   over. */
	[self stop];
	[ask toggle:nil];
	resume = [NSTimer scheduledTimerWithTimeInterval:1.0
	                                         target:self
	                                       selector:@selector(maybeResume:)
	                                       userInfo:nil
	                                        repeats:YES];
}

- (void)maybeResume:(NSTimer *)timer
{
	NekoAsk *ask = [NekoAsk sharedAsk];
	if([ask isBusy] || [ask isSpeaking])
		return;
	[resume invalidate];
	resume = nil;
	[self applySettings];
}

- (void)dealloc
{
	[self stop];
}

@end
