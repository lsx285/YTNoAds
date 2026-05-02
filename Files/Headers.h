// Headers.h — YTNoAds
// YouTube internals
#import <YouTubeHeader/_ASDisplayView.h>
#import <YouTubeHeader/YTIIcon.h>
#import <YouTubeHeader/YTRightNavigationButtons.h>
#import <YouTubeHeader/YTIElementRenderer.h>
#import <YouTubeHeader/YTPlayerBarController.h>
#import <YouTubeHeader/YTPlayerViewController.h>
#import <YouTubeHeader/YTWatchController.h>
#import <YouTubeHeader/YTIMenuConditionalServiceItemRenderer.h>
#import <YouTubeHeader/YTIPivotBarRenderer.h>
#import <YouTubeHeader/YTPivotBarItemView.h>
#import <YouTubeHeader/YTActionSheetAction.h>
#import <YouTubeHeader/YTIMenuItemSupportedRenderers.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayView.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTVideoQualitySwitchOriginalController.h>
#import <YouTubeHeader/YTVideoQualitySwitchRedesignedController.h>
#import <YouTubeHeader/YTInnerTubeCollectionViewController.h>
#import <YouTubeHeader/YTIShowFullscreenInterstitialCommand.h>
#import <YouTubeHeader/YTISectionListRenderer.h>
#import <YouTubeHeader/YTIShelfRenderer.h>
#import <YouTubeHeader/YTIWatchNextResponse.h>
#import <YouTubeHeader/YTPlayerOverlay.h>
#import <YouTubeHeader/YTPlayerOverlayProvider.h>
#import <YouTubeHeader/YTReelModel.h>
#import <YouTubeHeader/YTAlertView.h>
#import <YouTubeHeader/YTMultiSizeViewController.h>
#import <YouTubeHeader/YTInlinePlayerBarContainerView.h>
#import <YouTubeHeader/YTSingleVideoTime.h>
#import <YouTubeHeader/YTSingleVideoController.h>
#import <YouTubeHeader/YTPlayerView.h>
#import <YouTubeHeader/YTLabel.h>
#import <MediaPlayer/MediaPlayer.h>
#import <dlfcn.h>

// For Settings.x and SponsorBlockSettings.x
#import <YouTubeHeader/YTDefaultSheetController.h>

@interface YTDefaultSheetController (YTNoAds)
+ (instancetype)sheetControllerWithParentResponder:(id)responder;
- (void)addAction:(YTActionSheetAction *)action;
- (void)presentFromViewController:(UIViewController *)vc animated:(BOOL)animated completion:(void (^)(void))completion;
@end
#import <YouTubeHeader/YTSettingsGroupData.h>
#import <YouTubeHeader/YTSettingsPickerViewController.h>
#import <YouTubeHeader/YTSettingsSectionItem.h>
#import <YouTubeHeader/YTSearchableSettingsViewController.h>
#import <YouTubeHeader/YTSettingsSectionItemManager.h>
#import <YouTubeHeader/YTSettingsViewController.h>
#import <YouTubeHeader/YTToastResponderEvent.h>
#import <YouTubeHeader/YTUIUtils.h>

// Convenience macros
#define IS_ENABLED(k) [[NSUserDefaults standardUserDefaults] boolForKey:k]
#define INTFORVAL(v) [[NSUserDefaults standardUserDefaults] integerForKey:v]
#define FLOAT_FOR_KEY(k) [[NSUserDefaults standardUserDefaults] floatForKey:k]

// SponsorBlock preference keys
#define SBEnabled              @"YouModSBEnabled"
#define SBShowButton           @"YouModSBShowButton"
#define SBShowNotifications    @"YouModSBShowNotifications"
#define SBAudioNotification    @"YouModSBAudioNotification"
#define SBSegmentsInFeed       @"YouModSBSegmentsInFeed"
#define SBSegmentsInMiniPlayer @"YouModSBSegmentsInMiniPlayer"
#define SBShowDuration         @"YouModSBShowDuration"
#define SBMinDuration          @"YouModSBMinDuration"
#define SBSkipAlertDuration    @"YouModSBSkipAlertDuration"
#define SBUnskipAlertDuration  @"YouModSBUnskipAlertDuration"

#define SB_ACTION_KEY(cat) [NSString stringWithFormat:@"YouModSBAction_%@", cat]
#define SB_COLOR_KEY(cat)  [NSString stringWithFormat:@"YouModSBColor_%@", cat]

// ─── Pivot bar (for Extras.x) ────────────────────────────────────────────────

@interface YTIPivotBarItemRenderer : NSObject
- (NSString *)pivotIdentifier;
@end

@interface YTIPivotBarIconOnlyItemRenderer : NSObject
- (NSString *)pivotIdentifier;
@end

@interface YTIPivotBarSupportedRenderers : NSObject
- (YTIPivotBarItemRenderer *)pivotBarItemRenderer;
- (YTIPivotBarIconOnlyItemRenderer *)pivotBarIconOnlyItemRenderer;
@end

// ─── Misc YouTube interfaces ──────────────────────────────────────────────────

@interface YTITopbarLogoRenderer : NSObject
@property(readonly, nonatomic) YTIIcon *iconImage;
@end

@interface YTRightNavigationButtons (YTNoAds)
@property (nonatomic, strong) YTQTMButton *notificationButton;
@property (nonatomic, strong) YTQTMButton *searchButton;
@end

@interface YTMainAppVideoPlayerOverlayView (YTNoAds)
@property (nonatomic, strong) YTQTMButton *playbackRouteButton;
@end

@interface YTNavigationBarTitleView : UIView
@end

@interface YTChipCloudCell : UICollectionViewCell
@end

@interface YTSearchViewController : UIViewController
@end

@interface YTPlayabilityResolutionUserActionUIController : NSObject
- (void)confirmAlertDidPressConfirm;
@end

@interface YTPlayabilityResolutionUserActionUIControllerImpl : NSObject
- (void)confirmAlertDidPressConfirm;
@end

@interface YTPivotBarViewController : UIViewController
- (void)selectItemWithPivotIdentifier:(id)pivotIndentifier;
@end

@interface YTPlayerViewController (YTNoAds)
- (void)setPlaybackRate:(float)rate;
@end

@interface SSOConfiguration : NSObject
@end

@interface YTVideoQualitySwitchOriginalController (YTNoAds)
@property (retain, nonatomic) YTVideoQualitySwitchRedesignedController *redesignedController;
@end

@interface UIView (Private)
@property (nonatomic, assign, readonly) BOOL _mapkit_isDarkModeEnabled;
- (UIViewController *)_viewControllerForAncestor;
@end

@interface YTInlinePlayerBarContainerView (YTNoAds)
@property (nonatomic, strong, readwrite) NSString *endTimeString;
- (CGFloat)scrubXForScrubRange:(CGFloat)scrubRange;
@end

@interface YTSingleVideoController (YTNoAds)
@property (nonatomic, assign, readonly) CGFloat totalMediaTime;
@end

@interface YTMainAppVideoPlayerOverlayViewController (YTNoAds)
@property (nonatomic, strong, readwrite) YTPlayerBarController *playerBarController;
@end

@interface YTPlayerBarController (YTNoAds)
- (void)didScrub:(UIPanGestureRecognizer *)gestureRecognizer;
- (void)startScrubbing;
- (void)didScrubToPoint:(CGPoint)point;
- (void)endScrubbingForSeekSource:(int)seekSource;
@end

// ─── SponsorBlock types ───────────────────────────────────────────────────────

typedef NS_ENUM(NSInteger, SBSegmentAction) {
    SBSegmentActionDisable  = 0,
    SBSegmentActionAutoSkip = 1,
    SBSegmentActionAsk      = 2,
    SBSegmentActionDisplay  = 3,
    SBSegmentActionSkipTo   = 4
};

@interface SBSegment : NSObject
@property (nonatomic, strong) NSString *UUID;
@property (nonatomic, strong) NSString *category;
@property (nonatomic, assign) float startTime;
@property (nonatomic, assign) float endTime;
@property (nonatomic, strong) NSString *actionType;
+ (instancetype)segmentWithUUID:(NSString *)UUID category:(NSString *)category start:(float)start end:(float)end action:(NSString *)actionType;
- (SBSegmentAction)configuredAction;
- (UIColor *)segmentColor;
@end

@interface SBRequest : NSObject
+ (void)fetchSegmentsForVideoID:(NSString *)videoID completion:(void (^)(NSArray<SBSegment *> *segments))completion;
@end

@interface SBSkipNotificationView : UIView
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, copy) void (^onAction)(void);
+ (instancetype)showInView:(UIView *)parentView message:(NSString *)message buttonTitle:(NSString *)buttonTitle action:(void (^)(void))action duration:(NSTimeInterval)duration;
- (void)dismiss;
@end

@interface YTPlayerViewController (SponsorBlock)
@property (nonatomic, strong) NSString *sbLastVideoID;
@property (nonatomic, strong) NSArray<SBSegment *> *sbSegments;
@property (nonatomic, strong) NSMutableSet<NSString *> *sbSkippedSegments;
@property (nonatomic, strong) SBSkipNotificationView *sbNotificationView;
@property (nonatomic, strong) UIButton *sbOverlayButton;
@property (nonatomic, assign) BOOL sbEnabledForVideo;
- (void)sbPerformSkip:(SBSegment *)segment;
- (void)sbShowAskNotification:(SBSegment *)segment;
- (void)sbShowHighlightBannerIfNeeded:(NSArray<SBSegment *> *)segments;
- (void)sbSkipToHighlight;
@end

@interface YTSegmentableInlinePlayerBarView : UIView
@end

@interface YTSegmentableInlinePlayerBarView (SponsorBlock)
@property (nonatomic, strong) NSArray<UIView *> *sbMarkerViews;
- (void)sbRenderSegments:(NSArray<SBSegment *> *)segments;
- (void)sbClearSegments;
@end
