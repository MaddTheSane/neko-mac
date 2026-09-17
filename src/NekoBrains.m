#import "NekoBrains.h"
#import "NekoAppleProvider.h"
#import "NekoLocalProvider.h"
#import "NekoModelStore.h"

/* Two gigabytes. Qwen2.5 3B and the two 4B models clear it; the 1.5B, which
   measurably cannot hold the instructions, does not. */
static const long long NekoBrainsCapable = 2000000000LL;

@implementation NekoBrains

+ (long long)capableModelBytes
{
	return NekoBrainsCapable;
}

+ (NekoAppleProvider *)apple
{
	static NekoAppleProvider *shared = nil;
	if(shared == nil)
		shared = [[NekoAppleProvider alloc] init];
	return shared;
}

+ (NekoLocalProvider *)local
{
	static NekoLocalProvider *shared = nil;
	if(shared == nil)
		shared = [[NekoLocalProvider alloc] init];
	return shared;
}

+ (id)biggestInstalledModel
{
	NekoModelStore *store = [NekoModelStore sharedStore];
	NekoLocalModel *best = nil;
	long long bestBytes = 0;
	for(NekoLocalModel *model in [store catalogue]) {
		if([store installedURLForIdentifier:[model identifier]] == nil)
			continue;
		long long bytes = [store installedBytesForIdentifier:[model identifier]];
		if(bytes > bestBytes) {
			bestBytes = bytes;
			best = model;
		}
	}
	return bestBytes >= NekoBrainsCapable ? best : nil;
}

+ (id<NekoAnswerProvider>)bestOnDeviceProvider
{
	NekoAppleProvider *apple = [self apple];
	if([apple isConfigured])
		return apple;

	NekoLocalModel *model = [self biggestInstalledModel];
	if(model == nil)
		return nil;

	/* Its own provider instance, pointed at the capable model: the preference
	   for questions is left exactly as the user set it. */
	NekoLocalProvider *local = [self local];
	[local setPreferredModel:[model identifier]];
	return [local isConfigured] ? local : nil;
}

+ (BOOL)staysOnThisMac:(id<NekoAnswerProvider>)provider
{
	if(provider == nil)
		return NO;
	return [provider isKindOfClass:[NekoAppleProvider class]]
	    || [provider isKindOfClass:[NekoLocalProvider class]];
}

+ (BOOL)hasSomethingWorthHearing
{
	return [self bestOnDeviceProvider] != nil;
}

+ (NSString *)describeChoice
{
	if([[self apple] isConfigured])
		return NSLocalizedString(@"Apple Intelligence, on this Mac, is what speaks when Neko speaks on its own.", @"Apple Intelligence, on this Mac, is what speaks when Neko speaks on its own.");

	NekoLocalModel *model = [self biggestInstalledModel];
	if(model != nil)
		return [NSString stringWithFormat:
			NSLocalizedString(@"%@, on this Mac, is what speaks when Neko speaks on its own.", @"%@, on this Mac, is what speaks when Neko speaks on its own."),
			[model name]];

	return NSLocalizedString(@"Nothing on this Mac is up to writing remarks: Apple Intelligence is unavailable and no model of about two gigabytes or more is downloaded. The cat falls back to its own few written-in lines, and says less. Whatever engine is set for questions is untouched by this — it is only that a remark nobody asked for is not sent to a remote service.", @"Nothing on this Mac is up to writing remarks: Apple Intelligence is unavailable and no model of about two gigabytes or more is downloaded. The cat falls back to its own few written-in lines, and says less. Whatever engine is set for questions is untouched by this — it is only that a remark nobody asked for is not sent to a remote service.");
}

@end
