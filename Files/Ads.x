#import "Headers.h"

// YouTube-X (https://github.com/PoomSmart/YouTube-X)
static BOOL isProductList(YTICommand *command) {
    if ([command respondsToSelector:@selector(yt_showEngagementPanelEndpoint)]) {
        YTIShowEngagementPanelEndpoint *endpoint = [command yt_showEngagementPanelEndpoint];
        return [endpoint.identifier.tag isEqualToString:@"PAproduct_list"];
    }
    return NO;
}

NSString *getAdString(NSString *description) {
    for (NSString *str in @[
        @"brand_promo",
        @"carousel_footered_layout",
        @"carousel_headered_layout",
        @"eml.expandable_metadata",
        @"feed_ad_metadata",
        @"full_width_portrait_image_layout",
        @"full_width_square_image_layout",
        @"landscape_image_wide_button_layout",
        @"post_shelf",
        @"product_carousel",
        @"product_engagement_panel",
        @"product_item",
        @"shopping_carousel",
        @"shopping_item_card_list",
        @"statement_banner",
        @"square_image_layout",
        @"text_image_button_layout",
        @"text_search_ad",
        @"video_display_full_layout",
        @"video_display_full_buttoned_layout"
    ])
        if ([description containsString:str]) return str;
    return nil;
}

static BOOL isAdRenderer(YTIElementRenderer *elementRenderer, int kind) {
    if ([elementRenderer respondsToSelector:@selector(hasCompatibilityOptions)] && elementRenderer.hasCompatibilityOptions && elementRenderer.compatibilityOptions.hasAdLoggingData) {
        return YES;
    }
    NSString *description = [elementRenderer description];
    NSString *adString = getAdString(description);
    if (adString) {
        return YES;
    }
    return NO;
}

static NSMutableArray <YTIItemSectionRenderer *> *filteredArray(NSArray <YTIItemSectionRenderer *> *array) {
    NSMutableArray <YTIItemSectionRenderer *> *newArray = [array mutableCopy];
    NSIndexSet *removeIndexes = [newArray indexesOfObjectsPassingTest:^BOOL(YTIItemSectionRenderer *sectionRenderer, NSUInteger idx, BOOL *stop) {
        if ([sectionRenderer isKindOfClass:%c(YTIShelfRenderer)]) {
            YTIShelfSupportedRenderers *content = ((YTIShelfRenderer *)sectionRenderer).content;
            YTIHorizontalListRenderer *horizontalListRenderer = content.horizontalListRenderer;
            NSMutableArray <YTIHorizontalListSupportedRenderers *> *itemsArray = horizontalListRenderer.itemsArray;
            NSIndexSet *removeItemsArrayIndexes = [itemsArray indexesOfObjectsPassingTest:^BOOL(YTIHorizontalListSupportedRenderers *horizontalListSupportedRenderers, NSUInteger idx2, BOOL *stop2) {
                YTIElementRenderer *elementRenderer = horizontalListSupportedRenderers.elementRenderer;
                return isAdRenderer(elementRenderer, 4);
            }];
            [itemsArray removeObjectsAtIndexes:removeItemsArrayIndexes];
        }
        if (![sectionRenderer isKindOfClass:%c(YTIItemSectionRenderer)])
            return NO;
        NSMutableArray <YTIItemSectionSupportedRenderers *> *contentsArray = sectionRenderer.contentsArray;
        if (contentsArray.count > 1) {
            NSIndexSet *removeContentsArrayIndexes = [contentsArray indexesOfObjectsPassingTest:^BOOL(YTIItemSectionSupportedRenderers *sectionSupportedRenderers, NSUInteger idx2, BOOL *stop2) {
                YTIElementRenderer *elementRenderer = sectionSupportedRenderers.elementRenderer;
                return isAdRenderer(elementRenderer, 3);
            }];
            [contentsArray removeObjectsAtIndexes:removeContentsArrayIndexes];
        }
        YTIItemSectionSupportedRenderers *firstObject = [contentsArray firstObject];
        YTIElementRenderer *elementRenderer = firstObject.elementRenderer;
        return isAdRenderer(elementRenderer, 2);
    }];
    [newArray removeObjectsAtIndexes:removeIndexes];
    return newArray;
}

%hook YTPlayerResponse
%new(@@:)
- (NSMutableArray *)playerAdsArray { return [NSMutableArray array]; }
%new(@@:)
- (NSMutableArray *)adSlotsArray { return [NSMutableArray array]; }
%end

%hook YTIClientMdxGlobalConfig
%new(B@:)
- (BOOL)enableSkippableAd { return YES; }
%end

%hook YTAdShieldUtils
+ (id)spamSignalsDictionary { return @{}; }
+ (id)spamSignalsDictionaryWithoutIDFA { return @{}; }
%end

%hook YTDataUtils
+ (id)spamSignalsDictionary { return @{ @"ms": @"" }; }
+ (id)spamSignalsDictionaryWithoutIDFA { return @{}; }
%end

%hook YTAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context {}
%end

%hook YTAccountScopedAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context {}
%end

%hook YTIPlayerResponse
- (BOOL)isMonetized { return NO; }
%end

%hook YTLocalPlaybackController
- (id)createAdsPlaybackCoordinator { return nil; }
%end

%hook MDXSession
- (void)adPlaying:(id)ad {}
%end

%hook MDXSessionImpl
- (void)adPlaying:(id)ad {}
%end

%hook YTReelDataSource
- (YTReelModel *)makeContentModelForEntry:(id)entry {
    YTReelModel *model = %orig;
    if ([model respondsToSelector:@selector(videoType)] && model.videoType == 3)
        return nil;
    return model;
}
%end

%hook YTReelInfinitePlaybackDataSource
- (YTReelModel *)makeContentModelForEntry:(id)entry {
    YTReelModel *model = %orig;
    if ([model respondsToSelector:@selector(videoType)] && model.videoType == 3)
        return nil;
    return model;
}
- (void)setReels:(NSMutableOrderedSet <YTReelModel *> *)reels {
    [reels removeObjectsAtIndexes:[reels indexesOfObjectsPassingTest:^BOOL(YTReelModel *obj, NSUInteger idx, BOOL *stop) {
        return [obj respondsToSelector:@selector(videoType)] ? obj.videoType == 3 : NO;
    }]];
    %orig;
}
%end

%hook YTWatchNextResponseViewController
- (void)loadWithModel:(YTIWatchNextResponse *)model {
    YTICommand *onUiReady = model.onUiReady;
    if ([onUiReady respondsToSelector:@selector(yt_commandExecutorCommand)]) {
        YTICommandExecutorCommand *commandExecutorCommand = [onUiReady yt_commandExecutorCommand];
        NSMutableArray <YTICommand *> *commandsArray = commandExecutorCommand.commandsArray;
        [commandsArray removeObjectsAtIndexes:[commandsArray indexesOfObjectsPassingTest:^BOOL(YTICommand *command, NSUInteger idx, BOOL *stop) {
            return isProductList(command);
        }]];
    }
    if (isProductList(onUiReady))
        model.onUiReady = nil;
    %orig;
}
%end

%hook YTMainAppVideoPlayerOverlayViewController
- (void)playerOverlayProvider:(YTPlayerOverlayProvider *)provider didInsertPlayerOverlay:(YTPlayerOverlay *)overlay {
    if ([[overlay overlayIdentifier] isEqualToString:@"player_overlay_product_in_video"]) return;
    %orig;
}
%end

%hook YTInnerTubeCollectionViewController
- (void)displaySectionsWithReloadingSectionControllerByRenderer:(id)renderer {
    NSMutableArray *sectionRenderers = [self valueForKey:@"_sectionRenderers"];
    [self setValue:filteredArray(sectionRenderers) forKey:@"_sectionRenderers"];
    %orig;
}
- (void)addSectionsFromArray:(NSArray <YTIItemSectionRenderer *> *)array {
    %orig(filteredArray(array));
}
%end

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    if ([self.accessibilityIdentifier isEqualToString:@"eml.expandable_metadata.vpp"]) [self removeFromSuperview];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.ad_layout.full_width_square_image_layout"]) self.hidden = YES;
}
%end

// Premium
%hook YTColdConfig
- (BOOL)cxClientDisableMementoPromotions { return YES; }
%end

%hook YTHotConfig
- (BOOL)iosPlayerClientSharedConfigShowPipClingPromo { return NO; }
- (BOOL)liveChatEnableEngagementPanelPromo { return NO; }
- (BOOL)livestreamClientConfigEnableCreationModesPromosTriggered { return NO; }
%end

// NoYTPremium - @PoomSmart https://github.com/PoomSmart/NoYTPremium
// Alert
%hook YTCommerceEventGroupHandler
- (void)addEventHandlers {}
%end

// Full-screen
%hook YTInterstitialPromoEventGroupHandler
- (void)addEventHandlers {}
%end

%hook YTPromosheetEventGroupHandler
- (void)addEventHandlers {}
%end

%hook YTPromoThrottleController
- (BOOL)canShowThrottledPromo { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCap:(id)arg1 { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCaps:(id)arg1 { return NO; }
%end

%hook YTPromoThrottleControllerImpl
- (BOOL)canShowThrottledPromo { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCap:(id)arg1 { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCaps:(id)arg1 { return NO; }
%end

%hook YTIShowFullscreenInterstitialCommand
- (BOOL)shouldThrottleInterstitial {
    if (self.hasModalClientThrottlingRules)
        self.modalClientThrottlingRules.oncePerTimeWindow = YES;
    return %orig;
}
%end

// "Try new features" in settings
%hook YTSettingsSectionItemManager
- (void)updatePremiumEarlyAccessSectionWithEntry:(id)arg1 {}
%end

// Survey
%hook YTSurveyController
- (void)showSurveyWithRenderer:(id)arg1 surveyParentResponder:(id)arg2 {}
%end

// Hide AI things
%hook YTShortsSharedGalleryPresentationView
- (BOOL)shouldShowAiMontageButton { return NO; }
%end

%hook YTShortsSharedGalleryPresentationViewController
- (BOOL)shouldShowAiMontageButton { return NO; }
%end

%hook YTVideoSubtitleView
- (BOOL)shouldShowAdBadge { return NO; }
%end

%hook YTIPlayerCompanionAdsSupportedRenderers
- (BOOL)hasAppPromoCompanionAdRenderer { return NO; }
%end

%hook YTIRenderer
- (id)appPromoAdCtaRenderer { return nil; }
- (BOOL)hasAppPromoAdCtaRenderer { return NO; }
%end

%hook YTIInStreamPlayerCtaAdsSupportedRenderers
- (BOOL)hasAppPromoAdCtaRenderer { return NO; }
%end

%hook YTInterstitialPromoViewController
- (void)showInterstitialPromo:(id)arg1 enableClientImpressionThrottling:(BOOL)arg2 interstitialParentResponder:(id)arg3 {}
- (void)showInterstitialPromo:(id)arg1 interstitialParentResponder:(id)arg2 {}
%end

%hook YTMealbarPromoController
- (id)promoRenderer { return nil; }
- (void)showMealbarPromoWithEvent:(id)arg {}
%end

%hook YTOfflineButtonPromoController
- (void)showOfflinePromoWithRenderer:(id)arg1 endpoint:(id)arg2 parentResponder:(id)arg3 {}
%end

%hook YTOfflineButtonPromoView
- (id)initWithFrame:(CGRect)arg1 renderer:(id)arg2 attributedView:(id)arg3 formattedStringLabelDelegate:(id)arg4 offlineButtonPromoDelegate:(id)arg5 { return nil; }
%end

%hook YTWatchMiniBarControlsView
- (void)setTitle:(id)arg1 byline:(id)arg2 showingPaidPromotion:(BOOL)arg3 showingPremiumBadge:(BOOL)arg4 {}
%end

%hook MDXFeatureFlags
- (BOOL)areMementoPromotionsEnabled { return NO; }
%end

%hook YTUserDefaults
- (BOOL)enablePromoDebugToast { return NO; }
- (BOOL)isPromoForced { return NO; }
%end

%hook YTAppMealbarPromoController
- (id)mealbarPromoController { return nil; }
%end

%hook YTAppMealbarPromoControllerImpl
- (id)mealbarPromoController { return nil; }
%end

%hook YTSurveyPromosheet
- (id)expandablePromosheetDelegate { return nil; }
- (void)setExpandablePromosheetDelegate:(id)arg {}
%end

%hook YTSPromotionServiceBlockImpl
- (BOOL)createPromotion:(id)arg1 writer:(id)arg2 error:(NSError **)arg3 { return NO; }
%end

%hook YTSPromotionServiceBlock
- (BOOL)createPromotion:(id)arg1 writer:(id)arg2 error:(NSError **)arg3 { return NO; }
%end

%hook YTPromosheetController
- (BOOL)canPresentPromosheetWithGlobalThrottling:(BOOL)arg1 customizedThrottling:(id)arg2 shouldReplacePromosheet:(BOOL)arg3 { return NO; }
- (void)setCurrentPromosheet:(id)arg {}
%end

%hook YTWatchSurveyTriggerController
- (id)initWithParentResponder:(id)arg1 promosheetController:(id)arg2 { return nil; }
%end

%hook YTShareMainView
- (BOOL)shouldShowPromo { return NO; }
- (void)setPromoView:(id)arg {}
%end

%hook YCHLiveChatActionPanelView
- (BOOL)shouldShowUpsellButton { return NO; }
%end

%hook YTPromosheetContainerView
- (BOOL)shouldShowExpandButton { return NO; }
- (void)setPromosheet:(id)arg {}
- (void)setPromosheetDisplayed:(BOOL)arg {}
- (void)setPromosheet:(id)arg1 animated:(BOOL)arg2 completion:(id)arg3 {}
%end

%hook ELMPBShowBottomSheetCommand
- (void)showMealbarPromoWithContainerView:(id)arg1 handler:(id)arg2 {}
%end

%hook YTIElementRenderer
- (NSData *)elementData {
    NSString *description = [self description];
    NSString *adString = getAdString(description);
    if (adString) return nil;
    // NSArray *shortsToRemove = @[@"shorts_shelf.eml", @"shorts_video_cell.eml", @"6Shorts", @"eml.shorts-shelf"];
    // for (NSString *shorts in shortsToRemove) {
    //     if (IS_ENABLED(HideShortsShelf) && [description containsString:shorts] && ![description containsString:@"history*"]) {
    //         return nil;
    //     }
    // }
    return %orig;
}
%end