#import <Foundation/Foundation.h>
#import "LookinAttribute.h"

@class LookinDisplayItem;
@class LookinAttribute;

NS_ASSUME_NONNULL_BEGIN

@interface LookinMCPAttributeFormatter : NSObject

- (NSArray<NSDictionary *> *)normalizedAttributesForDisplayItem:(LookinDisplayItem *)item;
- (NSDictionary *)rawSummaryForDisplayItem:(LookinDisplayItem *)item;
- (NSString *)stringValueForAttribute:(LookinAttribute *)attribute;
- (NSString *)stringForAttributeType:(LookinAttrType)type;

@end

NS_ASSUME_NONNULL_END
