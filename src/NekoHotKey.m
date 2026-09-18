#import "NekoHotKey.h"
#include <Carbon/Carbon.h>

static NSMutableDictionary *NekoHotKeysByIdentifier = nil;
static unsigned NekoNextHotKeyIdentifier = 1;

@interface NekoHotKey ()
- (void)fireRelease;
@end

static OSStatus NekoHotKeyHandler(EventHandlerCallRef call, EventRef event, void *context)
{
	EventHotKeyID pressed;
	if(GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL,
	                     sizeof(pressed), NULL, &pressed) != noErr)
		return eventNotHandledErr;

	NekoHotKey *hotKey = [NekoHotKeysByIdentifier
		objectForKey:[NSNumber numberWithUnsignedInt:pressed.id]];
	if(hotKey == nil)
		return eventNotHandledErr;
	if(GetEventKind(event) == kEventHotKeyReleased) {
		[hotKey performSelector:@selector(fireRelease)];
		return noErr;
	}
	[hotKey performSelector:@selector(fire)];
	return noErr;
}

@implementation NekoHotKey

+ (void)initialize
{
	if(self != [NekoHotKey class])
		return;
	NekoHotKeysByIdentifier = [[NSMutableDictionary alloc] init];
	EventTypeSpec specs[] = {
		{ kEventClassKeyboard, kEventHotKeyPressed },
		{ kEventClassKeyboard, kEventHotKeyReleased }
	};
	InstallApplicationEventHandler(&NekoHotKeyHandler, 2, specs, NULL, NULL);
}

+ (unsigned short)defaultKeyCode
{
	return 0x2D;                 /* kVK_ANSI_N */
}

+ (NSEventModifierFlags)defaultModifiers
{
	return NSEventModifierFlagControl | NSEventModifierFlagOption;
}

- (id)initWithTarget:(id)aTarget action:(SEL)anAction
{
	if((self = [super init]) != nil) {
		target = aTarget;
		action = anAction;
		identifier = NekoNextHotKeyIdentifier++;
	}
	return self;
}

- (void)dealloc
{
	[self unregister];
	[super dealloc];
}

- (void)setReleaseAction:(SEL)anAction
{
	releaseAction = anAction;
}

- (void)fire
{
	[target performSelector:action withObject:self];
}

- (void)fireRelease
{
	if(releaseAction != NULL)
		[target performSelector:releaseAction withObject:self];
}

#pragma mark Registration

static UInt32 carbonModifiers(NSEventModifierFlags flags)
{
	UInt32 carbon = 0;
	if(flags & NSEventModifierFlagCommand)  carbon |= cmdKey;
	if(flags & NSEventModifierFlagShift)    carbon |= shiftKey;
	if(flags & NSEventModifierFlagOption)   carbon |= optionKey;
	if(flags & NSEventModifierFlagControl)  carbon |= controlKey;
	return carbon;
}

- (BOOL)registerKeyCode:(unsigned short)code modifiers:(NSEventModifierFlags)flags
{
	[self unregister];

	UInt32 carbon = carbonModifiers(flags);
	if(carbon == 0)
		return NO;               /* a bare key would swallow ordinary typing */

	EventHotKeyRef ref = NULL;
	EventHotKeyID hotID = { 'NEKO', identifier };
	OSStatus err = RegisterEventHotKey(code, carbon, hotID,
	                                   GetApplicationEventTarget(), 0, &ref);
	if(err != noErr)
		return NO;               /* almost always: someone else has it */

	reference = ref;
	keyCode = code;
	modifiers = flags;
	[NekoHotKeysByIdentifier setObject:self
	                           forKey:[NSNumber numberWithUnsignedInt:identifier]];
	return YES;
}

- (void)unregister
{
	if(reference != NULL) {
		UnregisterEventHotKey((EventHotKeyRef)reference);
		reference = NULL;
	}
	[NekoHotKeysByIdentifier removeObjectForKey:
		[NSNumber numberWithUnsignedInt:identifier]];
}

- (BOOL)isRegistered
{
	return reference != NULL;
}

@synthesize keyCode;
@synthesize modifiers;

#pragma mark Showing it to the user

/* Enough of the ANSI layout for anything someone would choose as a shortcut. */
+ (NSString *)nameForKeyCode:(unsigned short)code
{
	/* One byte per key code, in kVK_ANSI order. The section key is a filler
	   here: a multi-byte character in this string would shift every code after
	   it, which is exactly the bug this comment replaces. */
	static const char letters[] = "asdfhgzxcv\1bqweryt123465=97-80]ou[ip\1lj'k;\\,/nm.";
	if(code < sizeof(letters) - 1 && letters[code] > ' ') {
		char c = letters[code];
		return [[NSString stringWithFormat:@"%c", c] uppercaseString];
	}
	switch(code) {
		case 0x0A: return @"§";
		case 0x31: return @"Space";
		case 0x24: return @"Return";
		case 0x30: return @"Tab";
		case 0x35: return @"Esc";
		case 0x7A: return @"F1";
		case 0x78: return @"F2";
		case 0x63: return @"F3";
		case 0x76: return @"F4";
		case 0x60: return @"F5";
		case 0x61: return @"F6";
		default:   return [NSString stringWithFormat:@"#%u", code];
	}
}

+ (NSString *)displayNameForKeyCode:(unsigned short)code modifiers:(NSEventModifierFlags)flags
{
	NSMutableString *name = [NSMutableString string];
	if(flags & NSEventModifierFlagControl) [name appendString:@"⌃"];
	if(flags & NSEventModifierFlagOption)  [name appendString:@"⌥"];
	if(flags & NSEventModifierFlagShift)   [name appendString:@"⇧"];
	if(flags & NSEventModifierFlagCommand) [name appendString:@"⌘"];
	[name appendString:[self nameForKeyCode:code]];
	return name;
}

- (NSString *)displayName
{
	return [NekoHotKey displayNameForKeyCode:keyCode modifiers:modifiers];
}

@end
