#import <Foundation/Foundation.h>

@class LKInspectableApp;

typedef NS_ENUM(NSInteger, LookinMCPSessionState) {
    LookinMCPSessionStateDisconnected = 0,
    LookinMCPSessionStateConnecting,
    LookinMCPSessionStateConnected,
    LookinMCPSessionStateReconnecting,
};

NS_ASSUME_NONNULL_BEGIN

@interface LookinMCPSessionManager : NSObject

@property(nonatomic, copy, nullable) void (^didInvalidateSnapshot)(void);
@property(nonatomic, strong, readonly, nullable) LKInspectableApp *currentApp;
@property(nonatomic, copy, readonly, nullable) NSString *currentAppRef;
@property(nonatomic, copy, readonly) NSString *sessionIdentifier;
@property(nonatomic, assign, readonly) LookinMCPSessionState state;

- (NSArray<LKInspectableApp *> * _Nullable)scanAppsWithError:(NSError **)error;
- (BOOL)connectToApp:(LKInspectableApp *)app error:(NSError **)error;
- (void)disconnect;
- (NSString *)stateName;
- (NSDictionary *)appSummaryForApp:(LKInspectableApp *)app;

@end

NS_ASSUME_NONNULL_END
