/* NekoPermissions */

#import <Cocoa/Cocoa.h>

/*! What each permission is doing right now. */
typedef NS_ENUM(int, NekoPermissionState) {
	NekoPermissionUnknown = 0,   /*!< never asked; asking is possible */
	NekoPermissionGranted,
	NekoPermissionDenied,        /*!< refused once: only System Settings can undo it */
	NekoPermissionUnavailable    /*!< this Mac cannot offer it at all */
};

/*! One thing macOS can allow or refuse, and what it costs the app when refused.

   Neko asks for five, none of them at launch and none of them unless a feature
   that needs it is switched on. Gathered in one place because five scattered
   prompts, each arriving weeks apart in the middle of something else, is how an
   app ends up with a permission the user cannot remember granting. */
@interface NekoPermission : NSObject
{
	NSString *identifier;
}

- (id)initWithIdentifier:(NSString *)key;

@property (readonly, copy) NSString *identifier;
@property (readonly, copy, nonatomic) NSString *name;
- (NSString *)identifier;
- (NSString *)name;          /*!< "Microphone" */
- (NSString *)explanation;   /*!< what stops working without it */
- (NekoPermissionState)permissionState;

/*! Whether this one is needed for what is currently switched on. A permission
   nothing uses is worth showing, but not worth nagging about. */
- (BOOL)isNeeded;

/*! Asks the system, where the system still allows asking. NO when the only way
   left is System Settings. */
- (BOOL)canRequest;
- (void)request;

/*! Opens the right pane of System Settings, for when asking is no longer
   possible. */
- (void)openSettings;

@end


@interface NekoPermissions : NSObject

/*! All of them, in the order they matter. */
+ (NSArray<NekoPermission*> *)all;

/*! Everything that is switched on but not allowed. */
+ (NSArray<NekoPermission*> *)missing;

@end
