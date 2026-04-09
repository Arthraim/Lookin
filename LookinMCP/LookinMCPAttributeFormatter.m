#import "LookinMCPAttributeFormatter.h"
#import "LookinMCPUtilities.h"
#import "LookinAttributesGroup+LookinClient.h"
#import "NSColor+LookinClient.h"
#import "LKEnumListRegistry.h"
#import "LookinDisplayItem.h"
#import "LookinAttributesGroup.h"
#import "LookinAttributesSection.h"
#import "LookinAttribute.h"
#import "LookinDashboardBlueprint.h"

@implementation LookinMCPAttributeFormatter

- (NSArray<NSDictionary *> *)normalizedAttributesForDisplayItem:(LookinDisplayItem *)item {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    NSArray<LookinAttributesGroup *> *groups = [item queryAllAttrGroupList];
    [groups enumerateObjectsUsingBlock:^(LookinAttributesGroup * _Nonnull group, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *groupTitle = [group queryDisplayTitle] ?: @"";
        [group.attrSections enumerateObjectsUsingBlock:^(LookinAttributesSection * _Nonnull section, NSUInteger idx, BOOL * _Nonnull stop) {
            NSString *sectionTitle = [self sectionTitleForSection:section];
            [section.attributes enumerateObjectsUsingBlock:^(LookinAttribute * _Nonnull attr, NSUInteger idx, BOOL * _Nonnull stop) {
                NSString *displayTitle = attr.displayTitle ?: [LookinDashboardBlueprint fullTitleWithAttrID:attr.identifier] ?: @"";
                [result addObject:@{
                    @"group_title": groupTitle,
                    @"group_id": group.identifier ?: @"",
                    @"section_title": sectionTitle ?: @"",
                    @"section_id": section.identifier ?: @"",
                    @"attr_id": attr.identifier ?: @"",
                    @"display_title": displayTitle,
                    @"attr_type": [self stringForAttributeType:attr.attrType],
                    @"value_text": [self stringValueForAttribute:attr] ?: @"",
                    @"is_user_custom": @(attr.isUserCustom),
                    @"raw_value_present": @(attr.value != nil)
                }];
            }];
        }];
    }];
    return result.copy;
}

- (NSDictionary *)rawSummaryForDisplayItem:(LookinDisplayItem *)item {
    return @{
        @"has_group_screenshot": @(item.groupScreenshot != nil),
        @"has_solo_screenshot": @(item.soloScreenshot != nil),
        @"attributes_group_count": @(item.attributesGroupList.count),
        @"custom_attributes_group_count": @(item.customAttrGroupList.count),
        @"frame": LookinMCPRectJSON(item.frame),
        @"bounds": LookinMCPRectJSON(item.bounds),
        @"alpha": @(item.alpha),
        @"hidden": @(item.isHidden),
        @"custom_display_title": item.customDisplayTitle ?: @"",
        @"danceui_source_present": @(((NSString *)item.danceuiSource).length > 0)
    };
}

- (NSString *)sectionTitleForSection:(LookinAttributesSection *)section {
    NSString *customTitle = LookinMCPValueForKey(section, @"userCustomTitle");
    if (customTitle.length > 0) {
        return customTitle;
    }
    return [LookinDashboardBlueprint sectionTitleWithSectionID:section.identifier] ?: @"";
}

- (NSString *)stringValueForAttribute:(LookinAttribute *)attribute {
    switch (attribute.attrType) {
        case LookinAttrTypeNone:
        case LookinAttrTypeVoid:
        case LookinAttrTypeCustomObj:
            return @"";

        case LookinAttrTypeChar:
        case LookinAttrTypeInt:
        case LookinAttrTypeShort:
        case LookinAttrTypeLong:
        case LookinAttrTypeLongLong:
        case LookinAttrTypeUnsignedChar:
        case LookinAttrTypeUnsignedInt:
        case LookinAttrTypeUnsignedShort:
        case LookinAttrTypeUnsignedLong:
        case LookinAttrTypeUnsignedLongLong:
        case LookinAttrTypeFloat:
        case LookinAttrTypeDouble:
        case LookinAttrTypeSel:
        case LookinAttrTypeClass:
        case LookinAttrTypeCGVector:
        case LookinAttrTypeCGAffineTransform:
        case LookinAttrTypeUIOffset:
            return LookinMCPStringFromValue(attribute.value);

        case LookinAttrTypeBOOL:
            return [attribute.value boolValue] ? @"YES" : @"NO";

        case LookinAttrTypeCGPoint:
            return [NSString lookin_stringFromPoint:[(NSValue *)attribute.value pointValue]];
        case LookinAttrTypeCGSize:
            return [NSString lookin_stringFromSize:[(NSValue *)attribute.value sizeValue]];
        case LookinAttrTypeCGRect:
            return [NSString lookin_stringFromRect:[(NSValue *)attribute.value rectValue]];
        case LookinAttrTypeUIEdgeInsets:
            return [NSString lookin_stringFromInset:[(NSValue *)attribute.value edgeInsetsValue]];

        case LookinAttrTypeNSString:
        case LookinAttrTypeEnumString:
            return LookinMCPStringFromValue(attribute.value);

        case LookinAttrTypeEnumInt:
        case LookinAttrTypeEnumLong: {
            NSInteger enumValue = [attribute.value integerValue];
            NSString *enumListName = [LookinDashboardBlueprint enumListNameWithAttrID:attribute.identifier];
            NSString *enumString = [[LKEnumListRegistry sharedInstance] descForEnumName:enumListName value:enumValue];
            return enumString.length > 0 ? enumString : LookinMCPStringFromValue(attribute.value);
        }

        case LookinAttrTypeUIColor: {
            NSColor *color = [NSColor lk_colorFromRGBAComponents:attribute.value];
            if (!color) {
                return @"nil";
            }
            NSNumber *rgbaFormat = [[NSUserDefaults standardUserDefaults] objectForKey:@"egbaFormat"];
            BOOL useRGBA = rgbaFormat ? rgbaFormat.boolValue : YES;
            return useRGBA ? color.rgbaString : color.hexString;
        }

        case LookinAttrTypeShadow:
        case LookinAttrTypeJson:
            return @"……";
    }

    return @"";
}

- (NSString *)stringForAttributeType:(LookinAttrType)type {
    switch (type) {
        case LookinAttrTypeNone:
            return @"none";
        case LookinAttrTypeVoid:
            return @"void";
        case LookinAttrTypeBOOL:
            return @"bool";
        case LookinAttrTypeChar:
            return @"char";
        case LookinAttrTypeInt:
            return @"int";
        case LookinAttrTypeShort:
            return @"short";
        case LookinAttrTypeLong:
            return @"long";
        case LookinAttrTypeLongLong:
            return @"long_long";
        case LookinAttrTypeUnsignedChar:
            return @"unsigned_char";
        case LookinAttrTypeUnsignedInt:
            return @"unsigned_int";
        case LookinAttrTypeUnsignedShort:
            return @"unsigned_short";
        case LookinAttrTypeUnsignedLong:
            return @"unsigned_long";
        case LookinAttrTypeUnsignedLongLong:
            return @"unsigned_long_long";
        case LookinAttrTypeFloat:
            return @"float";
        case LookinAttrTypeDouble:
            return @"double";
        case LookinAttrTypeCGPoint:
            return @"cg_point";
        case LookinAttrTypeCGSize:
            return @"cg_size";
        case LookinAttrTypeCGRect:
            return @"cg_rect";
        case LookinAttrTypeUIEdgeInsets:
            return @"edge_insets";
        case LookinAttrTypeUIOffset:
            return @"ui_offset";
        case LookinAttrTypeCGVector:
            return @"cg_vector";
        case LookinAttrTypeCGAffineTransform:
            return @"cg_affine_transform";
        case LookinAttrTypeNSString:
            return @"string";
        case LookinAttrTypeUIColor:
            return @"color";
        case LookinAttrTypeShadow:
            return @"shadow";
        case LookinAttrTypeSel:
            return @"selector";
        case LookinAttrTypeClass:
            return @"class";
        case LookinAttrTypeEnumInt:
            return @"enum_int";
        case LookinAttrTypeEnumLong:
            return @"enum_long";
        case LookinAttrTypeEnumString:
            return @"enum_string";
        case LookinAttrTypeCustomObj:
            return @"custom_object";
        case LookinAttrTypeJson:
            return @"json";
    }

    return @"unknown";
}

@end
