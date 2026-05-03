#include "Headers.h"

static id NSSTR(const char *str) {
    return ((id(*)(id,SEL,const char*))objc_msgSend)(CLS("NSString"), sel_registerName("stringWithUTF8String:"), str);
}

/* SBSegmentMarkerView */
static CGFloat get_startFrac(id self, SEL _cmd) { id v = objc_getAssociatedObject(self, sel_registerName("startFrac")); return v ? SEND(CGFloat, v, "doubleValue") : 0.0; }
static void set_startFrac(id self, SEL _cmd, CGFloat v) { objc_setAssociatedObject(self, sel_registerName("startFrac"), ((id(*)(id,SEL,double))objc_msgSend)(CLS("NSNumber"), sel_registerName("numberWithDouble:"), v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static CGFloat get_endFrac(id self, SEL _cmd) { id v = objc_getAssociatedObject(self, sel_registerName("endFrac")); return v ? SEND(CGFloat, v, "doubleValue") : 0.0; }
static void set_endFrac(id self, SEL _cmd, CGFloat v) { objc_setAssociatedObject(self, sel_registerName("endFrac"), ((id(*)(id,SEL,double))objc_msgSend)(CLS("NSNumber"), sel_registerName("numberWithDouble:"), v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static bool get_isPoi(id self, SEL _cmd) { id v = objc_getAssociatedObject(self, sel_registerName("isPoi")); return v ? SEND(bool, v, "boolValue") : false; }
static void set_isPoi(id self, SEL _cmd, bool v) { objc_setAssociatedObject(self, sel_registerName("isPoi"), ((id(*)(id,SEL,bool))objc_msgSend)(CLS("NSNumber"), sel_registerName("numberWithBool:"), v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

/* SBSkipNotificationView */
static void sb_notif_dismiss(id self, SEL _cmd) {
    void (^anim)(void) = ^{
        ((void(*)(id,SEL,CGFloat))objc_msgSend)(self, sel_registerName("setAlpha:"), 0.0);
        CGAffineTransform trans = CGAffineTransformMakeScale(0.9, 0.9);
        ((void(*)(id,SEL,CGAffineTransform))objc_msgSend)(self, sel_registerName("setTransform:"), trans);
    };
    void (^comp)(bool) = ^(bool finished) {
        SEND(void, self, "removeFromSuperview");
    };
    ((void(*)(id,SEL,double,void(^)(void),void(^)(bool)))objc_msgSend)(CLS("UIView"), sel_registerName("animateWithDuration:animations:completion:"), 0.2, anim, comp);
}

static void sb_notif_handleTap(id self, SEL _cmd) {
    void (^onAction)(void) = objc_getAssociatedObject(self, sel_registerName("onAction"));
    if (onAction) onAction();
    sb_notif_dismiss(self, NULL);
}

id sb_showNotificationView(id parentView, id message, id buttonTitle, id target, SEL action, double duration) {
    if (!parentView) return nil;

    id subviews = SEND(id, parentView, "subviews");
    NSUInteger count = SEND(NSUInteger, subviews, "count");
    for (NSInteger i = count - 1; i >= 0; i--) {
        id sub = ((id(*)(id,SEL,NSUInteger))objc_msgSend)(subviews, sel_registerName("objectAtIndex:"), i);
        if (((bool(*)(id,SEL,Class))objc_msgSend)(sub, sel_registerName("isKindOfClass:"), objc_getClass("SBSkipNotificationView"))) {
            SEND(void, sub, "dismiss");
        }
    }

    id view = SEND(id, SEND(id, objc_getClass("SBSkipNotificationView"), "alloc"), "initWithFrame:", CGRectZero);
    SEND(void, view, "setTranslatesAutoresizingMaskIntoConstraints:", false);
    
    id bgColor = ((id(*)(id,SEL,CGFloat,CGFloat))objc_msgSend)(CLS("UIColor"), sel_registerName("colorWithWhite:alpha:"), 0.0, 0.9);
    SEND(void, view, "setBackgroundColor:", bgColor);
    
    id layer = SEND(id, view, "layer");
    ((void(*)(id,SEL,CGFloat))objc_msgSend)(layer, sel_registerName("setCornerRadius:"), 20.0);
    ((void(*)(id,SEL,id))objc_msgSend)(layer, sel_registerName("setShadowColor:"), SEND(id, SEND(id, CLS("UIColor"), "blackColor"), "CGColor"));
    ((void(*)(id,SEL,CGSize))objc_msgSend)(layer, sel_registerName("setShadowOffset:"), CGSizeMake(0, 4));
    ((void(*)(id,SEL,CGFloat))objc_msgSend)(layer, sel_registerName("setShadowRadius:"), 10.0);
    ((void(*)(id,SEL,float))objc_msgSend)(layer, sel_registerName("setShadowOpacity:"), 0.5);
    SEND(void, view, "setUserInteractionEnabled:", true);

    void (^onAction)(void) = ^{
        ((void(*)(id,SEL,SEL,id,bool))objc_msgSend)(target, sel_registerName("performSelectorOnMainThread:withObject:waitUntilDone:"), action, nil, false);
    };
    objc_setAssociatedObject(view, sel_registerName("onAction"), [onAction copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    id tap = ((id(*)(id,SEL,id,SEL))objc_msgSend)(SEND(id, CLS("UITapGestureRecognizer"), "alloc"), sel_registerName("initWithTarget:action:"), view, sel_registerName("handleTap"));
    SEND(void, view, "addGestureRecognizer:", tap);

    id label = SEND(id, SEND(id, CLS("UILabel"), "alloc"), "initWithFrame:", CGRectZero);
    SEND(void, label, "setTranslatesAutoresizingMaskIntoConstraints:", false);
    SEND(void, label, "setText:", message);
    SEND(void, label, "setTextColor:", SEND(id, CLS("UIColor"), "whiteColor"));
    SEND(void, label, "setFont:", ((id(*)(id,SEL,CGFloat,CGFloat))objc_msgSend)(CLS("UIFont"), sel_registerName("systemFontOfSize:weight:"), 14.0, 0.0 /* Medium */));
    SEND(void, label, "setNumberOfLines:", 1);
    SEND(void, label, "setTextAlignment:", 1);
    SEND(void, view, "addSubview:", label);

    SEND(void, parentView, "addSubview:", view);

    CGRect parentBounds = SEND(CGRect, parentView, "bounds");
    bool isLandscape = parentBounds.size.width > parentBounds.size.height;
    CGFloat bottomOffset = isLandscape ? -30.0 : -70.0;

    id safeArea = SEND(id, parentView, "safeAreaLayoutGuide");
    id constraints = SEND(id, CLS("NSMutableArray"), "array");
    SEND(void, constraints, "addObject:", SEND(id, SEND(id, view, "centerXAnchor"), "constraintEqualToAnchor:", SEND(id, parentView, "centerXAnchor")));
    SEND(void, constraints, "addObject:", SEND(id, SEND(id, view, "bottomAnchor"), "constraintEqualToAnchor:constant:", SEND(id, safeArea, "bottomAnchor"), bottomOffset));
    SEND(void, constraints, "addObject:", SEND(id, SEND(id, view, "heightAnchor"), "constraintEqualToConstant:", 40.0));
    SEND(void, constraints, "addObject:", SEND(id, SEND(id, label, "leadingAnchor"), "constraintEqualToAnchor:constant:", SEND(id, view, "leadingAnchor"), 20.0));
    SEND(void, constraints, "addObject:", SEND(id, SEND(id, label, "trailingAnchor"), "constraintEqualToAnchor:constant:", SEND(id, view, "trailingAnchor"), -20.0));
    SEND(void, constraints, "addObject:", SEND(id, SEND(id, label, "centerYAnchor"), "constraintEqualToAnchor:", SEND(id, view, "centerYAnchor")));
    
    ((void(*)(id,SEL,id))objc_msgSend)(CLS("NSLayoutConstraint"), sel_registerName("activateConstraints:"), constraints);

    SEND(void, view, "setAlpha:", 0.0);
    CGAffineTransform trans = CGAffineTransformMakeScale(0.9, 0.9);
    ((void(*)(id,SEL,CGAffineTransform))objc_msgSend)(view, sel_registerName("setTransform:"), trans);

    void (^animIn)(void) = ^{
        ((void(*)(id,SEL,CGFloat))objc_msgSend)(view, sel_registerName("setAlpha:"), 1.0);
        ((void(*)(id,SEL,CGAffineTransform))objc_msgSend)(view, sel_registerName("setTransform:"), CGAffineTransformIdentity);
    };
    ((void(*)(id,SEL,double,double,double,double,NSUInteger,void(^)(void),void(^)(bool)))objc_msgSend)(CLS("UIView"), sel_registerName("animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:"), 0.3, 0, 0.7, 0.5, 0, animIn, nil);

    if (duration > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SEND(void, view, "dismiss");
        });
    }
    return view;
}

static id sbPlayerBarFromContainer(id container) {
    SEL modSel = sel_registerName("modularPlayerBar");
    if (((bool(*)(id,SEL,SEL))objc_msgSend)(container, sel_registerName("respondsToSelector:"), modSel)) {
        id modular = SEND(id, container, "modularPlayerBar");
        if (((bool(*)(id,SEL,SEL))objc_msgSend)(modular, sel_registerName("respondsToSelector:"), sel_registerName("view"))) {
            return SEND(id, modular, "view");
        }
    }
    SEL segSel = sel_registerName("segmentablePlayerBar");
    if (((bool(*)(id,SEL,SEL))objc_msgSend)(container, sel_registerName("respondsToSelector:"), segSel)) {
        return SEND(id, container, "segmentablePlayerBar");
    }
    return container;
}

static void sbUpdateMarkerFrames(id playerBar, CGFloat barWidth) {
    id referenceView = nil;
    id subviews = SEND(id, playerBar, "subviews");
    NSUInteger count = SEND(NSUInteger, subviews, "count");
    Class rectDeco = objc_getClass("YTPlayerBarRectangleDecorationView");
    Class progDeco = objc_getClass("YTPlayerBarProgressDecorationView");
    
    for (NSUInteger i = 0; i < count; i++) {
        id sub = ((id(*)(id,SEL,NSUInteger))objc_msgSend)(subviews, sel_registerName("objectAtIndex:"), i);
        if ((rectDeco && ((bool(*)(id,SEL,Class))objc_msgSend)(sub, sel_registerName("isKindOfClass:"), rectDeco)) ||
            (progDeco && ((bool(*)(id,SEL,Class))objc_msgSend)(sub, sel_registerName("isKindOfClass:"), progDeco))) {
            referenceView = sub;
            break;
        }
    }

    CGRect refFrame = referenceView ? SEND(CGRect, referenceView, "frame") : CGRectZero;
    CGFloat markerHeight = referenceView ? refFrame.size.height : 3.0;
    if (markerHeight < 2.0) markerHeight = 2.0;
    
    CGFloat markerY = referenceView ? (refFrame.origin.y + (refFrame.size.height - markerHeight) / 2.0) : ((SEND(CGRect, playerBar, "bounds")).size.height - markerHeight) / 2.0;

    for (NSUInteger i = 0; i < count; i++) {
        id sub = ((id(*)(id,SEL,NSUInteger))objc_msgSend)(subviews, sel_registerName("objectAtIndex:"), i);
        if (!((bool(*)(id,SEL,Class))objc_msgSend)(sub, sel_registerName("isKindOfClass:"), objc_getClass("SBSegmentMarkerView"))) continue;
        
        CGFloat startFrac = get_startFrac(sub, NULL);
        CGFloat endFrac = get_endFrac(sub, NULL);
        bool isPoi = get_isPoi(sub, NULL);
        
        CGFloat x = startFrac * barWidth;
        CGFloat w = (endFrac - startFrac) * barWidth;
        
        if (isPoi) {
            w = 3.0;
            x = x - (3.0 / 2.0);
            if (x < 0) x = 0;
        } else {
            if (w < 2.0) w = 2.0;
        }
        
        ((void(*)(id,SEL,CGRect))objc_msgSend)(sub, sel_registerName("setFrame:"), CGRectMake(x, markerY, w, markerHeight));
    }
}

static void hook_YTInlinePlayerBar_layoutSubviews(id self, SEL _cmd) {
    ((void(*)(id,SEL))objc_msgSend)(self, sel_registerName("layoutSubviews")); /* Orig */
    id playerBar = sbPlayerBarFromContainer(self);
    if (!playerBar) return;
    
    CGRect bounds = SEND(CGRect, playerBar, "bounds");
    CGFloat barWidth = bounds.size.width;
    if (barWidth <= 0) return;
    
    sbUpdateMarkerFrames(playerBar, barWidth);
}

static void hook_YTPlayerVC_segmentsDidLoad(id self, SEL _cmd, id notif) {
    id segments = ((id(*)(id,SEL,id))objc_msgSend)(SEND(id, notif, "userInfo"), sel_registerName("objectForKey:"), NSSTR("segments"));
    id overlay = SEND(id, self, "activeVideoPlayerOverlay");
    if (!overlay || !((bool(*)(id,SEL,SEL))objc_msgSend)(overlay, sel_registerName("respondsToSelector:"), sel_registerName("playerBarController"))) return;
    
    id barController = SEND(id, overlay, "playerBarController");
    id containerView = SEND(id, barController, "playerBar");
    if (!containerView) return;
    
    id playerBar = sbPlayerBarFromContainer(containerView);
    id subviews = SEND(id, playerBar, "subviews");
    NSUInteger count = SEND(NSUInteger, subviews, "count");
    Class markerClass = objc_getClass("SBSegmentMarkerView");
    
    for (NSInteger i = count - 1; i >= 0; i--) {
        id sub = ((id(*)(id,SEL,NSUInteger))objc_msgSend)(subviews, sel_registerName("objectAtIndex:"), i);
        if (((bool(*)(id,SEL,Class))objc_msgSend)(sub, sel_registerName("isKindOfClass:"), markerClass)) {
            SEND(void, sub, "removeFromSuperview");
        }
    }
    
    if (!segments || SEND(NSUInteger, segments, "count") == 0) return;

    CGFloat totalTime = SEND(CGFloat, self, "currentVideoTotalMediaTime");
    if (totalTime <= 0) return;

    id referenceView = nil;
    id scrubberView = nil;
    Class rectDeco = objc_getClass("YTPlayerBarRectangleDecorationView");
    Class progDeco = objc_getClass("YTPlayerBarProgressDecorationView");
    Class scrubDeco = objc_getClass("YTPlayerBarScrubberDotDecorationView");

    subviews = SEND(id, playerBar, "subviews");
    count = SEND(NSUInteger, subviews, "count");
    for (NSUInteger i = 0; i < count; i++) {
        id sub = ((id(*)(id,SEL,NSUInteger))objc_msgSend)(subviews, sel_registerName("objectAtIndex:"), i);
        if (rectDeco && ((bool(*)(id,SEL,Class))objc_msgSend)(sub, sel_registerName("isKindOfClass:"), rectDeco)) referenceView = sub;
        else if (!referenceView && progDeco && ((bool(*)(id,SEL,Class))objc_msgSend)(sub, sel_registerName("isKindOfClass:"), progDeco)) referenceView = sub;
        else if (scrubDeco && ((bool(*)(id,SEL,Class))objc_msgSend)(sub, sel_registerName("isKindOfClass:"), scrubDeco)) scrubberView = sub;
    }

    NSUInteger segCount = SEND(NSUInteger, segments, "count");
    for (NSUInteger i = 0; i < segCount; i++) {
        id segment = ((id(*)(id,SEL,NSUInteger))objc_msgSend)(segments, sel_registerName("objectAtIndex:"), i);
        
        SEL actSel = sel_registerName("action");
        NSInteger action = ((NSInteger(*)(id,SEL))objc_msgSend)(segment, actSel);
        if (action == 0) continue;
        
        float start = ((float(*)(id,SEL))objc_msgSend)(segment, sel_registerName("startTime"));
        float end = ((float(*)(id,SEL))objc_msgSend)(segment, sel_registerName("endTime"));
        id category = ((id(*)(id,SEL))objc_msgSend)(segment, sel_registerName("category"));
        id color = ((id(*)(id,SEL))objc_msgSend)(segment, sel_registerName("color"));
        
        bool isPoi = ((bool(*)(id,SEL,id))objc_msgSend)(category, sel_registerName("isEqualToString:"), NSSTR("poi_highlight"));
        
        id marker = SEND(id, SEND(id, markerClass, "alloc"), "initWithFrame:", CGRectZero);
        SEND(void, marker, "setBackgroundColor:", color);
        SEND(void, marker, "setUserInteractionEnabled:", false);
        set_startFrac(marker, NULL, start / totalTime);
        set_endFrac(marker, NULL, end / totalTime);
        set_isPoi(marker, NULL, isPoi);
        
        if (referenceView) {
            ((void(*)(id,SEL,id,id))objc_msgSend)(playerBar, sel_registerName("insertSubview:aboveSubview:"), marker, referenceView);
        } else {
            SEND(void, playerBar, "addSubview:", marker);
        }
    }
    
    SEND(void, containerView, "setNeedsLayout");
    if (scrubberView) {
        id target = SEND(id, scrubberView, "superview") ? SEND(id, scrubberView, "superview") : scrubberView;
        SEND(void, playerBar, "bringSubviewToFront:", target);
    }
}

static void (*orig_YTPlayerVC_viewDidLoad)(id, SEL);
static void hook_YTPlayerVC_viewDidLoad(id self, SEL _cmd) {
    orig_YTPlayerVC_viewDidLoad(self, _cmd);
    id nc = SEND(id, CLS("NSNotificationCenter"), "defaultCenter");
    SEND(void, nc, "removeObserver:name:object:", self, NSSTR("SBSegmentsDidLoad"), self);
    ((void(*)(id,SEL,id,SEL,id,id))objc_msgSend)(nc, sel_registerName("addObserver:selector:name:object:"), self, sel_registerName("sbSegmentsDidLoad:"), NSSTR("SBSegmentsDidLoad"), self);
}

static void (*orig_YTPlayerVC_dealloc)(id, SEL);
static void hook_YTPlayerVC_dealloc(id self, SEL _cmd) {
    SEND(void, SEND(id, CLS("NSNotificationCenter"), "defaultCenter"), "removeObserver:name:object:", self, NSSTR("SBSegmentsDidLoad"), self);
    orig_YTPlayerVC_dealloc(self, _cmd);
}

__attribute__((constructor))
static void YTNoAds_SponsorBlockUI_Init(void) {
    Class marker = objc_allocateClassPair(objc_getClass("UIView"), "SBSegmentMarkerView", 0);
    objc_registerClassPair(marker);

    Class notif = objc_allocateClassPair(objc_getClass("UIView"), "SBSkipNotificationView", 0);
    class_addMethod(notif, sel_registerName("dismiss"), (IMP)sb_notif_dismiss, "v@:");
    class_addMethod(notif, sel_registerName("handleTap"), (IMP)sb_notif_handleTap, "v@:");
    objc_registerClassPair(notif);

    HOOK_INST("YTInlinePlayerBarContainerView", "layoutSubviews", hook_YTInlinePlayerBar_layoutSubviews, NULL);
    
    ADD_METHOD("YTPlayerViewController", "sbSegmentsDidLoad:", hook_YTPlayerVC_segmentsDidLoad, "v@:@");
    HOOK_INST("YTPlayerViewController", "viewDidLoad", hook_YTPlayerVC_viewDidLoad, &orig_YTPlayerVC_viewDidLoad);
    HOOK_INST("YTPlayerViewController", "dealloc", hook_YTPlayerVC_dealloc, &orig_YTPlayerVC_dealloc);
}