#import "TMThemes.h"

@implementation TMTheme

- (instancetype)initName:(NSString *)n bg:(uint32_t)bg fg:(uint32_t)fg cursor:(uint32_t)c sel:(uint32_t)s light:(BOOL)l ansi:(const uint32_t *)a {
    if ((self = [super init])) {
        _name = n; _background = bg; _foreground = fg; _cursor = c; _selection = s; _light = l;
        NSMutableArray *arr = [NSMutableArray array];
        for (int i = 0; i < 16; i++) [arr addObject:@(a[i])];
        _ansi = arr;
    }
    return self;
}

+ (NSArray<TMTheme *> *)all {
    static NSArray *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
#define T(NM, BG, FG, CUR, SEL, LT, ...) [[TMTheme alloc] initName:NM bg:BG fg:FG cursor:CUR sel:SEL light:LT ansi:(const uint32_t[16]){__VA_ARGS__}]
        all = @[
            T(@"Makr", 0x0b0f19, 0xd7dce8, 0x4da3ff, 0x233b66, NO,
              0x1b2233, 0xff6b7a, 0x6bd68a, 0xf2cd6b, 0x4da3ff, 0xc08bff, 0x4fd8e0, 0xd7dce8,
              0x4a5470, 0xff8a96, 0x8ae8a6, 0xffe08a, 0x7dbcff, 0xd2a8ff, 0x7ae8ee, 0xffffff),
            T(@"Dracula", 0x282a36, 0xf8f8f2, 0xf8f8f2, 0x44475a, NO,
              0x21222c, 0xff5555, 0x50fa7b, 0xf1fa8c, 0xbd93f9, 0xff79c6, 0x8be9fd, 0xf8f8f2,
              0x6272a4, 0xff6e6e, 0x69ff94, 0xffffa5, 0xd6acff, 0xff92df, 0xa4ffff, 0xffffff),
            T(@"One Dark", 0x282c34, 0xabb2bf, 0x528bff, 0x3e4451, NO,
              0x282c34, 0xe06c75, 0x98c379, 0xe5c07b, 0x61afef, 0xc678dd, 0x56b6c2, 0xabb2bf,
              0x5c6370, 0xe06c75, 0x98c379, 0xe5c07b, 0x61afef, 0xc678dd, 0x56b6c2, 0xffffff),
            T(@"Tokyo Night", 0x1a1b26, 0xc0caf5, 0xc0caf5, 0x33467c, NO,
              0x15161e, 0xf7768e, 0x9ece6a, 0xe0af68, 0x7aa2f7, 0xbb9af7, 0x7dcfff, 0xa9b1d6,
              0x414868, 0xf7768e, 0x9ece6a, 0xe0af68, 0x7aa2f7, 0xbb9af7, 0x7dcfff, 0xc0caf5),
            T(@"Nord", 0x2e3440, 0xd8dee9, 0xd8dee9, 0x434c5e, NO,
              0x3b4252, 0xbf616a, 0xa3be8c, 0xebcb8b, 0x81a1c1, 0xb48ead, 0x88c0d0, 0xe5e9f0,
              0x4c566a, 0xbf616a, 0xa3be8c, 0xebcb8b, 0x81a1c1, 0xb48ead, 0x8fbcbb, 0xeceff4),
            T(@"Gruvbox", 0x282828, 0xebdbb2, 0xebdbb2, 0x504945, NO,
              0x282828, 0xcc241d, 0x98971a, 0xd79921, 0x458588, 0xb16286, 0x689d6a, 0xa89984,
              0x928374, 0xfb4934, 0xb8bb26, 0xfabd2f, 0x83a598, 0xd3869b, 0x8ec07c, 0xebdbb2),
            T(@"Solarized Dark", 0x002b36, 0x839496, 0x93a1a1, 0x073642, NO,
              0x073642, 0xdc322f, 0x859900, 0xb58900, 0x268bd2, 0xd33682, 0x2aa198, 0xeee8d5,
              0x002b36, 0xcb4b16, 0x586e75, 0x657b83, 0x839496, 0x6c71c4, 0x93a1a1, 0xfdf6e3),
            T(@"Monokai", 0x272822, 0xf8f8f2, 0xf8f8f0, 0x49483e, NO,
              0x272822, 0xf92672, 0xa6e22e, 0xf4bf75, 0x66d9ef, 0xae81ff, 0xa1efe4, 0xf8f8f2,
              0x75715e, 0xf92672, 0xa6e22e, 0xf4bf75, 0x66d9ef, 0xae81ff, 0xa1efe4, 0xf9f8f5),
            T(@"Solarized Light", 0xfdf6e3, 0x657b83, 0x586e75, 0xeee8d5, YES,
              0x073642, 0xdc322f, 0x859900, 0xb58900, 0x268bd2, 0xd33682, 0x2aa198, 0xeee8d5,
              0x002b36, 0xcb4b16, 0x586e75, 0x657b83, 0x839496, 0x6c71c4, 0x93a1a1, 0xfdf6e3),
            T(@"GitHub Light", 0xffffff, 0x24292f, 0x0969da, 0xb6d6ff, YES,
              0x24292f, 0xcf222e, 0x116329, 0x4d2d00, 0x0969da, 0x8250df, 0x1b7c83, 0x6e7781,
              0x57606a, 0xa40e26, 0x1a7f37, 0x633c01, 0x218bff, 0xa475f9, 0x3192aa, 0x8c959f),
        ];
#undef T
    });
    return all;
}

+ (TMTheme *)themeNamed:(NSString *)name {
    for (TMTheme *t in [self all]) if ([t.name isEqualToString:name]) return t;
    return [self all].firstObject;
}

- (NSDictionary *)xtermTheme {
    static NSArray *names;
    if (!names) names = @[@"black", @"red", @"green", @"yellow", @"blue", @"magenta", @"cyan", @"white",
                          @"brightBlack", @"brightRed", @"brightGreen", @"brightYellow", @"brightBlue", @"brightMagenta", @"brightCyan", @"brightWhite"];
    NSMutableDictionary *d = [@{@"background": TMHexString(_background), @"foreground": TMHexString(_foreground),
                                @"cursor": TMHexString(_cursor), @"cursorAccent": TMHexString(_background),
                                @"selectionBackground": TMHexString(_selection)} mutableCopy];
    for (int i = 0; i < 16; i++) d[names[i]] = TMHexString((uint32_t)[_ansi[i] unsignedIntValue]);
    return d;
}

@end

uint32_t TMMix(uint32_t a, uint32_t b, double t) {
    int ar = (a >> 16) & 255, ag = (a >> 8) & 255, ab = a & 255, br = (b >> 16) & 255, bg = (b >> 8) & 255, bb = b & 255;
    return ((uint32_t)(ar + (br - ar) * t) << 16) | ((uint32_t)(ag + (bg - ag) * t) << 8) | (uint32_t)(ab + (bb - ab) * t);
}

@implementation TMTheme (Chrome)
- (uint32_t)chromeBackground { return self.light ? TMMix(self.background, 0x000000, 0.06) : TMMix(self.background, 0x000000, 0.28); }
- (uint32_t)keyBarBackground { return self.light ? TMMix(self.background, 0x000000, 0.09) : TMMix(self.background, self.foreground, 0.10); }
- (uint32_t)accent { return self.cursor; }
- (uint32_t)lockColor { return (uint32_t)[self.ansi[self.light ? 3 : 11] unsignedIntValue]; }
@end
