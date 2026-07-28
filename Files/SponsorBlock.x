#import "Headers.h"

@interface YTPlayerViewController (SBInternal)
- (void)sbLoadSegmentsForVideoID:(NSString *)videoID;
- (void)sbHandleTimeChange;
@end

// In-memory only: this dictionary lives for the lifetime of the process.
// It is never written to disk, so a fresh launch of the app always starts
// with an empty cache, and it's also cleared on memory warnings below.
static NSMutableDictionary<NSString *, NSArray<SBSegment *> *> *sbSegmentCache;

void SBClearSegmentCache() {
    @synchronized(sbSegmentCache) {
        [sbSegmentCache removeAllObjects];
    }
}

static NSArray<NSString *> *sbEnabledCategories() {
    NSMutableArray *enabled = [NSMutableArray array];
    for (NSString *cat in SBAllCategories())
        if (SBDefaultActionForCategory(cat) != SBSegmentActionDisable)
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

@implementation SBSegment
+ (instancetype)segmentWithUUID:(NSString *)UUID category:(NSString *)category
                          start:(float)start end:(float)end action:(NSString *)actionType {
    SBSegment *seg = [[SBSegment alloc] init];
    seg.UUID       = UUID;
    seg.category   = category;
    seg.startTime  = start;
    seg.endTime    = end;
    seg.actionType = actionType;
    seg.action     = SBDefaultActionForCategory(category);
    seg.color      = SBColorFromHex(SBDefaultColorHexForCategory(category));
    return seg;
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
                        [segments addObject:[SBSegment segmentWithUUID:item[@"UUID"] ?: @""
                                                              category:item[@"category"] ?: @""
                                                                 start:[seg[0] floatValue]
                                                                   end:[seg[1] floatValue]
                                                                action:item[@"actionType"] ?: @"skip"]];
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            @synchronized(sbSegmentCache) {
                sbSegmentCache[videoID] = segments;
            }
            if (completion) completion(segments);
        });
    }] resume];
}
@end

%hook YTPlayerViewController
%property (nonatomic, strong) NSString               *sbLastVideoID;
%property (nonatomic, strong) NSArray                *sbSegments;
%property (nonatomic, strong) NSMutableSet           *sbSkippedSegments;
%property (nonatomic, strong) NSMutableSet           *sbIgnoredSegments;
%property (nonatomic, strong) SBSkipNotificationView *sbNotificationView;
%property (nonatomic, assign) BOOL                    sbEnabledForVideo;
%property (nonatomic, assign) CGFloat                 sbLastSeenTime;
%property (nonatomic, assign) BOOL                    sbIsPerformingSystemSkip;
%property (nonatomic, strong) NSMutableArray         *sbNotificationQueue;
%property (nonatomic, assign) BOOL                    sbNotificationShowing;
%property (nonatomic, assign) BOOL                    sbHighlightPromptShown;

- (void)setContentVideoID:(NSString *)videoID {
    %orig;
    [self sbTriggerLoadIfNeededForVideoID:videoID];
}

- (void)playbackController:(id)pc didActivateVideo:(id)video withPlaybackData:(id)data {
    %orig;
    @try {
        if (self.isPlayingAd) return;
        [self sbTriggerLoadIfNeededForVideoID:[self contentVideoID]];
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
- (void)sbTriggerLoadIfNeededForVideoID:(NSString *)videoID {
    if (!videoID.length || !SB_ENABLED) return;
    if ([self.sbLastVideoID isEqualToString:videoID] && self.sbSegments.count) return;
    self.sbLastVideoID = videoID;
    [self sbLoadSegmentsForVideoID:videoID];
}

%new
- (void)sbLoadSegmentsForVideoID:(NSString *)videoID {
    self.sbEnabledForVideo = YES;
    self.sbSkippedSegments = [NSMutableSet set];
    self.sbIgnoredSegments = [NSMutableSet set];
    self.sbIsPerformingSystemSkip = NO;
    self.sbLastSeenTime    = 0;
    self.sbSegments        = nil;
    self.sbHighlightPromptShown = NO;
    [self.sbNotificationQueue removeAllObjects];
    self.sbNotificationShowing = NO;
    [self.sbNotificationView dismiss];
    self.sbNotificationView = nil;
    
    __weak typeof(self) weakSelf = self;
    [SBRequest fetchSegmentsForVideoID:videoID completion:^(NSArray<SBSegment *> *segments) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.sbSegments = segments;
        [[NSNotificationCenter defaultCenter] postNotificationName:SBSegmentsDidLoadNotification
                                                            object:strongSelf
                                                          userInfo:@{@"segments": segments}];
        [strongSelf sbCheckForHighlightSegment:segments];
    }];
}

%new
- (void)sbCheckForHighlightSegment:(NSArray<SBSegment *> *)segments {
    if (self.sbHighlightPromptShown || !SB_SHOW_NOTIFICATIONS) return;
    for (SBSegment *segment in segments) {
        if ([segment.category isEqualToString:@"poi_highlight"] && segment.action == SBSegmentActionSkipTo) {
            self.sbHighlightPromptShown = YES;
            [self sbShowHighlightNotification:segment];
            return;
        }
    }
}

%new
- (void)sbHandleTimeChange {
    if (!self.sbEnabledForVideo || self.isPlayingAd || !self.sbSegments.count) return;

    CGFloat currentTime = [self currentVideoMediaTime];
    if (currentTime == self.sbLastSeenTime) return;

    BOOL isManualSeek = (self.sbLastSeenTime > 0) && (fabs(currentTime - self.sbLastSeenTime) > SB_BACKWARD_SEEK_THRESH) && !self.sbIsPerformingSystemSkip;
    self.sbIsPerformingSystemSkip = NO;

    if (currentTime < self.sbLastSeenTime - SB_BACKWARD_SEEK_THRESH) {
        [self.sbSkippedSegments removeAllObjects];
    }
    
    self.sbLastSeenTime = currentTime;

    for (SBSegment *segment in self.sbSegments) {
        if (segment.action == SBSegmentActionDisable || segment.action == SBSegmentActionDisplay || segment.action == SBSegmentActionSkipTo) continue;
        if (currentTime < segment.startTime || currentTime >= segment.endTime - 0.5) continue;
        
        if (isManualSeek) {
            [self.sbIgnoredSegments addObject:segment.UUID];
            continue;
        }

        if ([self.sbSkippedSegments containsObject:segment.UUID]) continue;
        if ([self.sbIgnoredSegments containsObject:segment.UUID]) continue;

        if (segment.action == SBSegmentActionAutoSkip) [self sbPerformSkip:segment];
        else if (segment.action == SBSegmentActionAsk) [self sbShowAskNotification:segment];
        break;
    }
}

%new
- (void)sbPerformSkip:(SBSegment *)segment {
    [self.sbSkippedSegments addObject:segment.UUID];
    self.sbIsPerformingSystemSkip = YES;
    [self seekToTime:(CGFloat)segment.endTime];
    
    if (!SB_SHOW_NOTIFICATIONS) return;
    
    NSString *message = [NSString stringWithFormat:@"%@ segment has been skipped", SBCategoryName(segment.category)];
    float startTime = segment.startTime;
    NSString *segmentUUID = segment.UUID;
    CGFloat unskipDuration = SB_UNSKIP_ALERT_DURATION;
    
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SB_NOTIFICATION_DELAY * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf sbEnqueueNotificationWithMessage:message
                                          buttonTitle:@"Unskip"
                                               action:^{
                                                   __strong typeof(weakSelf) ss = weakSelf;
                                                   if (ss) {
                                                       [ss.sbIgnoredSegments addObject:segmentUUID];
                                                       [ss seekToTime:(CGFloat)startTime];
                                                   }
                                               }
                                             duration:unskipDuration];
    });
}

%new
- (void)sbShowAskNotification:(SBSegment *)segment {
    [self.sbSkippedSegments addObject:segment.UUID];
    NSString *message = [NSString stringWithFormat:@"%@ segment detected", SBCategoryName(segment.category)];
    float endTime = segment.endTime;
    
    __weak typeof(self) weakSelf = self;
    [self sbEnqueueNotificationWithMessage:message
                                buttonTitle:@"Skip"
                                     action:^{
                                         __strong typeof(weakSelf) ss = weakSelf;
                                         if (ss) {
                                             ss.sbIsPerformingSystemSkip = YES;
                                             [ss seekToTime:(CGFloat)endTime];
                                         }
                                     }
                                   duration:SB_SKIP_ALERT_DURATION];
}

%new
- (void)sbShowHighlightNotification:(SBSegment *)segment {
    NSString *message = @"Highlight available";
    float startTime = segment.startTime;
    
    __weak typeof(self) weakSelf = self;
    [self sbEnqueueNotificationWithMessage:message
                                buttonTitle:@"Skip to highlight"
                                     action:^{
                                         __strong typeof(weakSelf) ss = weakSelf;
                                         if (ss) {
                                             ss.sbIsPerformingSystemSkip = YES;
                                             [ss seekToTime:(CGFloat)startTime];
                                         }
                                     }
                                   duration:SB_SKIP_ALERT_DURATION];
}

%new
- (void)sbEnqueueNotificationWithMessage:(NSString *)message buttonTitle:(NSString *)buttonTitle
                                   action:(void (^)(void))action duration:(NSTimeInterval)duration {
    if (!self.sbNotificationQueue) self.sbNotificationQueue = [NSMutableArray array];
    void (^safeAction)(void) = action ?: ^{};
    [self.sbNotificationQueue addObject:@{
        @"message":     message ?: @"",
        @"buttonTitle": buttonTitle ?: @"",
        @"action":      [safeAction copy],
        @"duration":    @(duration)
    }];
    [self sbProcessNotificationQueue];
}

%new
- (void)sbProcessNotificationQueue {
    if (self.sbNotificationShowing || !self.sbNotificationQueue.count) return;
    self.sbNotificationShowing = YES;

    NSDictionary *item = self.sbNotificationQueue.firstObject;
    [self.sbNotificationQueue removeObjectAtIndex:0];

    __weak typeof(self) weakSelf = self;
    self.sbNotificationView = [SBSkipNotificationView
        showInView:self.playerView
           message:item[@"message"]
       buttonTitle:item[@"buttonTitle"]
            action:item[@"action"]
          duration:[item[@"duration"] doubleValue]];

    if (!self.sbNotificationView) {
        // No playerView to attach to (e.g. player not visible) — don't stall the queue.
        self.sbNotificationShowing = NO;
        [self sbProcessNotificationQueue];
        return;
    }

    self.sbNotificationView.onDismiss = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.sbNotificationShowing = NO;
        [strongSelf sbProcessNotificationQueue];
    };
}
%end

%ctor {
    sbSegmentCache = [NSMutableDictionary dictionary];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        SBClearSegmentCache();
    }];
    %init;
}