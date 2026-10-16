#import "TMTerminalView.h"
#import "TMExtraKeysBar.h"
#import "TMSettings.h"
#import "TMThemes.h"
#import "TMKeys.h"
#import "TMBoxDrawing.h"
#import "TMEmu.h"
#import <CoreText/CoreText.h>
#import <objc/runtime.h>

@class TMGridView;
@interface TMGridView : UIView
@property (nonatomic, weak) TMTerminalView *owner;
@end

@interface TMTerminalView () <UIScrollViewDelegate, UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate, TMExtraKeysBarDelegate>
- (void)drawGridRect:(CGRect)rect context:(CGContextRef)ctx;
- (void)emuWrite:(const uint8_t *)d length:(size_t)n;
- (void)emuTitle:(const char *)t;
- (void)emuBell;
- (void)emuModes;
@end

@implementation TMGridView
- (void)drawRect:(CGRect)r { [self.owner drawGridRect:r context:UIGraphicsGetCurrentContext()]; }
@end

static void cbWrite(void *c, const uint8_t *d, size_t n) { [(__bridge TMTerminalView *)c emuWrite:d length:n]; }
static void cbTitle(void *c, const char *t) { [(__bridge TMTerminalView *)c emuTitle:t]; }
static void cbBell(void *c) { [(__bridge TMTerminalView *)c emuBell]; }
static void cbModes(void *c) { [(__bridge TMTerminalView *)c emuModes]; }

@implementation TMTerminalView {
    TMEmu *_emu;
    UIScrollView *_scroll;
    TMGridView *_grid;
    TMExtraKeysBar *_extraKeys;
    CTFontRef _fonts[4];                  // обычный, жирный, курсив, жирный курсив
    CTFontRef _baseFont;
    NSMutableDictionary<NSNumber *, id> *_fallback;
    CGFloat _cellW, _cellH, _ascent, _scale;
    CGFloat _padX, _padY;
    uint32_t _palette[256];
    uint32_t _defFg, _defBg, _cursorColor, _selColor;
    BOOL _ready, _focused, _cursorOn, _atBottom, _lightTheme;
    NSTimer *_blink;
    BOOL _hasSel; int _selR0, _selC0, _selR1, _selC1;     // выделение: начало и конец (абсолютные строки)
    int _selAnchorR, _selAnchorC;
    double _pinchBase;
    UIEditMenuInteraction *_menu;
    NSTimer *_repeat;
    UIImpactFeedbackGenerator *_haptic;
    NSString *_fontKey; double _fontSizeApplied;
    int _lastScrollback; CGFloat _panAcc;
}

@synthesize extraKeys = _extraKeys;

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _scale = [UIScreen mainScreen].scale; _padX = 6; _padY = 2;
        _fallback = [NSMutableDictionary dictionary];
        self.clipsToBounds = YES;
        _scroll = [UIScrollView new];
        _scroll.delegate = self; _scroll.alwaysBounceVertical = YES; _scroll.showsHorizontalScrollIndicator = NO;
        _scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite; _scroll.delaysContentTouches = NO; _scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeNone;
        [self addSubview:_scroll];
        _grid = [TMGridView new]; _grid.owner = self; _grid.opaque = YES; _grid.contentMode = UIViewContentModeRedraw; _grid.userInteractionEnabled = NO;
        [_scroll addSubview:_grid];
        _atBottom = YES; _cursorOn = YES;

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
        tap.delegate = self; [_scroll addGestureRecognizer:tap];
        UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapped:)];
        dbl.numberOfTapsRequired = 2; dbl.delegate = self; [_scroll addGestureRecognizer:dbl]; [tap requireGestureRecognizerToFail:dbl];
        UITapGestureRecognizer *tri = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tripleTapped:)];
        tri.numberOfTapsRequired = 3; tri.delegate = self; [_scroll addGestureRecognizer:tri]; [dbl requireGestureRecognizerToFail:tri];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
        lp.minimumPressDuration = 0.35; lp.delegate = self; [_scroll addGestureRecognizer:lp];
        UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinched:)];
        pinch.delegate = self; [_scroll addGestureRecognizer:pinch];
        _menu = [[UIEditMenuInteraction alloc] initWithDelegate:self];
        [self addInteraction:_menu];
        _haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];

        _extraKeys = [[TMExtraKeysBar alloc] initWithFrame:CGRectMake(0, 0, 320, 46)];
        _extraKeys.delegate = self;
        self.inputAssistantItem.leadingBarButtonGroups = @[];
        self.inputAssistantItem.trailingBarButtonGroups = @[];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(focusChanged) name:UIKeyboardDidShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(focusChanged) name:UIKeyboardDidHideNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appActive) name:UIApplicationDidBecomeActiveNotification object:nil];
        _blink = [NSTimer scheduledTimerWithTimeInterval:0.55 target:self selector:@selector(blinkTick) userInfo:nil repeats:YES];
        [self applySettings];
    }
    return self;
}

- (void)dealloc {
    [_blink invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_emu) tm_emu_free(_emu);
    for (int i = 0; i < 4; i++) if (_fonts[i]) CFRelease(_fonts[i]);
}

- (BOOL)ready { return _ready; }
- (int)cols { return _emu ? tm_emu_cols(_emu) : 80; }
- (int)rows { return _emu ? tm_emu_rows(_emu) : 24; }

#pragma mark - Шрифты и цвета

static CTFontRef makeFont(NSString *family, double size, BOOL bold, BOOL italic) {
    NSString *ps = nil;
    if ([family isEqualToString:@"JetBrains Mono"]) ps = bold ? (italic ? @"JetBrainsMono-BoldItalic" : @"JetBrainsMono-Bold") : (italic ? @"JetBrainsMono-Italic" : @"JetBrainsMono-Regular");
    else if ([family isEqualToString:@"Menlo"]) ps = bold ? (italic ? @"Menlo-BoldItalic" : @"Menlo-Bold") : (italic ? @"Menlo-Italic" : @"Menlo-Regular");
    if (ps) { CTFontRef f = CTFontCreateWithName((__bridge CFStringRef)ps, size, NULL); if (f) return f; }
    UIFont *u = [UIFont monospacedSystemFontOfSize:size weight:bold ? UIFontWeightBold : UIFontWeightRegular];
    CTFontRef f = (CTFontRef)CFBridgingRetain(u);
    if (italic) { CTFontRef it = CTFontCreateCopyWithSymbolicTraits(f, size, NULL, kCTFontItalicTrait, kCTFontItalicTrait); if (it) { CFRelease(f); f = it; } }
    return f;
}

- (void)rebuildFonts {
    TMSettings *s = [TMSettings shared];
    for (int i = 0; i < 4; i++) if (_fonts[i]) { CFRelease(_fonts[i]); _fonts[i] = NULL; }
    for (int i = 0; i < 4; i++) _fonts[i] = makeFont(s.fontFamily, s.fontSize, i & 1, i & 2);
    [_fallback removeAllObjects];
    CTFontRef f = _fonts[0];
    UniChar m = 'M'; CGGlyph g; CGSize adv;
    CTFontGetGlyphsForCharacters(f, &m, &g, 1); CTFontGetAdvancesForGlyphs(f, kCTFontOrientationHorizontal, &g, &adv, 1);
    _cellW = MAX(1, round(adv.width * _scale) / _scale);
    CGFloat asc = CTFontGetAscent(f), desc = CTFontGetDescent(f), lead = CTFontGetLeading(f);
    _cellH = ceil((asc + desc + lead) * _scale) / _scale;
    _ascent = asc + (_cellH - (asc + desc)) / 2;   // базовая линия с центровкой по высоте строки
    _fontKey = s.fontFamily; _fontSizeApplied = s.fontSize;
}

static uint32_t rgbMix(uint32_t a, uint32_t b, double t) {   // a*(1-t) + b*t
    int ar = (a >> 16) & 255, ag = (a >> 8) & 255, ab = a & 255, br = (b >> 16) & 255, bg = (b >> 8) & 255, bb = b & 255;
    return ((uint32_t)(ar + (br - ar) * t) << 16) | ((uint32_t)(ag + (bg - ag) * t) << 8) | (uint32_t)(ab + (bb - ab) * t);
}

- (void)rebuildPalette:(TMTheme *)t {
    for (int i = 0; i < 16; i++) _palette[i] = (uint32_t)[t.ansi[i] unsignedIntValue];
    static const int lv[6] = {0, 95, 135, 175, 215, 255};
    for (int i = 0; i < 216; i++) _palette[16 + i] = ((uint32_t)lv[(i / 36) % 6] << 16) | ((uint32_t)lv[(i / 6) % 6] << 8) | (uint32_t)lv[i % 6];
    for (int i = 0; i < 24; i++) { uint32_t v = (uint32_t)(8 + i * 10); _palette[232 + i] = (v << 16) | (v << 8) | v; }
    _defFg = t.foreground; _defBg = t.background; _cursorColor = t.cursor; _selColor = t.selection; _lightTheme = t.light;
}

- (void)applySettings {
    TMSettings *s = [TMSettings shared];
    TMTheme *t = [TMTheme themeNamed:s.themeName];
    [self rebuildPalette:t];
    TMLog(@"applySettings themeName=%@ theme=%@ bg=%06x fg=%06x font=%@ %g count=%d", s.themeName, t.name, t.background, t.foreground, s.fontFamily, s.fontSize, (int)[TMTheme all].count);
    self.backgroundColor = TMHex(t.background);
    _scroll.backgroundColor = TMHex(t.background); _grid.backgroundColor = TMHex(t.background);
    _scroll.indicatorStyle = t.light ? UIScrollViewIndicatorStyleBlack : UIScrollViewIndicatorStyleWhite;
    [_extraKeys applyBackground:TMHex(t.keyBarBackground) foreground:TMHex(t.foreground) accent:TMHex(t.accent) lock:TMHex(t.lockColor)];
    if (self.isFirstResponder) [self reloadInputViews];
    if (_emu) { tm_emu_set_default_colors(_emu, t.foreground, t.background); tm_emu_set_scrollback(_emu, (int)s.scrollback); }
    BOOL fontChanged = ![_fontKey isEqualToString:s.fontFamily] || _fontSizeApplied != s.fontSize || !_fonts[0];
    if (fontChanged) { [self rebuildFonts]; [self setNeedsLayout]; }
    [self restartBlink];
    [_grid setNeedsDisplay];
}

#pragma mark - Раскладка и размер

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_fonts[0]) [self rebuildFonts];
    CGSize sz = self.bounds.size;
    if (sz.width < 10 || sz.height < 10) return;
    _scroll.frame = self.bounds;
    int cols = MAX(2, (int)floor((sz.width - 2 * _padX) / _cellW)), rows = MAX(1, (int)floor((sz.height - 2 * _padY) / _cellH));
    BOOL firstTime = !_emu;
    if (!_emu) {
        TMEmuCallbacks cb = {(__bridge void *)self, cbWrite, cbTitle, cbBell, cbModes, NULL, NULL};
        _emu = tm_emu_new(cols, rows, (int)[TMSettings shared].scrollback, cb);
        TMTheme *t = [TMTheme themeNamed:[TMSettings shared].themeName]; tm_emu_set_default_colors(_emu, t.foreground, t.background);
    } else if (cols != tm_emu_cols(_emu) || rows != tm_emu_rows(_emu)) {
        tm_emu_resize(_emu, cols, rows);
        [self.delegate terminalView:self resizedToCols:cols rows:rows];
    }
    [self updateScrollGeometry];
    if (firstTime) { TMLog(@"first layout %.0fx%.0f cols=%d rows=%d cell=%.2fx%.2f", sz.width, sz.height, cols, rows, _cellW, _cellH); _ready = YES; [self.delegate terminalViewReady:self]; }
}

- (void)updateScrollGeometry {
    if (!_emu) return;
    CGSize b = self.bounds.size;
    int total = tm_emu_total_lines(_emu);
    CGFloat h = MAX(b.height, total * _cellH + 2 * _padY);
    BOOL alt = tm_emu_alt_screen(_emu);
    _scroll.scrollEnabled = !alt;
    _scroll.contentSize = CGSizeMake(b.width, h);
    if (_atBottom || alt) _scroll.contentOffset = CGPointMake(0, MAX(0, h - b.height));
    _grid.frame = CGRectMake(0, _scroll.contentOffset.y, b.width, b.height);
    [_grid setNeedsDisplay];
}

- (void)scrollViewDidScroll:(UIScrollView *)s {
    CGFloat maxY = MAX(0, s.contentSize.height - s.bounds.size.height);
    _atBottom = s.contentOffset.y >= maxY - 2;
    _grid.frame = CGRectMake(0, s.contentOffset.y, s.bounds.size.width, s.bounds.size.height);
    [_grid setNeedsDisplay];
}

#pragma mark - Вывод

- (void)writeOutput:(NSData *)data {
    if (!_emu || !data.length) return;
    tm_emu_feed(_emu, data.bytes, data.length);
    _cursorOn = YES;
    int first, last; bool all;
    BOOL any = tm_emu_take_dirty(_emu, &first, &last, &all);
    int sb = tm_emu_scrollback_count(_emu);
    BOOL grew = sb != _lastScrollback || tm_emu_alt_screen(_emu);
    _lastScrollback = sb;
    if (grew || all) [self updateScrollGeometry];
    if (any && !all && !grew) {
        CGFloat off = _scroll.contentOffset.y;
        CGRect r = CGRectMake(0, _padY + (sb + first) * _cellH - off, self.bounds.size.width, (last - first + 1) * _cellH);
        [_grid setNeedsDisplayInRect:CGRectInset(r, 0, -1)];
    } else if (any) [_grid setNeedsDisplay];
    if (_hasSel && !_scroll.isDragging) { /* выделение остаётся: координаты абсолютные */ }
}

#pragma mark - Цвета ячейки

- (uint32_t)rgbFor:(TMColor)c fallback:(uint32_t)def bold:(BOOL)bold {
    if (tm_color_is_indexed(c)) { uint32_t i = c & 255; if (bold && i < 8) i += 8; return _palette[i]; }
    if (tm_color_is_rgb(c)) return c & 0xffffff;
    return def;
}

typedef struct { CGGlyph glyphs[256]; CGPoint pos[256]; int n; CTFontRef font; uint32_t color; BOOL have; } GlyphBatch;
static inline CGColorRef cgColor(uint32_t rgb, CGColorSpaceRef cs);
static void flushBatch(CGContextRef ctx, CGColorSpaceRef cs, GlyphBatch *b) {
    if (b->n > 0 && b->font) {
        CGColorRef col = cgColor(b->color, cs); CGContextSetFillColorWithColor(ctx, col); CGColorRelease(col);
        // контекст UIKit перевёрнут по вертикали (y вниз) — для Core Text переворачиваем его обратно
        CGContextSaveGState(ctx);
        CGContextConcatCTM(ctx, CGAffineTransformMake(1, 0, 0, -1, 0, 0));
        CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
        for (int i = 0; i < b->n; i++) b->pos[i].y = -b->pos[i].y;
        CTFontDrawGlyphs(b->font, b->glyphs, b->pos, (size_t)b->n, ctx);
        CGContextRestoreGState(ctx);
    }
    b->n = 0;
}
static inline CGColorRef cgColor(uint32_t rgb, CGColorSpaceRef cs) {
    CGFloat comp[4] = {((rgb >> 16) & 255) / 255.0, ((rgb >> 8) & 255) / 255.0, (rgb & 255) / 255.0, 1};
    return CGColorCreate(cs, comp);
}

#pragma mark - Отрисовка

- (CTFontRef)fallbackFontFor:(uint32_t)cp base:(CTFontRef)base {
    id cached = _fallback[@(cp)];
    if (cached) return cached == [NSNull null] ? NULL : (__bridge CTFontRef)cached;
    UniChar u[2]; CFIndex n = 1;
    if (cp > 0xffff) { cp -= 0x10000; u[0] = (UniChar)(0xd800 + (cp >> 10)); u[1] = (UniChar)(0xdc00 + (cp & 0x3ff)); n = 2; cp += 0x10000; } else u[0] = (UniChar)cp;
    CFStringRef str = CFStringCreateWithCharacters(NULL, u, n);
    CTFontRef f = CTFontCreateForString(base, str, CFRangeMake(0, n));
    CFRelease(str);
    _fallback[@(cp)] = f ? (id)CFBridgingRelease(f) : (id)[NSNull null];
    return f;
}

- (void)drawGridRect:(CGRect)dirty context:(CGContextRef)ctx {
    if (!_emu || !_fonts[0]) return;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    BOOL reverse = tm_emu_reverse_video(_emu);
    uint32_t defFg = reverse ? _defBg : _defFg, defBg = reverse ? _defFg : _defBg;
    CGColorRef bgc = cgColor(_defBg, cs);
    CGContextSetFillColorWithColor(ctx, bgc); CGContextFillRect(ctx, dirty); CGColorRelease(bgc);
    CGFloat off = _scroll.contentOffset.y;
    int total = tm_emu_total_lines(_emu), cols = tm_emu_cols(_emu), sb = tm_emu_scrollback_count(_emu);
    TMLog(@"draw rect=%@ off=%.1f total=%d cell=%.1fx%.1f", NSStringFromCGRect(dirty), off, total, _cellW, _cellH);
    int first = MAX(0, (int)floor((off + dirty.origin.y - _padY) / _cellH)), last = MIN(total - 1, (int)floor((off + CGRectGetMaxY(dirty) - _padY) / _cellH));
    int curRow = sb + tm_emu_cursor_y(_emu), curCol = tm_emu_cursor_x(_emu);
    BOOL curVisible = tm_emu_cursor_visible(_emu);
    int style = tm_emu_cursor_style(_emu);
    TMCursorStyle cs0 = [TMSettings shared].cursorStyle;
    int shape = style == 0 ? (int)cs0 : (style <= 2 ? 0 : style <= 4 ? 2 : 1);   // 0 блок, 1 линия, 2 подчёркивание
    BOOL blink = style == 0 ? [TMSettings shared].cursorBlink : tm_emu_cursor_blink(_emu);
    BOOL showCursor = curVisible && _focused && (!blink || _cursorOn);
    BOOL blockHere = NO;
    CTFontRef base = _fonts[0];
    GlyphBatch B; B.n = 0; B.font = NULL; B.color = 0; B.have = NO;

    for (int r = first; r <= last; r++) {
        bool wrapped; const TMCell *cells = tm_emu_line(_emu, r, &wrapped);
        CGFloat y = _padY + r * _cellH - off;
        // 1. фон
        for (int c = 0; c < cols;) {
            TMCell cell = cells[c];
            BOOL isCursor = showCursor && r == curRow && c == curCol && shape == 0;
            uint32_t fg, bg;
            fg = [self rgbFor:cell.fg fallback:defFg bold:(cell.attr & TM_BOLD) != 0]; bg = [self rgbFor:cell.bg fallback:defBg bold:NO];
            if (cell.attr & TM_INVERSE) { uint32_t t = fg; fg = bg; bg = t; }
            if (isCursor) bg = _cursorColor;
            BOOL sel = _hasSel && [self isSelectedRow:r col:c];
            if (sel) bg = _selColor;
            int run = 1;
            while (c + run < cols) {
                TMCell n = cells[c + run];
                BOOL nCursor = showCursor && r == curRow && c + run == curCol && shape == 0;
                if (nCursor != isCursor) break;
                uint32_t nbg = [self rgbFor:n.bg fallback:defBg bold:NO];
                if (n.attr & TM_INVERSE) nbg = [self rgbFor:n.fg fallback:defFg bold:(n.attr & TM_BOLD) != 0];
                BOOL nsel = _hasSel && [self isSelectedRow:r col:c + run];
                if (nsel) nbg = _selColor; if (nCursor) nbg = _cursorColor;
                if (nbg != bg || nsel != sel) break;
                run++;
            }
            if (bg != _defBg || reverse) {
                CGColorRef col = cgColor(bg, cs); CGContextSetFillColorWithColor(ctx, col); CGColorRelease(col);
                CGContextFillRect(ctx, CGRectMake(_padX + c * _cellW, y, run * _cellW, _cellH));
            }
            c += run;
        }
        // 2. текст
        CGContextSaveGState(ctx);
        for (int c = 0; c < cols; c++) {
            TMCell cell = cells[c];
            if (cell.attr & TM_WIDE_CONT) continue;
            BOOL isCursor = showCursor && r == curRow && c == curCol && shape == 0;
            uint32_t fg = [self rgbFor:cell.fg fallback:defFg bold:(cell.attr & TM_BOLD) != 0], bg = [self rgbFor:cell.bg fallback:defBg bold:NO];
            if (cell.attr & TM_INVERSE) { uint32_t t = fg; fg = bg; bg = t; }
            if (isCursor) { fg = _defBg; blockHere = YES; }
            else if (_hasSel && [self isSelectedRow:r col:c]) { fg = _lightTheme ? 0x000000 : (cell.attr & TM_INVERSE ? bg : fg); }
            if (cell.attr & TM_DIM) fg = rgbMix(fg, bg, 0.5);
            if (cell.attr & TM_INVISIBLE) continue;
            CGFloat x = _padX + c * _cellW;
            // линии: подчёркивание и зачёркивание
            if (cell.attr & (TM_UNDERLINE | TM_STRIKE)) {
                flushBatch(ctx, cs, &B);
                CGColorRef col = cgColor(fg, cs); CGContextSetFillColorWithColor(ctx, col); CGColorRelease(col);
                CGFloat w = ((cell.attr & TM_WIDE) ? 2 : 1) * _cellW, th = 1.0 / _scale * (_scale >= 3 ? 1.5 : 1);
                if (cell.attr & TM_UNDERLINE) {
                    CGContextFillRect(ctx, CGRectMake(x, y + _ascent + 1.5, w, th));
                    if (cell.attr & TM_DOUBLE_UL) CGContextFillRect(ctx, CGRectMake(x, y + _ascent + 3.5, w, th));
                }
                if (cell.attr & TM_STRIKE) CGContextFillRect(ctx, CGRectMake(x, y + _cellH * 0.5, w, th));
            }
            uint32_t ch = cell.ch;
            if (ch == 0 || ch == ' ') continue;
            // псевдографика — прямоугольниками
            if ((ch >= 0x2500 && ch <= 0x259f) || (ch >= 0xe0b0 && ch <= 0xe0b3)) {
                flushBatch(ctx, cs, &B);
                CGColorRef col = cgColor(fg, cs);
                BOOL ok = TMDrawBoxChar(ctx, ch, CGRectMake(x, y, _cellW * ((cell.attr & TM_WIDE) ? 2 : 1), _cellH), _scale, col);
                CGColorRelease(col);
                if (ok) continue;
            }
            int variant = ((cell.attr & TM_BOLD) ? 1 : 0) | ((cell.attr & TM_ITALIC) ? 2 : 0);
            CTFontRef font = _fonts[variant];
            UniChar u[2]; CFIndex nu = 1; uint32_t cp = ch;
            if (cp > 0xffff) { cp -= 0x10000; u[0] = (UniChar)(0xd800 + (cp >> 10)); u[1] = (UniChar)(0xdc00 + (cp & 0x3ff)); nu = 2; } else u[0] = (UniChar)cp;
            CGGlyph g[2] = {0, 0};
            if (!CTFontGetGlyphsForCharacters(font, u, g, nu) || g[0] == 0) {
                CTFontRef fb = [self fallbackFontFor:ch base:base];
                if (!fb) continue;
                CTFontGetGlyphsForCharacters(fb, u, g, nu);
                if (g[0] == 0) continue;
                font = fb;
            }
            if (font != B.font || !B.have || B.color != fg || B.n >= 255) { flushBatch(ctx, cs, &B); B.font = font; B.color = fg; B.have = YES; }
            B.glyphs[B.n] = g[0]; B.pos[B.n] = CGPointMake(x, y + _ascent); B.n++;
            // CTFontDrawGlyphs использует систему координат CoreGraphics; переворачиваем для текущей позиции
        }
        flushBatch(ctx, cs, &B);
        CGContextRestoreGState(ctx);
    }
    // курсор-линия/подчёркивание и контур при потере фокуса
    if (curVisible && curRow >= first && curRow <= last) {
        CGFloat x = _padX + curCol * _cellW, y = _padY + curRow * _cellH - off;
        CGColorRef col = cgColor(_cursorColor, cs); CGContextSetFillColorWithColor(ctx, col); CGContextSetStrokeColorWithColor(ctx, col); CGColorRelease(col);
        if (!_focused) { CGContextSetLineWidth(ctx, 1); CGContextStrokeRect(ctx, CGRectMake(x + 0.5, y + 0.5, _cellW - 1, _cellH - 1)); }
        else if (showCursor && shape == 1) CGContextFillRect(ctx, CGRectMake(x, y, 2, _cellH));
        else if (showCursor && shape == 2) CGContextFillRect(ctx, CGRectMake(x, y + _cellH - 2, _cellW, 2));
    }
    (void)blockHere;
    CGColorSpaceRelease(cs);
}

- (BOOL)isSelectedRow:(int)r col:(int)c {
    int r0 = _selR0, c0 = _selC0, r1 = _selR1, c1 = _selC1;
    if (r0 > r1 || (r0 == r1 && c0 > c1)) { int t = r0; r0 = r1; r1 = t; t = c0; c0 = c1; c1 = t; }
    if (r < r0 || r > r1) return NO;
    if (r == r0 && c < c0) return NO;
    if (r == r1 && c > c1) return NO;
    return YES;
}

#pragma mark - Курсор

- (void)focusChanged { BOOL f = [self isFirstResponder]; if (f != _focused) { _focused = f; [self restartBlink]; [_grid setNeedsDisplay]; } }
- (void)appActive { [self focusChanged]; }
- (void)restartBlink { _cursorOn = YES; [self invalidateCursorRow]; }
- (void)blinkTick {
    if (!_emu || !_focused) return;
    _cursorOn = !_cursorOn;
    [self invalidateCursorRow];
}
- (void)invalidateCursorRow {
    if (!_emu) return;
    CGFloat y = _padY + (tm_emu_scrollback_count(_emu) + tm_emu_cursor_y(_emu)) * _cellH - _scroll.contentOffset.y;
    [_grid setNeedsDisplayInRect:CGRectMake(0, y - 1, self.bounds.size.width, _cellH + 2)];
}
- (BOOL)becomeFirstResponder { BOOL r = [super becomeFirstResponder]; if (r) { _focused = YES; [self restartBlink]; [_grid setNeedsDisplay]; if (_emu && tm_emu_focus_events(_emu)) [self sendRaw:"\x1b[I" length:3]; } return r; }
- (BOOL)resignFirstResponder { BOOL r = [super resignFirstResponder]; if (r) { _focused = NO; [_grid setNeedsDisplay]; if (_emu && tm_emu_focus_events(_emu)) [self sendRaw:"\x1b[O" length:3]; } return r; }

#pragma mark - Эмулятор → приложение

- (void)emuWrite:(const uint8_t *)d length:(size_t)n { [self.delegate terminalView:self sendData:[NSData dataWithBytes:d length:n]]; }
- (void)emuTitle:(const char *)t { [self.delegate terminalView:self titleChanged:[NSString stringWithUTF8String:t] ?: @""]; }
- (void)emuBell { if ([TMSettings shared].hapticBell) [_haptic impactOccurred]; }
- (void)emuModes { dispatch_async(dispatch_get_main_queue(), ^{ [self updateScrollGeometry]; }); }

#pragma mark - Ввод

- (BOOL)canBecomeFirstResponder { return YES; }
- (UIView *)inputAccessoryView { return _extraKeys; }
- (UITextAutocapitalizationType)autocapitalizationType { return UITextAutocapitalizationTypeNone; }
- (UITextAutocorrectionType)autocorrectionType { return UITextAutocorrectionTypeNo; }
- (UITextSpellCheckingType)spellCheckingType { return UITextSpellCheckingTypeNo; }
- (UITextSmartQuotesType)smartQuotesType { return UITextSmartQuotesTypeNo; }
- (UITextSmartDashesType)smartDashesType { return UITextSmartDashesTypeNo; }
- (UITextSmartInsertDeleteType)smartInsertDeleteType { return UITextSmartInsertDeleteTypeNo; }
- (UIKeyboardType)keyboardType { return UIKeyboardTypeDefault; }
- (UIKeyboardAppearance)keyboardAppearance { return _lightTheme ? UIKeyboardAppearanceLight : UIKeyboardAppearanceDark; }
- (BOOL)hasText { return YES; }

- (void)send:(NSData *)d {
    if (!d.length) return;
    if (!_atBottom) { _atBottom = YES; [self updateScrollGeometry]; }
    if (_hasSel) { _hasSel = NO; [_grid setNeedsDisplay]; }
    _cursorOn = YES;
    [self.delegate terminalView:self sendData:d];
}
- (void)sendRaw:(const char *)s length:(size_t)n { [self.delegate terminalView:self sendData:[NSData dataWithBytes:s length:n]]; }

- (void)sendString:(NSString *)text {
    if (!text.length) return;
    NSString *t = [text stringByReplacingOccurrencesOfString:@"\n" withString:@"\r"];
    TMExtraKeysBar *bar = _extraKeys;
    NSData *ctrl = bar.ctrl != TMModOff ? TMControlForCharacter(t) : nil;
    if (ctrl) { [self send:bar.alt != TMModOff ? [self prefixEsc:ctrl] : ctrl]; [bar consumeModifiers]; return; }
    NSData *d = [t dataUsingEncoding:NSUTF8StringEncoding];
    if (bar.alt != TMModOff) d = [self prefixEsc:d];
    [self send:d];
    [bar consumeModifiers];
}
- (NSData *)prefixEsc:(NSData *)d { NSMutableData *m = [NSMutableData dataWithBytes:"\e" length:1]; [m appendData:d]; return m; }
- (void)insertText:(NSString *)text { [self sendString:text]; }
- (void)deleteBackward { uint8_t b = 0x7f; [self send:[NSData dataWithBytes:&b length:1]]; }

- (void)sendKey:(UIKeyboardHIDUsage)usage modifiers:(UIKeyModifierFlags)mods {
    TMExtraKeysBar *bar = _extraKeys;
    if (bar.ctrl != TMModOff) mods |= UIKeyModifierControl;
    if (bar.alt != TMModOff) mods |= UIKeyModifierAlternate;
    NSData *d = TMSequenceForKey(usage, mods, _emu && tm_emu_app_cursor(_emu));
    if (d) { [self send:d]; [bar consumeModifiers]; }
}

- (void)pasteFromPasteboard {
    NSString *s = [UIPasteboard generalPasteboard].string;
    if (!s.length) return;
    s = [s stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\r"];
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@"\r"];
    BOOL br = _emu && tm_emu_bracketed_paste(_emu);
    NSMutableData *d = [NSMutableData data];
    if (br) [d appendData:[@"\e[200~" dataUsingEncoding:NSUTF8StringEncoding]];
    [d appendData:[s dataUsingEncoding:NSUTF8StringEncoding]];
    if (br) [d appendData:[@"\e[201~" dataUsingEncoding:NSUTF8StringEncoding]];
    [self send:d];
}

- (NSString *)selectedText {
    if (!_hasSel || !_emu) return nil;
    int r0 = _selR0, c0 = _selC0, r1 = _selR1, c1 = _selC1;
    if (r0 > r1 || (r0 == r1 && c0 > c1)) { int t = r0; r0 = r1; r1 = t; t = c0; c0 = c1; c1 = t; }
    char *t = tm_emu_text(_emu, r0, c0, r1, c1);
    NSString *s = [NSString stringWithUTF8String:t]; free(t);
    return s;
}
- (void)copySelection {
    NSString *s = [self selectedText];
    if (s.length) [UIPasteboard generalPasteboard].string = s;
    _hasSel = NO; [_grid setNeedsDisplay];
}
- (void)clearScreen {
    uint8_t c = 0x0c; [self send:[NSData dataWithBytes:&c length:1]];
    if (_emu) { [self writeOutput:[@"\e[3J" dataUsingEncoding:NSUTF8StringEncoding]]; }
}
- (void)showKeyboard { [self becomeFirstResponder]; }
- (void)hideKeyboard { [self resignFirstResponder]; }

- (NSString *)visibleText {
    if (!_emu) return @"";
    int sb = tm_emu_scrollback_count(_emu);
    char *t = tm_emu_text(_emu, sb, 0, sb + tm_emu_rows(_emu) - 1, tm_emu_cols(_emu) - 1);
    NSString *s = [NSString stringWithUTF8String:t]; free(t); return s;
}

// Поиск по истории и экрану: выделяет найденное и прокручивает к нему
- (BOOL)findText:(NSString *)q forward:(BOOL)fwd {
    if (!_emu || !q.length) return NO;
    int total = tm_emu_total_lines(_emu), cols = tm_emu_cols(_emu);
    int start = _hasSel ? (fwd ? MAX(_selR0, _selR1) : MIN(_selR0, _selR1)) : (fwd ? 0 : total - 1);
    for (int k = 0; k < total; k++) {
        int r = fwd ? (start + k) % total : ((start - k) % total + total) % total;
        char *t = tm_emu_text(_emu, r, 0, r, cols - 1);
        NSString *line = [NSString stringWithUTF8String:t]; free(t);
        NSRange rg = [line rangeOfString:q options:NSCaseInsensitiveSearch];
        if (rg.location != NSNotFound) {
            _hasSel = YES; _selR0 = _selR1 = r; _selC0 = (int)rg.location; _selC1 = (int)(rg.location + rg.length) - 1;
            CGFloat y = _padY + r * _cellH - self.bounds.size.height / 2;
            [_scroll setContentOffset:CGPointMake(0, MAX(0, MIN(y, _scroll.contentSize.height - self.bounds.size.height))) animated:YES];
            [_grid setNeedsDisplay]; return YES;
        }
    }
    return NO;
}

// Аппаратная клавиатура: стрелки, F-клавиши, Ctrl/Alt-комбинации; остальное — через insertText
- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    NSMutableSet *rest = [NSMutableSet set];
    for (UIPress *p in presses) {
        UIKey *k = p.key;
        if (!k) { [rest addObject:p]; continue; }
        UIKeyModifierFlags mods = k.modifierFlags & (UIKeyModifierShift | UIKeyModifierAlternate | UIKeyModifierControl);
        if (k.modifierFlags & UIKeyModifierCommand) { [rest addObject:p]; continue; }
        NSData *seq = TMSequenceForKey(k.keyCode, mods, _emu && tm_emu_app_cursor(_emu));
        if (!seq && (mods & UIKeyModifierControl)) seq = TMControlForCharacter(k.charactersIgnoringModifiers);
        if (!seq && (mods & UIKeyModifierAlternate) && k.charactersIgnoringModifiers.length == 1 && k.keyCode >= UIKeyboardHIDUsageKeyboardA && k.keyCode <= UIKeyboardHIDUsageKeyboardSlash)
            seq = [self prefixEsc:[k.charactersIgnoringModifiers dataUsingEncoding:NSUTF8StringEncoding]];
        if (!seq && k.keyCode == UIKeyboardHIDUsageKeyboardReturnOrEnter) seq = [NSData dataWithBytes:"\r" length:1];
        if (seq) {
            [self send:seq];
            BOOL arrow = k.keyCode >= UIKeyboardHIDUsageKeyboardRightArrow && k.keyCode <= UIKeyboardHIDUsageKeyboardUpArrow;
            if (arrow || k.keyCode == UIKeyboardHIDUsageKeyboardDeleteOrBackspace) [self startRepeat:seq];
        } else [rest addObject:p];
    }
    if (rest.count) [super pressesBegan:rest withEvent:event];
}
- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event { [self stopRepeat]; [super pressesEnded:presses withEvent:event]; }
- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event { [self stopRepeat]; [super pressesCancelled:presses withEvent:event]; }
- (void)startRepeat:(NSData *)seq {
    [self stopRepeat];
    __weak TMTerminalView *ws = self;
    _repeat = [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:NO block:^(NSTimer *t) { [ws beginRepeating:seq]; }];
}
- (void)beginRepeating:(NSData *)seq {
    __weak TMTerminalView *ws = self;
    _repeat = [NSTimer scheduledTimerWithTimeInterval:0.04 repeats:YES block:^(NSTimer *t) { [ws send:seq]; }];
}
- (void)stopRepeat { [_repeat invalidate]; _repeat = nil; }

#pragma mark - Панель клавиш

- (void)extraKeysBar:(TMExtraKeysBar *)bar sendText:(NSString *)text { [self sendString:text]; }
- (void)extraKeysBar:(TMExtraKeysBar *)bar sendKey:(UIKeyboardHIDUsage)usage { [self sendKey:usage modifiers:0]; }
- (void)extraKeysBarPaste:(TMExtraKeysBar *)bar { [self pasteFromPasteboard]; }
- (void)extraKeysBarHideKeyboard:(TMExtraKeysBar *)bar { [self hideKeyboard]; }

#pragma mark - Жесты и мышь

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }

- (BOOL)cellAt:(CGPoint)p row:(int *)row col:(int *)col {
    if (!_emu) return NO;
    int c = (int)floor((p.x - _padX) / _cellW), r = (int)floor((p.y + _scroll.contentOffset.y - _padY) / _cellH);
    int total = tm_emu_total_lines(_emu);
    *col = MAX(0, MIN(tm_emu_cols(_emu) - 1, c)); *row = MAX(0, MIN(total - 1, r));
    return YES;
}

// Мышь приложению: только на экране (не в истории)
- (BOOL)sendMouse:(int)button at:(CGPoint)p release:(BOOL)rel motion:(BOOL)motion {
    if (!_emu || tm_emu_mouse_mode(_emu) == TM_MOUSE_NONE) return NO;
    int r, c; [self cellAt:CGPointMake(p.x, p.y) row:&r col:&c];
    int sbn = tm_emu_scrollback_count(_emu); int sr = r - sbn; if (sr < 0) return NO;
    uint8_t buf[48]; size_t n = tm_emu_encode_mouse(_emu, button, c, sr, 0, motion, rel, buf, sizeof buf);
    if (n) { [self.delegate terminalView:self sendData:[NSData dataWithBytes:buf length:n]]; return YES; }
    return YES;
}

- (void)tapped:(UITapGestureRecognizer *)g {
    if (_hasSel) { _hasSel = NO; [_grid setNeedsDisplay]; }
    [self becomeFirstResponder];
    CGPoint p = [g locationInView:self];
    if (_emu && tm_emu_mouse_mode(_emu) != TM_MOUSE_NONE) { [self sendMouse:0 at:p release:NO motion:NO]; [self sendMouse:0 at:p release:YES motion:NO]; }
}
- (void)selectWordAtPoint:(CGPoint)p {
    int r, c; if (![self cellAt:p row:&r col:&c]) return;
    bool w; const TMCell *cells = tm_emu_line(_emu, r, &w); int cols = tm_emu_cols(_emu);
    BOOL (^isWord)(int) = ^BOOL(int i) { uint32_t ch = cells[i].ch; return ch != 0 && ch != ' ' && !(ch == '"' || ch == '\'' || ch == '(' || ch == ')' || ch == '<' || ch == '>' || ch == ',' || ch == ';' || ch == '[' || ch == ']' || ch == '{' || ch == '}' || ch == '|'); };
    int a = c, b = c;
    if (isWord(c)) { while (a > 0 && isWord(a - 1)) a--; while (b < cols - 1 && isWord(b + 1)) b++; }
    _hasSel = YES; _selR0 = _selR1 = _selAnchorR = r; _selC0 = _selAnchorC = a; _selC1 = b;
    [_grid setNeedsDisplay];
}
- (void)doubleTapped:(UITapGestureRecognizer *)g { [self becomeFirstResponder]; [self selectWordAtPoint:[g locationInView:self]]; [self showEditMenuAt:[g locationInView:self]]; }
- (void)tripleTapped:(UITapGestureRecognizer *)g {
    int r, c; if (![self cellAt:[g locationInView:self] row:&r col:&c]) return;
    _hasSel = YES; _selR0 = _selR1 = r; _selC0 = 0; _selC1 = tm_emu_cols(_emu) - 1; [_grid setNeedsDisplay];
    [self showEditMenuAt:[g locationInView:self]];
}
- (void)longPressed:(UILongPressGestureRecognizer *)g {
    CGPoint p = [g locationInView:self];
    if (g.state == UIGestureRecognizerStateBegan) { [_haptic impactOccurred]; [self selectWordAtPoint:p]; }
    else if (g.state == UIGestureRecognizerStateChanged) {
        int r, c; if (![self cellAt:p row:&r col:&c]) return;
        BOOL fwd = r > _selAnchorR || (r == _selAnchorR && c >= _selAnchorC);
        if (fwd) { _selR0 = _selAnchorR; _selC0 = _selAnchorC; _selR1 = r; _selC1 = c; } else { _selR0 = r; _selC0 = c; _selR1 = _selAnchorR; _selC1 = _selAnchorC; }
        [_grid setNeedsDisplay];
    } else if (g.state == UIGestureRecognizerStateEnded) [self showEditMenuAt:p];
}
- (void)showEditMenuAt:(CGPoint)p {
    UIEditMenuConfiguration *c = [UIEditMenuConfiguration configurationWithIdentifier:nil sourcePoint:p];
    [_menu presentEditMenuWithConfiguration:c];
}

- (void)pinched:(UIPinchGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) _pinchBase = [TMSettings shared].fontSize;
    else if (g.state == UIGestureRecognizerStateChanged) {
        double s = round(_pinchBase * g.scale * 2) / 2;
        if (s != [TMSettings shared].fontSize) [TMSettings shared].fontSize = s;
    }
}

// Колесо: на альтернативном экране (vim, less, htop) — события мыши или стрелки; прокрутка истории выполняется самим UIScrollView
- (void)scrollViewDidEndDragging:(UIScrollView *)s willDecelerate:(BOOL)d { _panAcc = 0; }

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g { return YES; }

- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [super touchesBegan:t withEvent:e]; }

- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e { return [super hitTest:p withEvent:e]; }

// Прокрутка пальцем на альтернативном экране: добавляем pan, только когда он нужен
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window && !objc_getAssociatedObject(self, "pan")) {
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
        pan.maximumNumberOfTouches = 1; pan.delegate = self; [_scroll addGestureRecognizer:pan];
        objc_setAssociatedObject(self, "pan", pan, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
- (void)panned:(UIPanGestureRecognizer *)g {
    if (!_emu) return;
    BOOL alt = tm_emu_alt_screen(_emu), mouse = tm_emu_mouse_mode(_emu) != TM_MOUSE_NONE;
    if (!alt && !mouse) return;
    if (g.state == UIGestureRecognizerStateBegan) _panAcc = 0;
    CGFloat dy = [g translationInView:self].y; [g setTranslation:CGPointZero inView:self];
    _panAcc += dy;
    CGFloat step = _cellH;
    while (fabs(_panAcc) >= step) {
        BOOL up = _panAcc > 0; _panAcc += up ? -step : step;
        if (mouse) [self sendMouse:up ? 64 : 65 at:[g locationInView:self] release:NO motion:NO];
        else if (tm_emu_alt_scroll(_emu)) [self sendKey:up ? UIKeyboardHIDUsageKeyboardUpArrow : UIKeyboardHIDUsageKeyboardDownArrow modifiers:0];
    }
}

#pragma mark - Меню правки

- (UIMenu *)editMenuInteraction:(UIEditMenuInteraction *)i menuForConfiguration:(UIEditMenuConfiguration *)c suggestedActions:(NSArray<UIMenuElement *> *)s {
    __weak TMTerminalView *ws = self;
    NSMutableArray *items = [NSMutableArray array];
    if (_hasSel) [items addObject:[UIAction actionWithTitle:TMT(@"Copy", @"Копировать") image:nil identifier:nil handler:^(UIAction *a) { [ws copySelection]; }]];
    [items addObject:[UIAction actionWithTitle:TMT(@"Paste", @"Вставить") image:nil identifier:nil handler:^(UIAction *a) { [ws pasteFromPasteboard]; }]];
    [items addObject:[UIAction actionWithTitle:TMT(@"Select all", @"Выделить всё") image:nil identifier:nil handler:^(UIAction *a) { [ws selectAll]; }]];
    [items addObject:[UIAction actionWithTitle:TMT(@"Clear", @"Очистить") image:nil identifier:nil handler:^(UIAction *a) { [ws clearScreen]; }]];
    return [UIMenu menuWithChildren:items];
}
- (void)selectAll {
    if (!_emu) return;
    int total = tm_emu_total_lines(_emu);
    _hasSel = YES; _selR0 = 0; _selC0 = 0; _selR1 = total - 1; _selC1 = tm_emu_cols(_emu) - 1; [_grid setNeedsDisplay];
}
- (BOOL)canPerformAction:(SEL)a withSender:(id)s {
    if (a == @selector(paste:)) return [UIPasteboard generalPasteboard].hasStrings;
    if (a == @selector(copy:)) return _hasSel;
    return [super canPerformAction:a withSender:s];
}
- (void)paste:(id)sender { [self pasteFromPasteboard]; }
- (void)copy:(id)sender { [self copySelection]; }

@end
