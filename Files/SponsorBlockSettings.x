// SponsorBlockSettings.x — YTNoAds
// Full SponsorBlock settings UI (YouMod-style: sliders, rainbow color circles,
// per-category dropdowns) surfaced as a native YouTube settings push from the
// top-level SponsorBlock section registered in Settings.x.
#import "Headers.h"
#import <objc/runtime.h>
#import <objc/message.h>

extern UIColor *SBColorFromHex(NSString *hexString);

// ─── Hardcoded English strings (no bundle / PSHeader needed) ─────────────────

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
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (int)(r * 255), (int)(g * 255), (int)(b * 255)];
}

static NSArray<NSString *> *SBCategories() {
    return @[@"sponsor", @"intro", @"outro", @"interaction",
             @"selfpromo", @"music_offtopic", @"preview",
             @"poi_highlight", @"filler"];
}

// ─── Rainbow + filled-center color circle ────────────────────────────────────

@interface SBColorCircleView : UIView
@property (nonatomic, strong) UIColor *fillColor;
- (instancetype)initWithFrame:(CGRect)frame color:(UIColor *)color;
@end

@implementation SBColorCircleView

- (instancetype)initWithFrame:(CGRect)frame color:(UIColor *)color {
    self = [super initWithFrame:frame];
    if (self) {
        _fillColor = color;
        self.backgroundColor = [UIColor clearColor];
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat size = MIN(rect.size.width, rect.size.height);
    CGRect sq = CGRectMake((rect.size.width - size) / 2,
                           (rect.size.height - size) / 2, size, size);
    CGFloat cx = CGRectGetMidX(sq), cy = CGRectGetMidY(sq);
    CGFloat ringW = 3.0, radius = (size - ringW) / 2.0;

    NSInteger segs = 64;
    CGFloat step = (2.0 * M_PI) / segs;
    for (NSInteger i = 0; i < segs; i++) {
        CGFloat start = i * step - M_PI_2;
        CGFloat end   = start + step + 0.02;
        UIColor *c = [UIColor colorWithHue:(CGFloat)i / segs
                                saturation:1.0 brightness:1.0 alpha:1.0];
        CGContextSetStrokeColorWithColor(ctx, c.CGColor);
        CGContextSetLineWidth(ctx, ringW);
        CGContextAddArc(ctx, cx, cy, radius, start, end, 0);
        CGContextStrokePath(ctx);
    }

    UIBezierPath *inner = [UIBezierPath
        bezierPathWithOvalInRect:CGRectInset(sq, ringW + 2, ringW + 2)];
    [self.fillColor setFill];
    [inner fill];
}

- (void)setFillColor:(UIColor *)fillColor {
    _fillColor = fillColor;
    [self setNeedsDisplay];
}

@end

// ─── SBSettingsViewController ─────────────────────────────────────────────────

@interface SBSettingsViewController : UIViewController
    <UITableViewDelegate, UITableViewDataSource, UIColorPickerViewControllerDelegate>
@end

static const void *kSBTableKey    = &kSBTableKey;
static const void *kSBColorKey_k  = &kSBColorKey_k;
static const void *kSBColorIdxKey = &kSBColorIdxKey;

@implementation SBSettingsViewController

- (UITableView *)sbTableView {
    return objc_getAssociatedObject(self, kSBTableKey);
}
- (void)setSbTableView:(UITableView *)tv {
    objc_setAssociatedObject(self, kSBTableKey, tv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSString *)activeColorKey {
    return objc_getAssociatedObject(self, kSBColorKey_k);
}
- (void)setActiveColorKey:(NSString *)k {
    objc_setAssociatedObject(self, kSBColorKey_k, k, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSIndexPath *)activeColorIndexPath {
    return objc_getAssociatedObject(self, kSBColorIdxKey);
}
- (void)setActiveColorIndexPath:(NSIndexPath *)ip {
    objc_setAssociatedObject(self, kSBColorIdxKey, ip, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UIColor *)sbTextColor {
    return (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark)
        ? [UIColor whiteColor] : [UIColor labelColor];
}
- (UIColor *)sbSecondaryTextColor {
    return [UIColor colorWithWhite:0.55 alpha:1.0];
}
- (UIColor *)sbAccentColor {
    return [UIColor colorWithRed:0.6 green:0.2 blue:0.9 alpha:1.0];
}

- (void)viewDidLoad {
    Class ytStyled = objc_getClass("YTStyledViewController");
    struct objc_super sup = { self, ytStyled ?: [UIViewController class] };
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, @selector(viewDidLoad));

    self.title = @"SponsorBlock";

    UITableView *tv = [[UITableView alloc] initWithFrame:self.view.bounds
                                                   style:UITableViewStyleGrouped];
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

- (void)viewWillAppear:(BOOL)animated {
    Class ytStyled = objc_getClass("YTStyledViewController");
    struct objc_super sup = { self, ytStyled ?: [UIViewController class] };
    ((void (*)(struct objc_super *, SEL, BOOL))objc_msgSendSuper)(&sup,
        @selector(viewWillAppear:), animated);
}

#pragma mark - Table structure: 0 = toggles, 1 = sliders, 2 = categories

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 7;
    if (section == 1) return 2;
    return (NSInteger)SBCategories().count * 2;
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
    NSString *title = nil;
    if (section == 0) title = @"General";
    if (section == 2) title = @"Categories";
    if (!title) return nil;

    UIView *header = [[UIView alloc] init];
    UILabel *label = [[UILabel alloc] init];
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
        BOOL isAction  = (indexPath.row % 2 == 0);
        NSInteger catIdx = indexPath.row / 2;
        if (isAction && catIdx > 0) return 64;
        return 48;
    }
    return UITableViewAutomaticDimension;
}

- (UITableViewCell *)tableView:(UITableView *)tv
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return [self toggleCellForRow:indexPath.row tableView:tv];
    if (indexPath.section == 1) return [self sliderCellForRow:indexPath.row tableView:tv];
    return [self segmentCellForRow:indexPath.row tableView:tv];
}

#pragma mark - Toggle cells (section 0)

- (UITableViewCell *)toggleCellForRow:(NSInteger)row tableView:(UITableView *)tv {
    UITableViewCell *cell = [[UITableViewCell alloc]
        initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor           = [UIColor clearColor];
    cell.selectionStyle            = UITableViewCellSelectionStyleNone;
    cell.textLabel.textColor       = [self sbTextColor];
    cell.textLabel.font            = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    cell.detailTextLabel.textColor = [self sbSecondaryTextColor];
    cell.detailTextLabel.font      = [UIFont systemFontOfSize:13];
    cell.detailTextLabel.numberOfLines = 0;

    NSString *title, *desc, *key;
    switch (row) {
        case 0:  title=@"Enable SponsorBlock";        desc=@"Skip sponsored segments using community data.";            key=SBEnabled; break;
        case 1:  title=@"Show overlay button";        desc=@"Display a SponsorBlock toggle button in the player.";     key=SBShowButton; break;
        case 2:  title=@"Show skip notifications";    desc=@"Show a banner when a segment is auto-skipped.";           key=SBShowNotifications; break;
        case 3:  title=@"Segments in feed";           desc=@"Show colored segments on feed player progress bars.";     key=SBSegmentsInFeed; break;
        case 4:  title=@"Segments in mini-player";    desc=@"Show colored segments on the mini-player progress bar.";  key=SBSegmentsInMiniPlayer; break;
        case 5:  title=@"Haptic feedback";            desc=@"Vibrate when a segment is skipped.";                      key=SBAudioNotification; break;
        default: title=@"Show duration without ads";  desc=@"Show video length excluding skippable segments.";         key=SBShowDuration; break;
    }

    cell.textLabel.text       = title;
    cell.detailTextLabel.text = desc;

    UISwitch *sw   = [[UISwitch alloc] init];
    sw.on          = [[NSUserDefaults standardUserDefaults] boolForKey:key];
    sw.onTintColor = [self sbAccentColor];
    sw.tag         = row;
    [sw addTarget:self action:@selector(toggleChanged:)
         forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)toggleChanged:(UISwitch *)sender {
    NSString *keys[] = {
        SBEnabled, SBShowButton, SBShowNotifications,
        SBSegmentsInFeed, SBSegmentsInMiniPlayer,
        SBAudioNotification, SBShowDuration
    };
    if (sender.tag >= 0 && sender.tag < 7)
        [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:keys[sender.tag]];
}

#pragma mark - Slider cells (section 1)

- (UITableViewCell *)sliderCellForRow:(NSInteger)row tableView:(UITableView *)tv {
    UITableViewCell *cell = [[UITableViewCell alloc]
        initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
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
    [slider addTarget:self action:@selector(sliderChanged:)
             forControlEvents:UIControlEventValueChanged];

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
        [titleLabel.topAnchor     constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
        [titleLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],

        [slider.topAnchor      constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
        [slider.leadingAnchor  constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [slider.trailingAnchor constraintEqualToAnchor:valueLabel.leadingAnchor constant:-8],
        [slider.bottomAnchor   constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],

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

#pragma mark - Category cells (section 2)

- (UITableViewCell *)segmentCellForRow:(NSInteger)row tableView:(UITableView *)tv {
    NSInteger catIdx  = row / 2;
    BOOL isColorRow   = (row % 2 == 1);
    NSString *cat     = SBCategories()[catIdx];
    NSString *catName = SBCategoryName(cat);
    return isColorRow
        ? [self colorCellForCategory:cat name:catName tableView:tv]
        : [self actionCellForCategory:cat name:catName tableView:tv];
}

- (UITableViewCell *)actionCellForCategory:(NSString *)category
                                      name:(NSString *)catName
                                 tableView:(UITableView *)tv {
    UITableViewCell *cell = [[UITableViewCell alloc]
        initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [UIColor clearColor];
    cell.selectionStyle  = UITableViewCellSelectionStyleNone;
    cell.textLabel.text      = catName;
    cell.textLabel.textColor = [self sbTextColor];
    cell.textLabel.font      = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];

    NSString *actionKey     = SB_ACTION_KEY(category);
    BOOL isHighlight        = [category isEqualToString:@"poi_highlight"];
    NSInteger currentAction = [[NSUserDefaults standardUserDefaults] integerForKey:actionKey];

    UIButton *menuBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [menuBtn setTitle:SBActionLabel(currentAction) forState:UIControlStateNormal];
    [menuBtn setTitleColor:[self sbSecondaryTextColor] forState:UIControlStateNormal];
    menuBtn.titleLabel.font          = [UIFont systemFontOfSize:15];
    menuBtn.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [menuBtn setImage:[UIImage systemImageNamed:@"chevron.up.chevron.down"]
             forState:UIControlStateNormal];
    menuBtn.tintColor = [self sbSecondaryTextColor];

    NSMutableArray *menuActions = [NSMutableArray array];
    NSArray *actionDefs = isHighlight
        ? @[@[@(SBSegmentActionDisable), @"Disabled"],
            @[@(SBSegmentActionSkipTo),  @"Skip to"],
            @[@(SBSegmentActionDisplay), @"Show on bar"]]
        : @[@[@(SBSegmentActionDisable),  @"Disabled"],
            @[@(SBSegmentActionAutoSkip), @"Auto-skip"],
            @[@(SBSegmentActionAsk),      @"Ask to skip"],
            @[@(SBSegmentActionDisplay),  @"Show on bar"]];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
        configurationWithPointSize:14];

    for (NSArray *def in actionDefs) {
        NSInteger val      = [def[0] integerValue];
        NSString *defTitle = def[1];
        UIImage *check     = (val == currentAction)
            ? [UIImage systemImageNamed:@"checkmark" withConfiguration:cfg] : nil;

        UIAction *act = [UIAction actionWithTitle:defTitle
                                            image:check
                                       identifier:nil
                                          handler:^(__kindof UIAction *a) {
            [[NSUserDefaults standardUserDefaults] setInteger:val forKey:actionKey];
            [[self sbTableView] reloadData];
        }];
        if (val == currentAction) act.state = UIMenuElementStateOn;
        [menuActions addObject:act];
    }

    menuBtn.menu = [UIMenu menuWithTitle:catName children:menuActions];
    menuBtn.showsMenuAsPrimaryAction = YES;
    [menuBtn sizeToFit];
    cell.accessoryView = menuBtn;
    return cell;
}

- (UITableViewCell *)colorCellForCategory:(NSString *)category
                                     name:(NSString *)catName
                                tableView:(UITableView *)tv {
    UITableViewCell *cell = [[UITableViewCell alloc]
        initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [UIColor clearColor];
    cell.selectionStyle  = UITableViewCellSelectionStyleNone;
    cell.textLabel.text      = [NSString stringWithFormat:@"%@ color", catName];
    cell.textLabel.textColor = [self sbTextColor];
    cell.textLabel.font      = [UIFont systemFontOfSize:15];

    NSString *hex  = [[NSUserDefaults standardUserDefaults]
                      stringForKey:SB_COLOR_KEY(category)];
    UIColor *color = SBColorFromHex(hex);
    SBColorCircleView *circle = [[SBColorCircleView alloc]
        initWithFrame:CGRectMake(0, 0, 34, 34) color:color];
    cell.accessoryView = circle;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 2 || indexPath.row % 2 != 1) return;

    NSInteger catIdx   = indexPath.row / 2;
    NSString *cat      = SBCategories()[catIdx];
    NSString *catName  = SBCategoryName(cat);
    NSString *colorKey = SB_COLOR_KEY(cat);

    [self setActiveColorKey:colorKey];
    [self setActiveColorIndexPath:indexPath];

    UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
    picker.title         = [NSString stringWithFormat:@"%@ color", catName];
    picker.supportsAlpha = NO;
    picker.delegate      = self;
    NSString *hex = [[NSUserDefaults standardUserDefaults] stringForKey:colorKey];
    if (hex) picker.selectedColor = SBColorFromHex(hex);

    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIColorPickerViewControllerDelegate

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)vc {
    [[NSUserDefaults standardUserDefaults]
        setObject:SBHexFromColor(vc.selectedColor) forKey:[self activeColorKey]];
    [[self sbTableView] reloadRowsAtIndexPaths:@[[self activeColorIndexPath]]
                              withRowAnimation:UITableViewRowAnimationNone];
}

- (void)colorPickerViewController:(UIColorPickerViewController *)vc
                   didSelectColor:(UIColor *)color
                       continuously:(BOOL)continuously {
    if (!continuously) {
        [[NSUserDefaults standardUserDefaults]
            setObject:SBHexFromColor(color) forKey:[self activeColorKey]];
        [[self sbTableView] reloadRowsAtIndexPaths:@[[self activeColorIndexPath]]
                                  withRowAnimation:UITableViewRowAnimationNone];
    }
}

#pragma mark - Footer spacing

- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)section {
    return (section == 2) ? 0 : 16;
}
- (UIView *)tableView:(UITableView *)tv viewForFooterInSection:(NSInteger)section {
    return [[UIView alloc] init];
}

@end

// ─── Hook: register top-level SponsorBlock section ───────────────────────────

static const NSInteger kSBSectionCategory = 'ytsb';

@interface YTSettingsSectionItemManager (SponsorBlock)
- (void)updateSponsorBlockSectionWithEntry:(id)entry;
@end

%hook YTSettingsSectionItemManager

%new(v@:@)
- (void)updateSponsorBlockSectionWithEntry:(id)entry {
    YTSettingsViewController *settingsVC =
        [self valueForKey:@"_settingsViewControllerDelegate"];
    Class Item = %c(YTSettingsSectionItem);

    // One row whose selectBlock pushes the full SBSettingsViewController
    YTSettingsSectionItem *sbItem = [Item
        itemWithTitle:@"SponsorBlock"
        accessibilityIdentifier:nil
        detailTextBlock:nil
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            Class sbClass = objc_getClass("SBSettingsViewControllerStyled");
            if (!sbClass) sbClass = [SBSettingsViewController class];
            id allocated = [sbClass alloc];
            SBSettingsViewController *sbVC =
                (SBSettingsViewController *)((id (*)(id, SEL, id))objc_msgSend)
                    (allocated, @selector(initWithParentResponder:), settingsVC);
            [settingsVC pushViewController:sbVC];
            return YES;
        }];

    YTIIcon *icon = [%c(YTIIcon) new];
    icon.iconType = 530;
    sbItem.settingIcon = icon;

    NSMutableArray<YTSettingsSectionItem *> *items =
        [NSMutableArray arrayWithObject:sbItem];

    if ([settingsVC respondsToSelector:
            @selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:)])
        [settingsVC setSectionItems:items
                        forCategory:kSBSectionCategory
                              title:@"SponsorBlock"
                               icon:icon
                   titleDescription:nil
                       headerHidden:NO];
    else
        [settingsVC setSectionItems:items
                        forCategory:kSBSectionCategory
                              title:@"SponsorBlock"
                   titleDescription:nil
                       headerHidden:NO];
}

%end

// ─── Runtime subclass + defaults ─────────────────────────────────────────────

%ctor {
    // Register SBSettingsViewControllerStyled as a YTStyledViewController subclass
    // so YouTube applies its own nav-bar theming to our settings screen.
    Class ytStyled = %c(YTStyledViewController);
    if (ytStyled) {
        Class sbStyled = objc_allocateClassPair(ytStyled, "SBSettingsViewControllerStyled", 0);
        if (sbStyled) {
            unsigned int count = 0;
            Method *methods = class_copyMethodList([SBSettingsViewController class], &count);
            for (unsigned int i = 0; i < count; i++) {
                SEL sel        = method_getName(methods[i]);
                IMP imp        = method_getImplementation(methods[i]);
                const char *ty = method_getTypeEncoding(methods[i]);
                class_addMethod(sbStyled, sel, imp, ty);
            }
            free(methods);

            unsigned int propCount = 0;
            objc_property_t *props = class_copyPropertyList(
                [SBSettingsViewController class], &propCount);
            for (unsigned int i = 0; i < propCount; i++) {
                unsigned int attrCount = 0;
                objc_property_attribute_t *attrs =
                    property_copyAttributeList(props[i], &attrCount);
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
