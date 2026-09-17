/* NekoPermissionsTab */

#import <Cocoa/Cocoa.h>

/*! The Permissions tab: six rows, what each is for, and a button per row.

   Taken out of `NekoController`, which had grown to 2,377 lines and 118 methods
   and was the largest thing in the project by a factor of two. This is the first
   of the five preference tabs to move, and it went first because it was the
   easiest to move honestly: 206 lines with exactly **two** of the controller's
   instance variables in them, against 182 mentions for the local-model tab.

   The pattern is the one that has worked five times already here —
   `NekoPlugins`, `NekoRecall`, `NekoWhen`, `NekoStream`, `NekoGlance`: one
   coherent job, its own header saying why it exists, nothing clever. The other
   four tabs can follow it, and the point of doing one is that the next person can
   see the shape rather than being told about it.

   One thing still reaches back. The folders row is not one permission but six, so
   pressing it opens the same menu the Ask Neko tab uses, which lives in the
   controller. That is a real dependency rather than laziness: the menu belongs
   where the folders are chosen. */
@interface NekoPermissionsTab : NSObject
{
	/*! the tab's own view, not owned */
	__unsafe_unretained NSView *content;
	/*! the line naming what is missing */
	NSTextField *summary;
}

/*! Builds itself into that view and keeps it. Call once. */
- (void)buildInView:(NSView *)view;

/*! Draws the rows again, from what the system says now. Cheap, and called when a
   permission may have changed behind the application's back. */
- (void)rebuild;

@end
