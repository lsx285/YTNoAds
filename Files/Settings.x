// Settings.x — YTNoAds
// Adds a "SponsorBlock" section directly to YouTube's native settings screen.
#import "Headers.h"

// FourCC tag for our section — unlikely to collide with YouTube's own categories.
static const NSInteger SBSection = 'ytsb';

// Forward-declare the method added by SponsorBlockSettings.x so we can call it.
@interface YTSettingsSectionItemManager (YTNoAds)
- (void)updateSponsorBlockSectionWithEntry:(id)entry;
@end

// ─── Insert our section into the category list ────────────────────────────────

%hook YTSettingsGroupData
- (NSArray<NSNumber *> *)orderedCategories {
    if (self.type != 1 || class_getClassMethod(objc_getClass("YTSettingsGroupData"), @selector(tweaks)))
        return %orig;
    NSMutableArray *cats = [%orig mutableCopy];
    [cats insertObject:@(SBSection) atIndex:0];
    return [cats copy];
}
%end

%hook YTAppSettingsPresentationData
+ (NSArray<NSNumber *> *)settingsCategoryOrder {
    NSMutableArray<NSNumber *> *order = [%orig mutableCopy];
    NSUInteger idx = [order indexOfObject:@(1)];
    if (idx != NSNotFound)
        [order insertObject:@(SBSection) atIndex:idx + 1];
    return [order copy];
}
%end

// ─── Route YouTube's section population call to SponsorBlock ─────────────────

%hook YTSettingsSectionItemManager

- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    %orig;
    if (category == (NSUInteger)SBSection)
        [self updateSponsorBlockSectionWithEntry:entry];
}

%end
