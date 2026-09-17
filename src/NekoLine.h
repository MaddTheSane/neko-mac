/* NekoLine */

#import <Cocoa/Cocoa.h>

/*! One line to type, beside the cat.

   The other half of being answerable. Speaking is quicker, but it is not always
   available: an open-plan office, a meeting, a Mac with the microphone denied,
   or a word the recogniser will never get right. Holding the keystroke opens
   this instead — a single field, Return to send, Escape to forget it.

   Unlike the bubble, this one has to take the keyboard focus: there is no way to
   type into a window that cannot become key. It gives the focus back to whatever
   application had it, which is the least it can do for having taken it. */
@interface NekoLine : NSPanel <NSTextFieldDelegate>
{
	NSTextField *field;
	void (^finished)(NSString *typed);
	NSRunningApplication *previous;   /* whoever we took the keyboard from */
	BOOL closing;
}

- (id)init;

/*! Opens the line above the cat and waits. The block is called with what was
   typed, or with nil if it was abandoned — Escape, a click elsewhere, or an
   empty line. */
- (void)askNearRect:(NSRect)catFrame
        placeholder:(NSString *)placeholder
           finished:(void (^)(NSString *typed))block;

- (void)close;
- (BOOL)isShowing;

@end
