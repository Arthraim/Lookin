#import "LookinMCPUtilities.h"

NSString *const LookinMCPErrorDomain = @"LookinMCPErrorDomain";

NSError *LookinMCPMakeError(LookinMCPErrorCode code, NSString *description, NSString *suggestion) {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (description.length > 0) {
        userInfo[NSLocalizedDescriptionKey] = description;
    }
    if (suggestion.length > 0) {
        userInfo[NSLocalizedRecoverySuggestionErrorKey] = suggestion;
    }
    return [NSError errorWithDomain:LookinMCPErrorDomain code:code userInfo:userInfo];
}

id LookinMCPWaitForSingleValue(RACSignal *signal, NSTimeInterval timeout, NSError **error) {
    NSArray *values = LookinMCPCollectSignalValues(signal, timeout, error);
    return values.firstObject;
}

NSArray *LookinMCPCollectSignalValues(RACSignal *signal, NSTimeInterval timeout, NSError **error) {
    if (!signal) {
        if (error) {
            *error = LookinMCPMakeError(LookinMCPErrorCodeUnknown, @"Missing signal.", nil);
        }
        return nil;
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSMutableArray *receivedValues = [NSMutableArray array];
    __block NSError *receivedError = nil;
    __block BOOL finished = NO;

    RACDisposable *disposable = [signal subscribeNext:^(id  _Nullable x) {
        if (x) {
            [receivedValues addObject:x];
        }
    } error:^(NSError * _Nullable subscribeError) {
        receivedError = subscribeError;
        finished = YES;
        dispatch_semaphore_signal(semaphore);
    } completed:^{
        finished = YES;
        dispatch_semaphore_signal(semaphore);
    }];

    long waitResult = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)));
    if (waitResult != 0) {
        [disposable dispose];
        receivedError = LookinMCPMakeError(LookinMCPErrorCodeTimeout, @"The request timed out.", @"Please retry in a few seconds.");
    }

    if (!finished && !receivedError) {
        receivedError = LookinMCPMakeError(LookinMCPErrorCodeUnknown, @"The request finished unexpectedly.", nil);
    }

    if (error) {
        *error = receivedError;
    }
    if (receivedError) {
        return nil;
    }
    return receivedValues.copy;
}

id LookinMCPValueForKey(id object, NSString *key) {
    if (!object || key.length == 0) {
        return nil;
    }
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

NSDictionary *LookinMCPRectJSON(CGRect rect) {
    return @{
        @"x": @(rect.origin.x),
        @"y": @(rect.origin.y),
        @"width": @(rect.size.width),
        @"height": @(rect.size.height)
    };
}

NSString *LookinMCPSanitizePathComponent(NSString *string) {
    if (string.length == 0) {
        return @"unknown";
    }
    NSCharacterSet *invalidSet = [NSCharacterSet characterSetWithCharactersInString:@"/\\:?%*|\"<> "];
    NSArray<NSString *> *components = [string componentsSeparatedByCharactersInSet:invalidSet];
    NSString *joined = [[components filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@"-"];
    return joined.length > 0 ? joined : @"unknown";
}

NSString *LookinMCPISO8601StringFromDate(NSDate *date) {
    if (!date) {
        return nil;
    }
    static NSISO8601DateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    });
    return [formatter stringFromDate:date];
}

NSString *LookinMCPStringFromValue(id value) {
    if (!value || value == [NSNull null]) {
        return @"";
    }
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    return [value description];
}
