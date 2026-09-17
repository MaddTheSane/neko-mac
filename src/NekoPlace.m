#import "NekoPlace.h"
#import <CoreLocation/CoreLocation.h>

NSString * const NekoPlaceTownKey   = @"NekoPlaceTown";
NSString * const NekoPlaceRegionKey = @"NekoPlaceRegion";
NSString * const NekoPlaceAskedKey  = @"NekoPlaceAsked";
NSString * const NekoPlaceDidChangeNotification = @"NekoPlaceDidChange";

@implementation NekoPlace

+ (NekoPlace *)sharedPlace
{
	static NekoPlace *shared = nil;
	if(shared == nil)
		shared = [[NekoPlace alloc] init];
	return shared;
}

- (void)dealloc
{
	[manager release];
	[report release];
	[super dealloc];
}

+ (BOOL)isAvailable
{
	if(NSClassFromString(@"CLLocationManager") == Nil)
		return NO;
	return [CLLocationManager locationServicesEnabled];
}

/*! What the system last told us, which is not the same as what a manager says the
   moment it is made: a fresh CLLocationManager answers "not determined" until the
   answer arrives on the delegate, and the Permissions row is drawn before that.
   Kept in the defaults so the row is right immediately after a relaunch too. */
static NSString * const NekoPlaceStatusKey = @"NekoPlaceStatus";

+ (NSInteger)authorizationStatus
{
	if(NSClassFromString(@"CLLocationManager") == Nil)
		return 1;
	CLAuthorizationStatus status = [(CLLocationManager *)[[self sharedPlace] manager] authorizationStatus];
	if(status == kCLAuthorizationStatusNotDetermined) {
		NSInteger remembered = [[NSUserDefaults standardUserDefaults]
			integerForKey:NekoPlaceStatusKey];
		if(remembered > 0)
			return remembered;
	}
	switch(status) {
		case kCLAuthorizationStatusNotDetermined: return 0;
		case kCLAuthorizationStatusDenied:        return 1;
		case kCLAuthorizationStatusRestricted:    return 2;
		default:                                  return 3;
	}
}

/* Made once and kept. A manager that is created for one question and released
   afterwards never hears the answer: the authorization callback arrives when
   somebody has finished reading a dialog, which is whole seconds later. */
- (id)manager
{
	if(manager == nil) {
		CLLocationManager *locations = [[CLLocationManager alloc] init];
		[locations setDelegate:(id)self];
		/* A town, not a street: the coarser accuracy is both enough and less to
		   ask for. */
		if(@available(macOS 11.0, *))
			[locations setDesiredAccuracy:kCLLocationAccuracyReduced];
		else
			[locations setDesiredAccuracy:kCLLocationAccuracyKilometer];
		manager = locations;
	}
	return manager;
}

#pragma mark What is already known

- (NSString *)town
{
	return [[NSUserDefaults standardUserDefaults] stringForKey:NekoPlaceTownKey];
}

- (NSString *)region
{
	return [[NSUserDefaults standardUserDefaults] stringForKey:NekoPlaceRegionKey];
}

/* The time zone, which every Mac has and nobody has to allow. Europe/Rome is
   Italy whether or not anyone ever presses the location button. */
- (NSString *)country
{
	NSString *fromLocale = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
	if([fromLocale length] == 2)
		return [fromLocale uppercaseString];
	NSString *zone = [[NSTimeZone systemTimeZone] name];
	if([zone hasPrefix:@"Europe/Rome"])
		return @"IT";
	return nil;
}

/* What the system says, as one overridable answer. */
- (NSInteger)permission
{
	return [NekoPlace authorizationStatus];
}

- (BOOL)mayLook
{
	if(![NekoPlace isAvailable])
		return NO;
	NSInteger status = [self permission];
	return status == 0 || status == 3;
}

- (void)forget
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults removeObjectForKey:NekoPlaceTownKey];
	[defaults removeObjectForKey:NekoPlaceRegionKey];
	[defaults removeObjectForKey:NekoPlaceAskedKey];
	[defaults removeObjectForKey:NekoPlaceStatusKey];
}

#pragma mark Finding out

- (BOOL)askedToday
{
	NSDate *last = [[NSUserDefaults standardUserDefaults] objectForKey:NekoPlaceAskedKey];
	if(![last isKindOfClass:[NSDate class]])
		return NO;
	return [[NSCalendar currentCalendar] isDateInToday:last];
}

- (void)finishWith:(NSString *)town region:(NSString *)region
{
	looking = NO;
	void (^done)(NSString *, NSString *) = [report retain];
	[report release];
	report = nil;

	if([town length] > 0 || [region length] > 0) {
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		if([town length] > 0)
			[defaults setObject:town forKey:NekoPlaceTownKey];
		if([region length] > 0)
			[defaults setObject:region forKey:NekoPlaceRegionKey];
		[defaults setObject:[NSDate date] forKey:NekoPlaceAskedKey];
	}

	if(done != NULL) {
		done([self town], [self region]);
		[done release];
	}
	[[NSNotificationCenter defaultCenter]
		postNotificationName:NekoPlaceDidChangeNotification object:self];
}

- (void)lookAgain:(void (^)(NSString *town, NSString *region))done
{
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:NekoPlaceAskedKey];
	[self findOut:done];
}

- (void)findOut:(void (^)(NSString *town, NSString *region))done
{
	if(!looking && [self askedToday] && [[self town] length] > 0) {
		/* Already known, and a town does not move. */
		if(done != NULL)
			done([self town], [self region]);
		return;
	}
	if(![self mayLook]) {
		if(done != NULL)
			done([self town], [self region]);
		return;
	}

	[report release];
	report = [done copy];
	looking = YES;

	if([self permission] == 0) {
		/* Ask for permission and stop there. Asking for a position in the same
		   breath is what "the button does nothing" was: CoreLocation answers the
		   position request immediately with a refusal, the whole thing unwinds,
		   and the dialog never gets its chance. The position is requested from
		   -locationManagerDidChangeAuthorization:, when there is an answer to
		   act on. */
		waitingForPermission = YES;
		/* An accessory application is not necessarily in front, and a dialog
		   behind three windows is a dialog nobody saw. */
		[NSApp activateIgnoringOtherApps:YES];
		if(@available(macOS 11.0, *))
			[(CLLocationManager *)[self manager] requestWhenInUseAuthorization];
		/* Long enough for somebody to read it and decide. */
		[self performSelector:@selector(giveUp) withObject:nil afterDelay:90.0];
		return;
	}

	[self askForAPosition];
}

- (void)askForAPosition
{
	waitingForPermission = NO;
	[(CLLocationManager *)[self manager] requestLocation];
	/* macOS answers a location request when it feels like it, and sometimes not
	   at all. Whoever asked gets an answer either way. */
	[NSObject cancelPreviousPerformRequestsWithTarget:self
	                                        selector:@selector(giveUp) object:nil];
	[self performSelector:@selector(giveUp) withObject:nil afterDelay:20.0];
}

/* The dialog was answered, or the setting was changed in System Settings while
   the app was running. Either way this is the moment the answer exists. */
- (void)authorizationChanged
{
	if(@available(macOS 11.0, *)) {
		CLAuthorizationStatus now = [(CLLocationManager *)[self manager] authorizationStatus];
		if(now != kCLAuthorizationStatusNotDetermined)
			[[NSUserDefaults standardUserDefaults]
				setInteger:(now == kCLAuthorizationStatusAuthorizedAlways
				            || now == kCLAuthorizationStatusAuthorized) ? 3
				           : (now == kCLAuthorizationStatusRestricted ? 2 : 1)
				    forKey:NekoPlaceStatusKey];
	}
	[[NSNotificationCenter defaultCenter]
		postNotificationName:NekoPlaceDidChangeNotification object:self];

	if(!waitingForPermission)
		return;
	if([self permission] == 3) {
		[self askForAPosition];
		return;
	}
	if([self permission] != 0)
		[self finishWith:nil region:nil];   /* refused: stop waiting */
}

- (void)locationManagerDidChangeAuthorization:(id)locations
{
	[self authorizationChanged];
}

- (void)locationManager:(id)locations didChangeAuthorizationStatus:(int)status
{
	[self authorizationChanged];
}

- (void)giveUp
{
	waitingForPermission = NO;
	if(looking)
		[self finishWith:nil region:nil];
}

#pragma mark What CoreLocation says

- (void)locationManager:(id)locations didUpdateLocations:(NSArray *)positions
{
	CLLocation *where = [positions lastObject];
	if(where == nil) {
		[self finishWith:nil region:nil];
		return;
	}

	/* Apple's own lookup, on the system, and the coordinates go no further than
	   this method. */
	CLGeocoder *geocoder = [[[CLGeocoder alloc] init] autorelease];
	[geocoder reverseGeocodeLocation:where
	              completionHandler:^(NSArray *marks, NSError *error) {
		CLPlacemark *mark = [marks firstObject];
		dispatch_async(dispatch_get_main_queue(), ^{
			[NSObject cancelPreviousPerformRequestsWithTarget:self
			                                         selector:@selector(giveUp) object:nil];
			[self finishWith:[mark locality] region:[mark administrativeArea]];
		});
	}];
}

- (void)locationManager:(id)locations didFailWithError:(NSError *)error
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self
	                                         selector:@selector(giveUp) object:nil];
	[self finishWith:nil region:nil];
}

@end
