/* NekoListener */

#import <Cocoa/Cocoa.h>

@class SFSpeechRecognizer, SFSpeechAudioBufferRecognitionRequest;
@class SFSpeechRecognitionTask, AVAudioEngine;

/*! Turns what you say into text, and nothing else.

   The microphone opens when listening starts and closes when it stops: there is
   no hot word and no background capture. Recognition runs on the device when
   the language allows it, and says which mode it is in rather than leaving the
   user to guess.

   Speech is weakly linked, since SFSpeechRecognizer arrived in macOS 10.15 and
   this project still builds for older systems, where the whole feature is
   simply unavailable. */
@interface NekoListener : NSObject
{
	SFSpeechRecognizer *recognizer;
	SFSpeechAudioBufferRecognitionRequest *request;
	SFSpeechRecognitionTask *task;
	AVAudioEngine *engine;
	void (^report)(NSString *, BOOL, NSError *);
	NSTimer *silence;
	NSString *heard;
	BOOL onDevice;
}

/*! `NO` on systems without the Speech framework. */
+ (BOOL)isAvailable;

/*! 0 undetermined, 1 denied, 2 restricted, 3 authorised. Reading it prompts
   nobody. */
+ (NSInteger)authorizationStatus;
+ (void)requestAuthorization:(void (^)(BOOL granted))completion;

/*! Starts capturing. The block is called with partial text as it arrives, then
   once more with final set, or with an error. Stops itself after a few seconds
   of silence. */
- (BOOL)startListeningWithLocale:(NSLocale *)locale
                          report:(void (^)(NSString *text, BOOL final, NSError *error))block;

/*! The same, saying how long to hold the microphone open before giving up on a
   sentence that never started. A question deserves fifteen seconds; the moment
   after the cat has spoken deserves a few, and no more. */
- (BOOL)startListeningWithLocale:(NSLocale *)locale
                        patience:(NSTimeInterval)seconds
                          report:(void (^)(NSString *text, BOOL final, NSError *error))block;

/*! Stops the microphone and waits for the last words to be transcribed. */
- (void)stop;

/*! Stops everything and reports nothing. */
- (void)cancel;

- (BOOL)isListening;

/*! Whether the recogniser is keeping the audio on this Mac. */
- (BOOL)isOnDevice;

@end
