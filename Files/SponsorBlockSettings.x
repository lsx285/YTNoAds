// SponsorBlockSettings.x — YTNoAds
#import "Headers.h"

static NSString *SBCategoryName(NSString *category) {
    static NSDictionary *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @{
            @"sponsor":        @"Sponsor",
            @"intro":          @"Intro",
            @"outro":          @"Endcards",
            @"interaction":    @"Interaction",
            @"selfpromo":      @"Self-promotion",
            @"music_offtopic": @"Non-music",
            @"preview":        @"Preview",
            @"poi_highlight":  @"Highlight",
            @"filler":         @"Filler",
        };
    });
    return names[category] ?: category;
}

static NSString *SBActionName(NSInteger action) {
    switch (action) {
        case SBSegmentActionAutoSkip: return @"Auto-skip";
        case SBSegmentActionAsk:      return @"Ask before skipping";
        case SBSegmentActionDisplay:  return @"Show on seek bar only";
        case SBSegmentActionSkipTo:   return @"Skip to segment";
        default:                      return @"Disable";
    }
}

#pragma mark - Hook entry point

// Must match the SBSection FourCC defined in Settings.x
static const NSInteger kSBSectionCategory = 'ytsb';

@interface YTSettingsSectionItemManager (SponsorBlock)
- (void)updateSponsorBlockSectionWithEntry:(id)entry;
@end

%hook YTSettingsSectionItemManager

%new(v@:@)
- (void)updateSponsorBlockSectionWithEntry:(id)entry {
    YTSettingsViewController *settingsVC = [self valueForKey:@"_settingsViewControllerDelegate"];

    // Build the SponsorBlock settings items using a native YTSettingsSectionItem row
    // for each toggle/slider/category — mirroring what SBSettingsViewController showed,
    // but registered directly as a YouTube settings section so it appears inline.
    NSMutableArray<YTSettingsSectionItem *> *items = [NSMutableArray array];
    Class Item = %c(YTSettingsSectionItem);

    // ── Main toggles ──────────────────────────────────────────────────────────

    struct { NSString *title; NSString *desc; NSString *key; } toggleDefs[] = {
        { @"Enable SponsorBlock",          @"Skip sponsored segments automatically using community-submitted data.", SBEnabled },
        { @"Show overlay button",          @"Display a SponsorBlock toggle button in the player overlay.", SBShowButton },
        { @"Show notifications",           @"Display notifications when segments are skipped.", SBShowNotifications },
        { @"Haptic feedback",              @"Provide haptic feedback when a segment is skipped.", SBAudioNotification },
        { @"Segments in feed",             @"Display colored segments on the progress bar of players in the feed.", SBSegmentsInFeed },
        { @"Segments in mini-player",      @"Display colored segments on the progress bar of the mini-player.", SBSegmentsInMiniPlayer },
        { @"Show duration without segments", @"Display the total video duration excluding skippable segments.", SBShowDuration },
    };

    for (NSUInteger i = 0; i < sizeof(toggleDefs) / sizeof(toggleDefs[0]); i++) {
        NSString *key = toggleDefs[i].key;
        YTSettingsSectionItem *item = [Item switchItemWithTitle:toggleDefs[i].title
            titleDescription:toggleDefs[i].desc
            accessibilityIdentifier:nil
            switchOn:[[NSUserDefaults standardUserDefaults] boolForKey:key]
            switchBlock:^BOOL(YTSettingsCell *cell, BOOL enabled) {
                [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:key];
                return YES;
            }
            settingItemId:0
        ];
        [items addObject:item];
    }

    // ── Per-category action rows ───────────────────────────────────────────────

    NSArray<NSString *> *categories = @[@"sponsor", @"intro", @"outro", @"interaction",
                                        @"selfpromo", @"music_offtopic", @"preview",
                                        @"poi_highlight", @"filler"];

    for (NSString *cat in categories) {
        NSString *catName = SBCategoryName(cat);
        NSString *actionKey = SB_ACTION_KEY(cat);
        BOOL isHighlight = [cat isEqualToString:@"poi_highlight"];

        YTSettingsSectionItem *catItem = [Item itemWithTitle:catName
            titleDescription:nil
            accessibilityIdentifier:nil
            detailTextBlock:^NSString *{
                return SBActionName([[NSUserDefaults standardUserDefaults] integerForKey:actionKey]);
            }
            selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
                NSArray<NSNumber *> *actionVals = isHighlight
                    ? @[@(SBSegmentActionDisable), @(SBSegmentActionSkipTo), @(SBSegmentActionDisplay)]
                    : @[@(SBSegmentActionDisable), @(SBSegmentActionAutoSkip), @(SBSegmentActionAsk), @(SBSegmentActionDisplay)];

                UIAlertController *alert = [UIAlertController alertControllerWithTitle:catName
                    message:nil
                    preferredStyle:UIAlertControllerStyleActionSheet];

                for (NSNumber *num in actionVals) {
                    NSInteger val = [num integerValue];
                    UIAlertAction *action = [UIAlertAction actionWithTitle:SBActionName(val)
                        style:UIAlertActionStyleDefault
                        handler:^(UIAlertAction *a) {
                            [[NSUserDefaults standardUserDefaults] setInteger:val forKey:actionKey];
                            [settingsVC reloadData];
                        }
                    ];
                    [alert addAction:action];
                }

                [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
                [settingsVC presentViewController:alert animated:YES completion:nil];
                return YES;
            }
        ];
        [items addObject:catItem];
    }

    // Register items as the SponsorBlock section
    if ([settingsVC respondsToSelector:@selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:)])
        [settingsVC setSectionItems:items forCategory:kSBSectionCategory title:@"SponsorBlock" icon:nil titleDescription:nil headerHidden:NO];
    else
        [settingsVC setSectionItems:items forCategory:kSBSectionCategory title:@"SponsorBlock" titleDescription:nil headerHidden:NO];
}

%end

%ctor {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        SBEnabled: @YES,
        SBShowButton: @YES,
        SBShowNotifications: @YES,
        SBAudioNotification: @NO,
        SBSegmentsInFeed: @NO,
        SBSegmentsInMiniPlayer: @YES,
        SBShowDuration: @NO,
        SBSkipAlertDuration: @4.0,
        SBUnskipAlertDuration: @4.0,
        SB_ACTION_KEY(@"sponsor"): @(SBSegmentActionAutoSkip),
        SB_ACTION_KEY(@"intro"): @(SBSegmentActionAutoSkip),
        SB_ACTION_KEY(@"outro"): @(SBSegmentActionAutoSkip),
        SB_ACTION_KEY(@"interaction"): @(SBSegmentActionAutoSkip),
        SB_ACTION_KEY(@"selfpromo"): @(SBSegmentActionAutoSkip),
        SB_ACTION_KEY(@"music_offtopic"): @(SBSegmentActionAutoSkip),
        SB_ACTION_KEY(@"preview"): @(SBSegmentActionAutoSkip),
        SB_ACTION_KEY(@"poi_highlight"): @(SBSegmentActionSkipTo),
        SB_ACTION_KEY(@"filler"): @(SBSegmentActionDisplay),
        SB_COLOR_KEY(@"sponsor"): @"#00D400",
        SB_COLOR_KEY(@"intro"): @"#00FFFF",
        SB_COLOR_KEY(@"outro"): @"#0202ED",
        SB_COLOR_KEY(@"interaction"): @"#CC00FF",
        SB_COLOR_KEY(@"selfpromo"): @"#FFFF00",
        SB_COLOR_KEY(@"music_offtopic"): @"#FF9900",
        SB_COLOR_KEY(@"preview"): @"#008FD6",
        SB_COLOR_KEY(@"poi_highlight"): @"#FFFFFF",
        SB_COLOR_KEY(@"filler"): @"#7300FF",
    }];
    %init;
}
