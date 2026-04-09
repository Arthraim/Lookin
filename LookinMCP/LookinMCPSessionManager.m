#import "LookinMCPSessionManager.h"
#import "LookinMCPUtilities.h"
#import "LKAppsManager.h"
#import "LKInspectableApp.h"
#import "LKConnectionManager.h"
#import "Lookin_PTChannel.h"

@interface LookinMCPSessionManager ()

@property(nonatomic, strong, readwrite) LKInspectableApp *currentApp;
@property(nonatomic, copy, readwrite) NSString *currentAppRef;
@property(nonatomic, copy, readwrite) NSString *sessionIdentifier;
@property(nonatomic, assign, readwrite) LookinMCPSessionState state;
@property(nonatomic, assign) BOOL manualDisconnecting;

@end

@implementation LookinMCPSessionManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _sessionIdentifier = NSUUID.UUID.UUIDString;
        _state = LookinMCPSessionStateDisconnected;

        [LKConnectionManager sharedInstance];
        [LKAppsManager sharedInstance];

        @weakify(self);
        [[NSNotificationCenter defaultCenter] addObserverForName:LKInspectingAppDidEndNotificationName object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification * _Nonnull note) {
            @strongify(self);
            if (!self || self.manualDisconnecting || !self.currentAppRef.length) {
                return;
            }
            self.currentApp = nil;
            self.state = LookinMCPSessionStateReconnecting;
            if (self.didInvalidateSnapshot) {
                self.didInvalidateSnapshot();
            }
        }];

        [[LKAppsManager sharedInstance].didAutoReconnectSucc subscribeNext:^(LKInspectableApp *app) {
            @strongify(self);
            if (!self || !app) {
                return;
            }
            self.currentApp = app;
            self.currentAppRef = [self.class appRefForApp:app];
            self.state = LookinMCPSessionStateConnected;
            if (self.didInvalidateSnapshot) {
                self.didInvalidateSnapshot();
            }
        }];
    }
    return self;
}

- (NSArray<LKInspectableApp *> *)scanAppsWithError:(NSError **)error {
    self.state = self.currentApp ? LookinMCPSessionStateConnected : LookinMCPSessionStateConnecting;
    NSArray<LKInspectableApp *> *apps = LookinMCPWaitForSingleValue([[LKAppsManager sharedInstance] fetchAppInfosWithImage:NO localInfos:nil], 6, error);
    if (!apps && (!error || !*error)) {
        apps = @[];
    }
    if (apps) {
        self.state = self.currentApp ? LookinMCPSessionStateConnected : LookinMCPSessionStateDisconnected;
    } else if (self.currentApp) {
        self.state = LookinMCPSessionStateConnected;
    } else {
        self.state = LookinMCPSessionStateDisconnected;
    }
    return apps;
}

- (BOOL)connectToApp:(LKInspectableApp *)app error:(NSError **)error {
    if (!app) {
        if (error) {
            *error = LookinMCPMakeError(LookinMCPErrorCodeAppNotFound, @"The requested app was not found.", nil);
        }
        return NO;
    }
    if (app.serverVersionError) {
        if (error) {
            *error = LookinMCPMakeError(LookinMCPErrorCodeAppIncompatible, @"The requested app cannot be inspected because the LookinServer version is incompatible.", app.serverVersionError.localizedRecoverySuggestion ?: app.serverVersionError.localizedDescription);
        }
        return NO;
    }

    self.state = LookinMCPSessionStateConnecting;
    [LKAppsManager sharedInstance].inspectingApp = app;
    self.currentApp = app;
    self.currentAppRef = [self.class appRefForApp:app];
    self.state = LookinMCPSessionStateConnected;
    self.sessionIdentifier = NSUUID.UUID.UUIDString;
    if (self.didInvalidateSnapshot) {
        self.didInvalidateSnapshot();
    }
    return YES;
}

- (void)disconnect {
    self.manualDisconnecting = YES;
    [LKAppsManager sharedInstance].inspectingApp = nil;
    self.manualDisconnecting = NO;

    self.currentApp = nil;
    self.currentAppRef = nil;
    self.state = LookinMCPSessionStateDisconnected;
    self.sessionIdentifier = NSUUID.UUID.UUIDString;
    if (self.didInvalidateSnapshot) {
        self.didInvalidateSnapshot();
    }
}

- (NSString *)stateName {
    switch (self.state) {
        case LookinMCPSessionStateDisconnected:
            return @"disconnected";
        case LookinMCPSessionStateConnecting:
            return @"connecting";
        case LookinMCPSessionStateConnected:
            return @"connected";
        case LookinMCPSessionStateReconnecting:
            return @"reconnecting";
    }

    return @"disconnected";
}

- (NSDictionary *)appSummaryForApp:(LKInspectableApp *)app {
    NSString *bundleID = LookinMCPStringFromValue(LookinMCPValueForKey(app.appInfo, @"appBundleIdentifier"));
    NSString *deviceName = LookinMCPStringFromValue(LookinMCPValueForKey(app.appInfo, @"deviceDescription"));
    NSString *osDescription = LookinMCPStringFromValue(LookinMCPValueForKey(app.appInfo, @"osDescription"));
    NSString *appName = LookinMCPStringFromValue(LookinMCPValueForKey(app.appInfo, @"appName"));
    NSNumber *appInfoIdentifier = LookinMCPValueForKey(app.appInfo, @"appInfoIdentifier") ?: @0;
    NSNumber *portNumber = LookinMCPValueForKey(app.channel, @"portNumber") ?: @0;
    BOOL isSimulator = app.appInfo.deviceType == LookinAppInfoDeviceSimulator;
    NSString *serverVersionStatus = @"supported";
    if (app.serverVersionError.code == LookinErrCode_ServerVersionTooLow) {
        serverVersionStatus = @"too_low";
    } else if (app.serverVersionError.code == LookinErrCode_ServerVersionTooHigh) {
        serverVersionStatus = @"too_high";
    } else if (app.serverVersionError) {
        serverVersionStatus = @"unknown";
    }

    NSString *appRef = [self.class appRefForBundleID:bundleID deviceName:deviceName appInfoIdentifier:appInfoIdentifier];
    return @{
        @"app_ref": appRef,
        @"bundle_id": bundleID ?: @"",
        @"app_name": appName ?: @"",
        @"device_type": isSimulator ? @"simulator" : @"usb",
        @"device_name": deviceName ?: @"",
        @"os_description": osDescription ?: @"",
        @"is_usb": @(!isSimulator),
        @"is_simulator": @(isSimulator),
        @"server_version_status": serverVersionStatus,
        @"app_info_identifier": appInfoIdentifier,
        @"port_number": portNumber
    };
}

+ (NSString *)appRefForApp:(LKInspectableApp *)app {
    NSString *bundleID = LookinMCPStringFromValue(LookinMCPValueForKey(app.appInfo, @"appBundleIdentifier"));
    NSString *deviceName = LookinMCPStringFromValue(LookinMCPValueForKey(app.appInfo, @"deviceDescription"));
    NSNumber *appInfoIdentifier = LookinMCPValueForKey(app.appInfo, @"appInfoIdentifier") ?: @0;
    return [self appRefForBundleID:bundleID deviceName:deviceName appInfoIdentifier:appInfoIdentifier];
}

+ (NSString *)appRefForBundleID:(NSString *)bundleID deviceName:(NSString *)deviceName appInfoIdentifier:(NSNumber *)appInfoIdentifier {
    return [NSString stringWithFormat:@"%@|%@|%@", bundleID ?: @"", deviceName ?: @"", appInfoIdentifier ?: @0];
}

@end
