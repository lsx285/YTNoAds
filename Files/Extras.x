#import "Headers.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

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

%hook YTShortsPlayerViewController
- (BOOL)shouldAlwaysEnablePlayerBar { return YES; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return NO; }
%end

%hook YTReelPlayerViewController
- (BOOL)shouldAlwaysEnablePlayerBar { return YES; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return NO; }
%end

%hook YTReelPlayerViewControllerSub
- (BOOL)shouldAlwaysEnablePlayerBar { return YES; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return NO; }
%end

%hook YTColdConfig
- (BOOL)iosEnableVideoPlayerScrubber { return YES; }
- (BOOL)mobileShortsTablnlinedExpandWatchOnDismiss { return YES; }
%end

%hook YTHotConfig
- (BOOL)enablePlayerBarForVerticalVideoWhenControlsHiddenInFullscreen { return YES; }
%end

// Enable YouTube's native Liquid Glass tab bar when the feature exists.
static void YTNoAdsForceYES(Class cls, SEL sel, BOOL isClassMethod) {
    if (!cls) return;

    Method method = isClassMethod ? class_getClassMethod(cls, sel)
                                  : class_getInstanceMethod(cls, sel);
    if (!method) return;

    const char *types = method_getTypeEncoding(method);
    if (!types || types[0] != 'B') return;

    Class target = isClassMethod ? object_getClass(cls) : cls;
    IMP implementation = imp_implementationWithBlock(^BOOL(id receiver) {
        (void)receiver;
        return YES;
    });
    class_replaceMethod(target, sel, implementation, types);
}

static void YTNoAdsForceInteger(Class cls, SEL sel, BOOL isClassMethod, NSInteger value) {
    if (!cls) return;

    Method method = isClassMethod ? class_getClassMethod(cls, sel)
                                  : class_getInstanceMethod(cls, sel);
    if (!method) return;

    const char *types = method_getTypeEncoding(method);
    if (!types || types[0] != 'q') return;

    Class target = isClassMethod ? object_getClass(cls) : cls;
    IMP implementation = imp_implementationWithBlock(^NSInteger(id receiver) {
        (void)receiver;
        return value;
    });
    class_replaceMethod(target, sel, implementation, types);
}

%ctor {
    @autoreleasepool {
        if (!NSClassFromString(@"UIGlassEffect")) return;

        YTNoAdsForceYES(NSClassFromString(@"YTColdConfig"),
                        NSSelectorFromString(@"mainAppCoreClientIos27EnableLiquidGlass"), NO);
        YTNoAdsForceYES(NSClassFromString(@"YTColdConfigMainAppCoreClientImpl"),
                        NSSelectorFromString(@"ios27EnableLiquidGlass"), NO);

        YTNoAdsForceYES(NSClassFromString(@"YTColdConfig"),
                        NSSelectorFromString(@"mainAppCoreClientIosEnablePositionedFloatyBars"), NO);
        YTNoAdsForceYES(NSClassFromString(@"YTColdConfigMainAppCoreClientImpl"),
                        NSSelectorFromString(@"iosEnablePositionedFloatyBars"), NO);

        YTNoAdsForceInteger(NSClassFromString(@"YTColdConfig"),
                            NSSelectorFromString(@"mainAppCoreClientIosFloatingBarStyle"), NO, 2);
        YTNoAdsForceInteger(NSClassFromString(@"YTColdConfigMainAppCoreClientImpl"),
                            NSSelectorFromString(@"iosFloatingBarStyle"), NO, 2);

        Class glassClass = NSClassFromString(@"M3CLiquidGlass");
        SEL availabilitySelectors[] = {
            NSSelectorFromString(@"isLiquidGlassAvailable"),
            NSSelectorFromString(@"computeIsLiquidGlassAvailable")
        };
        for (NSUInteger i = 0; i < sizeof(availabilitySelectors) / sizeof(availabilitySelectors[0]); i++) {
            YTNoAdsForceYES(glassClass, availabilitySelectors[i], YES);
            YTNoAdsForceYES(glassClass, availabilitySelectors[i], NO);
        }
    }
}
