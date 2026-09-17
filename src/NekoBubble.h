/* NekoBubble */

#import <Cocoa/Cocoa.h>

/*! What the cat says, in a rounded panel beside it.

   It never becomes the key window: being asked a question should not take the
   focus away from whatever the user was typing in. That also means it cannot
   catch Escape, so it is dismissed by clicking it, by the hotkey, or by its own
   timeout. */
@interface NekoBubble : NSPanel
{
	NSTextField *label;
	NSTextField *hintLabel;      /* the small line under the words */
	NSString *hint;
	NSString *lastText;          /* so a hint can redraw what is already up */
	NSRect lastCat;
	NSImageView *picture;
	NSButton *saveButton;        /* over a drawing, while the pointer is inside */
	NSTrackingArea *hover;
	NSButton *yesButton;
	NSButton *noButton;
	void (^decision)(BOOL yes);
	NSTimer *dismissal;
	__unsafe_unretained id owner;                    /* not retained */
	SEL dismissedAction;
}

- (id)init;

/* Places the bubble against the cat's frame, flipping below and sliding
   sideways as the screen requires. Pass 0 to leave it up until told. */
- (void)showText:(NSString *)text
        nearRect:(NSRect)catFrame
    dismissAfter:(NSTimeInterval)seconds;

/* The same, with a drawing above the words. Pass nil for either. */
- (void)showText:(NSString *)text
         picture:(NSImage *)image
        nearRect:(NSRect)catFrame
    dismissAfter:(NSTimeInterval)seconds;

/* Asks something with two buttons under it and waits. Nothing happens until one
   of them is clicked or the bubble is dismissed, which counts as no. */
- (void)askText:(NSString *)text
       nearRect:(NSRect)catFrame
        decided:(void (^)(BOOL yes))block;

/*! A small dim line under the words, for saying what the app is doing rather
   than what the cat is saying: "listening" while the microphone is open. Set it
   before showing something; it lasts until it is set to nil. */
@property (nonatomic, copy) NSString *hint;

/* How long is left before it goes away on its own, and a way to give it longer.
   Used when the microphone stays open after the words: the sign that says so
   has to be on screen for as long as the microphone is. */
- (NSTimeInterval)secondsLeft;
- (void)keepUpFor:(NSTimeInterval)seconds;

- (void)hide;
- (BOOL)isShowing;

/* Called when the user clicks the bubble away. */
- (void)setDismissalTarget:(id)target action:(SEL)action;

/* How long a piece of text deserves to stay up. */
+ (NSTimeInterval)readingTimeFor:(NSString *)text;

@end
