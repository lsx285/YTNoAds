#import "Headers.h"

static BOOL isProductList(YTICommand *command) {
    if ([command respondsToSelector:@selector(yt_showEngagementPanelEndpoint)])
        return [[command yt_showEngagementPanelEndpoint].identifier.tag isEqualToString:@"PAproduct_list"];
    return NO;
}

static BOOL isAdDescription(NSString *description) {
    if (!description) return NO;
    static NSRegularExpression *regex;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"brand_promo|carousel_footered_layout|carousel_headered_layout|eml\\.expandable_metadata|feed_ad_metadata|full_width_portrait_image_layout|full_width_square_image_layout|landscape_image_wide_button_layout|post_shelf|product_carousel|product_engagement_panel|product_item|shopping_carousel|shopping_item_card_list|statement_banner|square_image_layout|text_image_button_layout|text_search_ad|video_display_full_layout|video_display_full_buttoned_layout" options:0 error:nil];
    });
    return [regex firstMatchInString:description options:0 range:NSMakeRange(0, description.length)] != nil;
}

static BOOL isAdRenderer(YTIElementRenderer *renderer) {
    return ([renderer respondsToSelector:@selector(hasCompatibilityOptions)] &&
            renderer.hasCompatibilityOptions &&
            renderer.compatibilityOptions.hasAdLoggingData) ||
           isAdDescription([renderer description]);
}

static BOOL isAdReelModel(YTReelModel *model) {
    if (!model) return NO;
    if ([model respondsToSelector:@selector(videoType)] && model.videoType == 3) return YES;
    if ([model respondsToSelector:@selector(hasCompatibilityOptions)] &&
        model.hasCompatibilityOptions && model.compatibilityOptions.hasAdLoggingData) return YES;
    if ([model respondsToSelector:@selector(description)] && isAdDescription([model description])) return YES;
    return NO;
}

static NSMutableArray<YTIItemSectionRenderer *> *filteredArray(NSArray<YTIItemSectionRenderer *> *array) {
    NSMutableArray *newArray = [array mutableCopy];
    for (NSInteger i = newArray.count - 1; i >= 0; i--) {
        YTIItemSectionRenderer *section = newArray[i];
        BOOL removeSection = NO;
        if ([section isKindOfClass:%c(YTIShelfRenderer)]) {
            NSMutableArray *items = ((YTIShelfRenderer *)section).content.horizontalListRenderer.itemsArray;
            for (NSInteger j = items.count - 1; j >= 0; j--) {
                if (isAdRenderer([items[j] elementRenderer])) {
                    [items removeObjectAtIndex:j];
                }
            }
        } else if ([section isKindOfClass:%c(YTIItemSectionRenderer)]) {
            NSMutableArray *contents = section.contentsArray;
            if (contents.count > 1) {
                for (NSInteger j = contents.count - 1; j >= 0; j--) {
                    if (isAdRenderer([contents[j] elementRenderer])) {
                        [contents removeObjectAtIndex:j];
                    }
                }
            }
            removeSection = contents.count > 0 && isAdRenderer(((YTIItemSectionSupportedRenderers *)[contents firstObject]).elementRenderer);
        }
        if (removeSection) {
            [newArray removeObjectAtIndex:i];
        }
    }
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
- (void)decorateContext:(id)context { %orig(nil); }
%end

%hook YTAccountScopedAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context { %orig(nil); }
%end

%hook YTIPlayerResponse
- (BOOL)isMonetized { return NO; }
- (void)decorateContext:(id)context { %orig(nil); }
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
    for (NSInteger i = reels.count - 1; i >= 0; i--) {
        if (isAdReelModel(reels[i])) {
            [reels removeObjectAtIndex:i];
        }
    }
    %orig;
}
%end

%hook YTWatchNextResponseViewController
- (void)loadWithModel:(YTIWatchNextResponse *)model {
    YTICommand *onUiReady = model.onUiReady;
    if ([onUiReady respondsToSelector:@selector(yt_commandExecutorCommand)]) {
        NSMutableArray<YTICommand *> *commands = [onUiReady yt_commandExecutorCommand].commandsArray;
        for (NSInteger i = commands.count - 1; i >= 0; i--) {
            if (isProductList(commands[i])) {
                [commands removeObjectAtIndex:i];
            }
        }
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
    [self setValue:filteredArray([self valueForKey:@"_sectionRenderers"]) forKey:@"_sectionRenderers"];
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

%hook YTSurveyController
- (void)showSurveyWithRenderer:(id)arg1 surveyParentResponder:(id)arg2 {}
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

%hook YTIElementRenderer
- (NSData *)elementData {
    NSString *description = [self description];
    if (isAdDescription(description) || 
       ([self respondsToSelector:@selector(hasCompatibilityOptions)] && self.hasCompatibilityOptions && self.compatibilityOptions.hasAdLoggingData)) {
        return [NSData data];
    }
    return %orig;
}
%end
