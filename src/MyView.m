#import "MyView.h"

@implementation MyView

- (id)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect]) != nil) {
		image = nil;
	}
	return self;
}

/* Owned, because it is drawn later and from somewhere else. Held without a retain
   it was fine for eighteen years and crashed the moment a plugin could be switched
   on: that releases the character list, the panel lets go of the frames it was
   holding, and the next redraw sent a message to a freed image. Two crash reports,
   both EXC_BAD_ACCESS inside this method's one message send. */
- (void)setImage:(NSImage*)theImage
{
	if(image == theImage)
		return;
	image = theImage;
	[self setNeedsDisplay:YES];
}

@synthesize image;

- (void)drawRect:(NSRect)rect
{
    if(image) {
        [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationNone];
		/* drawn into the whole view so the cat scales with the panel */
		[image drawInRect:[self bounds] fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1.0f];
    }
	//printf("draw %d\n", image);
}

@end
