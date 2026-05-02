#import "Headers.h"
#import <AudioToolbox/AudioToolbox.h>

static NSMutableDictionary<NSString *, NSArray<SBSegment *> *> *sbSegmentCache;

static NSArray<NSString *> *sbAllCategories() {
    static NSArray *cats;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cats = @[@"sponsor", @"intro", @"outro", @"interaction", @"selfpromo",
                 @"music_offtopic", @"preview", @"poi_highlight", @"filler"];
    });
    return cats;
}

static NSArray<NSString *> *sbEnabledCategories() {
    NSMutableArray *enabled = [NSMutableArray array];
    for (NSString *cat in sbAllCategories()) {
        NSInteger action = [[NSUserDefaults standardUserDefaults] integerForKey:SB_ACTION_KEY(cat)];
        if (action != SBSegmentActionDisable) {
            [enabled addObject:cat];
        }
    }
    return enabled;
}

UIColor *SBColorFromHex(NSString *hexString) {
    if (!hexString || hexString.length < 7) return [UIColor whiteColor];
    unsigned int hex = 0;
    NSScanner *scanner = [NSScanner scannerWithString:[hexString substringFromIndex:1]];
    [scanner scanHexInt:&hex];
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:1.0];
}

#pragma mark - SBSegment Implementation

@implementation SBSegment

+ (instancetype)segmentWithUUID:(NSString *)UUID category:(NSString *)category start:(float)start end:(float)end action:(NSString *)actionType {
    SBSegment *seg = [[SBSegment alloc] init];
    seg.UUID = UUID;
    seg.category = category;
    seg.startTime = start;
    seg.endTime = end;
    seg.actionType = actionType;
    return seg;
}

- (SBSegmentAction)configuredAction {
    return (SBSegmentAction)[[NSUserDefaults standardUserDefaults] integerForKey:SB_ACTION_KEY(self.category)];
}

- (UIColor *)segmentColor {
    NSString *hex = [[NSUserDefaults standardUserDefaults] stringForKey:SB_COLOR_KEY(self.category)];
    return SBColorFromHex(hex);
}

@end

#pragma mark - SBRequest Implementation

@implementation SBRequest

+ (void)fetchSegmentsForVideoID:(NSString *)videoID completion:(void (^)(NSArray<SBSegment *> *))completion {
    if (!videoID || videoID.length == 0) {
        if (completion) completion(@[]);
        return;
    }

    @synchronized(sbSegmentCache) {
        NSArray *cached = sbSegmentCache[videoID];
        if (cached) {
            if (completion) completion(cached);
            return;
        }
    }

    NSArray *categories = sbEnabledCategories();
    if (categories.count == 0) {
        if (completion) completion(@[]);
        return;
    }

    NSData *catJSON = [NSJSONSerialization dataWithJSONObject:categories options:0 error:nil];
    NSString *catString = [[NSString alloc] initWithData:catJSON encoding:NSUTF8StringEncoding];
    NSString *encoded = [catString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *urlStr = [NSString stringWithFormat:@"https://sponsor.ajay.app/api/skipSegments?videoID=%@&categories=%@", videoID, encoded];
    NSURL *url = [NSURL URLWithString:urlStr];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSMutableArray<SBSegment *> *segments = [NSMutableArray array];

        if (!error && data) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            if (httpResp.statusCode == 200) {
                NSArray *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if ([json isKindOfClass:[NSArray class]]) {
                    for (NSDictionary *item in json) {
                        NSArray *segment = item[@"segment"];
                        if (segment.count >= 2) {
                            SBSegment *seg = [SBSegment segmentWithUUID:item[@"UUID"] ?: @""
                                                              category:item[@"category"] ?: @""
                                                                 start:[segment[0] floatValue]
                                                                   end:[segment[1] floatValue]
                                                                action:item[@"actionType"] ?: @"skip"];
                            [segments addObject:seg];
                        }
                    }
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            @synchronized(sbSegmentCache) {
                sbSegmentCache[videoID] = segments;
            }
            if (completion) completion(segments);
        });
    }];
    [task resume];
}

@end

#pragma mark - YTPlayerViewController Hooks

%hook YTPlayerViewController
%property (nonatomic, strong) NSString *sbLastVideoID;
%property (nonatomic, strong) NSArray *sbSegments;
%property (nonatomic, strong) NSMutableSet *sbSkippedSegments;
%property (nonatomic, strong) SBSkipNotificationView *sbNotificationView;
%property (nonatomic, strong) UIButton *sbOverlayButton;
%property (nonatomic, assign) BOOL sbEnabledForVideo;

// Alternative: fires when video content changes (works in newer YT versions)
- (void)setContentVideoID:(NSString *)videoID {
    %orig;
    @try {
        if (!IS_ENABLED(SBEnabled)) return;
        if (!videoID || videoID.length == 0) return;
        if ([self.sbLastVideoID isEqualToString:videoID] && self.sbSegments.count > 0) return;
        self.sbLastVideoID = videoID;

        self.sbEnabledForVideo = YES;
        self.sbSkippedSegments = [NSMutableSet set];
        self.sbSegments = nil;
        [self.sbNotificationView dismiss];

        __weak typeof(self) weakSelf = self;
        [SBRequest fetchSegmentsForVideoID:videoID completion:^(NSArray<SBSegment *> *segments) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.sbSegments = segments;
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SBSegmentsDidLoad"
                                                                object:strongSelf
                                                              userInfo:@{@"segments": segments ?: @[]}];

            [strongSelf sbShowHighlightBannerIfNeeded:segments];
        }];
    } @catch (NSException *e) {}
}

- (void)playbackController:(id)playbackController didActivateVideo:(id)video withPlaybackData:(id)playbackData {
    %orig;
    @try {
        if (!IS_ENABLED(SBEnabled)) return;
        if (self.isPlayingAd) return;

        self.sbEnabledForVideo = YES;
        self.sbSkippedSegments = [NSMutableSet set];
        self.sbSegments = nil;

        [self.sbNotificationView dismiss];

        NSString *videoID = [self contentVideoID];
        if (!videoID) return;
        if ([self.sbLastVideoID isEqualToString:videoID] && self.sbSegments.count > 0) return;
        self.sbLastVideoID = videoID;

        __weak typeof(self) weakSelf = self;
        [SBRequest fetchSegmentsForVideoID:videoID completion:^(NSArray<SBSegment *> *segments) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.sbSegments = segments;
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SBSegmentsDidLoad"
                                                                object:strongSelf
                                                              userInfo:@{@"segments": segments ?: @[]}];

            [strongSelf sbShowHighlightBannerIfNeeded:segments];
        }];
    } @catch (NSException *e) {}
}

- (void)singleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;
    @try {
        if (!IS_ENABLED(SBEnabled) || !self.sbEnabledForVideo) return;
        if (self.isPlayingAd) return;

        CGFloat currentTime = [self currentVideoMediaTime];
        float minDuration = FLOAT_FOR_KEY(SBMinDuration);

        for (SBSegment *segment in self.sbSegments) {
            SBSegmentAction action = [segment configuredAction];
            if (action == SBSegmentActionDisable || action == SBSegmentActionDisplay) continue;
            if (action == SBSegmentActionSkipTo) continue;

            float duration = segment.endTime - segment.startTime;
            if (duration < minDuration) continue;

            if (currentTime >= segment.startTime && currentTime < segment.endTime - 0.5) {
                NSString *segID = segment.UUID;
                if ([self.sbSkippedSegments containsObject:segID]) continue;

                if (action == SBSegmentActionAutoSkip) {
                    [self sbPerformSkip:segment];
                } else if (action == SBSegmentActionAsk) {
                    [self sbShowAskNotification:segment];
                }
                break;
            }
        }
    } @catch (NSException *e) {}
}

// Alternative hook for newer YouTube versions where method was renamed
- (void)potentiallyMutatedSingleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;
    @try {
        if (!IS_ENABLED(SBEnabled) || !self.sbEnabledForVideo) return;
        if (self.isPlayingAd) return;

        CGFloat currentTime = [self currentVideoMediaTime];
        float minDuration = FLOAT_FOR_KEY(SBMinDuration);

        for (SBSegment *segment in self.sbSegments) {
            SBSegmentAction action = [segment configuredAction];
            if (action == SBSegmentActionDisable || action == SBSegmentActionDisplay) continue;
            if (action == SBSegmentActionSkipTo) continue;

            float duration = segment.endTime - segment.startTime;
            if (duration < minDuration) continue;

            if (currentTime >= segment.startTime && currentTime < segment.endTime - 0.5) {
                NSString *segID = segment.UUID;
                if ([self.sbSkippedSegments containsObject:segID]) continue;

                if (action == SBSegmentActionAutoSkip) {
                    [self sbPerformSkip:segment];
                } else if (action == SBSegmentActionAsk) {
                    [self sbShowAskNotification:segment];
                }
                break;
            }
        }
    } @catch (NSException *e) {}
}

%new
- (void)sbPerformSkip:(SBSegment *)segment {
    [self.sbSkippedSegments addObject:segment.UUID];
    [self seekToTime:(CGFloat)segment.endTime];

    if (IS_ENABLED(SBAudioNotification)) {
        AudioServicesPlaySystemSound(1519);
    }

    if (IS_ENABLED(SBShowNotifications)) {
        NSBundle *bundle = [NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:@"YTNoAds" ofType:@"bundle"]];
        NSString *catName = [bundle localizedStringForKey:[NSString stringWithFormat:@"SB_CAT_%@", segment.category] value:segment.category table:nil];
        NSString *message = [NSString stringWithFormat:[bundle localizedStringForKey:@"SB_SKIPPED" value:@"%@ skipped" table:nil], catName];
        NSString *unskipTitle = [bundle localizedStringForKey:@"SB_UNSKIP" value:@"Unskip" table:nil];

        float alertDuration = FLOAT_FOR_KEY(SBUnskipAlertDuration);
        if (alertDuration <= 0) alertDuration = 3.0;

        __weak typeof(self) weakSelf = self;
        // Delay notification so the seek completes before the banner is shown,
        // preventing the time-change callback from dismissing it immediately.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            UIView *parentView = strongSelf.playerView;
            strongSelf.sbNotificationView = [SBSkipNotificationView showInView:parentView
                message:message
                buttonTitle:unskipTitle
                action:^{
                    __strong typeof(weakSelf) ss = weakSelf;
                    if (ss) [ss seekToTime:(CGFloat)segment.startTime];
                }
                duration:alertDuration];
        });
    }
}

%new
- (void)sbShowAskNotification:(SBSegment *)segment {
    [self.sbSkippedSegments addObject:segment.UUID];

    NSBundle *bundle = [NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:@"YTNoAds" ofType:@"bundle"]];
    NSString *catName = [bundle localizedStringForKey:[NSString stringWithFormat:@"SB_CAT_%@", segment.category] value:segment.category table:nil];
    NSString *message = [NSString stringWithFormat:[bundle localizedStringForKey:@"SB_DETECTED" value:@"%@ detected" table:nil], catName];

    float alertDuration = FLOAT_FOR_KEY(SBSkipAlertDuration);
    if (alertDuration <= 0) alertDuration = 5.0;

    UIView *parentView = self.playerView;
    __weak typeof(self) weakSelf = self;
    self.sbNotificationView = [SBSkipNotificationView showInView:parentView
        message:message
        buttonTitle:[bundle localizedStringForKey:@"SB_SKIP_NOW" value:@"Skip" table:nil]
        action:^{
            __strong typeof(weakSelf) ss = weakSelf;
            if (ss) [ss seekToTime:(CGFloat)segment.endTime];
        }
        duration:alertDuration];
}

%new
- (void)sbShowHighlightBannerIfNeeded:(NSArray<SBSegment *> *)segments {
    for (SBSegment *seg in segments) {
        if ([seg.category isEqualToString:@"poi_highlight"] && [seg configuredAction] == SBSegmentActionSkipTo) {
            NSBundle *bundle = [NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:@"YTNoAds" ofType:@"bundle"]];
            NSString *message = [bundle localizedStringForKey:@"SB_JUMP_TO_HIGHLIGHT" value:@"Highlight available. Jump to the point?" table:nil];
            NSString *skipTitle = [bundle localizedStringForKey:@"SB_SKIP_NOW" value:@"Skip" table:nil];
            UIView *parentView = self.playerView;
            self.sbNotificationView = [SBSkipNotificationView showInView:parentView
                message:message
                buttonTitle:skipTitle
                action:^{ [self sbSkipToHighlight]; }
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

            if (IS_ENABLED(SBShowNotifications)) {
                NSBundle *bundle = [NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:@"YTNoAds" ofType:@"bundle"]];
                NSString *message = [bundle localizedStringForKey:@"SB_JUMPED_TO_HIGHLIGHT" value:@"Jumped to highlight" table:nil];
                self.sbNotificationView = [SBSkipNotificationView showInView:self.playerView
                    message:message
                    buttonTitle:nil
                    action:nil
                    duration:2.0];
            }
            break;
        }
    }
}

%end

%ctor {
    sbSegmentCache = [NSMutableDictionary dictionary];
    %init;
}
