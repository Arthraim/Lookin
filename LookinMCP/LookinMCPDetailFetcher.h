#import <Foundation/Foundation.h>

@class LKInspectableApp;
@class LookinDisplayItem;
@class LookinMCPSnapshotStore;

NS_ASSUME_NONNULL_BEGIN

@interface LookinMCPDetailFetcher : NSObject

- (instancetype)initWithSnapshotStore:(LookinMCPSnapshotStore *)snapshotStore;
- (BOOL)ensureDetailForItem:(LookinDisplayItem *)item app:(LKInspectableApp *)app includeAttributes:(BOOL)includeAttributes screenshotKind:(NSString *_Nullable)screenshotKind error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
