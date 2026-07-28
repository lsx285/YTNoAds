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
#import <YouTubeHeader/YTDefaultSheetController.h>
#import <YouTubeHeader/YTSettingsGroupData.h>
#import <YouTubeHeader/YTSettingsPickerViewController.h>
#import <YouTubeHeader/YTSettingsSectionItem.h>
#import <YouTubeHeader/YTSearchableSettingsViewController.h>
#import <YouTubeHeader/YTSettingsSectionItemManager.h>
#import <YouTubeHeader/YTSettingsViewController.h>
#import <YouTubeHeader/YTToastResponderEvent.h>
#import <YouTubeHeader/YTUIUtils.h>
#import <dlfcn.h>

@interface YTDefaultSheetController (YTNoAds)
+ (instancetype)sheetControllerWithParentResponder:(id)responder;
- (void)addAction:(YTActionSheetAction *)action;
- (void)presentFromViewController:(UIViewController *)vc animated:(BOOL)animated completion:(void (^)(void))completion;
@end

#define SBSegmentsDidLoadNotification @"SBSegmentsDidLoad"

#define SB_MARKER_HEIGHT_DEFAULT 3.0
#define SB_MARKER_HEIGHT_MIN     2.0
#define SB_POI_WIDTH             3.0
#define SB_BACKWARD_SEEK_THRESH  2.0
#define SB_NOTIFICATION_DELAY    0.3

#define SB_ENABLED               YES
#define SB_SHOW_NOTIFICATIONS    YES
#define SB_SKIP_ALERT_DURATION   4.0
#define SB_UNSKIP_ALERT_DURATION 4.0

static inline NSArray<NSString *> *SBAllCategories(void) {
    static NSArray *cats;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cats = @[@"sponsor", @"intro", @"outro", @"interaction", @"selfpromo",
                 @"music_offtopic", @"preview", @"poi_highlight", @"filler"];
    });
    return cats;
}

static inline NSString *SBCategoryName(NSString *category) {
    static NSDictionary *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{
            @"sponsor":        @"Sponsor",
            @"intro":          @"Intro / Intermission",
            @"outro":          @"Endcards / Credits",
            @"interaction":    @"Interaction Reminder",
            @"selfpromo":      @"Unpaid Self-promotion",
            @"music_offtopic": @"Non-music Section",
            @"preview":        @"Preview / Recap",
            @"poi_highlight":  @"Highlight",
            @"filler":         @"Filler Tangent",
        };
    });
    return names[category] ?: category;
}

typedef NS_ENUM(NSInteger, SBSegmentAction) {
    SBSegmentActionDisable  = 0,
    SBSegmentActionAutoSkip = 1,
    SBSegmentActionAsk      = 2,
    SBSegmentActionDisplay  = 3,
    SBSegmentActionSkipTo   = 4
};

static inline SBSegmentAction SBDefaultActionForCategory(NSString *category) {
    static NSDictionary *actions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        actions = @{
            @"sponsor":        @(SBSegmentActionAutoSkip),
            @"intro":          @(SBSegmentActionAutoSkip),
            @"outro":          @(SBSegmentActionAutoSkip),
            @"interaction":    @(SBSegmentActionAutoSkip),
            @"selfpromo":      @(SBSegmentActionAutoSkip),
            @"music_offtopic": @(SBSegmentActionAutoSkip),
            @"preview":        @(SBSegmentActionAutoSkip),
            @"poi_highlight":  @(SBSegmentActionSkipTo),
            @"filler":         @(SBSegmentActionDisplay),
        };
    });
    NSNumber *val = actions[category];
    return val ? (SBSegmentAction)val.integerValue : SBSegmentActionDisable;
}

static inline NSString *SBDefaultColorHexForCategory(NSString *category) {
    static NSDictionary *colors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        colors = @{
            @"sponsor":        @"#00D400",
            @"intro":          @"#00FFFF",
            @"outro":          @"#0202ED",
            @"interaction":    @"#CC00FF",
            @"selfpromo":      @"#FFFF00",
            @"music_offtopic": @"#FF9900",
            @"preview":        @"#008FD6",
            @"poi_highlight":  @"#FF1684",
            @"filler":         @"#7300FF",
        };
    });
    return colors[category] ?: @"#FFFFFF";
}

@interface SBSegment : NSObject
@property (nonatomic, strong) NSString *UUID;
@property (nonatomic, strong) NSString *category;
@property (nonatomic, assign) float startTime;
@property (nonatomic, assign) float endTime;
@property (nonatomic, strong) NSString *actionType;
@property (nonatomic, assign) SBSegmentAction action;
@property (nonatomic, strong) UIColor *color;
+ (instancetype)segmentWithUUID:(NSString *)UUID category:(NSString *)category start:(float)start end:(float)end action:(NSString *)actionType;
@end

@interface SBRequest : NSObject
+ (void)fetchSegmentsForVideoID:(NSString *)videoID completion:(void (^)(NSArray<SBSegment *> *segments))completion;
@end

@interface SBSkipNotificationView : UIView
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) CAShapeLayer *fillLayer;
@property (nonatomic, copy) void (^onAction)(void);
@property (nonatomic, copy) void (^onDismiss)(void);
+ (instancetype)showInView:(UIView *)parentView message:(NSString *)message buttonTitle:(NSString *)buttonTitle action:(void (^)(void))action duration:(NSTimeInterval)duration;
- (void)dismiss;
@end

@interface YTPlayerViewController (SponsorBlock)
@property (nonatomic, strong) NSString *sbLastVideoID;
@property (nonatomic, strong) NSArray<SBSegment *> *sbSegments;
@property (nonatomic, strong) NSMutableSet<NSString *> *sbSkippedSegments;
@property (nonatomic, strong) NSMutableSet<NSString *> *sbIgnoredSegments;
@property (nonatomic, strong) SBSkipNotificationView *sbNotificationView;
@property (nonatomic, assign) BOOL sbEnabledForVideo;
@property (nonatomic, assign) CGFloat sbLastSeenTime;
@property (nonatomic, assign) BOOL sbIsPerformingSystemSkip;
@property (nonatomic, strong) NSMutableArray *sbNotificationQueue;
@property (nonatomic, assign) BOOL sbNotificationShowing;
@property (nonatomic, assign) BOOL sbHighlightPromptShown;
- (void)sbPerformSkip:(SBSegment *)segment;
- (void)sbShowAskNotification:(SBSegment *)segment;
- (void)sbShowHighlightNotification:(SBSegment *)segment;
- (void)sbCheckForHighlightSegment:(NSArray<SBSegment *> *)segments;
- (void)sbTriggerLoadIfNeededForVideoID:(NSString *)videoID;
- (void)sbEnqueueNotificationWithMessage:(NSString *)message buttonTitle:(NSString *)buttonTitle action:(void (^)(void))action duration:(NSTimeInterval)duration;
- (void)sbProcessNotificationQueue;
@end

void SBClearSegmentCache(void);
