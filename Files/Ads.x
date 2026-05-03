#import "Headers.h"

static BOOL isProductList(YTICommand *command) {
    if ([command respondsToSelector:@selector(yt_showEngagementPanelEndpoint)])
        return [[command yt_showEngagementPanelEndpoint].identifier.tag isEqualToString:@"PAproduct_list"];
    return NO;
}

static BOOL isAdDescription(NSString *description) {
    static NSArray *adStrings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        adStrings = @[
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
            @"video_display_full_buttoned_layout",
        ];
    });
    for (NSString *str in adStrings)
        if ([description containsString:str]) return YES;
    return NO;
}

static BOOL isAdRenderer(YTIElementRenderer *renderer) {
    return ([renderer respondsToSelector:@selector(hasCompatibilityOptions)] &&
            renderer.hasCompatibilityOptions &&
            renderer.compatibilityOptions.hasAdLoggingData) ||
           isAdDescription([renderer description]);
}

static BOOL isAdReelModel(YTReelModel *model) {
    return [model respondsToSelector:@selector(videoType)] && model.videoType == 3;
}

static NSMutableArray<YTIItemSectionRenderer *> *filteredArray(NSArray<YTIItemSectionRenderer *> *array) {
    NSMutableArray *newArray = [array mutableCopy];
    NSIndexSet *removeIndexes = [newArray indexesOfObjectsPassingTest:^BOOL(YTIItemSectionRenderer *section, NSUInteger idx, BOOL *stop) {
        if ([section isKindOfClass:%c(YTIShelfRenderer)]) {
            NSMutableArray *items = ((YTIShelfRenderer *)section).content.horizontalListRenderer.itemsArray;
            [items removeObjectsAtIndexes:[items indexesOfObjectsPassingTest:^BOOL(YTIHorizontalListSupportedRenderers *item, NSUInteger i, BOOL *s) {
                return isAdRenderer(item.elementRenderer);
            }]];
        }
        if (![section isKindOfClass:%c(YTIItemSectionRenderer)]) return NO;
        NSMutableArray *contents = section.contentsArray;
        if (contents.count > 1)
            [contents removeObjectsAtIndexes:[contents indexesOfObjectsPassingTest:^BOOL(YTIItemSectionSupportedRenderers *item, NSUInteger i, BOOL *s) {
                return isAdRenderer(item.elementRenderer);
            }]];
        return isAdRenderer(((YTIItemSectionSupportedRenderers *)[contents firstObject]).elementRenderer);
    }];
    [newArray removeObjectsAtIndexes:removeIndexes];
    return newArray;
}

%hook YTPlayerResponse
%new(@@:) - (NSMutableArray *)playerAdsArray { return [NSMutableArray array]; }
%new(@@:) - (NSMutableArray *)adSlotsArray   { return [NSMutableArray array]; }
%end

%hook YTIClientMdxGlobalConfig
%new(B@:) - (BOOL)enableSkippableAd { return YES; }
%end

%hook YTAdShieldUtils
+ (id)spamSignalsDictionary              { return @{}; }
+ (id)spamSignalsDictionaryWithoutIDFA   { return @{}; }
%end

%hook YTDataUtils
+ (id)spamSignalsDictionary              { return @{ @"ms": @"" }; }
+ (id)spamSignalsDictionaryWithoutIDFA   { return @{}; }
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
    return isAdReelModel(model) ? nil : model;
}
%end

%hook YTReelInfinitePlaybackDataSource
- (YTReelModel *)makeContentModelForEntry:(id)entry {
    YTReelModel *model = %orig;
    return isAdReelModel(model) ? nil : model;
}
- (void)setReels:(NSMutableOrderedSet<YTReelModel *> *)reels {
    [reels removeObjectsAtIndexes:[reels indexesOfObjectsPassingTest:^BOOL(YTReelModel *obj, NSUInteger idx, BOOL *stop) {
        return isAdReelModel(obj);
    }]];
    %orig;
}
%end

%hook YTWatchNextResponseViewController
- (void)loadWithModel:(YTIWatchNextResponse *)model {
    YTICommand *onUiReady = model.onUiReady;
    if ([onUiReady respondsToSelector:@selector(yt_commandExecutorCommand)]) {
        NSMutableArray<YTICommand *> *commands = [onUiReady yt_commandExecutorCommand].commandsArray;
        [commands removeObjectsAtIndexes:[commands indexesOfObjectsPassingTest:^BOOL(YTICommand *cmd, NSUInteger idx, BOOL *stop) {
            return isProductList(cmd);
        }]];
    }
    if (isProductList(onUiReady)) model.onUiReady = nil;
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
    NSMutableArray *sections = [self valueForKey:@"_sectionRenderers"];
    [self setValue:filteredArray(sections) forKey:@"_sectionRenderers"];
    %orig;
}
- (void)addSectionsFromArray:(NSArray<YTIItemSectionRenderer *> *)array {
    %orig(filteredArray(array));
}
%end

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    if ([self.accessibilityIdentifier isEqualToString:@"eml.expandable_metadata.vpp"])
        [self removeFromSuperview];
    if ([self.accessibilityIdentifier isEqualToString:@"eml.ad_layout.full_width_square_image_layout"])
        self.hidden = YES;
}
%end

%hook YTColdConfig
- (BOOL)cxClientDisableMementoPromotions { return YES; }
%end

%hook YTHotConfig
- (BOOL)iosPlayerClientSharedConfigShowPipClingPromo          { return NO; }
- (BOOL)liveChatEnableEngagementPanelPromo                    { return NO; }
- (BOOL)livestreamClientConfigEnableCreationModesPromosTriggered { return NO; }
%end

%hook YTCommerceEventGroupHandler
- (void)addEventHandlers {}
%end

%hook YTInterstitialPromoEventGroupHandler
- (void)addEventHandlers {}
%end

%hook YTPromosheetEventGroupHandler
- (void)addEventHandlers {}
%end

%hook YTPromoThrottleController
- (BOOL)canShowThrottledPromo                                       { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCap:(id)arg1              { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCaps:(id)arg1             { return NO; }
%end

%hook YTPromoThrottleControllerImpl
- (BOOL)canShowThrottledPromo                                       { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCap:(id)arg1              { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCaps:(id)arg1             { return NO; }
%end

%hook YTIShowFullscreenInterstitialCommand
- (BOOL)shouldThrottleInterstitial {
    if (self.hasModalClientThrottlingRules)
        self.modalClientThrottlingRules.oncePerTimeWindow = YES;
    return %orig;
}
%end

%hook YTSettingsSectionItemManager
- (void)updatePremiumEarlyAccessSectionWithEntry:(id)arg1 {}
%end

%hook YTSurveyController
- (void)showSurveyWithRenderer:(id)arg1 surveyParentResponder:(id)arg2 {}
%end

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
- (id)appPromoAdCtaRenderer        { return nil; }
- (BOOL)hasAppPromoAdCtaRenderer   { return NO; }
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
- (BOOL)isPromoForced         { return NO; }
%end

%hook YTAppMealbarPromoController
- (id)mealbarPromoController { return nil; }
%end

%hook YTAppMealbarPromoControllerImpl
- (id)mealbarPromoController { return nil; }
%end

%hook YTSurveyPromosheet
- (id)expandablePromosheetDelegate    { return nil; }
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
- (BOOL)shouldShowPromo    { return NO; }
- (void)setPromoView:(id)arg {}
%end

%hook YCHLiveChatActionPanelView
- (BOOL)shouldShowUpsellButton { return NO; }
%end

%hook YTPromosheetContainerView
- (BOOL)shouldShowExpandButton                                { return NO; }
- (void)setPromosheet:(id)arg                                {}
- (void)setPromosheetDisplayed:(BOOL)arg                     {}
- (void)setPromosheet:(id)arg1 animated:(BOOL)arg2 completion:(id)arg3 {}
%end

%hook ELMPBShowBottomSheetCommand
- (void)showMealbarPromoWithContainerView:(id)arg1 handler:(id)arg2 {}
%end

%hook YTIElementRenderer
- (NSData *)elementData {
    return isAdDescription([self description]) ? [NSData data] : %orig;
}
%end
