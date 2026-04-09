#import "LookinMCPServer.h"
#import "LookinMCPUtilities.h"
#import "LookinMCPSessionManager.h"
#import "LookinMCPSnapshotStore.h"
#import "LookinMCPDetailFetcher.h"
#import "LookinMCPAttributeFormatter.h"
#import "LookinMCPImageWriter.h"
#import "LKInspectableApp.h"
#import "LookinHierarchyInfo.h"
#import "LookinDisplayItem.h"

@interface LookinMCPServer ()

@property(nonatomic, strong) LookinMCPSessionManager *sessionManager;
@property(nonatomic, strong) LookinMCPSnapshotStore *snapshotStore;
@property(nonatomic, strong) LookinMCPDetailFetcher *detailFetcher;
@property(nonatomic, strong) LookinMCPAttributeFormatter *attributeFormatter;
@property(nonatomic, strong) LookinMCPImageWriter *imageWriter;
@property(nonatomic, assign) BOOL keepRunning;

@end

@implementation LookinMCPServer

- (instancetype)init {
    self = [super init];
    if (self) {
        _snapshotStore = [[LookinMCPSnapshotStore alloc] init];
        _sessionManager = [[LookinMCPSessionManager alloc] init];
        _detailFetcher = [[LookinMCPDetailFetcher alloc] initWithSnapshotStore:_snapshotStore];
        _attributeFormatter = [[LookinMCPAttributeFormatter alloc] init];
        @weakify(self);
        _imageWriter = [[LookinMCPImageWriter alloc] initWithSessionIdentifierProvider:^NSString *{
            @strongify(self);
            return self.sessionManager.sessionIdentifier ?: @"unknown-session";
        }];
        _sessionManager.didInvalidateSnapshot = ^{
            @strongify(self);
            [self.snapshotStore invalidate];
        };
        _keepRunning = YES;
    }
    return self;
}

- (int)run {
    @autoreleasepool {
        while (self.keepRunning) {
            NSDictionary *message = [self readMessage];
            if (!message) {
                break;
            }
            [self handleMessage:message];
        }
        [self.imageWriter clearSessionArtifacts];
    }
    return 0;
}

- (NSDictionary *)readMessage {
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    char lineBuffer[4096];
    BOOL didReadAnyHeader = NO;

    while (fgets(lineBuffer, sizeof(lineBuffer), stdin) != NULL) {
        NSString *line = [[NSString stringWithUTF8String:lineBuffer] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        if (line.length == 0) {
            break;
        }
        didReadAnyHeader = YES;
        NSRange separatorRange = [line rangeOfString:@":"];
        if (separatorRange.location == NSNotFound) {
            continue;
        }
        NSString *key = [[line substringToIndex:separatorRange.location] lowercaseString];
        NSString *value = [[line substringFromIndex:separatorRange.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        headers[key] = value;
    }

    if (!didReadAnyHeader) {
        return nil;
    }

    NSInteger contentLength = [headers[@"content-length"] integerValue];
    if (contentLength <= 0) {
        return nil;
    }

    NSMutableData *body = [NSMutableData dataWithLength:(NSUInteger)contentLength];
    NSUInteger bytesRead = fread(body.mutableBytes, 1, (NSUInteger)contentLength, stdin);
    if (bytesRead != (NSUInteger)contentLength) {
        return nil;
    }

    NSError *jsonError = nil;
    NSDictionary *message = [NSJSONSerialization JSONObjectWithData:body options:0 error:&jsonError];
    if (jsonError || ![message isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return message;
}

- (void)sendPayload:(NSDictionary *)payload {
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    if (jsonError || !data) {
        return;
    }
    NSString *header = [NSString stringWithFormat:@"Content-Length: %lu\r\n\r\n", (unsigned long)data.length];
    fwrite(header.UTF8String, 1, header.length, stdout);
    fwrite(data.bytes, 1, data.length, stdout);
    fflush(stdout);
}

- (void)handleMessage:(NSDictionary *)message {
    NSString *method = message[@"method"];
    id messageID = message[@"id"];
    NSDictionary *params = [message[@"params"] isKindOfClass:[NSDictionary class]] ? message[@"params"] : @{};

    if ([method isEqualToString:@"initialize"]) {
        [self sendResult:@{
            @"protocolVersion": @"2024-11-05",
            @"capabilities": @{@"tools": @{}},
            @"serverInfo": @{@"name": @"lookin-mcp", @"version": @"1.0.0"}
        } forID:messageID];
        return;
    }

    if ([method isEqualToString:@"notifications/initialized"]) {
        return;
    }

    if ([method isEqualToString:@"ping"]) {
        [self sendResult:@{} forID:messageID];
        return;
    }

    if ([method isEqualToString:@"shutdown"]) {
        [self sendResult:@{} forID:messageID];
        self.keepRunning = NO;
        return;
    }

    if ([method isEqualToString:@"exit"]) {
        self.keepRunning = NO;
        return;
    }

    if ([method isEqualToString:@"tools/list"]) {
        [self sendResult:@{@"tools": [self toolDefinitions]} forID:messageID];
        return;
    }

    if ([method isEqualToString:@"tools/call"]) {
        NSString *toolName = params[@"name"];
        NSDictionary *arguments = [params[@"arguments"] isKindOfClass:[NSDictionary class]] ? params[@"arguments"] : @{};
        NSDictionary *toolResult = [self handleToolCall:toolName arguments:arguments];
        [self sendResult:toolResult forID:messageID];
        return;
    }

    [self sendJSONRPCErrorCode:-32601 message:@"Method not found." data:nil forID:messageID];
}

- (NSDictionary *)handleToolCall:(NSString *)toolName arguments:(NSDictionary *)arguments {
    if ([toolName isEqualToString:@"list_apps"]) {
        return [self toolListApps];
    }
    if ([toolName isEqualToString:@"connect_app"]) {
        return [self toolConnectApp:arguments];
    }
    if ([toolName isEqualToString:@"session_status"]) {
        return [self toolSessionStatus];
    }
    if ([toolName isEqualToString:@"disconnect_app"]) {
        return [self toolDisconnectApp];
    }
    if ([toolName isEqualToString:@"get_hierarchy"]) {
        return [self toolGetHierarchy];
    }
    if ([toolName isEqualToString:@"find_nodes"]) {
        return [self toolFindNodes:arguments];
    }
    if ([toolName isEqualToString:@"get_node_detail"]) {
        return [self toolGetNodeDetail:arguments];
    }
    if ([toolName isEqualToString:@"get_node_screenshot"]) {
        return [self toolGetNodeScreenshot:arguments];
    }

    return [self toolErrorResultWithMessage:[NSString stringWithFormat:@"Unknown tool: %@", toolName ?: @""] suggestion:nil structured:@{}];
}

- (NSDictionary *)toolListApps {
    NSError *error = nil;
    NSArray<LKInspectableApp *> *apps = [self.sessionManager scanAppsWithError:&error];
    if (!apps) {
        return [self toolErrorResultWithError:error structured:@{}];
    }
    NSArray *summaries = [apps lookin_map:^id(NSUInteger idx, LKInspectableApp *value) {
        return [self.sessionManager appSummaryForApp:value];
    }] ?: @[];
    NSString *text = [NSString stringWithFormat:@"Found %@ inspectable app(s).", @(summaries.count)];
    return [self toolSuccessResultWithText:text structured:@{@"apps": summaries}];
}

- (NSDictionary *)toolConnectApp:(NSDictionary *)arguments {
    NSString *appRef = arguments[@"app_ref"];
    NSString *bundleID = arguments[@"bundle_id"];
    if (appRef.length == 0 && bundleID.length == 0) {
        return [self toolErrorResultWithMessage:@"connect_app requires app_ref or bundle_id." suggestion:nil structured:@{}];
    }

    NSError *scanError = nil;
    NSArray<LKInspectableApp *> *apps = [self.sessionManager scanAppsWithError:&scanError];
    if (!apps) {
        return [self toolErrorResultWithError:scanError structured:@{}];
    }

    NSArray<LKInspectableApp *> *matches = [apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(LKInspectableApp *app, NSDictionary<NSString *,id> * _Nullable bindings) {
        NSDictionary *summary = [self.sessionManager appSummaryForApp:app];
        if (appRef.length > 0) {
            return [summary[@"app_ref"] isEqualToString:appRef];
        }
        return [summary[@"bundle_id"] isEqualToString:bundleID];
    }]];

    if (matches.count == 0) {
        return [self toolErrorResultWithMessage:@"No matching app was found." suggestion:@"Call list_apps first and choose one of the returned app_ref values." structured:@{}];
    }
    if (matches.count > 1) {
        NSArray *candidates = [matches lookin_map:^id(NSUInteger idx, LKInspectableApp *value) {
            return [self.sessionManager appSummaryForApp:value];
        }] ?: @[];
        return [self toolErrorResultWithMessage:@"More than one app matched the request." suggestion:@"Retry with app_ref for an exact match." structured:@{@"matched_apps": candidates}];
    }

    NSError *connectError = nil;
    BOOL connected = [self.sessionManager connectToApp:matches.firstObject error:&connectError];
    if (!connected) {
        return [self toolErrorResultWithError:connectError structured:@{}];
    }

    NSDictionary *summary = [self.sessionManager appSummaryForApp:matches.firstObject];
    return [self toolSuccessResultWithText:[NSString stringWithFormat:@"Connected to %@ on %@.", summary[@"app_name"], summary[@"device_name"]] structured:@{
        @"session": [self sessionStatusPayload],
        @"app": summary
    }];
}

- (NSDictionary *)toolSessionStatus {
    return [self toolSuccessResultWithText:[NSString stringWithFormat:@"Session is %@.", self.sessionManager.stateName] structured:[self sessionStatusPayload]];
}

- (NSDictionary *)toolDisconnectApp {
    [self.imageWriter clearSessionArtifacts];
    [self.sessionManager disconnect];
    return [self toolSuccessResultWithText:@"Disconnected the active session." structured:[self sessionStatusPayload]];
}

- (NSDictionary *)toolGetHierarchy {
    NSError *availabilityError = [self ensureConnectedSession];
    if (availabilityError) {
        return [self toolErrorResultWithError:availabilityError structured:[self sessionStatusPayload]];
    }

    NSError *fetchError = nil;
    LookinHierarchyInfo *info = LookinMCPWaitForSingleValue([self.sessionManager.currentApp fetchHierarchyData], 6, &fetchError);
    if (!info) {
        return [self toolErrorResultWithError:fetchError structured:[self sessionStatusPayload]];
    }

    [self.snapshotStore replaceWithHierarchyInfo:info];
    NSDictionary *payload = [self.snapshotStore hierarchyPayload] ?: @{};
    return [self toolSuccessResultWithText:[NSString stringWithFormat:@"Fetched hierarchy snapshot %@.", self.snapshotStore.snapshotIdentifier] structured:payload];
}

- (NSDictionary *)toolFindNodes:(NSDictionary *)arguments {
    NSError *snapshotError = [self ensureValidSnapshot];
    if (snapshotError) {
        return [self toolErrorResultWithError:snapshotError structured:[self sessionStatusPayload]];
    }

    NSString *query = arguments[@"query"];
    NSString *className = arguments[@"class_name"];
    BOOL visibleOnly = arguments[@"visible_only"] ? [arguments[@"visible_only"] boolValue] : NO;
    NSUInteger limit = arguments[@"limit"] ? MAX(1, [arguments[@"limit"] unsignedIntegerValue]) : 50;

    NSArray *matches = [self.snapshotStore findNodesMatchingQuery:query className:className visibleOnly:visibleOnly limit:limit];
    return [self toolSuccessResultWithText:[NSString stringWithFormat:@"Found %@ node(s).", @(matches.count)] structured:@{
        @"snapshot_id": self.snapshotStore.snapshotIdentifier ?: @"",
        @"matches": matches
    }];
}

- (NSDictionary *)toolGetNodeDetail:(NSDictionary *)arguments {
    NSError *snapshotError = [self ensureValidSnapshot];
    if (snapshotError) {
        return [self toolErrorResultWithError:snapshotError structured:[self sessionStatusPayload]];
    }

    NSString *nodeID = LookinMCPStringFromValue(arguments[@"node_id"]);
    if (nodeID.length == 0) {
        return [self toolErrorResultWithMessage:@"get_node_detail requires node_id." suggestion:nil structured:@{}];
    }

    LookinDisplayItem *item = [self.snapshotStore itemForNodeID:nodeID];
    if (!item) {
        NSError *nodeError = LookinMCPMakeError(LookinMCPErrorCodeNodeNotFound, @"The node was not found in the current snapshot.", @"Call get_hierarchy again to refresh the snapshot.");
        return [self toolErrorResultWithError:nodeError structured:@{@"snapshot_id": self.snapshotStore.snapshotIdentifier ?: @""}];
    }

    NSError *availabilityError = [self ensureConnectedSession];
    if (availabilityError) {
        return [self toolErrorResultWithError:availabilityError structured:[self sessionStatusPayload]];
    }

    NSError *detailError = nil;
    BOOL success = [self.detailFetcher ensureDetailForItem:item app:self.sessionManager.currentApp includeAttributes:YES screenshotKind:nil error:&detailError];
    if (!success) {
        return [self toolErrorResultWithError:detailError structured:@{@"snapshot_id": self.snapshotStore.snapshotIdentifier ?: @"", @"node_id": nodeID}];
    }

    NSMutableDictionary *structured = [@{
        @"snapshot_id": self.snapshotStore.snapshotIdentifier ?: @"",
        @"node": [self.snapshotStore normalizedNodeForItem:item includeChildren:NO] ?: @{},
        @"attributes": [self.attributeFormatter normalizedAttributesForDisplayItem:item] ?: @[]
    } mutableCopy];
    if ([arguments[@"include_raw"] boolValue]) {
        structured[@"raw"] = [self.attributeFormatter rawSummaryForDisplayItem:item] ?: @{};
    }

    return [self toolSuccessResultWithText:[NSString stringWithFormat:@"Loaded detail for node %@.", nodeID] structured:structured];
}

- (NSDictionary *)toolGetNodeScreenshot:(NSDictionary *)arguments {
    NSError *snapshotError = [self ensureValidSnapshot];
    if (snapshotError) {
        return [self toolErrorResultWithError:snapshotError structured:[self sessionStatusPayload]];
    }

    NSString *nodeID = LookinMCPStringFromValue(arguments[@"node_id"]);
    NSString *kind = LookinMCPStringFromValue(arguments[@"kind"]);
    if (nodeID.length == 0) {
        return [self toolErrorResultWithMessage:@"get_node_screenshot requires node_id." suggestion:nil structured:@{}];
    }
    if (kind.length == 0) {
        kind = @"appropriate";
    }
    NSSet<NSString *> *allowedKinds = [NSSet setWithArray:@[@"appropriate", @"group", @"solo"]];
    if (![allowedKinds containsObject:kind]) {
        return [self toolErrorResultWithMessage:@"kind must be one of appropriate, group, or solo." suggestion:nil structured:@{}];
    }

    LookinDisplayItem *item = [self.snapshotStore itemForNodeID:nodeID];
    if (!item) {
        NSError *nodeError = LookinMCPMakeError(LookinMCPErrorCodeNodeNotFound, @"The node was not found in the current snapshot.", @"Call get_hierarchy again to refresh the snapshot.");
        return [self toolErrorResultWithError:nodeError structured:@{@"snapshot_id": self.snapshotStore.snapshotIdentifier ?: @""}];
    }

    NSError *availabilityError = [self ensureConnectedSession];
    if (availabilityError) {
        return [self toolErrorResultWithError:availabilityError structured:[self sessionStatusPayload]];
    }

    NSError *detailError = nil;
    BOOL success = [self.detailFetcher ensureDetailForItem:item app:self.sessionManager.currentApp includeAttributes:NO screenshotKind:kind error:&detailError];
    if (!success) {
        return [self toolErrorResultWithError:detailError structured:@{@"snapshot_id": self.snapshotStore.snapshotIdentifier ?: @"", @"node_id": nodeID}];
    }

    NSDictionary *node = [self.snapshotStore normalizedNodeForItem:item includeChildren:NO] ?: @{};
    NSDictionary *status = node[@"screenshot_status"] ?: @{};
    NSImage *image = nil;
    if ([kind isEqualToString:@"group"]) {
        image = item.groupScreenshot;
    } else if ([kind isEqualToString:@"solo"]) {
        image = item.soloScreenshot;
    } else {
        image = item.appropriateScreenshot;
    }

    if (!image) {
        id unavailableReason = status[@"unavailable_reason"];
        if (!unavailableReason || unavailableReason == [NSNull null]) {
            unavailableReason = @"not_fetched";
        }
        return [self toolSuccessResultWithText:[NSString stringWithFormat:@"Screenshot for node %@ is unavailable.", nodeID] structured:@{
            @"snapshot_id": self.snapshotStore.snapshotIdentifier ?: @"",
            @"node_id": nodeID,
            @"kind": kind,
            @"available": @NO,
            @"screenshot_status": status,
            @"unavailable_reason": unavailableReason
        }];
    }

    NSError *writeError = nil;
    NSDictionary *imageInfo = [self.imageWriter writeImage:image nodeID:nodeID kind:kind error:&writeError];
    if (!imageInfo) {
        return [self toolErrorResultWithError:writeError structured:@{@"snapshot_id": self.snapshotStore.snapshotIdentifier ?: @"", @"node_id": nodeID}];
    }

    NSMutableDictionary *structured = [@{
        @"snapshot_id": self.snapshotStore.snapshotIdentifier ?: @"",
        @"node_id": nodeID,
        @"kind": kind,
        @"available": @YES,
        @"screenshot_status": status
    } mutableCopy];
    [structured addEntriesFromDictionary:imageInfo];

    return [self toolSuccessResultWithText:[NSString stringWithFormat:@"Wrote %@ screenshot for node %@.", kind, nodeID] structured:structured];
}

- (NSError *)ensureConnectedSession {
    if (!self.sessionManager.currentApp) {
        if (self.sessionManager.state == LookinMCPSessionStateReconnecting) {
            return LookinMCPMakeError(LookinMCPErrorCodeSessionReconnecting, @"The current session is reconnecting.", @"Wait for the app to reconnect, then call session_status or get_hierarchy again.");
        }
        return LookinMCPMakeError(LookinMCPErrorCodeNoSession, @"No active inspect session.", @"Call connect_app first.");
    }
    if (self.sessionManager.state == LookinMCPSessionStateReconnecting) {
        return LookinMCPMakeError(LookinMCPErrorCodeSessionReconnecting, @"The current session is reconnecting.", @"Wait for the app to reconnect, then call session_status or get_hierarchy again.");
    }
    return nil;
}

- (NSError *)ensureValidSnapshot {
    NSError *availabilityError = [self ensureConnectedSession];
    if (availabilityError) {
        return availabilityError;
    }
    if (!self.snapshotStore.isValid || self.snapshotStore.snapshotIdentifier.length == 0) {
        return LookinMCPMakeError(LookinMCPErrorCodeSnapshotInvalid, @"The current snapshot is missing or invalid.", @"Call get_hierarchy to create a new snapshot.");
    }
    return nil;
}

- (NSDictionary *)sessionStatusPayload {
    return @{
        @"state": self.sessionManager.stateName,
        @"app": self.sessionManager.currentApp ? [self.sessionManager appSummaryForApp:self.sessionManager.currentApp] : [NSNull null],
        @"snapshot_id": self.snapshotStore.snapshotIdentifier ?: [NSNull null],
        @"snapshot_valid": @(self.snapshotStore.isValid),
        @"last_refresh_at": LookinMCPISO8601StringFromDate(self.snapshotStore.lastRefreshDate) ?: [NSNull null]
    };
}

- (NSArray<NSDictionary *> *)toolDefinitions {
    return @[
        @{
            @"name": @"list_apps",
            @"description": @"List all inspectable iOS apps currently visible to Lookin.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{}
            }
        },
        @{
            @"name": @"connect_app",
            @"description": @"Connect the MCP session to one inspectable app.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"app_ref": @{@"type": @"string"},
                    @"bundle_id": @{@"type": @"string"}
                }
            }
        },
        @{
            @"name": @"session_status",
            @"description": @"Return the active session state and current snapshot metadata.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{}
            }
        },
        @{
            @"name": @"disconnect_app",
            @"description": @"Disconnect the active app session and clear the snapshot cache.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{}
            }
        },
        @{
            @"name": @"get_hierarchy",
            @"description": @"Fetch a fresh hierarchy snapshot from the connected app.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{}
            }
        },
        @{
            @"name": @"find_nodes",
            @"description": @"Search nodes in the current snapshot.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"query": @{@"type": @"string"},
                    @"class_name": @{@"type": @"string"},
                    @"visible_only": @{@"type": @"boolean"},
                    @"limit": @{@"type": @"integer", @"minimum": @1}
                }
            }
        },
        @{
            @"name": @"get_node_detail",
            @"description": @"Load normalized attributes and metadata for one node in the current snapshot.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"node_id": @{@"type": @"string"},
                    @"include_raw": @{@"type": @"boolean"}
                },
                @"required": @[@"node_id"]
            }
        },
        @{
            @"name": @"get_node_screenshot",
            @"description": @"Write one node screenshot to a temporary PNG file and return its path.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"node_id": @{@"type": @"string"},
                    @"kind": @{@"type": @"string", @"enum": @[@"appropriate", @"group", @"solo"]}
                },
                @"required": @[@"node_id"]
            }
        }
    ];
}

- (NSDictionary *)toolSuccessResultWithText:(NSString *)text structured:(NSDictionary *)structured {
    return @{
        @"content": @[@{@"type": @"text", @"text": text ?: @""}],
        @"structuredContent": structured ?: @{},
        @"isError": @NO
    };
}

- (NSDictionary *)toolErrorResultWithError:(NSError *)error structured:(NSDictionary *)structured {
    return [self toolErrorResultWithMessage:error.localizedDescription ?: @"Unknown error." suggestion:error.localizedRecoverySuggestion structured:structured];
}

- (NSDictionary *)toolErrorResultWithMessage:(NSString *)message suggestion:(NSString *)suggestion structured:(NSDictionary *)structured {
    NSMutableDictionary *result = [@{
        @"content": @[@{@"type": @"text", @"text": message ?: @"Unknown error."}],
        @"structuredContent": structured ?: @{},
        @"isError": @YES
    } mutableCopy];
    if (suggestion.length > 0) {
        result[@"structuredContent"] = [structured ?: @{} mutableCopy];
        NSMutableDictionary *payload = [result[@"structuredContent"] mutableCopy];
        payload[@"suggestion"] = suggestion;
        result[@"structuredContent"] = payload;
    }
    return result.copy;
}

- (void)sendResult:(NSDictionary *)result forID:(id)messageID {
    [self sendPayload:@{
        @"jsonrpc": @"2.0",
        @"id": messageID ?: [NSNull null],
        @"result": result ?: @{}
    }];
}

- (void)sendJSONRPCErrorCode:(NSInteger)code message:(NSString *)message data:(id)data forID:(id)messageID {
    NSMutableDictionary *payload = [@{
        @"jsonrpc": @"2.0",
        @"id": messageID ?: [NSNull null],
        @"error": @{
            @"code": @(code),
            @"message": message ?: @"Unknown error."
        }
    } mutableCopy];
    if (data) {
        NSMutableDictionary *errorPayload = [payload[@"error"] mutableCopy];
        errorPayload[@"data"] = data;
        payload[@"error"] = errorPayload;
    }
    [self sendPayload:payload];
}

@end
