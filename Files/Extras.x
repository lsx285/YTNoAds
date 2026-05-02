#import "Headers.h"

// Background Playback
%hook MLVideo
- (BOOL)playableInBackground { return YES; }
%end

%hook YTIPlayabilityStatus
- (BOOL)isPlayableInBackground { return YES; }
%end

%hook YTPlaybackData
- (BOOL)isPlayableInBackground { return YES; }
%end

%hook YTIPlayerResponse
- (BOOL)isPlayableInBackground { return YES; }
%end

// Hide Create Button
%hook YTPivotBarView
- (void)setRenderer:(YTIPivotBarRenderer *)renderer {
    NSMutableArray *items = [renderer itemsArray];
    [items removeObjectsAtIndexes:[items indexesOfObjectsPassingTest:^BOOL(YTIPivotBarSupportedRenderers *item, NSUInteger idx, BOOL *stop) {
        return [[item pivotBarIconOnlyItemRenderer].pivotIdentifier isEqualToString:@"FEuploads"];
    }]];
    %orig(renderer);
}
%end
