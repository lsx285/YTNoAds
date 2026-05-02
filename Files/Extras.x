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
    NSMutableIndexSet *indicesToRemove = [NSMutableIndexSet indexSet];
    for (NSUInteger i = 0; i < items.count; i++) {
        NSString *pID2 = [[items[i] pivotBarIconOnlyItemRenderer] pivotIdentifier];
        if ([pID2 isEqualToString:@"FEuploads"]) [indicesToRemove addIndex:i];
    }
    [items removeObjectsAtIndexes:indicesToRemove];
    %orig(renderer);
}
%end
