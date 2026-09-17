/* NekoCharacter */

#import <Cocoa/Cocoa.h>

/* One animation state of the cat. The order is the order of the states in a
   character manifest and is not persisted anywhere. */
typedef enum {
	NekoStateStop = 0,
	NekoStateJare,
	NekoStateKaki,
	NekoStateAkubi,
	NekoStateSleep,
	NekoStateAwake,
	NekoStateUMove,
	NekoStateDMove,
	NekoStateLMove,
	NekoStateRMove,
	NekoStateULMove,
	NekoStateURMove,
	NekoStateDLMove,
	NekoStateDRMove,
	NekoStateUTogi,
	NekoStateDTogi,
	NekoStateLTogi,
	NekoStateRTogi,
	NekoStateCount
} NekoState;

/* A set of sprites loaded from a Foo.nekochar folder inside Resources/Characters.
   The folder holds a character.plist manifest plus one image per frame:

       Identifier    "neko"                 (unique, stored in the preferences)
       Name          "Neko"                 (shown in the menu)
       SpriteWidth   32
       SpriteHeight  32
       States        { sleep = { Frames = (sleep1.gif, ...); TicksPerFrame = 4; }; ... }

   A manifest only has to describe the "stop" state; anything missing falls back
   to a related state, so a partial character still animates. */
@interface NekoCharacter : NSObject
{
	NSString *identifier;
	NSString *name;
	NSString *persona;
	NSSize spriteSize;
	NSArray *frames[NekoStateCount];
	unsigned ticksPerFrame[NekoStateCount];
}

/* Every character bundled with the app, sorted by name. Never empty unless the
   app resources are broken. */
+ (NSArray<NekoCharacter*> *)availableCharacters;

/* Thrown away when a plugin is switched on or off, since plugins can ship
   characters and the list is cached. */
+ (void)forgetTheList;

/* The character with that identifier, or the first available one. */
+ (NekoCharacter *)characterWithIdentifier:(NSString *)theIdentifier;

@property (readonly, copy) NSString *identifier;
@property (readonly, copy) NSString *name;

/* Who this character is, in a phrase, for when it is asked a question. Taken
   from the manifest's Persona key; without one it falls back to being a cat by
   that name, which is what most of them are. */
@property (readonly, copy) NSString *persona;
@property (readonly) NSSize spriteSize;

/* Frames of a state, fallbacks already applied: never nil, never empty. */
- (NSArray<NSImage*> *)framesForState:(NekoState)state;

/* How many 0.125s ticks each frame of a state is held for. */
- (unsigned)ticksPerFrameForState:(NekoState)state;

/* The resting frame, sized and flagged for use in the menu bar. */
- (NSImage *)menuBarImage;

@end
