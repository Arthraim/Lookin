#import "LookinMCPSnapshotStore.h"
#import "LookinMCPUtilities.h"
#import "LookinDisplayItem+LookinClient.h"
#import "LookinObject+LookinClient.h"
#import "LookinHierarchyInfo.h"
#import "LookinDisplayItem.h"
#import "LookinDisplayItemDetail.h"
#import "LookinAppInfo.h"
#import "LookinCustomDisplayItemInfo+LookinClient.h"
#if __has_include("LookinMCP-Swift.h")
#import "LookinMCP-Swift.h"
#else
#import "Lookin-Swift.h"
#endif

@interface LookinMCPSnapshotStore ()

@property(nonatomic, copy, readwrite) NSString *snapshotIdentifier;
@property(nonatomic, strong, readwrite) NSDate *lastRefreshDate;
@property(nonatomic, assign, readwrite, getter=isValid) BOOL valid;
@property(nonatomic, strong) LookinHierarchyInfo *hierarchyInfo;
@property(nonatomic, copy) NSArray<LookinDisplayItem *> *rootItems;
@property(nonatomic, copy) NSArray<LookinDisplayItem *> *flatItems;
@property(nonatomic, copy) NSDictionary<NSString *, LookinDisplayItem *> *itemsByNodeID;
@property(nonatomic, copy) NSDictionary<NSNumber *, LookinDisplayItem *> *itemsByAnyOID;

@end

@implementation LookinMCPSnapshotStore

- (void)invalidate {
    self.valid = NO;
    self.snapshotIdentifier = nil;
    self.lastRefreshDate = nil;
    self.hierarchyInfo = nil;
    self.rootItems = @[];
    self.flatItems = @[];
    self.itemsByNodeID = @{};
    self.itemsByAnyOID = @{};
}

- (void)replaceWithHierarchyInfo:(LookinHierarchyInfo *)info {
    self.hierarchyInfo = info;
    self.rootItems = info.displayItems ?: @[];
    self.flatItems = [LookinDisplayItem flatItemsFromHierarchicalItems:self.rootItems] ?: @[];

    CGFloat screenScale = MAX(info.appInfo.screenScale, 1);
    CGFloat maxLengthInPx = LookinNodeImageMaxLengthInPx - 100;

    NSMutableDictionary<NSString *, LookinDisplayItem *> *nodeMap = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, LookinDisplayItem *> *oidMap = [NSMutableDictionary dictionary];
    [self.flatItems enumerateObjectsUsingBlock:^(LookinDisplayItem * _Nonnull item, NSUInteger idx, BOOL * _Nonnull stop) {
        CGFloat widthInPx = item.frame.size.width * screenScale;
        CGFloat heightInPx = item.frame.size.height * screenScale;
        if (widthInPx > maxLengthInPx || heightInPx > maxLengthInPx) {
            item.doNotFetchScreenshotReason = LookinDoNotFetchScreenshotForTooLarge;
        }

        unsigned long layerOID = item.layerObject.oid;
        if (layerOID > 0) {
            nodeMap[[NSString stringWithFormat:@"%lu", layerOID]] = item;
            oidMap[@(layerOID)] = item;
        }
        if (item.viewObject.oid > 0) {
            oidMap[@(item.viewObject.oid)] = item;
        }
    }];

    self.itemsByNodeID = nodeMap.copy;
    self.itemsByAnyOID = oidMap.copy;
    self.snapshotIdentifier = NSUUID.UUID.UUIDString;
    self.lastRefreshDate = [NSDate date];
    self.valid = YES;
}

- (LookinDisplayItem *)itemForNodeID:(NSString *)nodeID {
    return self.itemsByNodeID[nodeID];
}

- (LookinDisplayItem *)itemForAnyOID:(unsigned long)oid {
    return self.itemsByAnyOID[@(oid)];
}

- (void)applyDetail:(LookinDisplayItemDetail *)detail {
    if (!detail) {
        return;
    }
    LookinDisplayItem *item = [self itemForAnyOID:detail.displayItemOid];
    if (!item) {
        return;
    }

    if (detail.customDisplayTitle.length > 0) {
        item.customDisplayTitle = detail.customDisplayTitle;
    }
    if (detail.groupScreenshot) {
        item.groupScreenshot = detail.groupScreenshot;
    }
    if (detail.soloScreenshot) {
        item.soloScreenshot = detail.soloScreenshot;
    }
    if (detail.frameValue) {
        item.frame = detail.frameValue.rectValue;
    }
    if (detail.boundsValue) {
        item.bounds = detail.boundsValue.rectValue;
    }
    if (detail.hiddenValue) {
        item.isHidden = detail.hiddenValue.boolValue;
    }
    if (detail.alphaValue) {
        item.alpha = detail.alphaValue.doubleValue;
    }
    if (detail.attributesGroupList.count > 0) {
        item.attributesGroupList = detail.attributesGroupList;
    }
    if (detail.customAttrGroupList.count > 0) {
        item.customAttrGroupList = detail.customAttrGroupList;
    }
}

- (NSDictionary *)hierarchyPayload {
    if (!self.isValid || !self.hierarchyInfo) {
        return nil;
    }

    NSMutableDictionary<NSString *, NSDictionary *> *nodesByID = [NSMutableDictionary dictionaryWithCapacity:self.flatItems.count];
    [self.flatItems enumerateObjectsUsingBlock:^(LookinDisplayItem * _Nonnull item, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *nodeID = [NSString stringWithFormat:@"%lu", item.layerObject.oid];
        NSDictionary *normalized = [self normalizedNodeForItem:item includeChildren:NO];
        if (normalized) {
            nodesByID[nodeID] = normalized;
        }
    }];

    NSMutableArray<NSDictionary *> *tree = [NSMutableArray array];
    [self.rootItems enumerateObjectsUsingBlock:^(LookinDisplayItem * _Nonnull item, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary *normalized = [self normalizedNodeForItem:item includeChildren:YES];
        if (normalized) {
            [tree addObject:normalized];
        }
    }];

    return @{
        @"snapshot_id": self.snapshotIdentifier ?: @"",
        @"snapshot_valid": @(self.isValid),
        @"last_refresh_at": LookinMCPISO8601StringFromDate(self.lastRefreshDate) ?: [NSNull null],
        @"app": @{
            @"screen_width": @(self.hierarchyInfo.appInfo.screenWidth),
            @"screen_height": @(self.hierarchyInfo.appInfo.screenHeight),
            @"screen_scale": @(self.hierarchyInfo.appInfo.screenScale),
            @"os_description": self.hierarchyInfo.appInfo.osDescription ?: @""
        },
        @"tree": tree,
        @"nodes_by_id": nodesByID
    };
}

- (NSDictionary *)normalizedNodeForItem:(LookinDisplayItem *)item includeChildren:(BOOL)includeChildren {
    if (!item || item.layerObject.oid == 0) {
        return nil;
    }

    LookinObject *representedObject = item.viewObject ?: item.layerObject;
    NSString *representedType = item.customInfo ? @"custom" : (item.viewObject ? @"view" : @"layer");
    NSString *className = representedObject ? representedObject.lk_simpleDemangledClassName : (item.customInfo.title ?: @"");
    NSString *hostViewController = item.hostViewControllerObject ? item.hostViewControllerObject.lk_simpleDemangledClassName : @"";
    NSString *memoryAddress = representedObject.memoryAddress ?: @"";
    NSArray<NSString *> *classChain = [self normalizedClassChainForObject:representedObject];
    NSDictionary *screenshotStatus = [self screenshotStatusForItem:item];
    NSUInteger depth = 0;
    for (LookinDisplayItem *cursor = item.superItem; cursor != nil; cursor = cursor.superItem) {
        depth += 1;
    }

    NSMutableDictionary *result = [@{
        @"node_id": [NSString stringWithFormat:@"%lu", item.layerObject.oid],
        @"layer_oid": @(item.layerObject.oid),
        @"view_oid": @(item.viewObject.oid),
        @"represented_type": representedType,
        @"title": item.title ?: @"",
        @"subtitle": item.subtitle ?: @"",
        @"class_name": className ?: @"",
        @"class_chain": classChain ?: @[],
        @"host_view_controller": hostViewController ?: @"",
        @"memory_address": memoryAddress ?: @"",
        @"frame": LookinMCPRectJSON(item.frame),
        @"bounds": LookinMCPRectJSON(item.bounds),
        @"frame_to_root": LookinMCPRectJSON([item calculateFrameToRoot]),
        @"alpha": @(item.alpha),
        @"hidden": @(item.isHidden),
        @"is_expandable": @(item.isExpandable),
        @"is_expanded": @(item.isExpanded),
        @"displaying_in_hierarchy": @(item.displayingInHierarchy),
        @"in_hidden_hierarchy": @(item.inHiddenHierarchy),
        @"screenshot_status": screenshotStatus,
        @"child_node_ids": [self childNodeIDsForItem:item],
        @"depth": @(depth),
        @"parent_node_id": item.superItem ? [NSString stringWithFormat:@"%lu", item.superItem.layerObject.oid] : [NSNull null]
    } mutableCopy];

    if (includeChildren) {
        NSMutableArray<NSDictionary *> *children = [NSMutableArray arrayWithCapacity:item.subitems.count];
        [item.subitems enumerateObjectsUsingBlock:^(LookinDisplayItem * _Nonnull child, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *normalized = [self normalizedNodeForItem:child includeChildren:YES];
            if (normalized) {
                [children addObject:normalized];
            }
        }];
        result[@"children"] = children;
    }

    return result.copy;
}

- (NSArray<NSDictionary *> *)findNodesMatchingQuery:(NSString *)query className:(NSString *)className visibleOnly:(BOOL)visibleOnly limit:(NSUInteger)limit {
    NSUInteger cappedLimit = limit > 0 ? limit : 50;
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    NSString *queryLower = query.lowercaseString;
    NSString *classNameLower = className.lowercaseString;

    [self.flatItems enumerateObjectsUsingBlock:^(LookinDisplayItem * _Nonnull item, NSUInteger idx, BOOL * _Nonnull stop) {
        if (visibleOnly && (!item.displayingInHierarchy || item.inHiddenHierarchy)) {
            return;
        }

        if (classNameLower.length > 0) {
            NSString *resolvedClassName = ((item.viewObject ?: item.layerObject).lk_simpleDemangledClassName ?: @"").lowercaseString;
            if (![resolvedClassName isEqualToString:classNameLower]) {
                return;
            }
        }

        if (queryLower.length > 0 && ![self item:item matchesQuery:queryLower]) {
            return;
        }

        NSDictionary *normalized = [self normalizedNodeForItem:item includeChildren:NO];
        if (normalized) {
            [result addObject:normalized];
        }
        if (result.count >= cappedLimit) {
            *stop = YES;
        }
    }];

    return result.copy;
}

- (BOOL)item:(LookinDisplayItem *)item matchesQuery:(NSString *)queryLower {
    NSArray<NSString *> *searchFields = @[
        item.title ?: @"",
        item.subtitle ?: @"",
        (item.viewObject ?: item.layerObject).lk_simpleDemangledClassName ?: @"",
        (item.viewObject ?: item.layerObject).memoryAddress ?: @"",
        [[self normalizedClassChainForObject:(item.viewObject ?: item.layerObject)] componentsJoinedByString:@" "]
    ];
    for (NSString *field in searchFields) {
        if ([field.lowercaseString containsString:queryLower]) {
            return YES;
        }
    }
    return NO;
}

- (NSArray<NSString *> *)normalizedClassChainForObject:(LookinObject *)object {
    if (!object.classChainList.count) {
        return @[];
    }
    return [object.classChainList lookin_map:^id(NSUInteger idx, NSString *value) {
        return [LKSwiftDemangler simpleParseWithInput:value] ?: value;
    }];
}

- (NSArray<NSString *> *)childNodeIDsForItem:(LookinDisplayItem *)item {
    return [item.subitems lookin_map:^id(NSUInteger idx, LookinDisplayItem *value) {
        return [NSString stringWithFormat:@"%lu", value.layerObject.oid];
    }] ?: @[];
}

- (NSDictionary *)screenshotStatusForItem:(LookinDisplayItem *)item {
    NSMutableArray<NSString *> *availableKinds = [NSMutableArray array];
    if (item.groupScreenshot) {
        [availableKinds addObject:@"group"];
    }
    if (item.soloScreenshot) {
        [availableKinds addObject:@"solo"];
    }

    NSString *preferredKind = (item.isExpandable && item.isExpanded) ? @"solo" : @"group";
    NSString *reason = nil;
    if (availableKinds.count == 0) {
        if (item.doNotFetchScreenshotReason == LookinDoNotFetchScreenshotForTooLarge) {
            reason = @"too_large";
        } else if (item.doNotFetchScreenshotReason == LookinDoNotFetchScreenshotForUserConfig) {
            reason = @"user_config";
        } else if (item.inNoPreviewHierarchy || [LookinMCPValueForKey(item, @"noPreview") boolValue]) {
            reason = @"no_preview";
        } else {
            reason = @"not_fetched";
        }
    }

    return @{
        @"appropriate_kind": preferredKind,
        @"available_kinds": availableKinds,
        @"has_any": @(availableKinds.count > 0),
        @"unavailable_reason": reason ?: [NSNull null]
    };
}

@end
