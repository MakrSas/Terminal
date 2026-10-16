#import "TMTabBar.h"

@implementation TMTabBar {
    UIScrollView *_scroll;
    UIButton *_plus, *_gear;
    NSArray<NSString *> *_titles; NSArray<NSNumber *> *_roots; NSInteger _selected;
    UIColor *_bg, *_fg, *_accent;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _bg = TMHex(0x0b0f19); _fg = TMHex(0xd7dce8); _accent = TMHex(0x4da3ff);
        _scroll = [UIScrollView new]; _scroll.showsHorizontalScrollIndicator = NO; [self addSubview:_scroll];
        _plus = [UIButton buttonWithType:UIButtonTypeSystem];
        [_plus setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
        [_plus addTarget:self action:@selector(plusTapped) forControlEvents:UIControlEventTouchUpInside];
        __weak TMTabBar *ws = self;
        _plus.menu = [UIMenu menuWithChildren:@[
            [UIAction actionWithTitle:TMT(@"New root tab", @"Новая вкладка root") image:[UIImage systemImageNamed:@"number"] identifier:nil handler:^(UIAction *a) { [ws.delegate tabBarNewTabRoot:YES]; }],
            [UIAction actionWithTitle:TMT(@"New tab", @"Новая вкладка") image:[UIImage systemImageNamed:@"plus"] identifier:nil handler:^(UIAction *a) { [ws.delegate tabBarNewTabRoot:NO]; }]]];
        _plus.showsMenuAsPrimaryAction = NO;
        [self addSubview:_plus];
        _gear = [UIButton buttonWithType:UIButtonTypeSystem];
        [_gear setImage:[UIImage systemImageNamed:@"gearshape"] forState:UIControlStateNormal];
        [_gear addTarget:self action:@selector(gearTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_gear];
    }
    return self;
}

- (void)plusTapped { [self.delegate tabBarNewTab]; }
- (void)gearTapped { [self.delegate tabBarOpenSettings]; }

- (void)applyBackground:(UIColor *)bg foreground:(UIColor *)fg accent:(UIColor *)accent {
    _bg = bg; _fg = fg; _accent = accent; self.backgroundColor = bg; _plus.tintColor = fg; _gear.tintColor = fg; [self rebuild];
}

- (void)setTitles:(NSArray<NSString *> *)titles roots:(NSArray<NSNumber *> *)roots selected:(NSInteger)selected {
    _titles = titles; _roots = roots; _selected = selected; [self rebuild];
}

- (void)rebuild {
    for (UIView *v in _scroll.subviews) [v removeFromSuperview];
    CGFloat x = 8; CGRect selFrame = CGRectZero;
    const CGFloat H = 30, pad = 13, closeW = 20;
    for (NSInteger i = 0; i < (NSInteger)_titles.count; i++) {
        BOOL sel = i == _selected, root = [_roots[i] boolValue];
        NSString *t = _titles[i].length > 18 ? [[_titles[i] substringToIndex:17] stringByAppendingString:@"…"] : _titles[i];
        UIFont *f = [UIFont systemFontOfSize:14 weight:sel ? UIFontWeightSemibold : UIFontWeightRegular];
        NSMutableAttributedString *as = [NSMutableAttributedString new];
        if (root) [as appendAttributedString:[[NSAttributedString alloc] initWithString:@"# " attributes:@{NSFontAttributeName: [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightBold], NSForegroundColorAttributeName: TMHex(0xff5d5d)}]];
        [as appendAttributedString:[[NSAttributedString alloc] initWithString:t attributes:@{NSFontAttributeName: f, NSForegroundColorAttributeName: sel ? _fg : [_fg colorWithAlphaComponent:0.6]}]];
        CGFloat textW = ceil([as size].width);
        CGFloat w = MAX(56, pad + textW + (sel ? 4 + closeW : pad));
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(x, 7, w, H);
        b.backgroundColor = sel ? [_fg colorWithAlphaComponent:0.14] : [UIColor clearColor];
        b.layer.cornerRadius = H / 2; b.layer.cornerCurve = kCACornerCurveContinuous;
        b.tag = i;
        [b addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
        // подпись по центру оставшегося места (у активной вкладки справа — крестик)
        UILabel *l = [UILabel new]; l.attributedText = as; l.textAlignment = NSTextAlignmentCenter; l.userInteractionEnabled = NO;
        CGFloat labelW = w - (sel ? closeW + 4 : 0);
        l.frame = CGRectMake(0, 0, labelW + (sel ? 0 : 0), H);
        if (sel) l.frame = CGRectMake(pad / 2, 0, labelW - pad / 2, H);
        [b addSubview:l];
        __weak TMTabBar *ws = self;
        b.menu = [UIMenu menuWithChildren:@[[UIAction actionWithTitle:TMT(@"Close", @"Закрыть") image:[UIImage systemImageNamed:@"xmark"] identifier:nil handler:^(UIAction *a) { [ws.delegate tabBarClose:i]; }]]];
        b.showsMenuAsPrimaryAction = NO;
        [_scroll addSubview:b];
        if (sel) {
            selFrame = b.frame;
            UIButton *c = [UIButton buttonWithType:UIButtonTypeCustom];
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:9 weight:UIImageSymbolWeightBold];
            [c setImage:[[UIImage systemImageNamed:@"xmark" withConfiguration:cfg] imageWithTintColor:[_fg colorWithAlphaComponent:0.55] renderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
            c.tag = i; c.frame = CGRectMake(x + w - closeW - 6, 7, closeW + 6, H);
            [c addTarget:self action:@selector(closeTapped:) forControlEvents:UIControlEventTouchUpInside];
            [_scroll addSubview:c];
        }
        x += w + 6;
    }
    _scroll.contentSize = CGSizeMake(x, 44);
    [self setNeedsLayout];
    if (!CGRectIsEmpty(selFrame)) [_scroll scrollRectToVisible:CGRectInset(selFrame, -30, 0) animated:NO];
}

- (void)tabTapped:(UIButton *)b { [self.delegate tabBarSelect:b.tag]; }
- (void)closeTapped:(UIButton *)b { [self.delegate tabBarClose:b.tag]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width, L = self.safeAreaInsets.left, R = self.safeAreaInsets.right;
    _gear.frame = CGRectMake(W - R - 44, 0, 44, 44);
    _plus.frame = CGRectMake(W - R - 88, 0, 44, 44);
    _scroll.frame = CGRectMake(L, 0, W - L - R - 88, 44);
}

@end
