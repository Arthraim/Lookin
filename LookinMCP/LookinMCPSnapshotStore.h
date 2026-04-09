#import <Foundation/Foundation.h>

@class LookinHierarchyInfo;
@class LookinDisplayItem;
@class LookinDisplayItemDetail;

NS_ASSUME_NONNULL_BEGIN

@interface LookinMCPSnapshotStore : NSObject

@property(nonatomic, copy, readonly, nullable) NSString *snapshotIdentifier;
@property(nonatomic, strong, readonly, nullable) NSDate *lastRefreshDate;
@property(nonatomic, assign, readonly, getter=isValid) BOOL valid;

- (void)invalidate;
- (void)replaceWithHierarchyInfo:(LookinHierarchyInfo *)info;
- (LookinDisplayItem * _Nullable)itemForNodeID:(NSString *)nodeID;
- (LookinDisplayItem * _Nullable)itemForAnyOID:(unsigned long)oid;
- (void)applyDetail:(LookinDisplayItemDetail *)detail;
- (NSDictionary * _Nullable)hierarchyPayload;
- (NSDictionary * _Nullable)normalizedNodeForItem:(LookinDisplayItem *)item includeChildren:(BOOL)includeChildren;
- (NSArray<NSDictionary *> *)findNodesMatchingQuery:(NSString *_Nullable)query className:(NSString *_Nullable)className visibleOnly:(BOOL)visibleOnly limit:(NSUInteger)limit;

@end

NS_ASSUME_NONNULL_END
