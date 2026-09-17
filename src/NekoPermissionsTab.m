#import "NekoPermissionsTab.h"
#import "NekoController.h"
#import "NekoPermissions.h"
#import "NekoPlace.h"
#import "NekoPlayer.h"

@implementation NekoPermissionsTab

- (void)buildInView:(NSView *)view
{
	content = view;
	[self rebuild];
}

/* Its own, rather than the controller's: a tab that has to be handed a helper to
   draw a label is a tab that has not really moved. */
- (NSTextField *)labelWithString:(NSString *)string frame:(NSRect)frame
{
	NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
	[label setStringValue:string];
	[label setBezeled:NO];
	[label setDrawsBackground:NO];
	[label setEditable:NO];
	[label setSelectable:NO];
	[label setAlignment:NSTextAlignmentRight];
	return label;
}

- (void)rebuild
{
	/* Told rather than polled: the answer to a location dialog arrives whole
	   seconds after the button was pressed, and a tab rebuilt on a timer shows
	   the state from before the person answered. */
	[[NSNotificationCenter defaultCenter] removeObserver:self
	                                               name:NekoPlaceDidChangeNotification
	                                             object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                        selector:@selector(rebuild)
	                                            name:NekoPlaceDidChangeNotification
	                                          object:nil];
	/* The same shape for the players: the answer arrives when somebody has read
	   the system's prompt, which is long after this row was drawn. */
	[[NSNotificationCenter defaultCenter] removeObserver:self
	                                               name:NekoPlayerConsentDidChangeNotification
	                                             object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                        selector:@selector(rebuild)
	                                            name:NekoPlayerConsentDidChangeNotification
	                                          object:nil];

	NSEnumerator *old = [[[[content subviews] copy] autorelease] objectEnumerator];
	NSView *view;
	while((view = [old nextObject]) != nil)
		[view removeFromSuperview];

	/* Two lines' worth: this line names whichever permissions are missing, and
	   in Italian two names already do not fit on one. It cannot be any wider —
	   the two buttons start at 316. */
	summary = [self labelWithString:@""
	                                     frame:NSMakeRect(20.0f, 372.0f, 288.0f, 32.0f)];
	[summary setAlignment:NSTextAlignmentLeft];
	[content addSubview:summary];

	/* Six rows now, and a seventh would not fit either: the list scrolls rather
	   than being squeezed until the explanations are cut off. Which is what
	   happened when the location row was added — the last row's paragraph ended
	   up nine points below the bottom of the tab. */
	CGFloat rowHeight = 88.0f;
	NSArray<NekoPermission*> *permissions = [NekoPermissions all];
	CGFloat documentHeight = MAX((CGFloat)[permissions count] * rowHeight, 300.0);
	NSScrollView *scroll = [[NSScrollView alloc]
		initWithFrame:NSMakeRect(16.0, 60.0, 568.0, 300.0)];
	[scroll setHasVerticalScroller:YES];
	[scroll setDrawsBackground:NO];
	[scroll setBorderType:NSNoBorder];
	NSView *rows = [[[NSView alloc]
		initWithFrame:NSMakeRect(0.0, 0.0, 548.0, documentHeight)] autorelease];
	[scroll setDocumentView:rows];
	[content addSubview:scroll];
	[scroll release];

	NSUInteger index = 0;
	NSEnumerator *e = [permissions objectEnumerator];
	NekoPermission *permission;
	for(permission in e) {
		/* Measured down from the top of the list, which is where somebody reads
		   from. */
		CGFloat top = documentHeight - (CGFloat)index * rowHeight;
		index++;

		NekoPermissionState state = [permission permissionState];
		NSString *mark = state == NekoPermissionGranted ? @"●"
			: (state == NekoPermissionDenied ? @"✕"
			: (state == NekoPermissionUnavailable ? @"–" : @"○"));
		NSTextField *dot = [self labelWithString:mark
		                                   frame:NSMakeRect(4.0f, top - 17.0f, 16.0f, 17.0f)];
		[dot setTextColor:state == NekoPermissionGranted ? [NSColor systemGreenColor]
			: (state == NekoPermissionDenied ? [NSColor systemRedColor]
			                                 : [NSColor secondaryLabelColor])];
		[rows addSubview:dot];

		NSTextField *title = [self labelWithString:[permission name]
		                                     frame:NSMakeRect(26.0f, top - 17.0f, 320.0f, 17.0f)];
		[title setAlignment:NSTextAlignmentLeft];
		[title setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
		[rows addSubview:title];

		NSString *word = state == NekoPermissionGranted ? NSLocalizedString(@"allowed", @"allowed")
			: (state == NekoPermissionDenied ? NSLocalizedString(@"refused", @"refused")
			: (state == NekoPermissionUnavailable ? NSLocalizedString(@"not on this Mac", @"not on this Mac")
			                                      : NSLocalizedString(@"not asked yet", @"not asked yet")));
		if([permission isNeeded] && state != NekoPermissionGranted)
			word = [word stringByAppendingString:NSLocalizedString(@" — needed for what is switched on", @" - needed for what is switched on")];
		NSTextField *status = [self labelWithString:word
		                                      frame:NSMakeRect(26.0f, top - 34.0f, 420.0f, 15.0f)];
		[status setAlignment:NSTextAlignmentLeft];
		[status setFont:[NSFont systemFontOfSize:11.0f]];
		[status setTextColor:[NSColor secondaryLabelColor]];
		[rows addSubview:status];

		NSTextField *why = [self labelWithString:[permission explanation]
		                                   frame:NSMakeRect(26.0f, top - 82.0f, 420.0f, 46.0f)];
		[why setAlignment:NSTextAlignmentLeft];
		[why setFont:[NSFont systemFontOfSize:11.0f]];
		[[why cell] setWraps:YES];
		[rows addSubview:why];

		if(state != NekoPermissionGranted && state != NekoPermissionUnavailable) {
			NSButton *button = [[NSButton alloc]
				initWithFrame:NSMakeRect(452.0f, top - 28.0f, 92.0f, 28.0f)];
			[button setBezelStyle:NSBezelStyleRounded];
			[button setControlSize:NSControlSizeSmall];
			[button setTitle:[permission canRequest] ? NSLocalizedString(@"Ask", @"Ask")
			                                         : NSLocalizedString(@"Settings…", @"Settings…")];
			[button setTarget:self];
			[button setAction:@selector(permissionPressed:)];
			[button setTag:(NSInteger)[permissions indexOfObject:permission]];
			[button setIdentifier:[permission identifier]];
			[rows addSubview:button];
			[button release];
		}
	}
	/* The top of the list, not the bottom of it. */
	[rows scrollRectToVisible:NSMakeRect(0.0f, documentHeight - 1.0f, 548.0f, 1.0f)];

	NSTextField *note = [self labelWithString:
		NSLocalizedString(@"macOS applies a change to screen recording only after Neko is restarted. And because this build is signed ad hoc, every rebuild of the app is a different app as far as the system is concerned: permissions granted to the previous one have to be granted again.", @"macOS applies a change to screen recording only after Neko is restarted. And because this build is signed ad hoc, every rebuild of the app is a different app as far as the system is concerned: permissions granted to the previous one have to be granted again.")
	                                    frame:NSMakeRect(20.0f, 10.0f, 556.0f, 44.0f)];
	[note setAlignment:NSTextAlignmentLeft];
	[note setFont:[NSFont systemFontOfSize:11.0f]];
	[[note cell] setWraps:YES];
	[note setTextColor:[NSColor secondaryLabelColor]];
	[content addSubview:note];

	NSButton *relaunch = [[NSButton alloc] initWithFrame:NSMakeRect(452.0f, 378.0f, 130.0f, 28.0f)];
	[relaunch setBezelStyle:NSBezelStyleRounded];
	[relaunch setTitle:NSLocalizedString(@"Restart Neko", @"Restart Neko")];
	[relaunch setTarget:self];
	[relaunch setAction:@selector(relaunchPressed:)];
	[content addSubview:relaunch];
	[relaunch release];

	NSButton *refresh = [[NSButton alloc] initWithFrame:NSMakeRect(316.0f, 378.0f, 130.0f, 28.0f)];
	[refresh setBezelStyle:NSBezelStyleRounded];
	[refresh setTitle:NSLocalizedString(@"Check again", @"Check again")];
	[refresh setTarget:self];
	[refresh setAction:@selector(rebuild)];
	[content addSubview:refresh];
	[refresh release];

	[self refreshSummary];
}

/* Screen recording, and one or two of the others, only take effect on a fresh
   launch: rather than explaining that, the app can do it. */
- (void)relaunchPressed:(id)sender
{
	NSURL *me = [[NSBundle mainBundle] bundleURL];
	NSTask *task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath:@"/usr/bin/open"];
	[task setArguments:[NSArray arrayWithObjects:@"-n", [me path], nil]];
	NS_DURING
		[task launch];
	NS_HANDLER
		return;
	NS_ENDHANDLER
	[NSApp terminate:nil];
}

- (void)refreshSummary
{
	NSArray *missing = [NekoPermissions missing];
	if([missing count] == 0) {
		[summary setStringValue:
			NSLocalizedString(@"Everything switched on has what it needs.", @"Everything switched on has what it needs.")];
		[summary setTextColor:[NSColor labelColor]];
		return;
	}
	NSMutableArray *names = [NSMutableArray array];
	NSEnumerator *e = [missing objectEnumerator];
	NekoPermission *permission;
	while((permission = [e nextObject]) != nil)
		[names addObject:[permission name]];
	[summary setStringValue:[NSString stringWithFormat:
		NSLocalizedString(@"Switched on but not allowed: %@.", @"Switched on but not allowed: %@."),
		[names componentsJoinedByString:@", "]]];
	[summary setTextColor:[NSColor systemRedColor]];
}

/* Asking is asynchronous and the answer arrives in a system dialogue, so the
   row is redrawn a moment later rather than immediately. */
- (void)permissionPressed:(id)sender
{
	NSString *key = [sender identifier];
	/* Folders are not one permission but six, so the button asks which — the
	   same menu the Ask Neko tab uses. */
	if([key isEqualToString:@"folders"]) {
		[[NekoController sharedController] showFolderPressed:sender];
		[self performSelector:@selector(rebuild) withObject:nil afterDelay:0.5];
		return;
	}
	NSEnumerator *e = [[NekoPermissions all] objectEnumerator];
	NekoPermission *permission;
	while((permission = [e nextObject]) != nil) {
		if(![[permission identifier] isEqualToString:key])
			continue;
		if([permission canRequest])
			[permission request];
		else
			[permission openSettings];
		break;
	}
	[self performSelector:@selector(rebuild) withObject:nil afterDelay:1.5];
}

@end
