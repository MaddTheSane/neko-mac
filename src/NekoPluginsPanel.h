/* NekoPluginsPanel */

#import <Cocoa/Cocoa.h>

/*! The plugins window.

   Its own window rather than a seventh tab in the preferences, for two reasons.
   The preferences are settings — things about how the cat behaves — and a plugin
   is not a setting, it is a thing somebody installed. And this window has to say
   more than a tab has room for: what each plugin adds, what it is allowed to do,
   why a refused one was refused, and the sentence about what none of them can
   reach. That paragraph belongs where somebody is deciding whether to trust a
   folder they downloaded. */
@interface NekoPluginsPanel : NSWindowController
{
	NSScrollView *scroll;
	NSView *rows;
	NSTextField *nothingYet;
}

+ (NekoPluginsPanel *)sharedPanel;
@property (readonly, class, retain) NekoPluginsPanel *sharedPanel;

/*! Opens it, brings it forward, and redraws it from what is installed. */
- (IBAction)show:(id)sender;

/*! What the Add… button does. Public so a test can drive it without a mouse. */
- (IBAction)addPressed:(id)sender;

@end
