#import "Headers.h"
#import <AudioToolbox/AudioToolbox.h>

@interface YTPlayerViewController (SBInternal)
- (void)sbLoadSegmentsForVideoID:(NSString *)videoID;
- (void)sbHandleTimeChange;
@end

static NSMutableDictionary<NSString *, NSArray<SBSegment *> *> *sbSegmentCache;

void SBClearSegmentCache() {
    @synchronized(sbSegmentCache) {
        [sbSegmentCache removeAllObjects];
    }
}

NSString *SBCacheSizeFormatted() {
    NSUInteger byteCount = 0;
    @synchronized(sbSegmentCache) {
        if (sbSegmentCache.count == 0) return @"0 KB";
        for (NSString *key in sbSegmentCache) {
            byteCount += [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            for (SBSegment *seg in sbSegmentCache[key]) {
                byteCount += [seg.UUID lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
                byteCount += [seg.category lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
                byteCount += [seg.actionType lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
                byteCount += sizeof(float) * 2 + sizeof(SBSegmentAction) + sizeof(id);
            }
        }
    }
    if (byteCount < 1024) return [NSString stringWithFormat:@"%lu B", (unsigned long)byteCount];
    if (byteCount < 1024 * 1024) return [NSString stringWithFormat:@"%.1f KB", byteCount / 1024.0];
    return [NSString stringWithFormat:@"%.1f MB", byteCount / (1024.0 * 1024.0)];
}

static NSArray<NSString *> *sbEnabledCategories() {
    NSMutableArray *enabled = [NSMutableArray array];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (NSString *cat in SBAllCategories())
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

@implementation SBSegment
+ (instancetype)segmentWithUUID:(NSString *)UUID category:(NSString *)category
                          start:(float)start end:(float)end action:(NSString *)actionType {
    SBSegment *seg = [[SBSegment alloc] init];
    seg.UUID       = UUID;
    seg.category   = category;
    seg.startTime  = start;
    seg.endTime    = end;
    seg.actionType = actionType;
    seg.action     = (SBSegmentAction)[[NSUserDefaults standardUserDefaults] integerForKey:SB_ACTION_KEY(category)];
    seg.color      = SBColorFromHex([[NSUserDefaults standardUserDefaults] stringForKey:SB_COLOR_KEY(category)]);
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
%property (nonatomic, assign) BOOL                    sbHapticFeedback;
%property (nonatomic, assign) BOOL                    sbShowNotifications;
%property (nonatomic, assign) CGFloat                 sbSkipAlertDuration;
%property (nonatomic, assign) CGFloat                 sbUnskipAlertDuration;
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
    if (!videoID.length || !IS_ENABLED(SBEnabled)) return;
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
    self.sbHapticFeedback = IS_ENABLED(SBHapticFeedback);
    self.sbShowNotifications = IS_ENABLED(SBShowNotifications);
    self.sbSkipAlertDuration = FLOAT_FOR_KEY(SBSkipAlertDuration) > 0 ? FLOAT_FOR_KEY(SBSkipAlertDuration) : 4.0;
    self.sbUnskipAlertDuration = FLOAT_FOR_KEY(SBUnskipAlertDuration) > 0 ? FLOAT_FOR_KEY(SBUnskipAlertDuration) : 4.0;
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
    if (self.sbHighlightPromptShown || !self.sbShowNotifications) return;
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
    
    if (self.sbHapticFeedback) AudioServicesPlaySystemSound(SB_HAPTIC_SOUND_ID);
    if (!self.sbShowNotifications) return;
    
    NSString *message = [NSString stringWithFormat:@"%@ segment has been skipped", SBCategoryName(segment.category)];
    float startTime = segment.startTime;
    NSString *segmentUUID = segment.UUID;
    CGFloat unskipDuration = self.sbUnskipAlertDuration;
    
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
                                   duration:self.sbSkipAlertDuration];
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
                                   duration:self.sbSkipAlertDuration];
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