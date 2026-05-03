#import "Headers.h"
#import <objc/runtime.h>
#import <objc/message.h>

extern UIColor *SBColorFromHex(NSString *hexString);

static NSString *SBCategoryName(NSString *category) {
    static NSDictionary *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{
            @"sponsor":        @"Sponsor",
            @"intro":          @"Intro / Intermission",
            @"outro":          @"Endcards / Credits",
            @"interaction":    @"Interaction Reminder",
            @"selfpromo":      @"Unpaid Self-promotion",
            @"music_offtopic": @"Non-music Section",
            @"preview":        @"Preview / Recap",
            @"poi_highlight":  @"Highlight",
            @"filler":         @"Filler Tangent",
        };
    });
    return names[category] ?: category;
}

static NSString *SBActionLabel(NSInteger action) {
    switch (action) {
        case SBSegmentActionAutoSkip: return @"Auto-skip";
        case SBSegmentActionAsk:      return @"Ask to skip";
        case SBSegmentActionDisplay:  return @"Show on bar";
        case SBSegmentActionSkipTo:   return @"Skip to";
        default:                      return @"Disabled";
    }
}

static NSString *SBHexFromColor(UIColor *color) {
    CGFloat r, g, b, a;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)(r * 255), (int)(g * 255), (int)(b * 255)];
}

static NSArray<NSString *> *SBCategories() {
    return @[@"sponsor", @"intro", @"outro", @"interaction",
             @"selfpromo", @"music_offtopic", @"preview", @"poi_highlight", @"filler"];
}

#define SB_SUPER_VOID(sel) \
    do { \
        Class _base = objc_getClass("YTStyledViewController") ?: [UIViewController class]; \
        struct objc_super _sup = { self, _base }; \
        ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&_sup, @selector(sel)); \
    } while (0)

#define SB_SUPER_BOOL(sel, val) \
    do { \
        Class _base = objc_getClass("YTStyledViewController") ?: [UIViewController class]; \
        struct objc_super _sup = { self, _base }; \
        ((void (*)(struct objc_super *, SEL, BOOL))objc_msgSendSuper)(&_sup, @selector(sel), val); \
    } while (0)

@interface SBColorCircleView : UIView
@property (nonatomic, strong) UIColor *fillColor;
- (instancetype)initWithFrame:(CGRect)frame color:(UIColor *)color;
@end

@implementation SBColorCircleView

- (instancetype)initWithFrame:(CGRect)frame color:(UIColor *)color {
    self = [super initWithFrame:frame];
    if (self) { _fillColor = color; self.backgroundColor = [UIColor clearColor]; }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat size   = MIN(rect.size.width, rect.size.height);
    CGRect  sq     = CGRectMake((rect.size.width  - size) / 2,
                                (rect.size.height - size) / 2, size, size);
    CGFloat cx     = CGRectGetMidX(sq), cy = CGRectGetMidY(sq);
    CGFloat ringW  = 3.0, radius = (size - ringW) / 2.0;
    CGFloat step   = (2.0 * M_PI) / 64;

    for (NSInteger i = 0; i < 64; i++) {
        CGFloat start = i * step - M_PI_2;
        CGContextSetStrokeColorWithColor(ctx,
            [UIColor colorWithHue:(CGFloat)i / 64 saturation:1 brightness:1 alpha:1].CGColor);
        CGContextSetLineWidth(ctx, ringW);
        CGContextAddArc(ctx, cx, cy, radius, start, start + step + 0.02, 0);
        CGContextStrokePath(ctx);
    }

    [self.fillColor setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectInset(sq, ringW + 2, ringW + 2)] fill];
}

- (void)setFillColor:(UIColor *)fillColor {
    _fillColor = fillColor;
    [self setNeedsDisplay];
}

@end

@interface SBSettingsViewController : UIViewController
    <UITableViewDelegate, UITableViewDataSource, UIColorPickerViewControllerDelegate>
@end

static const void *kSBTableKey    = &kSBTableKey;
static const void *kSBColorKey_k  = &kSBColorKey_k;
static const void *kSBColorIdxKey = &kSBColorIdxKey;

@implementation SBSettingsViewController

- (UITableView *)sbTableView { return objc_getAssociatedObject(self, kSBTableKey); }
- (void)setSbTableView:(UITableView *)tv {
    objc_setAssociatedObject(self, kSBTableKey, tv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSString *)activeColorKey { return objc_getAssociatedObject(self, kSBColorKey_k); }
- (void)setActiveColorKey:(NSString *)k {
    objc_setAssociatedObject(self, kSBColorKey_k, k, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSIndexPath *)activeColorIndexPath { return objc_getAssociatedObject(self, kSBColorIdxKey); }
- (void)setActiveColorIndexPath:(NSIndexPath *)ip {
    objc_setAssociatedObject(self, kSBColorIdxKey, ip, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UIColor *)sbTextColor {
    return (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark)
           ? [UIColor whiteColor] : [UIColor labelColor];
}
- (UIColor *)sbSecondaryTextColor { return [UIColor colorWithWhite:0.55 alpha:1.0]; }
- (UIColor *)sbAccentColor        { return [UIColor colorWithRed:0.6 green:0.2 blue:0.9 alpha:1.0]; }

- (void)viewDidLoad {
    SB_SUPER_VOID(viewDidLoad);
    self.title = @"SponsorBlock";

    UITableView *tv = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    tv.autoresizingMask   = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.delegate           = self;
    tv.dataSource         = self;
    tv.separatorStyle     = UITableViewCellSeparatorStyleNone;
    tv.estimatedRowHeight = 60;
    tv.rowHeight          = UITableViewAutomaticDimension;
    tv.backgroundColor    = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark)
                            ? [UIColor blackColor] : [UIColor systemBackgroundColor];
    [self.view addSubview:tv];
    [self setSbTableView:tv];
}

- (void)viewWillAppear:(BOOL)animated { SB_SUPER_BOOL(viewWillAppear:, animated); }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 7;
    if (section == 1) return 2;
    return (NSInteger)SBCategories().count * 2;
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
    NSString *title = (section == 0) ? @"General" : (section == 2) ? @"Categories" : nil;
    if (!title) return nil;

    UIView  *header = [[UIView alloc] init];
    UILabel *label  = [[UILabel alloc] init];
    label.text      = title;
    label.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    label.font      = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [label.bottomAnchor  constraintEqualToAnchor:header.bottomAnchor  constant:-6],
    ]];
    return header;
}

- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section {
    return (section == 1) ? 16 : 36;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) return 70;
    if (indexPath.section == 2) {
        NSInteger catIdx = indexPath.row / 2;
        return (indexPath.row % 2 == 0 && catIdx > 0) ? 64 : 48;
    }
    return UITableViewAutomaticDimension;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return [self toggleCellForRow:indexPath.row tableView:tv];
    if (indexPath.section == 1) return [self sliderCellForRow:indexPath.row tableView:tv];
    return [self segmentCellForRow:indexPath.row tableView:tv];
}

static NSDictionary *sbToggleDefAtRow(NSInteger row) {
    static NSArray *defs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        defs = @[
            @{@"title": @"Enable SponsorBlock",       @"desc": @"Skip sponsored segments using community data.",              @"key": SBEnabled},
            @{@"title": @"Show overlay button",        @"desc": @"Display a SponsorBlock toggle button in the player.",        @"key": SBShowButton},
            @{@"title": @"Show skip notifications",    @"desc": @"Show a banner when a segment is auto-skipped.",              @"key": SBShowNotifications},
            @{@"title": @"Segments in feed",           @"desc": @"Show colored segments on feed player progress bars.",        @"key": SBSegmentsInFeed},
            @{@"title": @"Segments in mini-player",    @"desc": @"Show colored segments on the mini-player progress bar.",     @"key": SBSegmentsInMiniPlayer},
            @{@"title": @"Haptic feedback",            @"desc": @"Vibrate when a segment is skipped.",                         @"key": SBAudioNotification},
            @{@"title": @"Show duration without ads",  @"desc": @"Show video length excluding skippable segments.",            @"key": SBShowDuration},
        ];
    });
    return (row >= 0 && row < (NSInteger)defs.count) ? defs[row] : nil;
}

- (UITableViewCell *)toggleCellForRow:(NSInteger)row tableView:(UITableView *)tv {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor           = [UIColor clearColor];
    cell.selectionStyle            = UITableViewCellSelectionStyleNone;
    cell.textLabel.textColor       = [self sbTextColor];
    cell.textLabel.font            = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    cell.detailTextLabel.textColor = [self sbSecondaryTextColor];
    cell.detailTextLabel.font      = [UIFont systemFontOfSize:13];
    cell.detailTextLabel.numberOfLines = 0;

    NSDictionary *def = sbToggleDefAtRow(row);
    cell.textLabel.text       = def[@"title"];
    cell.detailTextLabel.text = def[@"desc"];

    UISwitch *sw   = [[UISwitch alloc] init];
    sw.on          = [[NSUserDefaults standardUserDefaults] boolForKey:def[@"key"]];
    sw.onTintColor = [self sbAccentColor];
    sw.tag         = row;
    [sw addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)toggleChanged:(UISwitch *)sender {
    NSDictionary *def = sbToggleDefAtRow(sender.tag);
    if (def) [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:def[@"key"]];
}

- (UITableViewCell *)sliderCellForRow:(NSInteger)row tableView:(UITableView *)tv {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [UIColor clearColor];
    cell.selectionStyle  = UITableViewCellSelectionStyleNone;

    NSString *title = (row == 0) ? @"Skip alert duration" : @"Unskip alert duration";
    NSString *key   = (row == 0) ? SBSkipAlertDuration    : SBUnskipAlertDuration;
    float cur = [[NSUserDefaults standardUserDefaults] floatForKey:key];
    if (cur <= 0) cur = 4.0;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text      = title;
    titleLabel.textColor = [self sbSecondaryTextColor];
    titleLabel.font      = [UIFont systemFontOfSize:13];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UISlider *slider = [[UISlider alloc] init];
    slider.minimumValue          = 2.0;
    slider.maximumValue          = 20.0;
    slider.value                 = cur;
    slider.minimumTrackTintColor = [self sbAccentColor];
    slider.maximumTrackTintColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.tag = row;
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];

    UILabel *valueLabel = [[UILabel alloc] init];
    valueLabel.text          = [NSString stringWithFormat:@"%d secs", (int)cur];
    valueLabel.textColor     = [self sbSecondaryTextColor];
    valueLabel.font          = [UIFont systemFontOfSize:13];
    valueLabel.textAlignment = NSTextAlignmentRight;
    valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    valueLabel.tag = 100 + row;

    [cell.contentView addSubview:titleLabel];
    [cell.contentView addSubview:slider];
    [cell.contentView addSubview:valueLabel];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor     constraintEqualToAnchor:cell.contentView.topAnchor     constant:8],
        [titleLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],

        [slider.topAnchor      constraintEqualToAnchor:titleLabel.bottomAnchor          constant:8],
        [slider.leadingAnchor  constraintEqualToAnchor:cell.contentView.leadingAnchor   constant:16],
        [slider.trailingAnchor constraintEqualToAnchor:valueLabel.leadingAnchor         constant:-8],
        [slider.bottomAnchor   constraintEqualToAnchor:cell.contentView.bottomAnchor    constant:-8],

        [valueLabel.centerYAnchor  constraintEqualToAnchor:slider.centerYAnchor],
        [valueLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [valueLabel.widthAnchor    constraintEqualToConstant:50],
    ]];
    return cell;
}

- (void)sliderChanged:(UISlider *)sender {
    NSString *key = (sender.tag == 0) ? SBSkipAlertDuration : SBUnskipAlertDuration;
    int rounded   = (int)roundf(sender.value);
    sender.value  = rounded;
    [[NSUserDefaults standardUserDefaults] setFloat:(float)rounded forKey:key];
    UILabel *vl = (UILabel *)[sender.superview viewWithTag:100 + sender.tag];
    vl.text = [NSString stringWithFormat:@"%d secs", rounded];
}

- (UITableViewCell *)segmentCellForRow:(NSInteger)row tableView:(UITableView *)tv {
    NSString *cat     = SBCategories()[row / 2];
    NSString *catName = SBCategoryName(cat);
    return (row % 2 == 1) ? [self colorCellForCategory:cat name:catName tableView:tv]
                           : [self actionCellForCategory:cat name:catName tableView:tv];
}

- (UITableViewCell *)actionCellForCategory:(NSString *)category name:(NSString *)catName tableView:(UITableView *)tv {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor     = [UIColor clearColor];
    cell.selectionStyle      = UITableViewCellSelectionStyleNone;
    cell.textLabel.text      = catName;
    cell.textLabel.textColor = [self sbTextColor];
    cell.textLabel.font      = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];

    NSString  *actionKey     = SB_ACTION_KEY(category);
    BOOL       isHighlight   = [category isEqualToString:@"poi_highlight"];
    NSInteger  currentAction = [[NSUserDefaults standardUserDefaults] integerForKey:actionKey];

    UIButton *menuBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [menuBtn setTitle:SBActionLabel(currentAction) forState:UIControlStateNormal];
    [menuBtn setTitleColor:[self sbSecondaryTextColor] forState:UIControlStateNormal];
    menuBtn.titleLabel.font          = [UIFont systemFontOfSize:15];
    menuBtn.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [menuBtn setImage:[UIImage systemImageNamed:@"chevron.up.chevron.down"] forState:UIControlStateNormal];
    menuBtn.tintColor = [self sbSecondaryTextColor];

    NSArray *actionDefs = isHighlight
        ? @[@[@(SBSegmentActionDisable), @"Disabled"],
            @[@(SBSegmentActionSkipTo),  @"Skip to"],
            @[@(SBSegmentActionDisplay), @"Show on bar"]]
        : @[@[@(SBSegmentActionDisable),  @"Disabled"],
            @[@(SBSegmentActionAutoSkip), @"Auto-skip"],
            @[@(SBSegmentActionAsk),      @"Ask to skip"],
            @[@(SBSegmentActionDisplay),  @"Show on bar"]];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14];
    NSMutableArray *menuActions = [NSMutableArray arrayWithCapacity:actionDefs.count];
    for (NSArray *def in actionDefs) {
        NSInteger val = [def[0] integerValue];
        BOOL isCurrent = (val == currentAction);
        UIAction *act = [UIAction actionWithTitle:def[1]
                                            image:isCurrent ? [UIImage systemImageNamed:@"checkmark" withConfiguration:cfg] : nil
                                       identifier:nil
                                          handler:^(__kindof UIAction *a) {
            [[NSUserDefaults standardUserDefaults] setInteger:val forKey:actionKey];
            [[self sbTableView] reloadData];
        }];
        if (isCurrent) act.state = UIMenuElementStateOn;
        [menuActions addObject:act];
    }

    menuBtn.menu = [UIMenu menuWithTitle:catName children:menuActions];
    menuBtn.showsMenuAsPrimaryAction = YES;
    [menuBtn sizeToFit];
    cell.accessoryView = menuBtn;
    return cell;
}

- (UITableViewCell *)colorCellForCategory:(NSString *)category name:(NSString *)catName tableView:(UITableView *)tv {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor     = [UIColor clearColor];
    cell.selectionStyle      = UITableViewCellSelectionStyleNone;
    cell.textLabel.text      = [NSString stringWithFormat:@"%@ color", catName];
    cell.textLabel.textColor = [self sbTextColor];
    cell.textLabel.font      = [UIFont systemFontOfSize:15];

    NSString *hex = [[NSUserDefaults standardUserDefaults] stringForKey:SB_COLOR_KEY(category)];
    cell.accessoryView = [[SBColorCircleView alloc] initWithFrame:CGRectMake(0, 0, 34, 34)
                                                            color:SBColorFromHex(hex)];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 2 || indexPath.row % 2 != 1) return;

    NSString *cat      = SBCategories()[indexPath.row / 2];
    NSString *colorKey = SB_COLOR_KEY(cat);
    [self setActiveColorKey:colorKey];
    [self setActiveColorIndexPath:indexPath];

    UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
    picker.title         = [NSString stringWithFormat:@"%@ color", SBCategoryName(cat)];
    picker.supportsAlpha = NO;
    picker.delegate      = self;
    NSString *hex = [[NSUserDefaults standardUserDefaults] stringForKey:colorKey];
    if (hex) picker.selectedColor = SBColorFromHex(hex);
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)vc {
    [[NSUserDefaults standardUserDefaults] setObject:SBHexFromColor(vc.selectedColor) forKey:[self activeColorKey]];
    [[self sbTableView] reloadRowsAtIndexPaths:@[[self activeColorIndexPath]]
                              withRowAnimation:UITableViewRowAnimationNone];
}

- (void)colorPickerViewController:(UIColorPickerViewController *)vc
                   didSelectColor:(UIColor *)color continuously:(BOOL)continuously {
    if (continuously) return;
    [[NSUserDefaults standardUserDefaults] setObject:SBHexFromColor(color) forKey:[self activeColorKey]];
    [[self sbTableView] reloadRowsAtIndexPaths:@[[self activeColorIndexPath]]
                              withRowAnimation:UITableViewRowAnimationNone];
}

- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)section {
    return (section == 2) ? 0 : 16;
}
- (UIView *)tableView:(UITableView *)tv viewForFooterInSection:(NSInteger)section {
    return [[UIView alloc] init];
}

@end

%ctor {
    Class ytStyled = %c(YTStyledViewController);
    if (ytStyled) {
        Class sbStyled = objc_allocateClassPair(ytStyled, "SBSettingsViewControllerStyled", 0);
        if (sbStyled) {
            unsigned int count = 0;
            Method *methods = class_copyMethodList([SBSettingsViewController class], &count);
            for (unsigned int i = 0; i < count; i++)
                class_addMethod(sbStyled, method_getName(methods[i]),
                                method_getImplementation(methods[i]),
                                method_getTypeEncoding(methods[i]));
            free(methods);

            unsigned int propCount = 0;
            objc_property_t *props = class_copyPropertyList([SBSettingsViewController class], &propCount);
            for (unsigned int i = 0; i < propCount; i++) {
                unsigned int attrCount = 0;
                objc_property_attribute_t *attrs = property_copyAttributeList(props[i], &attrCount);
                class_addProperty(sbStyled, property_getName(props[i]), attrs, attrCount);
                free(attrs);
            }
            free(props);
            objc_registerClassPair(sbStyled);
        }
    }

    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        SBEnabled:              @YES,
        SBShowButton:           @YES,
        SBShowNotifications:    @YES,
        SBAudioNotification:    @NO,
        SBSegmentsInFeed:       @NO,
        SBSegmentsInMiniPlayer: @YES,
        SBShowDuration:         @NO,
        SBSkipAlertDuration:    @4.0,
        SBUnskipAlertDuration:  @4.0,
        SBMinDuration:          @0.0,
        SB_ACTION_KEY(@"sponsor"):        @(SBSegmentActionAutoSkip),
        SB_ACTION_KEY(@"intro"):          @(SBSegmentActionAutoSkip),
        SB_ACTION_KEY(@"outro"):          @(SBSegmentActionAutoSkip),
        SB_ACTION_KEY(@"interaction"):    @(SBSegmentActionAutoSkip),
        SB_ACTION_KEY(@"selfpromo"):      @(SBSegmentActionAutoSkip),
        SB_ACTION_KEY(@"music_offtopic"): @(SBSegmentActionAutoSkip),
        SB_ACTION_KEY(@"preview"):        @(SBSegmentActionAutoSkip),
        SB_ACTION_KEY(@"poi_highlight"):  @(SBSegmentActionSkipTo),
        SB_ACTION_KEY(@"filler"):         @(SBSegmentActionDisplay),
        SB_COLOR_KEY(@"sponsor"):         @"#00D400",
        SB_COLOR_KEY(@"intro"):           @"#00FFFF",
        SB_COLOR_KEY(@"outro"):           @"#0202ED",
        SB_COLOR_KEY(@"interaction"):     @"#CC00FF",
        SB_COLOR_KEY(@"selfpromo"):       @"#FFFF00",
        SB_COLOR_KEY(@"music_offtopic"):  @"#FF9900",
        SB_COLOR_KEY(@"preview"):         @"#008FD6",
        SB_COLOR_KEY(@"poi_highlight"):   @"#FFFFFF",
        SB_COLOR_KEY(@"filler"):          @"#7300FF",
    }];
    %init;
}
