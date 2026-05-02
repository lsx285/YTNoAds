// Settings.x — YTNoAds
// Adds a "YTNoAds" section to YouTube's native settings screen.
// The only item is a SponsorBlock entry that opens SBSettingsViewController
// (implemented in SponsorBlockSettings.x).
#import "Headers.h"

// The numeric tag for our custom settings category.
// Uses a FourCC so it's unlikely to collide with YouTube's own categories.
static const NSInteger YTNoAdsSection = 'ynoa';

// Forward-declare the method added by SponsorBlockSettings.x so we can call it.
@interface YTSettingsSectionItemManager (YTNoAds)
- (void)updateYTNoAdsSectionWithEntry:(id)entry;
- (void)updateSponsorBlockSectionWithEntry:(id)entry;
@end

// ─── Insert our section into the category list ────────────────────────────────

%hook YTSettingsGroupData
- (NSArray<NSNumber *> *)orderedCategories {
    // Only patch the primary settings group (type == 1).
    if (self.type != 1 || class_getClassMethod(objc_getClass("YTSettingsGroupData"), @selector(tweaks)))
        return %orig;
    NSMutableArray *cats = [%orig mutableCopy];
    [cats insertObject:@(YTNoAdsSection) atIndex:0];
    return [cats copy];
}
%end

%hook YTAppSettingsPresentationData
+ (NSArray<NSNumber *> *)settingsCategoryOrder {
    NSMutableArray<NSNumber *> *order = [[%orig] mutableCopy];
    NSUInteger idx = [order indexOfObject:@(1)];
    if (idx != NSNotFound)
        [order insertObject:@(YTNoAdsSection) atIndex:idx + 1];
    return [order copy];
}
%end

// ─── Populate our section when YouTube asks for it ────────────────────────────

%hook YTSettingsSectionItemManager

%new(v@:@)
- (void)updateYTNoAdsSectionWithEntry:(id)entry {
    NSMutableArray<YTSettingsSectionItem *> *items = [NSMutableArray array];
    Class Item = %c(YTSettingsSectionItem);
    YTSettingsViewController *settingsVC = [self valueForKey:@"_settingsViewControllerDelegate"];

    // SponsorBlock row — tapping pushes SBSettingsViewController.
    YTSettingsSectionItem *sbItem = [Item itemWithTitle:@"SponsorBlock"
        titleDescription:@"Skip sponsored segments automatically using community-submitted data."
        accessibilityIdentifier:nil
        detailTextBlock:nil
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            [self updateSponsorBlockSectionWithEntry:entry];
            return YES;
        }
    ];
    [items addObject:sbItem];

    // Register the items under our section.
    if ([settingsVC respondsToSelector:@selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:)])
        [settingsVC setSectionItems:items forCategory:YTNoAdsSection title:@"YTNoAds" icon:nil titleDescription:nil headerHidden:NO];
    else
        [settingsVC setSectionItems:items forCategory:YTNoAdsSection title:@"YTNoAds" titleDescription:nil headerHidden:NO];
}

// YouTube calls this whenever it needs to populate a settings section.
- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    %orig;
    if (category == (NSUInteger)YTNoAdsSection)
        [self updateYTNoAdsSectionWithEntry:entry];
}

%end
