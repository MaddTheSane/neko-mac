/* NekoHotKey */

#import <Cocoa/Cocoa.h>

/* A system-wide keystroke.

   Carbon's RegisterEventHotKey is used rather than an event monitor on purpose:
   registering a hotkey needs no permission and works inside the App Sandbox,
   while monitoring keystrokes would ask the user for Accessibility. It also
   means a combination already taken by another application fails loudly instead
   of silently doing nothing. */
@interface NekoHotKey : NSObject
{
	__unsafe_unretained id target;                   /* not retained */
	SEL action;
	SEL releaseAction;           /* optional: the key going back up */
	void *reference;             /* EventHotKeyRef */
	unsigned identifier;
	unsigned short keyCode;
	NSEventModifierFlags modifiers;        /* NSEventModifierFlags */
}

- (instancetype)initWithTarget:(id)aTarget action:(SEL)anAction;

/* Told when the key is let go as well as when it goes down, which is how a
   press and a hold tell themselves apart. Carbon reports both; nothing else
   about the registration changes. */
- (void)setReleaseAction:(SEL)anAction;

/* NO when the combination is already taken, or is missing a modifier. */
- (BOOL)registerKeyCode:(unsigned short)code modifiers:(NSEventModifierFlags)flags;
- (void)unregister;
@property (readonly, getter=isRegistered) BOOL registered;

@property (readonly) unsigned short keyCode;
@property (readonly) NSEventModifierFlags modifiers;

/* "⌃⌥N", for the preferences. */
- (NSString *)displayName;
+ (NSString *)displayNameForKeyCode:(unsigned short)code modifiers:(NSEventModifierFlags)flags;

/* Control-Option-N. */
@property (class, readonly) unsigned short defaultKeyCode;
@property (class, readonly) NSEventModifierFlags defaultModifiers;

@end
