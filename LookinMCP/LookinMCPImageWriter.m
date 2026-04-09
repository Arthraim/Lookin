#import "LookinMCPImageWriter.h"
#import "LookinMCPUtilities.h"

@interface LookinMCPImageWriter ()

@property(nonatomic, copy) NSString * (^sessionIdentifierProvider)(void);

@end

@implementation LookinMCPImageWriter

- (instancetype)initWithSessionIdentifierProvider:(NSString * (^)(void))sessionIdentifierProvider {
    self = [super init];
    if (self) {
        _sessionIdentifierProvider = [sessionIdentifierProvider copy];
    }
    return self;
}

- (NSDictionary *)writeImage:(NSImage *)image nodeID:(NSString *)nodeID kind:(NSString *)kind error:(NSError **)error {
    if (!image) {
        if (error) {
            *error = LookinMCPMakeError(LookinMCPErrorCodeIO, @"The screenshot is unavailable.", nil);
        }
        return nil;
    }

    NSString *sessionIdentifier = self.sessionIdentifierProvider ? self.sessionIdentifierProvider() : @"unknown-session";
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"lookin-mcp/%@", LookinMCPSanitizePathComponent(sessionIdentifier)]];
    NSError *dirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&dirError];
    if (dirError) {
        if (error) {
            *error = dirError;
        }
        return nil;
    }

    NSString *fileName = [NSString stringWithFormat:@"node-%@-%@.png", LookinMCPSanitizePathComponent(nodeID), LookinMCPSanitizePathComponent(kind)];
    NSString *path = [directory stringByAppendingPathComponent:fileName];

    NSData *tiffData = [image TIFFRepresentation];
    NSBitmapImageRep *representation = [[NSBitmapImageRep alloc] initWithData:tiffData];
    NSData *pngData = [representation representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (!tiffData || !representation || !pngData) {
        if (error) {
            *error = LookinMCPMakeError(LookinMCPErrorCodeIO, @"Failed to encode the screenshot as PNG.", nil);
        }
        return nil;
    }
    NSError *writeError = nil;
    BOOL success = [pngData writeToFile:path options:NSDataWritingAtomic error:&writeError];
    if (!success || writeError) {
        if (error) {
            *error = writeError ?: LookinMCPMakeError(LookinMCPErrorCodeIO, @"Failed to write the screenshot to disk.", nil);
        }
        return nil;
    }

    CGFloat scale = image.size.width > 0 ? (CGFloat)representation.pixelsWide / image.size.width : 1;
    return @{
        @"path": path,
        @"point_size": @{
            @"width": @(image.size.width),
            @"height": @(image.size.height)
        },
        @"pixel_size": @{
            @"width": @(representation.pixelsWide),
            @"height": @(representation.pixelsHigh)
        },
        @"scale": @(scale > 0 ? scale : 1)
    };
}

- (void)clearSessionArtifacts {
    NSString *sessionIdentifier = self.sessionIdentifierProvider ? self.sessionIdentifierProvider() : nil;
    if (sessionIdentifier.length == 0) {
        return;
    }
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"lookin-mcp/%@", LookinMCPSanitizePathComponent(sessionIdentifier)]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:directory]) {
        [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
    }
}

@end
