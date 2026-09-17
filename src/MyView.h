/* MyView */

#import <Cocoa/Cocoa.h>

@interface MyView : NSView
{
	NSImage *image;
}

@property (nonatomic, strong) NSImage *image;
- (void)setImageTo:(NSImage*)theImage API_DEPRECATED_WITH_REPLACEMENT("-setImage:", macos(10.0,10.0));

@end
