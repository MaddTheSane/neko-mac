/* NekoWakeWord */

#import <Cocoa/Cocoa.h>

@class SFSpeechRecognizer, SFSpeechAudioBufferRecognitionRequest;
@class SFSpeechRecognitionTask, AVAudioEngine;

/* BOOL: keep the microphone open and listen for the cat's name. Off unless
   asked for, and it says what it costs before it is. */
extern NSString * const NekoWakeWordKey;

/* Listening for "Neko", and for nothing else.

   This is the one part of the app that holds the microphone open, which is why
   it is a switch of its own rather than a detail of Ask Neko: the orange
   recording light in the menu bar stays on the whole time it runs, and the
   battery notices. What it does with the audio is the important half — the
   recogniser is told to stay on this Mac, and if this Mac cannot recognise the
   language without a server, the feature refuses to run rather than quietly
   streaming a room to one.

   Nothing is written down. The rolling transcript is looked at for one word and
   thrown away, the recognition task is torn down and rebuilt every fifty
   seconds because Speech ends one of its own accord at about a minute, and
   while a question is actually being handled the wake word stops listening
   altogether — otherwise the cat's own answer, read aloud, wakes it up again. */
@interface NekoWakeWord : NSObject
{
	SFSpeechRecognizer *recognizer;
	SFSpeechAudioBufferRecognitionRequest *request;
	SFSpeechRecognitionTask *task;
	AVAudioEngine *engine;                   
	NSTimer *renewal;            /* rebuilds the task before Speech drops it */
	NSTimer *watchdog;           /* and again if it went quiet without saying so */
	NSTimer *resume;             /* waits for the conversation to finish */
	NSDate *lastHeard;
	NSDate *lastResult;          /* when the recogniser last said anything */
	BOOL running;
	BOOL asking;                 /* a permission request is in flight */
}

+ (NekoWakeWord *)sharedWakeWord;

/* Whether this Mac can do it at all: Speech present, and able to recognise the
   interface language without sending the audio anywhere. */
+ (BOOL)isAvailable;
+ (NSString *)unavailableReason;

/* Starts or stops to match the settings. */
- (void)applySettings;

/* Lets the microphone go without changing the setting: -applySettings picks it
   up again. */
- (void)stop;

- (BOOL)isListening;

/* YES while the recogniser is actually producing results. */
- (BOOL)isHearing;

/* The matcher, which is worth testing on its own: speech recognisers spell the
   cat's name several ways, and none of them is the one in the dictionary. */
+ (BOOL)textNamesTheCat:(NSString *)text;

@end
