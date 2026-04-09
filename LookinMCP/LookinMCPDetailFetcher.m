#import "LookinMCPDetailFetcher.h"
#import "LookinMCPUtilities.h"
#import "LookinMCPSnapshotStore.h"
#import "LKInspectableApp.h"
#import "LookinDisplayItem.h"
#import "LookinDisplayItemDetail.h"
#import "LookinStaticAsyncUpdateTask.h"

@interface LookinMCPDetailFetcher ()

@property(nonatomic, weak) LookinMCPSnapshotStore *snapshotStore;

@end

@implementation LookinMCPDetailFetcher

- (instancetype)initWithSnapshotStore:(LookinMCPSnapshotStore *)snapshotStore {
    self = [super init];
    if (self) {
        _snapshotStore = snapshotStore;
    }
    return self;
}

- (BOOL)ensureDetailForItem:(LookinDisplayItem *)item app:(LKInspectableApp *)app includeAttributes:(BOOL)includeAttributes screenshotKind:(NSString *)screenshotKind error:(NSError **)error {
    LookinStaticAsyncUpdateTask *task = [self taskForItem:item includeAttributes:includeAttributes screenshotKind:screenshotKind];
    if (!task) {
        return YES;
    }

    NSArray *packages = [self packagesForTasks:@[task]];
    NSError *fetchError = nil;
    NSArray *received = LookinMCPCollectSignalValues([app fetchHierarchyDetailWithTaskPackages:packages], 6, &fetchError);
    if (fetchError) {
        [app cancelHierarchyDetailFetching];
        if (error) {
            *error = fetchError;
        }
        return NO;
    }

    [received enumerateObjectsUsingBlock:^(NSArray * _Nonnull details, NSUInteger idx, BOOL * _Nonnull stop) {
        [details enumerateObjectsUsingBlock:^(LookinDisplayItemDetail * _Nonnull detail, NSUInteger idx, BOOL * _Nonnull stop) {
            [self.snapshotStore applyDetail:detail];
        }];
    }];
    return YES;
}

- (LookinStaticAsyncUpdateTask *)taskForItem:(LookinDisplayItem *)item includeAttributes:(BOOL)includeAttributes screenshotKind:(NSString *)screenshotKind {
    BOOL needsAttributes = includeAttributes && [item queryAllAttrGroupList].count == 0;
    NSString *resolvedKind = [self resolvedScreenshotKindForItem:item kind:screenshotKind];
    BOOL needsScreenshot = resolvedKind.length > 0 && ![self item:item alreadyHasScreenshotForKind:resolvedKind];

    if (!needsAttributes && !needsScreenshot) {
        return nil;
    }

    LookinStaticAsyncUpdateTask *task = [LookinStaticAsyncUpdateTask new];
    task.oid = item.layerObject.oid;
    task.frameSize = item.frame.size;
    task.clientReadableVersion = [LKHelper lookinReadableVersion];
    task.attrRequest = needsAttributes ? LookinDetailUpdateTaskAttrRequest_Need : LookinDetailUpdateTaskAttrRequest_NotNeed;

    if (needsScreenshot) {
        task.taskType = [resolvedKind isEqualToString:@"solo"] ? LookinStaticAsyncUpdateTaskTypeSoloScreenshot : LookinStaticAsyncUpdateTaskTypeGroupScreenshot;
    } else {
        task.taskType = LookinStaticAsyncUpdateTaskTypeNoScreenshot;
    }
    return task;
}

- (NSString *)resolvedScreenshotKindForItem:(LookinDisplayItem *)item kind:(NSString *)kind {
    if (kind.length == 0) {
        return nil;
    }
    if (item.doNotFetchScreenshotReason != LookinFetchScreenshotPermitted) {
        return nil;
    }
    if ([kind isEqualToString:@"appropriate"]) {
        return (item.isExpandable && item.isExpanded) ? @"solo" : @"group";
    }
    return kind;
}

- (BOOL)item:(LookinDisplayItem *)item alreadyHasScreenshotForKind:(NSString *)kind {
    if ([kind isEqualToString:@"group"]) {
        return item.groupScreenshot != nil;
    }
    if ([kind isEqualToString:@"solo"]) {
        return item.soloScreenshot != nil;
    }
    return item.appropriateScreenshot != nil;
}

- (NSArray<LookinStaticAsyncUpdateTasksPackage *> *)packagesForTasks:(NSArray<LookinStaticAsyncUpdateTask *> *)tasks {
    NSMutableArray<LookinStaticAsyncUpdateTasksPackage *> *packages = [NSMutableArray array];
    NSMutableArray<LookinStaticAsyncUpdateTask *> *buffer = [NSMutableArray array];

    __block NSUInteger packageTotalArea = 0;
    const NSUInteger packageMaxArea = 2000000;
    const NSUInteger packageMaxTasksCount = 100;
    [tasks enumerateObjectsUsingBlock:^(LookinStaticAsyncUpdateTask * _Nonnull task, NSUInteger idx, BOOL * _Nonnull stop) {
        CGFloat currentArea = task.frameSize.width * task.frameSize.height;
        if ((packageTotalArea + currentArea > packageMaxArea || buffer.count >= packageMaxTasksCount) && buffer.count > 0) {
            LookinStaticAsyncUpdateTasksPackage *package = [LookinStaticAsyncUpdateTasksPackage new];
            package.tasks = buffer.copy;
            [packages addObject:package];
            [buffer removeAllObjects];
            packageTotalArea = 0;
        }

        [buffer addObject:task];
        packageTotalArea += currentArea;
    }];

    if (buffer.count > 0) {
        LookinStaticAsyncUpdateTasksPackage *package = [LookinStaticAsyncUpdateTasksPackage new];
        package.tasks = buffer.copy;
        [packages addObject:package];
    }
    return packages.copy;
}

@end
