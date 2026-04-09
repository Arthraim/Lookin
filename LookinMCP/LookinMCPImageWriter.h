#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface LookinMCPImageWriter : NSObject

- (instancetype)initWithSessionIdentifierProvider:(NSString * (^)(void))sessionIdentifierProvider;
- (NSDictionary * _Nullable)writeImage:(NSImage *)image nodeID:(NSString *)nodeID kind:(NSString *)kind error:(NSError **)error;
- (void)clearSessionArtifacts;

@end

NS_ASSUME_NONNULL_END
