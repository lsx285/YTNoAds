#import "Headers.h"
#import <objc/message.h>

@implementation SBSkipNotificationView

+ (instancetype)showInView:(UIView *)parentView message:(NSString *)message
               buttonTitle:(NSString *)buttonTitle action:(void (^)(void))action
                  duration:(NSTimeInterval)duration {
    if (!parentView) return nil;

    for (UIView *sub in [parentView.subviews copy])
        if ([sub isKindOfClass:[SBSkipNotificationView class]])
            [(SBSkipNotificationView *)sub dismiss];

    SBSkipNotificationView *view = [[SBSkipNotificationView alloc] initWithFrame:CGRectZero];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.backgroundColor     = [UIColor colorWithWhite:0.0 alpha:0.9];
    view.layer.cornerRadius  = 20.0;
    view.layer.shadowColor   = [UIColor blackColor].CGColor;
    view.layer.shadowOffset  = CGSizeMake(0, 4);
    view.layer.shadowRadius  = 10.0;
    view.layer.shadowOpacity = 0.5;
    view.userInteractionEnabled = YES;
    view.onAction            = action;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:view action:@selector(handleTap)];
    [view addGestureRecognizer:tap];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text          = message;
    label.textColor     = [UIColor whiteColor];
    label.font          = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    label.numberOfLines = 1;
    label.textAlignment = NSTextAlignmentCenter;
    view.messageLabel   = label;
    [view addSubview:label];

    [parentView addSubview:view];

    BOOL isLandscape = parentView.bounds.size.width > parentView.bounds.size.height;
    CGFloat bottomOffset = isLandscape ? -30.0 : -80.0;

    [NSLayoutConstraint activateConstraints:@[
        [view.centerXAnchor  constraintEqualToAnchor:parentView.centerXAnchor],
        [view.bottomAnchor   constraintEqualToAnchor:parentView.safeAreaLayoutGuide.bottomAnchor constant:bottomOffset],
        [view.heightAnchor   constraintEqualToConstant:40.0],

        [label.leadingAnchor  constraintEqualToAnchor:view.leadingAnchor    constant:20.0],
        [label.trailingAnchor constraintEqualToAnchor:view.trailingAnchor   constant:-20.0],
        [label.centerYAnchor  constraintEqualToAnchor:view.centerYAnchor]
    ]];

    view.alpha     = 0.0;
    view.transform = CGAffineTransformMakeScale(0.9, 0.9);
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
        view.alpha     = 1.0;
        view.transform = CGAffineTransformIdentity;
    } completion:nil];

    if (duration > 0)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [view dismiss]; });
    return view;
}

- (void)handleTap {
    if (self.onAction) self.onAction();
    [self dismiss];
}

- (void)dismiss {
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha     = 0.0;
        self.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL _) { [self removeFromSuperview]; }];
}

@end

static UIView *sbPlayerBarFromContainer(YTInlinePlayerBarContainerView *container) {
    if ([container respondsToSelector:@selector(modularPlayerBar)]) {
        id modular = container.modularPlayerBar;
        if ([modular respondsToSelector:@selector(view)]) return [modular view];
    }
    if ([container respondsToSelector:@selector(segmentablePlayerBar)])
        return (UIView *)container.segmentablePlayerBar;
    return container;
}

%hook YTInlinePlayerBarContainerView
- (void)layoutSubviews {
    %orig;
    UIView *playerBar = sbPlayerBarFromContainer(self);
    if (!playerBar) return;
    CGFloat barWidth = playerBar.bounds.size.width;
    if (barWidth <= 0) return;
    UIView *referenceView = nil;
    for (UIView *sub in playerBar.subviews) {
        if ([sub isKindOfClass:%c(YTPlayerBarRectangleDecorationView)] ||
            [sub isKindOfClass:%c(YTPlayerBarProgressDecorationView)]) {
            referenceView = sub;
            break;
        }
    }
    CGFloat markerY      = referenceView ? referenceView.frame.origin.y : (playerBar.bounds.size.height - 3.0);
    CGFloat markerHeight = MAX(2.0, referenceView ? referenceView.frame.size.height : 3.0);
    for (UIView *sub in playerBar.subviews) {
        if (sub.tag != SBMarkerTag) continue;
        NSArray *data = objc_getAssociatedObject(sub, @selector(sbSegmentData));
        if (data.count < 3) continue;
        CGFloat startFrac = [data[0] floatValue];
        CGFloat endFrac   = [data[1] floatValue];
        BOOL    isPoi     = [data[2] boolValue];
        CGFloat x = startFrac * barWidth;
        CGFloat w = (endFrac - startFrac) * barWidth;
        if (isPoi) { w = 3.0; x = MAX(0, x - 1.5); }
        else w = MAX(2.0, w);
        sub.frame = CGRectMake(x, markerY, w, markerHeight);
    }
}
%end

%group SBObserver
%hook YTPlayerViewController
- (void)viewDidLoad {
    %orig;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SBSegmentsDidLoadNotification object:self];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sbSegmentsDidLoad:)
                                                 name:SBSegmentsDidLoadNotification
                                               object:self];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SBSegmentsDidLoadNotification object:self];
    %orig;
}
%new
- (void)sbSegmentsDidLoad:(NSNotification *)notification {
    @try {
        NSArray<SBSegment *> *segments = notification.userInfo[@"segments"];
        id overlay = [self activeVideoPlayerOverlay];
        if (!overlay || ![overlay respondsToSelector:@selector(playerBarController)]) return;
        YTPlayerBarController *barController = [overlay playerBarController];
        YTInlinePlayerBarContainerView *containerView = barController.playerBar;
        if (!containerView) return;
        UIView *playerBar = sbPlayerBarFromContainer(containerView);
        for (UIView *sub in [playerBar.subviews copy])
            if (sub.tag == SBMarkerTag) [sub removeFromSuperview];
        if (!segments.count) return;
        CGFloat totalTime = [self currentVideoTotalMediaTime];
        CGFloat barWidth  = playerBar.bounds.size.width;
        if (totalTime <= 0 || barWidth <= 0) return;
        UIView *referenceView = nil, *scrubberView = nil;
        for (UIView *sub in playerBar.subviews) {
            if ([sub isKindOfClass:%c(YTPlayerBarRectangleDecorationView)])
                referenceView = sub;
            else if (!referenceView && [sub isKindOfClass:%c(YTPlayerBarProgressDecorationView)])
                referenceView = sub;
            else if ([sub isKindOfClass:%c(YTPlayerBarScrubberDotDecorationView)])
                scrubberView = sub;
        }
        CGFloat markerY      = referenceView ? referenceView.frame.origin.y : (playerBar.bounds.size.height - 3.0);
        CGFloat markerHeight = MAX(2.0, referenceView ? referenceView.frame.size.height : 3.0);
        for (SBSegment *segment in segments) {
            if ([segment configuredAction] == SBSegmentActionDisable) continue;
            CGFloat startFrac = segment.startTime / totalTime;
            CGFloat endFrac   = segment.endTime   / totalTime;
            BOOL    isPoi     = [segment.category isEqualToString:@"poi_highlight"];
            CGFloat x = startFrac * barWidth;
            CGFloat w = (endFrac - startFrac) * barWidth;
            if (isPoi) { w = 3.0; x = MAX(0, x - 1.5); }
            else w = MAX(2.0, w);
            UIView *marker = [[UIView alloc] initWithFrame:CGRectMake(x, markerY, w, markerHeight)];
            marker.backgroundColor        = [segment segmentColor];
            marker.userInteractionEnabled = NO;
            marker.tag                    = SBMarkerTag;
            objc_setAssociatedObject(marker, @selector(sbSegmentData),
                                     @[@(startFrac), @(endFrac), @(isPoi)],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (referenceView) [playerBar insertSubview:marker aboveSubview:referenceView];
            else               [playerBar addSubview:marker];
        }
        if (scrubberView) [playerBar bringSubviewToFront:scrubberView.superview ?: scrubberView];
    } @catch (NSException *e) {}
}
%end
%end

%ctor {
    %init;
    %init(SBObserver);
}
