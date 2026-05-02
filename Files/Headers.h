#import <YouTubeHeader/_ASDisplayView.h>
#import <YouTubeHeader/YTIElementRenderer.h>
#import <YouTubeHeader/YTISectionListRenderer.h>
#import <YouTubeHeader/YTIShelfRenderer.h>
#import <YouTubeHeader/YTIWatchNextResponse.h>
#import <YouTubeHeader/YTPlayerOverlay.h>
#import <YouTubeHeader/YTPlayerOverlayProvider.h>
#import <YouTubeHeader/YTReelModel.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTInnerTubeCollectionViewController.h>
#import <YouTubeHeader/YTIShowFullscreenInterstitialCommand.h>

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

@interface YTIPivotBarRenderer : NSObject
- (NSMutableArray <YTIPivotBarSupportedRenderers *> *)itemsArray;
@end
