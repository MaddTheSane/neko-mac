#import "NekoLine.h"

static const CGFloat NekoLineWidth = 320.0f;
static const CGFloat NekoLinePadding = 10.0f;
static const CGFloat NekoLineRadius = 10.0f;
static const CGFloat NekoLineGap = 6.0f;

/* The same rounded body as the bubble, without the tail: a field with a tail
   pointing at the cat reads as something the cat said, and this is something
   the cat is waiting to be told. */
@interface NekoLineView : NSView
@end

@implementation NekoLineView

- (BOOL)isOpaque
{
	return NO;
}

- (void)drawRect:(NSRect)dirty
{
	NSBezierPath *path = [NSBezierPath
		bezierPathWithRoundedRect:NSInsetRect([self bounds], 0.5f, 0.5f)
		                  xRadius:NekoLineRadius
		                  yRadius:NekoLineRadius];
	[[NSColor windowBackgroundColor] setFill];
	[path fill];
	[[[NSColor labelColor] colorWithAlphaComponent:0.20f] setStroke];
	[path setLineWidth:1.0f];
	[path stroke];
}

@end

@implementation NekoLine

- (id)init
{
	if (self = [super initWithContentRect:NSMakeRect(0.0, 0.0, NekoLineWidth, 44.0)
	                       styleMask:NSWindowStyleMaskBorderless
	                         backing:NSBackingStoreBuffered
									defer:NO]) {
		[self setOpaque:NO];
		[self setBackgroundColor:[NSColor clearColor]];
		[self setHasShadow:YES];
		[self setLevel:NSStatusWindowLevel + 1];
		[self setCollectionBehavior:(NSWindowCollectionBehaviorCanJoinAllSpaces
									 | NSWindowCollectionBehaviorStationary
									 | NSWindowCollectionBehaviorIgnoresCycle
									 | NSWindowCollectionBehaviorFullScreenAuxiliary)];
		[self setCanHide:NO];
		[self setHidesOnDeactivate:NO];
		[self setContentView:[[[NekoLineView alloc] initWithFrame:NSZeroRect] autorelease]];
		
		field = [[NSTextField alloc] initWithFrame:NSZeroRect];
		[field setBezelStyle:NSTextFieldRoundedBezel];
		[field setBezeled:YES];
		[field setFont:[NSFont systemFontOfSize:0.0]];
		[field setDelegate:self];
		[field setTarget:self];
		[field setAction:@selector(sendIt:)];
		[[self contentView] addSubview:field];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[field release];
	[finished release];
	[previous release];
	[super dealloc];
}

/* Borderless windows say no by default, and a window that cannot become key
   cannot be typed into. */
- (BOOL)canBecomeKeyWindow
{
	return YES;
}

- (BOOL)isShowing
{
	return [self isVisible];
}

- (void)askNearRect:(NSRect)catFrame
        placeholder:(NSString *)placeholder
           finished:(void (^)(NSString *typed))block
{
	[finished release];
	finished = [block copy];
	closing = NO;

	[field setStringValue:@""];
	[[field cell] setPlaceholderString:(placeholder ?: @"")];

	CGFloat height = 44.0f;
	NSScreen *screen = [self screenFor:catFrame];
	NSRect visible = [screen visibleFrame];
	CGFloat y = NSMaxY(catFrame) + NekoLineGap + height <= NSMaxY(visible)
		  ? NSMaxY(catFrame) + NekoLineGap
		  : NSMinY(catFrame) - NekoLineGap - height;
	CGFloat x = NSMidX(catFrame) - NekoLineWidth / 2.0;
	x = MIN(MAX(x, NSMinX(visible) + 4.0), NSMaxX(visible) - NekoLineWidth - 4.0);
	y = MIN(MAX(y, NSMinY(visible) + 4.0), NSMaxY(visible) - height - 4.0);
	[self setFrame:NSMakeRect(x, y, NekoLineWidth, height) display:NO];
	[field setFrame:NSMakeRect(NekoLinePadding, NekoLinePadding,
	                           NekoLineWidth - 2.0 * NekoLinePadding, 24.0)];

	/* Remembered before the theft, not after. */
	[previous release];
	previous = [[[NSWorkspace sharedWorkspace] frontmostApplication] retain];
	if([previous isEqual:[NSRunningApplication currentApplication]]) {
		[previous release];
		previous = nil;
	}

	/* Activation is a request, not an instruction: it arrives when the system
	   gets round to it, and a window ordered front before the application became
	   active does not have the keyboard. So the window asks once now and again
	   the moment activation actually lands. */
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(insist:)
	                                             name:NSApplicationDidBecomeActiveNotification
	                                           object:nil];
	[NSApp activateIgnoringOtherApps:YES];
	[self makeKeyAndOrderFront:nil];
	[self makeFirstResponder:field];
}

- (void)insist:(NSNotification *)note
{
	if(![self isVisible] || closing)
		return;
	[self makeKeyAndOrderFront:nil];
	[self makeFirstResponder:field];
}

- (NSScreen *)screenFor:(NSRect)rect
{
	NSEnumerator *e = [[NSScreen screens] objectEnumerator];
	NSScreen *screen;
	while((screen = [e nextObject]) != nil)
		if(NSIntersectsRect([screen frame], rect))
			return screen;
	return [NSScreen mainScreen];
}

#pragma mark Finishing

- (void)sendIt:(id)sender
{
	[self finishWith:[[field stringValue]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
}

- (void)finishWith:(NSString *)typed
{
	if(closing)
		return;
	closing = YES;

	[[NSNotificationCenter defaultCenter] removeObserver:self
	                                               name:NSApplicationDidBecomeActiveNotification
	                                             object:nil];
	void (^block)(NSString *) = [finished retain];
	[finished release];
	finished = nil;

	[self orderOut:nil];
	/* Whatever was being typed in before the keystroke gets the keyboard back,
	   which is the difference between a line to answer in and an interruption. */
	if(previous != nil) {
		[previous activateWithOptions:0];
		[previous release];
		previous = nil;
	}

	if(block != NULL) {
		block([typed length] > 0 ? typed : nil);
		[block release];
	}
}

- (void)close
{
	[self finishWith:nil];
}

/* Escape, and the arrow of last resort: a text field hands both of these to its
   delegate rather than to the window. */
- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)view
doCommandBySelector:(SEL)command
{
	if(command == @selector(cancelOperation:) || command == @selector(complete:)) {
		[self finishWith:nil];
		return YES;
	}
	if(command == @selector(insertNewline:)) {
		[self sendIt:control];
		return YES;
	}
	return NO;
}

/* Clicking into another application while the line is open means it is not
   wanted. Better than leaving a field floating over somebody's work. */
- (void)resignKeyWindow
{
	[super resignKeyWindow];
	if([self isVisible] && !closing)
		[self performSelector:@selector(close) withObject:nil afterDelay:0.0];
}

@end
