/* NekoAppleProvider */

#import <Cocoa/Cocoa.h>
#import "NekoAnswerProvider.h"

@class NekoAppleModel;

/*! Apple's on-device model, the one behind Apple Intelligence.

   Nothing leaves the Mac, there is no key and there is no bill. It exists only
   on macOS 26 and later, on hardware that supports Apple Intelligence, with the
   feature switched on; when any of that is missing the preferences say which.

   The model itself is reached through NekoAppleModel, the single Swift file in
   this project — FoundationModels ships no headers, so a Swift shim is the only
   way in. */
@interface NekoAppleProvider : NSObject <NekoAnswerProvider>
{
	NekoAppleModel *model;                    /* NekoAppleModel */
}

+ (BOOL)isSupported;
@property (class, readonly, getter=isSupported) BOOL supported;

@end
