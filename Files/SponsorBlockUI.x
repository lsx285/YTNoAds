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
    view.backgroundColor     = [UIColor colorWithWhite:0.0 alpha:0.85];
    view.layer.cornerRadius  = 12.0;
    view.layer.shadowColor   = [UIColor blackColor].CGColor;
    view.layer.shadowOffset  = CGSizeMake(0, 2);
    view.layer.shadowRadius  = 8.0;
    view.layer.shadowOpacity = 0.4;
    view.clipsToBounds       = NO;
    view.onAction            = action;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text          = message;
    label.textColor     = [UIColor whiteColor];
    label.font          = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    label.numberOfLines = 2;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    view.messageLabel   = label;
    [view addSubview:label];
    NSString *iconName = ([buttonTitle.lowercaseString containsString:@"unskip"] ||
                          [buttonTitle.lowercaseString containsString:@"back"])
                         ? @"backward.end.fill" : @"forward.end.fill";
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setImage:[UIImage systemImageNamed:iconName
                             withConfiguration:[UIImageSymbolConfiguration
                                 configurationWithPointSize:16 weight:UIImageSymbolWeightMedium]]
            forState:UIControlStateNormal];
    button.tintColor          = [UIColor whiteColor];
    button.backgroundColor    = [UIColor colorWithWhite:1.0 alpha:0.15];
    button.layer.cornerRadius = 18.0;
    button.clipsToBounds      = YES;
    [button addTarget:view action:@selector(actionButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    view.actionButton = button;
    [view addSubview:button];
    [parentView addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor  constraintEqualToAnchor:parentView.leadingAnchor  constant:16.0],
        [view.trailingAnchor constraintEqualToAnchor:parentView.trailingAnchor constant:-16.0],
        [view.bottomAnchor   constraintEqualToAnchor:parentView.bottomAnchor   constant:-80.0],
        [label.leadingAnchor  constraintEqualToAnchor:view.leadingAnchor    constant:16.0],
        [label.topAnchor      constraintEqualToAnchor:view.topAnchor        constant:12.0],
        [label.bottomAnchor   constraintEqualToAnchor:view.bottomAnchor     constant:-12.0],
        [label.trailingAnchor constraintEqualToAnchor:button.leadingAnchor  constant:-12.0],
        [button.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-12.0],
        [button.centerYAnchor  constraintEqualToAnchor:view.centerYAnchor],
        [button.widthAnchor    constraintEqualToConstant:36.0],
        [button.heightAnchor   constraintEqualToConstant:36.0],
    ]];
    UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:view action:@selector(dismiss)];
    swipe.direction = UISwipeGestureRecognizerDirectionDown;
    [view addGestureRecognizer:swipe];
    view.alpha     = 0.0;
    view.transform = CGAffineTransformMakeTranslation(0, 10);
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        view.alpha     = 1.0;
        view.transform = CGAffineTransformIdentity;
    } completion:nil];
    if (duration > 0)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [view dismiss]; });
    return view;
}
- (void)actionButtonTapped {
    if (self.onAction) self.onAction();
    [self dismiss];
}
- (void)dismiss {
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.alpha     = 0.0;
        self.transform = CGAffineTransformMakeTranslation(0, 10);
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