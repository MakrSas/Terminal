#import "TMExtraKeysBar.h"
#import "TMKeyBarConfig.h"
#import "TMSettings.h"

@interface TMKeyButton : UIButton
@property (nonatomic) BOOL repeats;
@property (nonatomic, copy) void (^action)(void);
@end
@implementation TMKeyButton {
    NSTimer *_t;
}
- (instancetype)initWithTitle:(NSString *)title {
    if ((self = [super initWithFrame:CGRectZero])) {
        [self setTitle:title forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightMedium];
        self.layer.cornerRadius = 7; self.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentEdgeInsets = UIEdgeInsetsMake(0, 11, 0, 11);
        [self addTarget:self action:@selector(down) forControlEvents:UIControlEventTouchDown];
        [self addTarget:self action:@selector(up) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    }
    return self;
}
- (void)down {
    if (self.action) self.action();
    if (self.repeats) {
        __weak TMKeyButton *ws = self;
        _t = [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:NO block:^(NSTimer *x) { [ws startRepeating]; }];
    }
    static UISelectionFeedbackGenerator *g; if (!g) g = [UISelectionFeedbackGenerator new];
    [g selectionChanged];
}
- (void)startRepeating {
    __weak TMKeyButton *ws = self;
    _t = [NSTimer scheduledTimerWithTimeInterval:0.045 repeats:YES block:^(NSTimer *y) { if (ws.action) ws.action(); }];
}
- (void)up { [_t invalidate]; _t = nil; }
@end

@implementation TMExtraKeysBar {
    UIScrollView *_scroll;
    UIButton *_hide;
    NSMutableArray<TMKeyButton *> *_buttons;
    TMKeyButton *_ctrlBtn, *_altBtn;
    BOOL _fnRow;
    UIColor *_bg, *_fg, *_accent, *_lock;
    NSDate *_lastCtrlTap, *_lastAltTap;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(0, 0, frame.size.width, 46)])) {
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _scroll = [UIScrollView new];
        _scroll.showsHorizontalScrollIndicator = NO; _scroll.alwaysBounceHorizontal = YES;
        [self addSubview:_scroll];
        _hide = [UIButton buttonWithType:UIButtonTypeSystem];
        [_hide setImage:[UIImage systemImageNamed:@"keyboard.chevron.compact.down"] forState:UIControlStateNormal];
        [_hide addTarget:self action:@selector(hideTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_hide];
        _bg = TMHex(0x151a26); _fg = TMHex(0xe6e9f2); _accent = TMHex(0x4da3ff); _lock = TMHex(0xff9f0a); _interactive = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rebuild) name:TM_DEFAULTS_CHANGED object:nil];
        [self rebuild];
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)applyBackground:(UIColor *)bg foreground:(UIColor *)fg accent:(UIColor *)accent lock:(UIColor *)lock { _bg = bg; _fg = fg; _accent = accent; _lock = lock; [self rebuild]; }

- (void)setFnRow:(BOOL)on { _fnRow = on; [self rebuild]; }
- (void)hideTapped { [self.delegate extraKeysBarHideKeyboard:self]; }

- (TMKeyButton *)key:(NSString *)title action:(void (^)(void))a {
    TMKeyButton *b = [[TMKeyButton alloc] initWithTitle:title];
    b.action = a;
    [_buttons addObject:b];
    return b;
}
- (TMKeyButton *)textKey:(NSString *)text title:(NSString *)title {
    __weak TMExtraKeysBar *ws = self;
    return [self key:title action:^{ [ws.delegate extraKeysBar:ws sendText:text]; }];
}
- (TMKeyButton *)usageKey:(NSString *)title usage:(UIKeyboardHIDUsage)u repeats:(BOOL)r {
    __weak TMExtraKeysBar *ws = self;
    TMKeyButton *b = [self key:title action:^{ [ws.delegate extraKeysBar:ws sendKey:u]; }];
    b.repeats = r;
    return b;
}

- (void)toggleMod:(BOOL)isCtrl {
    NSDate *now = [NSDate date];
    NSDate *last = isCtrl ? _lastCtrlTap : _lastAltTap;
    TMModState cur = isCtrl ? _ctrl : _alt, next;
    if (cur == TMModOff) next = (last && [now timeIntervalSinceDate:last] < 0.4) ? TMModLocked : TMModOnce;
    else next = TMModOff;
    if (cur == TMModOnce && last && [now timeIntervalSinceDate:last] < 0.4) next = TMModLocked;
    if (isCtrl) { _ctrl = next; _lastCtrlTap = now; } else { _alt = next; _lastAltTap = now; }
    [self refreshModifiers];
}

- (void)consumeModifiers {
    BOOL ch = NO;
    if (_ctrl == TMModOnce) { _ctrl = TMModOff; ch = YES; }
    if (_alt == TMModOnce) { _alt = TMModOff; ch = YES; }
    if (ch) [self refreshModifiers];
}

- (void)styleButton:(TMKeyButton *)b active:(BOOL)on locked:(BOOL)locked {
    b.backgroundColor = on ? (locked ? _lock : _accent) : [_fg colorWithAlphaComponent:0.13];
    [b setTitleColor:on ? _bg : _fg forState:UIControlStateNormal];
}
- (void)refreshModifiers {
    if (_ctrlBtn) [self styleButton:_ctrlBtn active:_ctrl != TMModOff locked:_ctrl == TMModLocked];
    if (_altBtn) [self styleButton:_altBtn active:_alt != TMModOff locked:_alt == TMModLocked];
}

- (void)rebuild {
    for (UIView *v in _scroll.subviews) [v removeFromSuperview];
    _buttons = [NSMutableArray array];
    self.backgroundColor = _bg;
    _hide.tintColor = _fg;
    __weak TMExtraKeysBar *ws = self;
    _ctrlBtn = nil; _altBtn = nil;
    if (!_fnRow) {
        for (NSDictionary *item in [TMSettings shared].keyBarItems) {
            TMKeyDef *d = [TMKeyBarConfig defForItem:item];
            if (!d) continue;
            switch (d.kind) {
                case TMKeyKindUsage: { [self usageKey:d.title usage:d.usage repeats:d.repeats]; break; }
                case TMKeyKindText: { [self textKey:d.text title:d.title]; break; }
                case TMKeyKindCtrl: { _ctrlBtn = [self key:d.title action:^{ [ws toggleMod:YES]; }]; break; }
                case TMKeyKindAlt: { _altBtn = [self key:d.title action:^{ [ws toggleMod:NO]; }]; break; }
                case TMKeyKindPaste: { [self key:TMT(@"paste", @"встав") action:^{ [ws.delegate extraKeysBarPaste:ws]; }]; break; }
                case TMKeyKindFn: { [self key:@"Fn" action:^{ [ws setFnRow:YES]; }]; break; }
            }
        }
    } else {
        for (int i = 0; i < 12; i++) [self usageKey:[NSString stringWithFormat:@"F%d", i + 1] usage:(UIKeyboardHIDUsage)(UIKeyboardHIDUsageKeyboardF1 + i) repeats:NO];
        [self usageKey:@"home" usage:UIKeyboardHIDUsageKeyboardHome repeats:NO];
        [self usageKey:@"end" usage:UIKeyboardHIDUsageKeyboardEnd repeats:NO];
        [self usageKey:@"pgup" usage:UIKeyboardHIDUsageKeyboardPageUp repeats:YES];
        [self usageKey:@"pgdn" usage:UIKeyboardHIDUsageKeyboardPageDown repeats:YES];
        [self usageKey:@"ins" usage:UIKeyboardHIDUsageKeyboardInsert repeats:NO];
        [self usageKey:@"del" usage:UIKeyboardHIDUsageKeyboardDeleteForward repeats:YES];
        [self key:@"ABC" action:^{ [ws setFnRow:NO]; }];
    }
    for (TMKeyButton *b in _buttons) {
        [_scroll addSubview:b];
        if (b != _ctrlBtn && b != _altBtn) [self styleButton:b active:NO locked:NO];
    }
    if (!_fnRow) [self refreshModifiers]; else { _ctrlBtn = nil; _altBtn = nil; }
    if (!_interactive) for (TMKeyButton *b in _buttons) b.userInteractionEnabled = NO;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width, H = 46, hideW = 46;
    _hide.frame = CGRectMake(W - hideW - self.safeAreaInsets.right, 0, hideW, H);
    _scroll.frame = CGRectMake(self.safeAreaInsets.left, 0, W - hideW - self.safeAreaInsets.left - self.safeAreaInsets.right, H);
    CGFloat x = 6;
    for (TMKeyButton *b in _buttons) {
        CGSize s = [b sizeThatFits:CGSizeMake(200, 34)];
        CGFloat w = MAX(36, s.width);
        b.frame = CGRectMake(x, 6, w, 34);
        x += w + 6;
    }
    _scroll.contentSize = CGSizeMake(x, H);
}

- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, 46); }

@end
