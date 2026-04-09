#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LookinMCPErrorCode) {
    LookinMCPErrorCodeUnknown = 1,
    LookinMCPErrorCodeInvalidParams = 2,
    LookinMCPErrorCodeNoSession = 3,
    LookinMCPErrorCodeSessionReconnecting = 4,
    LookinMCPErrorCodeSnapshotInvalid = 5,
    LookinMCPErrorCodeNodeNotFound = 6,
    LookinMCPErrorCodeAppNotFound = 7,
    LookinMCPErrorCodeAppAmbiguous = 8,
    LookinMCPErrorCodeAppIncompatible = 9,
    LookinMCPErrorCodeTimeout = 10,
    LookinMCPErrorCodeIO = 11,
};

FOUNDATION_EXPORT NSString *const LookinMCPErrorDomain;

NSError *LookinMCPMakeError(LookinMCPErrorCode code, NSString *description, NSString *_Nullable suggestion);
id _Nullable LookinMCPWaitForSingleValue(RACSignal *signal, NSTimeInterval timeout, NSError **error);
NSArray * _Nullable LookinMCPCollectSignalValues(RACSignal *signal, NSTimeInterval timeout, NSError **error);
id _Nullable LookinMCPValueForKey(id _Nullable object, NSString *key);
NSDictionary *LookinMCPRectJSON(CGRect rect);
NSString *LookinMCPSanitizePathComponent(NSString *string);
NSString *LookinMCPISO8601StringFromDate(NSDate *_Nullable date);
NSString *LookinMCPStringFromValue(id _Nullable value);

NS_ASSUME_NONNULL_END
