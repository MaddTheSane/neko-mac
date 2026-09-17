#import "NekoPluginsPanel.h"
#import "NekoPlugins.h"
#import "NekoPlugin.h"
#import "NekoShortcutProvider.h"

#define NekoPanelLocalized(text) NSLocalizedString(text, nil)

static const CGFloat NekoPanelWidth = 560.0f;
static const CGFloat NekoPanelHeight = 460.0f;
static const CGFloat NekoRowHeight = 86.0f;

@implementation NekoPluginsPanel

+ (NekoPluginsPanel *)sharedPanel
{
	static NekoPluginsPanel *shared = nil;
	if(shared == nil)
		shared = [[NekoPluginsPanel alloc] init];
	return shared;
}

- (id)init
{
	NSPanel *panel = [[[NSPanel alloc]
		initWithContentRect:NSMakeRect(0.0f, 0.0f, NekoPanelWidth, NekoPanelHeight)
		          styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
		                     | NSWindowStyleMaskResizable)
		            backing:NSBackingStoreBuffered
		              defer:NO] autorelease];
	[panel setTitle:NekoPanelLocalized(@"Neko Plugins")];
	[panel setReleasedWhenClosed:NO];
	[panel setHidesOnDeactivate:NO];
	/* Same rule as the preferences: it comes to whichever desktop you are on
	   rather than living where it was first opened. */
	[panel setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
	[panel setMinSize:NSMakeSize(460.0f, 320.0f)];
	[panel center];

	if((self = [super initWithWindow:panel]) != nil) {
		[self build];
		[[NSNotificationCenter defaultCenter]
			addObserver:self selector:@selector(refresh)
			       name:NekoPluginsDidChangeNotification object:nil];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

#pragma mark The window

- (void)build
{
	NSView *content = [[self window] contentView];
	[content setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

	/* The list, which scrolls: a plugin is a folder somebody added, and there is
	   no telling how many. */
	scroll = [[NSScrollView alloc] initWithFrame:
		NSMakeRect(16.0f, 96.0f, NekoPanelWidth - 32.0f, NekoPanelHeight - 128.0f)];
	[scroll setHasVerticalScroller:YES];
	[scroll setDrawsBackground:NO];
	[scroll setBorderType:NSNoBorder];
	[scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	rows = [[[NSView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f,
		NekoPanelWidth - 52.0f, 10.0f)] autorelease];
	[scroll setDocumentView:rows];
	[content addSubview:scroll];
	[scroll release];

	NSButton *add = [[[NSButton alloc] initWithFrame:
		NSMakeRect(16.0f, 56.0f, 140.0f, 30.0f)] autorelease];
	[add setBezelStyle:NSBezelStyleRounded];
	[add setTitle:NekoPanelLocalized(@"Add…")];
	[add setTarget:self];
	[add setAction:@selector(addPressed:)];
	[add setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
	[content addSubview:add];

	NSButton *folder = [[[NSButton alloc] initWithFrame:
		NSMakeRect(164.0f, 56.0f, 180.0f, 30.0f)] autorelease];
	[folder setBezelStyle:NSBezelStyleRounded];
	[folder setTitle:NekoPanelLocalized(@"Show the folder")];
	[folder setTarget:self];
	[folder setAction:@selector(revealFolderPressed:)];
	[folder setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
	[content addSubview:folder];

	/* Only if any shipped. A button that reveals an empty folder is worse than no
	   button. */
	if([[[NekoPlugins sharedPlugins] examples] count] > 0) {
		NSButton *examples = [[[NSButton alloc] initWithFrame:
			NSMakeRect(352.0f, 56.0f, 170.0f, 30.0f)] autorelease];
		[examples setBezelStyle:NSBezelStyleRounded];
		[examples setTitle:NekoPanelLocalized(@"Examples…")];
		[examples setTarget:self];
		[examples setAction:@selector(revealExamplesPressed:)];
		[examples setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
		[content addSubview:examples];
	}

	/* The sentence somebody needs while deciding whether to trust a folder they
	   downloaded, in the place where they are deciding. */
	/* Forty-eight, not forty. At forty the last line of it was two points short
	   of fitting, which tests/layout.m had been printing and nobody had been
	   failing on. */
	NSTextField *footer = [[[NSTextField alloc] initWithFrame:
		NSMakeRect(16.0f, 6.0f, NekoPanelWidth - 32.0f, 48.0f)] autorelease];
	[footer setStringValue:NekoPanelLocalized(@"Plugins live in Neko’s own folder in Application Support. Nothing here runs inside Neko, and nothing here can see your diary, your screen, your files or where you are — or make the cat speak on its own.")];
	[footer setBezeled:NO];
	[footer setDrawsBackground:NO];
	[footer setEditable:NO];
	[footer setSelectable:NO];
	[footer setFont:[NSFont systemFontOfSize:11.0f]];
	[footer setTextColor:[NSColor secondaryLabelColor]];
	[[footer cell] setWraps:YES];
	[footer setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
	[content addSubview:footer];

	[self refresh];
}

- (void)show:(id)sender
{
	[[NekoPlugins sharedPlugins] reload];
	[self refresh];
	[NSApp activateIgnoringOtherApps:YES];
	[[self window] makeKeyAndOrderFront:sender];
}

#pragma mark The rows

- (NSTextField *)labelAt:(NSRect)frame text:(NSString *)text small:(BOOL)small
{
	NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
	[label setStringValue:text ?: @""];
	[label setBezeled:NO];
	[label setDrawsBackground:NO];
	[label setEditable:NO];
	[label setSelectable:NO];
	[[label cell] setWraps:YES];
	if(small) {
		[label setFont:[NSFont systemFontOfSize:11.0f]];
		[label setTextColor:[NSColor secondaryLabelColor]];
	}
	return label;
}

/* How tall the sentence under a plugin's name comes out at this width. The same
   text the row will show, measured with the same font, because a row sized from
   a guess is a row that clips somebody's summary on the day they write a long
   one. */
- (CGFloat)heightOfDetailFor:(NekoPlugin *)plugin width:(CGFloat)width
{
	NSString *what = [plugin isUsable]
		? [NSString stringWithFormat:@"%@ — %@", [plugin describeWhatItAdds],
			[[plugin summary] length] > 0 ? [plugin summary]
				: NekoPanelLocalized(@"no summary")]
		: [plugin refusal];
	NSTextField *ruler = [self labelAt:NSMakeRect(0.0, 0.0, width, 32.0)
	                              text:what small:YES];
	NSSize needed = [[ruler cell] cellSizeForBounds:
		NSMakeRect(0.0, 0.0, width, 10000.0)];
	return MAX(32.0, needed.height + 1.0);
}

- (void)refresh
{
	NSEnumerator *old = [[[[rows subviews] copy] autorelease] objectEnumerator];
	NSView *view;
	while((view = [old nextObject]) != nil)
		[view removeFromSuperview];

	NekoPlugins *registry = [NekoPlugins sharedPlugins];
	NSArray *all = [registry all];
	CGFloat width = NSWidth([rows frame]);

	/* Each row is as tall as its own sentence needs, measured before anything is
	   drawn. It used to be a fixed height with the detail given 32 points of it,
	   which was enough for two lines — and a plugin that adds a route says what
	   it sends off this Mac, which is three. That sentence was being cut in half
	   by the layout, which is a poor place for a disclosure to end. */
	NSMutableArray *heights = [NSMutableArray array];
	CGFloat height = 0.0;
	for(NekoPlugin *measured in all) {
		CGFloat needed = [self heightOfDetailFor:measured width:width - 150.0f];
		CGFloat row = MAX(NekoRowHeight, 52.0f + needed + 16.0f);
		[heights addObject:[NSNumber numberWithFloat:row]];
		height += row;
	}
	height = MAX(height, NSHeight([scroll frame]));
	[rows setFrame:NSMakeRect(0.0f, 0.0f, width, height)];

	if([all count] == 0) {
		[rows addSubview:[self labelAt:NSMakeRect(8.0f, height - 60.0f, width - 16.0f, 40.0f)
		                          text:NekoPanelLocalized(@"Nothing installed. A plugin is a folder whose name ends in .nekoplugin; add one and it arrives switched off.")
		                         small:YES]];
		return;
	}

	NSUInteger index = 0;
	CGFloat spent = 0.0f;
	for(NekoPlugin *plugin in all) {
		CGFloat top = height - spent;
		CGFloat rowHeight = index < [heights count]
			? [[heights objectAtIndex:index] doubleValue] : NekoRowHeight;
		spent += rowHeight;
		index++;

		NSTextField *title = [self labelAt:NSMakeRect(8.0, top - 22.0, width - 150.0, 18.0)
		                              text:[plugin name] small:NO];
		[title setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
		[rows addSubview:title];

		NSString *by = [[plugin author] length] > 0
			? [NSString stringWithFormat:@"%@ · %@", [plugin author], [plugin version]]
			: [plugin version];
		[rows addSubview:[self labelAt:NSMakeRect(8.0, top - 40.0, width - 150.0, 16.0)
		                          text:by small:YES]];

		NSString *what = [plugin isUsable]
			? [NSString stringWithFormat:@"%@ — %@", [plugin describeWhatItAdds],
				[[plugin summary] length] > 0 ? [plugin summary]
					: NekoPanelLocalized(@"no summary")]
			: [plugin refusal];
		CGFloat detailHeight = [self heightOfDetailFor:plugin width:width - 150.0];
		NSTextField *detail = [self labelAt:
			NSMakeRect(8.0, top - 42.0 - detailHeight, width - 150.0, detailHeight)
		                               text:what small:YES];
		if(![plugin isUsable])
			[detail setTextColor:[NSColor systemRedColor]];
		[rows addSubview:detail];

		NSButton *switchOn = [[[NSButton alloc] initWithFrame:
			NSMakeRect(width - 134.0f, top - 26.0f, 60.0f, 20.0f)] autorelease];
		[switchOn setButtonType:NSButtonTypeSwitch];
		[switchOn setTitle:NekoPanelLocalized(@"On")];
		[switchOn setState:[registry isEnabled:plugin]
			? NSControlStateValueOn : NSControlStateValueOff];
		[switchOn setEnabled:[plugin isUsable]];
		[switchOn setTarget:self];
		[switchOn setAction:@selector(switchPressed:)];
		[switchOn setIdentifier:[plugin identifier]];
		[rows addSubview:switchOn];

		/* The one thing that goes wrong after a plugin is switched on: it names
		   Shortcuts of yours, and you have not made them yet. Said here, where you
		   can go and make them, rather than only in the bubble at the moment it
		   fails. */
		NSMutableArray *missing = [NSMutableArray array];
		if([plugin isUsable] && [registry isEnabled:plugin]) {
			for(NSString *name in [plugin shortcutsItNeeds]) {
				NekoShortcutProvider *runner = [[[NekoShortcutProvider alloc]
					initWithShortcutName:name] autorelease];
				if(![runner shortcutExists])
					[missing addObject:name];
			}
		}
		if([missing count] > 0) {
			NSTextField *needs = [self labelAt:
				NSMakeRect(8.0f, top - 90.0f, width - 150.0f, 16.0f)
			                              text:[NSString stringWithFormat:
				NekoPanelLocalized(@"Shortcuts you have not made yet: %@"),
				[missing componentsJoinedByString:@", "]]
			                             small:YES];
			[needs setTextColor:[NSColor systemOrangeColor]];
			[rows addSubview:needs];
		}

		BOOL shipped = [registry isBundled:plugin];
		if(shipped) {
			/* Removing one that ships with the app would only mean it came back
			   at the next launch. The switch is the whole of what to offer. */
			NSTextField *note = [self labelAt:
				NSMakeRect(width - 134.0f, top - 52.0f, 126.0f, 16.0f)
			                             text:NekoPanelLocalized(@"ships with Neko")
			                            small:YES];
			[rows addSubview:note];
		} else {
			NSButton *remove = [[[NSButton alloc] initWithFrame:
				NSMakeRect(width - 134.0f, top - 56.0f, 126.0f, 24.0f)] autorelease];
			[remove setBezelStyle:NSBezelStyleRounded];
			[remove setControlSize:NSControlSizeSmall];
			[remove setFont:[NSFont systemFontOfSize:
				[NSFont systemFontSizeForControlSize:NSControlSizeSmall]]];
			[remove setTitle:NekoPanelLocalized(@"Remove…")];
			[remove setTarget:self];
			[remove setAction:@selector(removePressed:)];
			[remove setIdentifier:[plugin identifier]];
			[rows addSubview:remove];
		}
	}

	[rows scrollRectToVisible:NSMakeRect(0.0f, height - 1.0f, width, 1.0f)];
}

#pragma mark Doing things

- (NekoPlugin *)pluginFor:(id)sender
{
	return [[NekoPlugins sharedPlugins] pluginWithIdentifier:[sender identifier]];
}

- (void)switchPressed:(id)sender
{
	NekoPlugin *plugin = [self pluginFor:sender];
	if(plugin == nil)
		return;
	[[NekoPlugins sharedPlugins] setEnabled:([sender state] == NSControlStateValueOn)
	                                    for:plugin];
}

/* The sandbox is why this is a panel rather than a folder somebody drops things
   into: the app can only read inside its own container, and this is the handover
   that puts a folder there. */
- (void)addPressed:(id)sender
{
	NSOpenPanel *choose = [NSOpenPanel openPanel];
	[choose setCanChooseDirectories:YES];
	[choose setCanChooseFiles:NO];
	[choose setAllowsMultipleSelection:NO];
	[choose setPrompt:NekoPanelLocalized(@"Add")];
	[choose setMessage:NekoPanelLocalized(@"Choose a plugin folder — its name ends in .nekoplugin. It will be copied in and left switched off.")];

	/* A sheet on this window, not an application-modal panel.
	   Measured, and it is why "Add does absolutely nothing" was true: this app is
	   an accessory — no Dock icon — and an app-modal open panel from one opens
	   behind whatever the person is looking at. The panel was there every time;
	   nobody could see it. A sheet is attached to the window and cannot be
	   behind anything. */
	[NSApp activateIgnoringOtherApps:YES];
	[[self window] makeKeyAndOrderFront:nil];
	[choose beginSheetModalForWindow:[self window]
	              completionHandler:^(NSModalResponse answer) {
		if(answer != NSModalResponseOK)
			return;
		NSString *problem = [[NekoPlugins sharedPlugins] installFrom:[choose URL]];
		[self refresh];
		if(problem == nil)
			return;

		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText:NekoPanelLocalized(@"That one was not added")];
		[alert setInformativeText:problem];
		[alert addButtonWithTitle:NekoPanelLocalized(@"All right")];
		[alert beginSheetModalForWindow:[self window] completionHandler:nil];
	}];
}

- (void)removePressed:(id)sender
{
	NekoPlugin *plugin = [self pluginFor:sender];
	if(plugin == nil)
		return;

	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:[NSString stringWithFormat:
		NekoPanelLocalized(@"Remove “%@”?"), [plugin name]]];
	[alert setInformativeText:[NSString stringWithFormat:
		NekoPanelLocalized(@"Its folder and everything it added — %@ — go. Nothing else changes. This cannot be undone."),
		[plugin describeWhatItAdds]]];
	[alert addButtonWithTitle:NekoPanelLocalized(@"Remove")];
	[alert addButtonWithTitle:NekoPanelLocalized(@"Cancel")];

	/* A sheet, for the same reason as the one above. */
	NekoPlugin *kept = [plugin retain];
	[alert beginSheetModalForWindow:[self window]
	            completionHandler:^(NSModalResponse answer) {
		if(answer == NSAlertFirstButtonReturn) {
			[[NekoPlugins sharedPlugins] remove:kept];
			[self refresh];
		}
		[kept release];
	}];
}

- (void)revealFolderPressed:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[[NekoPlugins sharedPlugins] directory]];
}

/* Shown in Finder with the folders selected, so that the next thing to do — drag
   one onto Add… — is in front of somebody rather than described to them. */
- (void)revealExamplesPressed:(id)sender
{
	NSArray *examples = [[NekoPlugins sharedPlugins] examples];
	if([examples count] == 0)
		return;
	[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:examples];
}

@end
