#import "Headers.h"
#import <AudioToolbox/AudioToolbox.h>

@interface YTPlayerViewController (SBInternal)
- (void)sbLoadSegmentsForVideoID:(NSString *)videoID;
- (void)sbHandleTimeChange;
@end

static NSMutableDictionary<NSString *, NSArray<SBSegment *> *> *sbSegmentCache;

static NSArray<NSString *> *sbAllCategories() {
    static NSArray *cats;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cats = @[@"sponsor", @"intro", @"outro", @"interaction", @"selfpromo",
                 @"music_offtopic", @"preview", @"poi_highlight", @"filler"];
    });
    return cats;
}

static NSArray<NSString *> *sbEnabledCategories() {
    NSMutableArray *enabled = [NSMutableArray array];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (NSString *cat in sbAllCategories())
        if ([ud integerForKey:SB_ACTION_KEY(cat)] != SBSegmentActionDisable)
            [enabled addObject:cat];
    return enabled;
}

UIColor *SBColorFromHex(NSString *hex) {
    if (hex.length < 7) return [UIColor whiteColor];
    unsigned int val = 0;
    [[NSScanner scannerWithString:[hex substringFromIndex:1]] scanHexInt:&val];
    return [UIColor colorWithRed:((val >> 16) & 0xFF) / 255.0
                           green:((val >>  8) & 0xFF) / 255.0
                            blue:( val        & 0xFF) / 255.0
                           alpha:1.0];
}

static NSString *SBLocalizedCategoryName(NSString *category) {
    static NSDictionary *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
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

@implementation SBSegment

+ (instancetype)segmentWithUUID:(NSString *)UUID category:(NSString *)category
                          start:(float)start end:(float)end action:(NSString *)actionType {
    SBSegment *seg = [[SBSegment alloc] init];
    seg.UUID       = UUID;
    seg.category   = category;
    seg.startTime  = start;
    seg.endTime    = end;
    seg.actionType = actionType;
    return seg;
}

- (SBSegmentAction)configuredAction {
    return (SBSegmentAction)[[NSUserDefaults standardUserDefaults] integerForKey:SB_ACTION_KEY(self.category)];
}

- (UIColor *)segmentColor {
    return SBColorFromHex([[NSUserDefaults standardUserDefaults] stringForKey:SB_COLOR_KEY(self.category)]);
}

@end

@implementation SBRequest

+ (void)fetchSegmentsForVideoID:(NSString *)videoID completion:(void (^)(NSArray<SBSegment *> *))completion {
    if (!videoID.length) { if (completion) completion(@[]); return; }

    @synchronized(sbSegmentCache) {
        NSArray *cached = sbSegmentCache[videoID];
        if (cached) { if (completion) completion(cached); return; }
    }

    NSArray *categories = sbEnabledCategories();
    if (!categories.count) { if (completion) completion(@[]); return; }

    NSData *catJSON = [NSJSONSerialization dataWithJSONObject:categories options:0 error:nil];
    NSString *catParam = [[[NSString alloc] initWithData:catJSON encoding:NSUTF8StringEncoding]
        stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:
        @"https://sponsor.ajay.app/api/skipSegments?videoID=%@&categories=%@", videoID, catParam]];

    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSMutableArray<SBSegment *> *segments = [NSMutableArray array];
        if (!error && data && ((NSHTTPURLResponse *)response).statusCode == 200) {
            NSArray *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSArray class]]) {
                for (NSDictionary *item in json) {
                    NSArray *seg = item[@"segment"];
                    if (seg.count >= 2)
                        [segments addObject:[SBSegment segmentWithUUID:item[@"UUID"]     ?: @""
                                                              category:item[@"category"] ?: @""
                                                                 start:[seg[0] floatValue]
                                                                   end:[seg[1] floatValue]
                                                                action:item[@"actionType"] ?: @"skip"]];
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            @synchronized(sbSegmentCache) { sbSegmentCache[videoID] = segments; }
            if (completion) completion(segments);
        });
    }] resume];
}

@end

%hook YTPlayerViewController
%property (nonatomic, strong) NSString              *sbLastVideoID;
%property (nonatomic, strong) NSArray               *sbSegments;
%property (nonatomic, strong) NSMutableSet          *sbSkippedSegments;
%property (nonatomic, strong) SBSkipNotificationView *sbNotificationView;
%property (nonatomic, strong) UIButton              *sbOverlayButton;
%property (nonatomic, assign) BOOL                   sbEnabledForVideo;

- (void)setContentVideoID:(NSString *)videoID {
    %orig;
    if (!IS_ENABLED(SBEnabled) || !videoID.length) return;
    if ([self.sbLastVideoID isEqualToString:videoID] && self.sbSegments.count) return;
    self.sbLastVideoID = videoID;
    [self sbLoadSegmentsForVideoID:videoID];
}

- (void)playbackController:(id)pc didActivateVideo:(id)video withPlaybackData:(id)data {
    %orig;
    @try {
        if (!IS_ENABLED(SBEnabled) || self.isPlayingAd) return;
        NSString *videoID = [self contentVideoID];
        if (!videoID.length) return;
        if ([self.sbLastVideoID isEqualToString:videoID] && self.sbSegments.count) return;
        self.sbLastVideoID = videoID;
        [self sbLoadSegmentsForVideoID:videoID];
    } @catch (NSException *e) {}
}

- (void)singleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;
    [self sbHandleTimeChange];
}

- (void)potentiallyMutatedSingleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;
    [self sbHandleTimeChange];
}

%new
- (void)sbLoadSegmentsForVideoID:(NSString *)videoID {
    self.sbEnabledForVideo = YES;
    self.sbSkippedSegments = [NSMutableSet set];
    self.sbSegments        = nil;
    [self.sbNotificationView dismiss];

    __weak typeof(self) weakSelf = self;
    [SBRequest fetchSegmentsForVideoID:videoID completion:^(NSArray<SBSegment *> *segments) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.sbSegments = segments;
        [[NSNotificationCenter defaultCenter] postNotificationName:SBSegmentsDidLoadNotification
                                                            object:strongSelf
                                                          userInfo:@{@"segments": segments}];
        [strongSelf sbShowHighlightBannerIfNeeded:segments];
    }];
}

%new
- (void)sbHandleTimeChange {
    if (!IS_ENABLED(SBEnabled) || !self.sbEnabledForVideo || self.isPlayingAd) return;

    CGFloat currentTime = [self currentVideoMediaTime];
    float   minDuration = FLOAT_FOR_KEY(SBMinDuration);

    for (SBSegment *segment in self.sbSegments) {
        SBSegmentAction action = [segment configuredAction];
        if (action == SBSegmentActionDisable ||
            action == SBSegmentActionDisplay ||
            action == SBSegmentActionSkipTo)  continue;
        if (segment.endTime - segment.startTime < minDuration)        continue;
        if (currentTime < segment.startTime || currentTime >= segment.endTime - 0.5) continue;
        if ([self.sbSkippedSegments containsObject:segment.UUID])     continue;

        if (action == SBSegmentActionAutoSkip) [self sbPerformSkip:segment];
        else if (action == SBSegmentActionAsk) [self sbShowAskNotification:segment];
        break;
    }
}

%new
- (void)sbPerformSkip:(SBSegment *)segment {
    [self.sbSkippedSegments addObject:segment.UUID];
    [self seekToTime:(CGFloat)segment.endTime];

    if (IS_ENABLED(SBAudioNotification)) AudioServicesPlaySystemSound(1519);
    if (!IS_ENABLED(SBShowNotifications)) return;

    float alertDuration = FLOAT_FOR_KEY(SBUnskipAlertDuration);
    if (alertDuration <= 0) alertDuration = 4.0;

    NSString *message = [NSString stringWithFormat:@"%@ segment has been skipped",
                         SBLocalizedCategoryName(segment.category)];
    float endTime = segment.endTime, startTime = segment.startTime;

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.sbNotificationView = [SBSkipNotificationView
            showInView:strongSelf.playerView
               message:message
           buttonTitle:@"Unskip"
                action:^{ __strong typeof(weakSelf) ss = weakSelf; if (ss) [ss seekToTime:(CGFloat)startTime]; }
              duration:alertDuration];
    });
}

%new
- (void)sbShowAskNotification:(SBSegment *)segment {
    [self.sbSkippedSegments addObject:segment.UUID];

    float alertDuration = FLOAT_FOR_KEY(SBSkipAlertDuration);
    if (alertDuration <= 0) alertDuration = 4.0;

    NSString *message = [NSString stringWithFormat:@"%@ segment detected.\nWould you like to skip?",
                         SBLocalizedCategoryName(segment.category)];
    float endTime = segment.endTime;

    __weak typeof(self) weakSelf = self;
    self.sbNotificationView = [SBSkipNotificationView
        showInView:self.playerView
           message:message
       buttonTitle:@"Skip"
            action:^{ __strong typeof(weakSelf) ss = weakSelf; if (ss) [ss seekToTime:(CGFloat)endTime]; }
          duration:alertDuration];
}

%new
- (void)sbShowHighlightBannerIfNeeded:(NSArray<SBSegment *> *)segments {
    for (SBSegment *seg in segments) {
        if ([seg.category isEqualToString:@"poi_highlight"] &&
            [seg configuredAction] == SBSegmentActionSkipTo) {
            __weak typeof(self) weakSelf = self;
            self.sbNotificationView = [SBSkipNotificationView
                showInView:self.playerView
                   message:@"Highlight available. Jump to the point?"
               buttonTitle:@"Skip"
                    action:^{ __strong typeof(weakSelf) ss = weakSelf; if (ss) [ss sbSkipToHighlight]; }
                  duration:8.0];
            break;
        }
    }
}

%new
- (void)sbSkipToHighlight {
    for (SBSegment *segment in self.sbSegments) {
        if ([segment.category isEqualToString:@"poi_highlight"]) {
            [self seekToTime:(CGFloat)segment.startTime];
            if (IS_ENABLED(SBShowNotifications))
                self.sbNotificationView = [SBSkipNotificationView
                    showInView:self.playerView
                       message:@"Jumped to highlight"
                   buttonTitle:nil
                        action:nil
                      duration:2.0];
            break;
        }
    }
}

%end

%ctor {
    sbSegmentCache = [NSMutableDictionary dictionary];
    %init;
}
