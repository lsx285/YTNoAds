// Settings.x — YTNoAds
// Adds a "SponsorBlock" entry directly to YouTube's native settings screen.
#import "Headers.h"
#import <objc/runtime.h>
#import <objc/message.h>

static const NSInteger SBSection = 'ytsb';

// Forward-declare SBSettingsViewController from SponsorBlockSettings.x
@interface SBSettingsViewController : UIViewController
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

// ─── Populate our section with one row that pushes SBSettingsViewController ──

%hook YTSettingsSectionItemManager

- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    %orig;
    if (category != (NSUInteger)SBSection) return;

    YTSettingsViewController *settingsVC =
        [self valueForKey:@"_settingsViewControllerDelegate"];
    Class Item = %c(YTSettingsSectionItem);

    YTSettingsSectionItem *sbRow = [Item
        itemWithTitle:@"SponsorBlock"
        accessibilityIdentifier:nil
        detailTextBlock:nil
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            Class sbClass = objc_getClass("SBSettingsViewControllerStyled");
            if (!sbClass) sbClass = [SBSettingsViewController class];
            id allocated = [sbClass alloc];
            SBSettingsViewController *sbVC =
                (SBSettingsViewController *)((id (*)(id, SEL, id))objc_msgSend)
                    (allocated, @selector(initWithParentResponder:), settingsVC);
            [settingsVC pushViewController:sbVC];
            return YES;
        }];

    YTIIcon *icon = [%c(YTIIcon) new];
    icon.iconType = 530;
    sbRow.settingIcon = icon;

    NSMutableArray<YTSettingsSectionItem *> *items =
        [NSMutableArray arrayWithObject:sbRow];

    // headerHidden:YES suppresses the section title so only the row is visible,
    // giving the appearance of a single flat entry in the settings list.
    if ([settingsVC respondsToSelector:
            @selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:)])
        [settingsVC setSectionItems:items
                        forCategory:SBSection
                              title:@"SponsorBlock"
                               icon:icon
                   titleDescription:nil
                       headerHidden:YES];
    else
        [settingsVC setSectionItems:items
                        forCategory:SBSection
                              title:@"SponsorBlock"
                   titleDescription:nil
                       headerHidden:YES];
}

%end
