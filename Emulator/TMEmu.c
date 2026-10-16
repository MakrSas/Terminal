#include "TMEmu.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define MAXP 24
#define OSC_MAX 8192

typedef struct { TMCell *cells; bool wrapped; } Line;
typedef struct { int x, y; bool pending; TMColor fg, bg; uint16_t attr; int gl; uint8_t cs[4]; bool origin; bool valid; } Saved;
typedef enum { S_GROUND, S_ESC, S_ESC_INT, S_CSI, S_CSI_IGNORE, S_OSC, S_STRING, S_STRING_ESC } PState;

struct TMEmu {
    int cols, rows;
    Line **primary, **alt, **screen;
    bool useAlt;
    Line **sb; int sbCap, sbHead, sbCount;
    int cx, cy; bool pending;
    TMColor fg, bg; uint16_t attr;
    Saved saved[2];
    int top, bot;
    bool autowrap, origin, insert, lnm, cursorVis, appCursor, appKeypad, bracketed, reverse, focusEv, altScroll, cursorBlink;
    int cursorStyle, mouseMode, mouseEnc;
    bool *tabs;
    uint8_t cs[4]; int gl;
    // разбор
    PState st;
    int params[MAXP]; bool sub[MAXP]; int np; bool havePrivate; char privMark; char inter[4]; int ni; bool paramStarted;
    char *osc; size_t oscLen;
    uint32_t utf; int utfLeft; uint32_t utfMin;
    uint32_t lastCh;
    // изменения
    bool *dirtyRow; bool allDirty;
    char *title; uint32_t defFg, defBg;
    TMEmuCallbacks cb;
};

// ---------- ширина символов ----------
typedef struct { uint32_t lo, hi; } Range;
static const Range kZero[] = {
    {0x0300, 0x036F}, {0x0483, 0x0489}, {0x0591, 0x05BD}, {0x05BF, 0x05BF}, {0x05C1, 0x05C2}, {0x05C4, 0x05C5}, {0x05C7, 0x05C7},
    {0x0610, 0x061A}, {0x064B, 0x065F}, {0x0670, 0x0670}, {0x06D6, 0x06DC}, {0x06DF, 0x06E4}, {0x06E7, 0x06E8}, {0x06EA, 0x06ED},
    {0x0900, 0x0902}, {0x093A, 0x093A}, {0x093C, 0x093C}, {0x0941, 0x0948}, {0x094D, 0x094D}, {0x0951, 0x0957}, {0x0E31, 0x0E31},
    {0x0E34, 0x0E3A}, {0x0E47, 0x0E4E}, {0x1AB0, 0x1AFF}, {0x1DC0, 0x1DFF}, {0x200B, 0x200F}, {0x202A, 0x202E}, {0x2060, 0x2064},
    {0x20D0, 0x20FF}, {0xFE00, 0xFE0F}, {0xFE20, 0xFE2F}, {0xFEFF, 0xFEFF}, {0x1F3FB, 0x1F3FF}, {0xE0100, 0xE01EF}
};
static const Range kWide[] = {
    {0x1100, 0x115F}, {0x231A, 0x231B}, {0x2329, 0x232A}, {0x23E9, 0x23EC}, {0x23F0, 0x23F0}, {0x23F3, 0x23F3}, {0x25FD, 0x25FE},
    {0x2614, 0x2615}, {0x2648, 0x2653}, {0x267F, 0x267F}, {0x2693, 0x2693}, {0x26A1, 0x26A1}, {0x26AA, 0x26AB}, {0x26BD, 0x26BE},
    {0x26C4, 0x26C5}, {0x26CE, 0x26CE}, {0x26D4, 0x26D4}, {0x26EA, 0x26EA}, {0x26F2, 0x26F3}, {0x26F5, 0x26F5}, {0x26FA, 0x26FA},
    {0x26FD, 0x26FD}, {0x2705, 0x2705}, {0x270A, 0x270B}, {0x2728, 0x2728}, {0x274C, 0x274C}, {0x274E, 0x274E}, {0x2753, 0x2755},
    {0x2757, 0x2757}, {0x2795, 0x2797}, {0x27B0, 0x27B0}, {0x27BF, 0x27BF}, {0x2B1B, 0x2B1C}, {0x2B50, 0x2B50}, {0x2B55, 0x2B55},
    {0x2E80, 0x303E}, {0x3041, 0x33FF}, {0x3400, 0x4DBF}, {0x4E00, 0x9FFF}, {0xA000, 0xA4CF}, {0xA960, 0xA97F}, {0xAC00, 0xD7A3},
    {0xF900, 0xFAFF}, {0xFE10, 0xFE19}, {0xFE30, 0xFE6F}, {0xFF00, 0xFF60}, {0xFFE0, 0xFFE6}, {0x1F004, 0x1F004}, {0x1F0CF, 0x1F0CF},
    {0x1F18E, 0x1F18E}, {0x1F191, 0x1F19A}, {0x1F200, 0x1F320}, {0x1F32D, 0x1F335}, {0x1F337, 0x1F37C}, {0x1F37E, 0x1F393},
    {0x1F3A0, 0x1F3CA}, {0x1F3CF, 0x1F3D3}, {0x1F3E0, 0x1F3F0}, {0x1F3F4, 0x1F3F4}, {0x1F3F8, 0x1F43E}, {0x1F440, 0x1F440},
    {0x1F442, 0x1F4FC}, {0x1F4FF, 0x1F53D}, {0x1F54B, 0x1F54E}, {0x1F550, 0x1F567}, {0x1F57A, 0x1F57A}, {0x1F595, 0x1F596},
    {0x1F5A4, 0x1F5A4}, {0x1F5FB, 0x1F64F}, {0x1F680, 0x1F6C5}, {0x1F6CC, 0x1F6CC}, {0x1F6D0, 0x1F6D2}, {0x1F6D5, 0x1F6D7},
    {0x1F6EB, 0x1F6EC}, {0x1F6F4, 0x1F6FC}, {0x1F7E0, 0x1F7EB}, {0x1F90C, 0x1F93A}, {0x1F93C, 0x1F945}, {0x1F947, 0x1F9FF},
    {0x1FA70, 0x1FAFF}, {0x20000, 0x2FFFD}, {0x30000, 0x3FFFD}
};
static bool in_ranges(uint32_t c, const Range *r, size_t n) {
    size_t lo = 0, hi = n;
    while (lo < hi) { size_t m = (lo + hi) / 2; if (c < r[m].lo) hi = m; else if (c > r[m].hi) lo = m + 1; else return true; }
    return false;
}
int tm_wcwidth(uint32_t c) {
    if (c < 0x20 || (c >= 0x7f && c < 0xa0)) return 0;
    if (c < 0x300) return 1;
    if (in_ranges(c, kZero, sizeof kZero / sizeof *kZero)) return 0;
    if (in_ranges(c, kWide, sizeof kWide / sizeof *kWide)) return 2;
    return 1;
}

// ---------- строки ----------
static TMCell blank_cell(const TMEmu *e) { TMCell c = {0, 0, e->bg, 0, 0}; return c; }
static Line *line_new(int cols, TMCell fill) {
    Line *l = malloc(sizeof *l);
    l->cells = malloc(sizeof(TMCell) * (size_t)cols);
    for (int i = 0; i < cols; i++) l->cells[i] = fill;
    l->wrapped = false;
    return l;
}
static void line_free(Line *l) { if (l) { free(l->cells); free(l); } }
static void line_clear(Line *l, int cols, TMCell fill) { for (int i = 0; i < cols; i++) l->cells[i] = fill; l->wrapped = false; }

static void mark(TMEmu *e, int row) { if (row >= 0 && row < e->rows) e->dirtyRow[row] = true; }
static void mark_all(TMEmu *e) { e->allDirty = true; }

// ---------- история ----------
static void sb_push(TMEmu *e, Line *l) {
    if (e->sbCap <= 0) { line_free(l); return; }
    if (e->sbCount == e->sbCap) { line_free(e->sb[e->sbHead]); e->sb[e->sbHead] = l; e->sbHead = (e->sbHead + 1) % e->sbCap; }
    else { e->sb[(e->sbHead + e->sbCount) % e->sbCap] = l; e->sbCount++; }
}
static Line *sb_at(const TMEmu *e, int i) { return e->sb[(e->sbHead + i) % e->sbCap]; }

// ---------- создание ----------
static void set_tabs(TMEmu *e) { for (int i = 0; i < e->cols; i++) e->tabs[i] = (i % 8) == 0; }

static Line **alloc_screen(int cols, int rows) {
    Line **s = malloc(sizeof(Line *) * (size_t)rows);
    TMCell z = {0, 0, 0, 0, 0};
    for (int i = 0; i < rows; i++) s[i] = line_new(cols, z);
    return s;
}

static void reset_state(TMEmu *e, bool full) {
    e->fg = e->bg = 0; e->attr = 0;
    e->top = 0; e->bot = e->rows - 1;
    e->autowrap = true; e->origin = false; e->insert = false; e->lnm = false; e->cursorVis = true; e->appCursor = false; e->appKeypad = false;
    e->bracketed = false; e->reverse = false; e->focusEv = false; e->altScroll = true; e->mouseMode = 0; e->mouseEnc = 0;
    e->cursorStyle = 0; e->cursorBlink = true;
    e->gl = 0; for (int i = 0; i < 4; i++) e->cs[i] = 0;
    e->pending = false;
    if (full) {
        e->cx = e->cy = 0;
        set_tabs(e);
        memset(e->saved, 0, sizeof e->saved);
    }
}

TMEmu *tm_emu_new(int cols, int rows, int scrollback, TMEmuCallbacks cb) {
    TMEmu *e = calloc(1, sizeof *e);
    if (cols < 1) cols = 1; if (rows < 1) rows = 1;
    e->cols = cols; e->rows = rows; e->cb = cb;
    e->primary = alloc_screen(cols, rows); e->alt = alloc_screen(cols, rows); e->screen = e->primary;
    e->sbCap = scrollback > 0 ? scrollback : 0; e->sb = e->sbCap ? calloc((size_t)e->sbCap, sizeof(Line *)) : NULL;
    e->tabs = calloc((size_t)cols, sizeof(bool));
    e->dirtyRow = calloc((size_t)rows, sizeof(bool)); e->allDirty = true;
    e->osc = malloc(OSC_MAX + 1);
    e->title = strdup("");
    e->defFg = 0xd7dce8; e->defBg = 0x0b0f19;
    reset_state(e, true);
    return e;
}

void tm_emu_free(TMEmu *e) {
    if (!e) return;
    for (int i = 0; i < e->rows; i++) { line_free(e->primary[i]); line_free(e->alt[i]); }
    free(e->primary); free(e->alt);
    for (int i = 0; i < e->sbCount; i++) line_free(sb_at(e, i));
    free(e->sb); free(e->tabs); free(e->dirtyRow); free(e->osc); free(e->title); free(e);
}

void tm_emu_set_default_colors(TMEmu *e, uint32_t fg, uint32_t bg) { e->defFg = fg; e->defBg = bg; }
void tm_emu_set_scrollback(TMEmu *e, int lines) {
    if (lines < 0) lines = 0;
    if (lines == e->sbCap) return;
    Line **n = lines ? calloc((size_t)lines, sizeof(Line *)) : NULL;
    int keep = e->sbCount < lines ? e->sbCount : lines, skip = e->sbCount - keep;
    for (int i = 0; i < skip; i++) line_free(sb_at(e, i));
    for (int i = 0; i < keep; i++) n[i] = sb_at(e, skip + i);
    free(e->sb); e->sb = n; e->sbCap = lines; e->sbHead = 0; e->sbCount = keep;
    mark_all(e);
}

// ---------- доступ ----------
int tm_emu_cols(const TMEmu *e) { return e->cols; }
int tm_emu_rows(const TMEmu *e) { return e->rows; }
int tm_emu_scrollback_count(const TMEmu *e) { return e->useAlt ? 0 : e->sbCount; }
int tm_emu_total_lines(const TMEmu *e) { return tm_emu_scrollback_count(e) + e->rows; }
const TMCell *tm_emu_line(const TMEmu *e, int abs, bool *wrapped) {
    int sbn = tm_emu_scrollback_count(e);
    Line *l = abs < sbn ? sb_at(e, abs) : e->screen[abs - sbn < e->rows ? abs - sbn : e->rows - 1];
    if (wrapped) *wrapped = l->wrapped;
    return l->cells;
}
int tm_emu_cursor_x(const TMEmu *e) { return e->cx; }
int tm_emu_cursor_y(const TMEmu *e) { return e->cy; }
bool tm_emu_cursor_visible(const TMEmu *e) { return e->cursorVis; }
int tm_emu_cursor_style(const TMEmu *e) { return e->cursorStyle; }
bool tm_emu_cursor_blink(const TMEmu *e) { return e->cursorBlink; }
bool tm_emu_app_cursor(const TMEmu *e) { return e->appCursor; }
bool tm_emu_app_keypad(const TMEmu *e) { return e->appKeypad; }
bool tm_emu_bracketed_paste(const TMEmu *e) { return e->bracketed; }
bool tm_emu_alt_screen(const TMEmu *e) { return e->useAlt; }
bool tm_emu_reverse_video(const TMEmu *e) { return e->reverse; }
bool tm_emu_focus_events(const TMEmu *e) { return e->focusEv; }
bool tm_emu_alt_scroll(const TMEmu *e) { return e->altScroll; }
TMMouseMode tm_emu_mouse_mode(const TMEmu *e) { return (TMMouseMode)e->mouseMode; }
const char *tm_emu_title(const TMEmu *e) { return e->title; }

bool tm_emu_take_dirty(TMEmu *e, int *first, int *last, bool *all) {
    bool any = e->allDirty; int f = e->rows, l = -1;
    for (int i = 0; i < e->rows; i++) if (e->dirtyRow[i]) { if (i < f) f = i; l = i; any = true; e->dirtyRow[i] = false; }
    *all = e->allDirty; e->allDirty = false;
    *first = f; *last = l;
    return any;
}

static void respond(TMEmu *e, const char *s) { if (e->cb.write) e->cb.write(e->cb.ctx, (const uint8_t *)s, strlen(s)); }
static void respondf(TMEmu *e, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
#include <stdarg.h>
static void respondf(TMEmu *e, const char *fmt, ...) {
    char buf[256]; va_list ap; va_start(ap, fmt); vsnprintf(buf, sizeof buf, fmt, ap); va_end(ap); respond(e, buf);
}
static void notify_modes(TMEmu *e) { if (e->cb.modes) e->cb.modes(e->cb.ctx); }

// ---------- прокрутка ----------
static void scroll_up(TMEmu *e, int n) {   // содержимое области уходит вверх
    int h = e->bot - e->top + 1;
    if (n > h) n = h;
    TMCell fill = blank_cell(e);
    for (int k = 0; k < n; k++) {
        Line *gone = e->screen[e->top];
        for (int r = e->top; r < e->bot; r++) e->screen[r] = e->screen[r + 1];
        if (e->top == 0 && !e->useAlt) {
            sb_push(e, gone);
            gone = line_new(e->cols, fill);
        } else line_clear(gone, e->cols, fill);
        e->screen[e->bot] = gone;
    }
    for (int r = e->top; r <= e->bot; r++) mark(e, r);
    mark_all(e);
}
static void scroll_down(TMEmu *e, int n) {
    int h = e->bot - e->top + 1;
    if (n > h) n = h;
    TMCell fill = blank_cell(e);
    for (int k = 0; k < n; k++) {
        Line *gone = e->screen[e->bot];
        for (int r = e->bot; r > e->top; r--) e->screen[r] = e->screen[r - 1];
        line_clear(gone, e->cols, fill);
        e->screen[e->top] = gone;
    }
    mark_all(e);
}
static void index_down(TMEmu *e) {   // IND / LF
    if (e->cy == e->bot) scroll_up(e, 1);
    else if (e->cy < e->rows - 1) e->cy++;
}
static void reverse_index(TMEmu *e) {
    if (e->cy == e->top) scroll_down(e, 1);
    else if (e->cy > 0) e->cy--;
}

// ---------- вывод символов ----------
static const uint32_t kDecGraphics[32] = {   // 0x5f…0x7e
    0x00A0, 0x25C6, 0x2592, 0x2409, 0x240C, 0x240D, 0x240A, 0x00B0, 0x00B1, 0x2424, 0x240B, 0x2518, 0x2510, 0x250C, 0x2514, 0x253C,
    0x23BA, 0x23BB, 0x2500, 0x23BC, 0x23BD, 0x251C, 0x2524, 0x2534, 0x252C, 0x2502, 0x2264, 0x2265, 0x03C0, 0x2260, 0x00A3, 0x00B7
};

static void blank_wide_at(TMEmu *e, Line *l, int x) {   // перед записью в ячейку убираем «половинки» широких символов
    if (x < 0 || x >= e->cols) return;
    TMCell b = blank_cell(e);
    if (l->cells[x].attr & TM_WIDE_CONT) { if (x > 0) { l->cells[x - 1] = b; } l->cells[x] = b; }
    else if (l->cells[x].attr & TM_WIDE) { l->cells[x] = b; if (x + 1 < e->cols) l->cells[x + 1] = b; }
}

static void wrap_line(TMEmu *e) {
    e->screen[e->cy]->wrapped = true;
    index_down(e);
    e->cx = 0; e->pending = false;
}

static void put_char(TMEmu *e, uint32_t cp) {
    if (cp >= 0x5f && cp <= 0x7e && e->cs[e->gl] == 1) cp = kDecGraphics[cp - 0x5f];
    int w = tm_wcwidth(cp);
    if (w == 0) return;   // комбинируемые знаки не занимают ячейку (в этой версии не рисуются)
    e->lastCh = cp;
    if (e->pending && e->autowrap) wrap_line(e);
    if (w == 2 && e->cx == e->cols - 1) {
        if (e->autowrap) { Line *l = e->screen[e->cy]; l->cells[e->cx] = blank_cell(e); wrap_line(e); }
        else return;
    }
    Line *l = e->screen[e->cy];
    if (e->insert) {
        for (int i = e->cols - 1; i >= e->cx + w; i--) l->cells[i] = l->cells[i - w];
    }
    blank_wide_at(e, l, e->cx);
    if (w == 2) blank_wide_at(e, l, e->cx + 1);
    TMCell c = {cp, e->fg, e->bg, (uint16_t)(e->attr | (w == 2 ? TM_WIDE : 0)), 0};
    l->cells[e->cx] = c;
    if (w == 2 && e->cx + 1 < e->cols) { TMCell cc = {0, e->fg, e->bg, (uint16_t)(e->attr | TM_WIDE_CONT), 0}; l->cells[e->cx + 1] = cc; }
    mark(e, e->cy);
    e->cx += w;
    if (e->cx >= e->cols) { e->cx = e->cols - 1; e->pending = true; }
}

// ---------- стирание, вставка, удаление ----------
static void erase_cells(TMEmu *e, int y, int x0, int x1) {   // [x0, x1)
    Line *l = e->screen[y]; TMCell b = blank_cell(e);
    if (x0 < 0) x0 = 0; if (x1 > e->cols) x1 = e->cols;
    if (x0 > 0 && (l->cells[x0].attr & TM_WIDE_CONT)) l->cells[x0 - 1] = b;
    if (x1 < e->cols && (l->cells[x1].attr & TM_WIDE_CONT)) l->cells[x1] = b;
    for (int i = x0; i < x1; i++) l->cells[i] = b;
    if (x1 >= e->cols) l->wrapped = false;
    mark(e, y);
}
static void erase_display(TMEmu *e, int mode) {
    if (mode == 0) { erase_cells(e, e->cy, e->cx, e->cols); for (int y = e->cy + 1; y < e->rows; y++) erase_cells(e, y, 0, e->cols); }
    else if (mode == 1) { for (int y = 0; y < e->cy; y++) erase_cells(e, y, 0, e->cols); erase_cells(e, e->cy, 0, e->cx + 1); }
    else if (mode == 2) { for (int y = 0; y < e->rows; y++) erase_cells(e, y, 0, e->cols); }
    else if (mode == 3) {   // стереть и историю
        for (int i = 0; i < e->sbCount; i++) line_free(sb_at(e, i));
        e->sbCount = 0; e->sbHead = 0; mark_all(e);
    }
    mark_all(e);
}
static void erase_line(TMEmu *e, int mode) {
    if (mode == 0) erase_cells(e, e->cy, e->cx, e->cols);
    else if (mode == 1) erase_cells(e, e->cy, 0, e->cx + 1);
    else if (mode == 2) erase_cells(e, e->cy, 0, e->cols);
}
static void insert_lines(TMEmu *e, int n) {
    if (e->cy < e->top || e->cy > e->bot) return;
    int save = e->top; e->top = e->cy; scroll_down(e, n); e->top = save; e->cx = 0; e->pending = false;
}
static void delete_lines(TMEmu *e, int n) {
    if (e->cy < e->top || e->cy > e->bot) return;
    int save = e->top; e->top = e->cy; scroll_up(e, n); e->top = save; e->cx = 0; e->pending = false;
}
static void insert_chars(TMEmu *e, int n) {
    Line *l = e->screen[e->cy]; if (n > e->cols - e->cx) n = e->cols - e->cx;
    TMCell b = blank_cell(e);
    for (int i = e->cols - 1; i >= e->cx + n; i--) l->cells[i] = l->cells[i - n];
    for (int i = e->cx; i < e->cx + n; i++) l->cells[i] = b;
    mark(e, e->cy); e->pending = false;
}
static void delete_chars(TMEmu *e, int n) {
    Line *l = e->screen[e->cy]; if (n > e->cols - e->cx) n = e->cols - e->cx;
    TMCell b = blank_cell(e);
    for (int i = e->cx; i < e->cols - n; i++) l->cells[i] = l->cells[i + n];
    for (int i = e->cols - n; i < e->cols; i++) l->cells[i] = b;
    mark(e, e->cy); e->pending = false;
}

// ---------- курсор ----------
static void clamp_cursor(TMEmu *e) {
    if (e->cx < 0) e->cx = 0; if (e->cx >= e->cols) e->cx = e->cols - 1;
    int lo = e->origin ? e->top : 0, hi = e->origin ? e->bot : e->rows - 1;
    if (e->cy < lo) e->cy = lo; if (e->cy > hi) e->cy = hi;
}
static void move_to(TMEmu *e, int row, int col) {   // 0-based; row относительно области при DECOM
    if (e->origin) row += e->top;
    e->cy = row; e->cx = col; e->pending = false; clamp_cursor(e);
}
static void save_cursor(TMEmu *e) {
    Saved *s = &e->saved[e->useAlt ? 1 : 0];
    s->x = e->cx; s->y = e->cy; s->pending = e->pending; s->fg = e->fg; s->bg = e->bg; s->attr = e->attr; s->gl = e->gl; memcpy(s->cs, e->cs, 4); s->origin = e->origin; s->valid = true;
}
static void restore_cursor(TMEmu *e) {
    Saved *s = &e->saved[e->useAlt ? 1 : 0];
    if (!s->valid) { e->cx = e->cy = 0; e->pending = false; e->fg = e->bg = 0; e->attr = 0; e->origin = false; return; }
    e->cx = s->x; e->cy = s->y; e->pending = s->pending; e->fg = s->fg; e->bg = s->bg; e->attr = s->attr; e->gl = s->gl; memcpy(e->cs, s->cs, 4); e->origin = s->origin;
    clamp_cursor(e);
}

static void use_alt(TMEmu *e, bool on, bool save) {
    if (on == e->useAlt) return;
    if (on) {
        if (save) save_cursor(e);
        e->useAlt = true; e->screen = e->alt;
        TMCell b = {0, 0, 0, 0, 0};
        for (int i = 0; i < e->rows; i++) line_clear(e->alt[i], e->cols, b);
    } else {
        e->useAlt = false; e->screen = e->primary;
        if (save) restore_cursor(e);
    }
    e->top = 0; e->bot = e->rows - 1; e->pending = false;
    mark_all(e); notify_modes(e);
}

// ---------- SGR ----------
static const uint8_t kStd[8] = {0, 1, 2, 3, 4, 5, 6, 7};
static void sgr(TMEmu *e) {
    if (e->np == 0) { e->np = 1; e->params[0] = 0; e->sub[0] = false; }
    for (int i = 0; i < e->np; i++) {
        int p = e->params[i];
        if (e->sub[i]) continue;   // подпараметры обрабатываются вместе с основным
        switch (p) {
            case 0: e->fg = e->bg = 0; e->attr = 0; break;
            case 1: e->attr |= TM_BOLD; break;
            case 2: e->attr |= TM_DIM; break;
            case 3: e->attr |= TM_ITALIC; break;
            case 4: {
                e->attr &= (uint16_t)~(TM_DOUBLE_UL | TM_CURLY_UL);
                if (i + 1 < e->np && e->sub[i + 1]) { int st = e->params[i + 1]; if (st == 0) e->attr &= (uint16_t)~TM_UNDERLINE; else { e->attr |= TM_UNDERLINE; if (st == 2) e->attr |= TM_DOUBLE_UL; if (st >= 3) e->attr |= TM_CURLY_UL; } }
                else e->attr |= TM_UNDERLINE;
                break; }
            case 5: case 6: e->attr |= TM_BLINK; break;
            case 7: e->attr |= TM_INVERSE; break;
            case 8: e->attr |= TM_INVISIBLE; break;
            case 9: e->attr |= TM_STRIKE; break;
            case 21: e->attr |= TM_UNDERLINE | TM_DOUBLE_UL; break;
            case 22: e->attr &= (uint16_t)~(TM_BOLD | TM_DIM); break;
            case 23: e->attr &= (uint16_t)~TM_ITALIC; break;
            case 24: e->attr &= (uint16_t)~(TM_UNDERLINE | TM_DOUBLE_UL | TM_CURLY_UL); break;
            case 25: e->attr &= (uint16_t)~TM_BLINK; break;
            case 27: e->attr &= (uint16_t)~TM_INVERSE; break;
            case 28: e->attr &= (uint16_t)~TM_INVISIBLE; break;
            case 29: e->attr &= (uint16_t)~TM_STRIKE; break;
            case 39: e->fg = 0; break;
            case 49: e->bg = 0; break;
            case 38: case 48: case 58: {
                TMColor c = 0; bool ok = false; int used = 0;
                bool colon = i + 1 < e->np && e->sub[i + 1];
                if (colon) {
                    // 38:5:n  или  38:2:[cs:]r:g:b
                    int j = i + 1, cnt = 0; while (j + cnt < e->np && e->sub[j + cnt]) cnt++;
                    int mode = e->params[j];
                    if (mode == 5 && cnt >= 2) { c = TM_COLOR_INDEXED(e->params[j + 1] & 255); ok = true; }
                    else if (mode == 2 && cnt >= 4) { int o = cnt >= 5 ? j + 2 : j + 1; c = TM_COLOR_RGB(e->params[o] & 255, e->params[o + 1] & 255, e->params[o + 2] & 255); ok = true; }
                    used = cnt;
                } else if (i + 1 < e->np) {
                    int mode = e->params[i + 1];
                    if (mode == 5 && i + 2 < e->np) { c = TM_COLOR_INDEXED(e->params[i + 2] & 255); ok = true; used = 2; }
                    else if (mode == 2 && i + 4 < e->np) { c = TM_COLOR_RGB(e->params[i + 2] & 255, e->params[i + 3] & 255, e->params[i + 4] & 255); ok = true; used = 4; }
                    else used = e->np - i - 1;
                }
                if (ok) { if (p == 38) e->fg = c; else if (p == 48) e->bg = c; }
                i += used; break; }
            case 53: case 55: break;
            case 59: break;
            default:
                if (p >= 30 && p <= 37) e->fg = TM_COLOR_INDEXED(kStd[p - 30]);
                else if (p >= 40 && p <= 47) e->bg = TM_COLOR_INDEXED(kStd[p - 40]);
                else if (p >= 90 && p <= 97) e->fg = TM_COLOR_INDEXED(8 + (p - 90));
                else if (p >= 100 && p <= 107) e->bg = TM_COLOR_INDEXED(8 + (p - 100));
                break;
        }
    }
}

// ---------- режимы ----------
static void set_mode(TMEmu *e, int mode, bool priv, bool on) {
    if (!priv) {
        if (mode == 4) e->insert = on;
        else if (mode == 20) e->lnm = on;
        return;
    }
    switch (mode) {
        case 1: e->appCursor = on; notify_modes(e); break;
        case 5: e->reverse = on; mark_all(e); notify_modes(e); break;
        case 6: e->origin = on; move_to(e, 0, 0); break;
        case 7: e->autowrap = on; break;
        case 9: e->mouseMode = on ? TM_MOUSE_X10 : 0; notify_modes(e); break;
        case 12: e->cursorBlink = on; mark(e, e->cy); break;
        case 25: e->cursorVis = on; mark(e, e->cy); break;
        case 47: case 1047: use_alt(e, on, false); break;
        case 1048: if (on) save_cursor(e); else restore_cursor(e); break;
        case 1049: use_alt(e, on, true); break;
        case 1000: case 1002: case 1003: e->mouseMode = on ? mode : (e->mouseMode == mode ? 0 : e->mouseMode); notify_modes(e); break;
        case 1004: e->focusEv = on; notify_modes(e); break;
        case 1005: case 1006: case 1015: e->mouseEnc = on ? mode : (e->mouseEnc == mode ? 0 : e->mouseEnc); notify_modes(e); break;
        case 1007: e->altScroll = on; notify_modes(e); break;
        case 2004: e->bracketed = on; notify_modes(e); break;
        default: break;
    }
}
static int mode_state(const TMEmu *e, int mode, bool priv) {   // 1 включён, 2 выключен, 0 неизвестен
    if (!priv) { if (mode == 4) return e->insert ? 1 : 2; if (mode == 20) return e->lnm ? 1 : 2; return 0; }
    switch (mode) {
        case 1: return e->appCursor ? 1 : 2; case 5: return e->reverse ? 1 : 2; case 6: return e->origin ? 1 : 2; case 7: return e->autowrap ? 1 : 2;
        case 12: return e->cursorBlink ? 1 : 2; case 25: return e->cursorVis ? 1 : 2; case 47: case 1047: case 1049: return e->useAlt ? 1 : 2;
        case 1000: case 1002: case 1003: return e->mouseMode == mode ? 1 : 2; case 1004: return e->focusEv ? 1 : 2;
        case 1006: case 1005: case 1015: return e->mouseEnc == mode ? 1 : 2; case 1007: return e->altScroll ? 1 : 2; case 2004: return e->bracketed ? 1 : 2;
        default: return 0;
    }
}

// ---------- CSI ----------
static int P(const TMEmu *e, int i, int def) { return (i < e->np && e->params[i] > 0) ? e->params[i] : def; }
static int P0(const TMEmu *e, int i) { return i < e->np ? e->params[i] : 0; }

static void csi_dispatch(TMEmu *e, uint8_t f) {
    bool priv = e->havePrivate && e->privMark == '?';
    bool gt = e->havePrivate && e->privMark == '>';
    int n;
    switch (f) {
        case '@': insert_chars(e, P(e, 0, 1)); break;
        case 'A': { int lim = e->cy >= e->top ? e->top : 0; e->cy -= P(e, 0, 1); if (e->cy < lim) e->cy = lim; e->pending = false; break; }
        case 'B': case 'e': { int lim = e->cy <= e->bot ? e->bot : e->rows - 1; e->cy += P(e, 0, 1); if (e->cy > lim) e->cy = lim; e->pending = false; break; }
        case 'C': case 'a': e->cx += P(e, 0, 1); e->pending = false; clamp_cursor(e); break;
        case 'D': e->cx -= P(e, 0, 1); e->pending = false; clamp_cursor(e); break;
        case 'E': e->cy += P(e, 0, 1); e->cx = 0; e->pending = false; clamp_cursor(e); break;
        case 'F': e->cy -= P(e, 0, 1); e->cx = 0; e->pending = false; clamp_cursor(e); break;
        case 'G': case '`': e->cx = P(e, 0, 1) - 1; e->pending = false; clamp_cursor(e); break;
        case 'H': case 'f': move_to(e, P(e, 0, 1) - 1, P(e, 1, 1) - 1); break;
        case 'I': for (n = P(e, 0, 1); n > 0 && e->cx < e->cols - 1; n--) { do e->cx++; while (e->cx < e->cols - 1 && !e->tabs[e->cx]); } e->pending = false; break;
        case 'Z': for (n = P(e, 0, 1); n > 0 && e->cx > 0; n--) { do e->cx--; while (e->cx > 0 && !e->tabs[e->cx]); } e->pending = false; break;
        case 'J': erase_display(e, P0(e, 0)); break;
        case 'K': erase_line(e, P0(e, 0)); break;
        case 'L': insert_lines(e, P(e, 0, 1)); break;
        case 'M': delete_lines(e, P(e, 0, 1)); break;
        case 'P': delete_chars(e, P(e, 0, 1)); break;
        case 'S': scroll_up(e, P(e, 0, 1)); break;
        case 'T': if (e->np <= 1) scroll_down(e, P(e, 0, 1)); break;
        case 'X': erase_cells(e, e->cy, e->cx, e->cx + P(e, 0, 1)); break;
        case 'b': { uint32_t ch = e->lastCh; for (n = P(e, 0, 1); ch && n > 0 && n < 65536; n--) put_char(e, ch); break; }
        case 'c':
            if (gt) respond(e, "\x1b[>0;276;0c");
            else if (!e->havePrivate && P0(e, 0) == 0) respond(e, "\x1b[?62;22c");
            break;
        case 'd': move_to(e, P(e, 0, 1) - 1, e->cx); break;
        case 'g': if (P0(e, 0) == 0) e->tabs[e->cx] = false; else if (P0(e, 0) == 3) memset(e->tabs, 0, (size_t)e->cols * sizeof(bool)); break;
        case 'h': case 'l':
            for (int i = 0; i < (e->np ? e->np : 1); i++) set_mode(e, P0(e, i), priv, f == 'h');
            break;
        case 'm': if (!e->havePrivate) sgr(e); break;
        case 'n':
            if (priv) { if (P0(e, 0) == 6) respondf(e, "\x1b[?%d;%dR", (e->origin ? e->cy - e->top : e->cy) + 1, e->cx + 1); }
            else if (P0(e, 0) == 5) respond(e, "\x1b[0n");
            else if (P0(e, 0) == 6) respondf(e, "\x1b[%d;%dR", (e->origin ? e->cy - e->top : e->cy) + 1, e->cx + 1);
            break;
        case 'p':
            if (e->ni == 1 && e->inter[0] == '$' && priv) respondf(e, "\x1b[?%d;%d$y", P0(e, 0), mode_state(e, P0(e, 0), true));
            else if (e->ni == 1 && e->inter[0] == '$') respondf(e, "\x1b[%d;%d$y", P0(e, 0), mode_state(e, P0(e, 0), false));
            else if (e->ni == 1 && e->inter[0] == '!') { reset_state(e, false); }   // DECSTR
            break;
        case 'q':
            if (e->ni == 1 && e->inter[0] == ' ') { int s = P0(e, 0); if (s >= 0 && s <= 6) { e->cursorStyle = s; e->cursorBlink = (s == 0 || s % 2 == 1); mark(e, e->cy); notify_modes(e); } }
            break;
        case 'r': {
            if (e->havePrivate) break;
            int t = P(e, 0, 1), b = P(e, 1, e->rows);
            if (t < 1) t = 1; if (b > e->rows) b = e->rows;
            if (t < b) { e->top = t - 1; e->bot = b - 1; move_to(e, 0, 0); }
            break; }
        case 's': if (!e->havePrivate) save_cursor(e); break;
        case 'u': if (!e->havePrivate) restore_cursor(e); break;
        case 't':
            if (P0(e, 0) == 18) respondf(e, "\x1b[8;%d;%dt", e->rows, e->cols);
            else if (P0(e, 0) == 19) respondf(e, "\x1b[9;%d;%dt", e->rows, e->cols);
            else if (P0(e, 0) == 11) respond(e, "\x1b[1t");
            break;
        default: break;
    }
}

// ---------- ESC ----------
static void esc_dispatch(TMEmu *e, uint8_t f) {
    if (e->ni == 1) {
        char i = e->inter[0];
        if (i == '(' || i == ')' || i == '*' || i == '+') {
            int g = i == '(' ? 0 : i == ')' ? 1 : i == '*' ? 2 : 3;
            e->cs[g] = (f == '0' || f == '2') ? 1 : 0;
        } else if (i == '#' && f == '8') {   // DECALN
            for (int y = 0; y < e->rows; y++) { for (int x = 0; x < e->cols; x++) { TMCell c = {'E', 0, 0, 0, 0}; e->screen[y]->cells[x] = c; } mark(e, y); }
        }
        return;
    }
    switch (f) {
        case '7': save_cursor(e); break;
        case '8': restore_cursor(e); break;
        case 'D': index_down(e); break;
        case 'E': index_down(e); e->cx = 0; e->pending = false; break;
        case 'H': e->tabs[e->cx] = true; break;
        case 'M': reverse_index(e); break;
        case 'c': {
            if (e->useAlt) use_alt(e, false, false);
            reset_state(e, true);
            for (int y = 0; y < e->rows; y++) erase_cells(e, y, 0, e->cols);
            mark_all(e); notify_modes(e); break; }
        case '=': e->appKeypad = true; notify_modes(e); break;
        case '>': e->appKeypad = false; notify_modes(e); break;
        case 'N': case 'O': break;
        case 'Z': respond(e, "\x1b[?62;22c"); break;
        default: break;
    }
}

// ---------- OSC ----------
static void set_title(TMEmu *e, const char *t) { free(e->title); e->title = strdup(t); if (e->cb.title) e->cb.title(e->cb.ctx, t); }
static void osc_dispatch(TMEmu *e) {
    e->osc[e->oscLen] = 0;
    char *s = e->osc; int code = 0; char *semi = strchr(s, ';');
    if (!semi) { if (e->oscLen && s[0] >= '0' && s[0] <= '9') code = atoi(s); semi = s + e->oscLen; } else { *semi = 0; code = atoi(s); semi++; }
    switch (code) {
        case 0: case 1: case 2: set_title(e, semi); break;
        case 7: if (e->cb.cwd) e->cb.cwd(e->cb.ctx, semi); break;
        case 10: case 11: {
            if (semi[0] == '?') { uint32_t c = code == 10 ? e->defFg : e->defBg; respondf(e, "\x1b]%d;rgb:%04x/%04x/%04x\x1b\\", code, ((c >> 16) & 255) * 257, ((c >> 8) & 255) * 257, (c & 255) * 257); }
            break; }
        case 52: {
            char *d = strchr(semi, ';'); if (!d || d[1] == '?') break;
            d++;   // base64
            size_t n = strlen(d), cap = n / 4 * 3 + 4; char *out = malloc(cap + 1); size_t o = 0; uint32_t acc = 0; int bits = 0;
            for (size_t i = 0; i < n; i++) {
                char c = d[i]; int v = (c >= 'A' && c <= 'Z') ? c - 'A' : (c >= 'a' && c <= 'z') ? c - 'a' + 26 : (c >= '0' && c <= '9') ? c - '0' + 52 : c == '+' ? 62 : c == '/' ? 63 : -1;
                if (v < 0) continue; acc = (acc << 6) | (uint32_t)v; bits += 6; if (bits >= 8) { bits -= 8; out[o++] = (char)((acc >> bits) & 255); }
            }
            out[o] = 0; if (e->cb.clipboard) e->cb.clipboard(e->cb.ctx, out); free(out); break; }
        default: break;
    }
}

// ---------- разбор ----------
static void param_reset(TMEmu *e) {
    e->np = 0; e->havePrivate = false; e->privMark = 0; e->ni = 0; e->paramStarted = false;
    memset(e->params, 0, sizeof e->params); memset(e->sub, 0, sizeof e->sub);
}
static void execute(TMEmu *e, uint8_t c) {
    switch (c) {
        case 0x07: if (e->cb.bell) e->cb.bell(e->cb.ctx); break;
        case 0x08: if (e->cx > 0) { e->cx--; } e->pending = false; break;
        case 0x09: { int x = e->cx; do x++; while (x < e->cols - 1 && !e->tabs[x]); e->cx = x >= e->cols ? e->cols - 1 : x; e->pending = false; break; }
        case 0x0a: case 0x0b: case 0x0c: index_down(e); if (e->lnm) e->cx = 0; e->pending = false; break;
        case 0x0d: e->cx = 0; e->pending = false; break;
        case 0x0e: e->gl = 1; break;
        case 0x0f: e->gl = 0; break;
        default: break;
    }
}

static void feed_byte(TMEmu *e, uint8_t b) {
    // прерывания во всех состояниях
    if (b == 0x18 || b == 0x1a) { e->st = S_GROUND; e->utfLeft = 0; return; }
    if (b == 0x1b) {
        if (e->st == S_OSC) { e->st = S_STRING_ESC; return; }      // ESC \ завершает OSC
        if (e->st == S_STRING) { e->st = S_STRING_ESC; return; }
        e->st = S_ESC; param_reset(e); e->utfLeft = 0; return;
    }
    switch (e->st) {
        case S_GROUND:
            if (b < 0x20) { execute(e, b); return; }
            if (b < 0x7f) { e->utfLeft = 0; put_char(e, b); return; }
            if (b == 0x7f) return;
            // UTF-8
            if (b >= 0xc2 && b <= 0xf4) {
                e->utfLeft = b >= 0xf0 ? 3 : b >= 0xe0 ? 2 : 1; e->utf = b & (b >= 0xf0 ? 0x07 : b >= 0xe0 ? 0x0f : 0x1f);
                e->utfMin = b >= 0xf0 ? 0x10000 : b >= 0xe0 ? 0x800 : 0x80; return;
            }
            if (b >= 0x80 && b <= 0xbf && e->utfLeft > 0) {
                e->utf = (e->utf << 6) | (b & 0x3f);
                if (--e->utfLeft == 0) {
                    uint32_t cp = e->utf;
                    if (cp < e->utfMin || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff)) cp = 0xfffd;
                    put_char(e, cp);
                }
                return;
            }
            e->utfLeft = 0; return;   // лишние байты игнорируем
        case S_ESC:
            if (b >= 0x20 && b <= 0x2f) { if (e->ni < 3) e->inter[e->ni++] = (char)b; e->st = S_ESC_INT; return; }
            if (b == '[') { param_reset(e); e->st = S_CSI; return; }
            if (b == ']') { e->oscLen = 0; e->st = S_OSC; return; }
            if (b == 'P' || b == 'X' || b == '^' || b == '_') { e->st = S_STRING; return; }
            if (b < 0x20) { execute(e, b); return; }
            esc_dispatch(e, b); e->st = S_GROUND; return;
        case S_ESC_INT:
            if (b >= 0x20 && b <= 0x2f) { if (e->ni < 3) e->inter[e->ni++] = (char)b; return; }
            if (b < 0x20) { execute(e, b); return; }
            esc_dispatch(e, b); e->st = S_GROUND; return;
        case S_CSI:
            if (b >= '0' && b <= '9') {
                if (e->np == 0) e->np = 1;
                if (e->np <= MAXP) { int *p = &e->params[e->np - 1]; if (*p < 100000) *p = *p * 10 + (b - '0'); }
                e->paramStarted = true; return;
            }
            if (b == ';' || b == ':') {
                if (e->np == 0) e->np = 1;
                if (e->np < MAXP) { e->sub[e->np] = (b == ':'); e->np++; }
                return;
            }
            if (b >= 0x3c && b <= 0x3f) { if (e->np == 0 && !e->paramStarted && !e->havePrivate) { e->havePrivate = true; e->privMark = (char)b; } else e->st = S_CSI_IGNORE; return; }
            if (b >= 0x20 && b <= 0x2f) { if (e->ni < 3) e->inter[e->ni++] = (char)b; return; }
            if (b >= 0x40 && b <= 0x7e) { csi_dispatch(e, b); e->st = S_GROUND; return; }
            if (b < 0x20) { execute(e, b); return; }
            e->st = S_CSI_IGNORE; return;
        case S_CSI_IGNORE:
            if (b >= 0x40 && b <= 0x7e) e->st = S_GROUND;
            else if (b < 0x20) execute(e, b);
            return;
        case S_OSC:
            if (b == 0x07) { osc_dispatch(e); e->st = S_GROUND; return; }
            if (e->oscLen < OSC_MAX) e->osc[e->oscLen++] = (char)b;
            return;
        case S_STRING: return;
        case S_STRING_ESC:
            if (b == '\\') { if (e->oscLen && e->st == S_STRING_ESC) { /* ST для OSC */ } }
            // ST закрывает строку; для OSC выполняем команду, если она была открыта
            e->st = S_GROUND;
            if (b == '\\') return;
            feed_byte(e, b); return;
    }
}

void tm_emu_feed(TMEmu *e, const uint8_t *data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        // OSC, завершённый ESC \ : выполняем при переходе в S_STRING_ESC из S_OSC — отметим заранее
        if (e->st == S_OSC && data[i] == 0x1b) { osc_dispatch(e); e->st = S_STRING_ESC; continue; }
        feed_byte(e, data[i]);
    }
    mark(e, e->cy);
}

// ---------- мышь ----------
size_t tm_emu_encode_mouse(const TMEmu *e, int button, int x, int y, int mods, bool motion, bool release, uint8_t *out, size_t cap) {
    if (e->mouseMode == 0 || cap < 32) return 0;
    if (e->mouseMode == TM_MOUSE_X10 && (release || motion || button >= 64)) return 0;
    if (motion && e->mouseMode == TM_MOUSE_NORMAL) return 0;
    int b = button;
    if (e->mouseEnc != 1006 && release) b = 3;
    if (e->mouseMode != TM_MOUSE_X10) b += mods;
    if (motion) b += 32;
    char buf[64]; size_t n = 0;
    if (e->mouseEnc == 1006) n = (size_t)snprintf(buf, sizeof buf, "\x1b[<%d;%d;%d%c", b, x + 1, y + 1, release ? 'm' : 'M');
    else if (e->mouseEnc == 1015) n = (size_t)snprintf(buf, sizeof buf, "\x1b[%d;%d;%dM", b + 32, x + 1, y + 1);
    else if (e->mouseEnc == 1005) {
        n = (size_t)snprintf(buf, sizeof buf, "\x1b[M%c", b + 32);
        int cx = x + 33, cy = y + 33;
        for (int k = 0; k < 2; k++) { int v = k ? cy : cx; if (v < 0x80) buf[n++] = (char)v; else { buf[n++] = (char)(0xc0 | (v >> 6)); buf[n++] = (char)(0x80 | (v & 0x3f)); } }
    } else {
        if (x > 222 || y > 222) return 0;
        n = (size_t)snprintf(buf, sizeof buf, "\x1b[M%c%c%c", b + 32, x + 33, y + 33);
    }
    memcpy(out, buf, n);
    return n;
}

// ---------- текст ----------
char *tm_emu_text(const TMEmu *e, int row0, int col0, int row1, int col1) {
    size_t cap = (size_t)(row1 - row0 + 1) * ((size_t)e->cols * 4 + 2) + 16, n = 0;
    char *out = malloc(cap);
    for (int r = row0; r <= row1; r++) {
        bool wrapped = false; const TMCell *cells = tm_emu_line(e, r, &wrapped);
        int a = r == row0 ? col0 : 0, b = r == row1 ? col1 : e->cols - 1;
        if (b >= e->cols) b = e->cols - 1;
        int last = b; if (r != row1 || col1 >= e->cols - 1) { while (last >= a && (cells[last].ch == 0 || cells[last].ch == ' ') && !(cells[last].attr & TM_WIDE_CONT)) last--; }
        for (int c = a; c <= last; c++) {
            if (cells[c].attr & TM_WIDE_CONT) continue;
            uint32_t ch = cells[c].ch ? cells[c].ch : ' ';
            if (ch < 0x80) out[n++] = (char)ch;
            else if (ch < 0x800) { out[n++] = (char)(0xc0 | (ch >> 6)); out[n++] = (char)(0x80 | (ch & 0x3f)); }
            else if (ch < 0x10000) { out[n++] = (char)(0xe0 | (ch >> 12)); out[n++] = (char)(0x80 | ((ch >> 6) & 0x3f)); out[n++] = (char)(0x80 | (ch & 0x3f)); }
            else { out[n++] = (char)(0xf0 | (ch >> 18)); out[n++] = (char)(0x80 | ((ch >> 12) & 0x3f)); out[n++] = (char)(0x80 | ((ch >> 6) & 0x3f)); out[n++] = (char)(0x80 | (ch & 0x3f)); }
        }
        if (r != row1 && !wrapped) out[n++] = '\n';
    }
    out[n] = 0;
    return out;
}

void tm_emu_reset(TMEmu *e) { const uint8_t s[] = "\x1b" "c"; tm_emu_feed(e, s, 2); }

// ---------- изменение размера с переносом строк ----------
typedef struct { TMCell *cells; int len; } Logical;

void tm_emu_resize(TMEmu *e, int cols, int rows) {
    if (cols < 1) cols = 1; if (rows < 1) rows = 1;
    if (cols == e->cols && rows == e->rows) return;
    int oc = e->cols, orows = e->rows;
    // альтернативный экран: просто обрезаем/дополняем
    Line **nalt = alloc_screen(cols, rows);
    for (int y = 0; y < rows && y < orows; y++) for (int x = 0; x < cols && x < oc; x++) nalt[y]->cells[x] = e->alt[y]->cells[x];
    for (int i = 0; i < orows; i++) line_free(e->alt[i]);
    free(e->alt); e->alt = nalt;

    if (e->useAlt) {
        // основной экран при активном альтернативном: обрезаем без переноса
        Line **np = alloc_screen(cols, rows);
        for (int y = 0; y < rows && y < orows; y++) for (int x = 0; x < cols && x < oc; x++) np[y]->cells[x] = e->primary[y]->cells[x];
        for (int i = 0; i < orows; i++) line_free(e->primary[i]);
        free(e->primary); e->primary = np;
        // история хранит строки старой ширины — приводим
        for (int i = 0; i < e->sbCount; i++) {
            Line *l = sb_at(e, i); TMCell *nc = malloc(sizeof(TMCell) * (size_t)cols); TMCell z = {0, 0, 0, 0, 0};
            for (int x = 0; x < cols; x++) nc[x] = x < oc ? l->cells[x] : z;
            free(l->cells); l->cells = nc;
        }
        e->screen = e->alt;
        e->cols = cols; e->rows = rows;
        e->cx = e->cx >= cols ? cols - 1 : e->cx; e->cy = e->cy >= rows ? rows - 1 : e->cy;
    } else {
        // собрать логические строки: история + экран; хвост пустых строк ниже курсора отбрасываем
        int total = e->sbCount + orows, lastKeep = e->sbCount + e->cy;
        for (int r = total - 1; r > lastKeep; r--) {
            Line *l = r < e->sbCount ? sb_at(e, r) : e->primary[r - e->sbCount];
            bool empty = true; for (int x = 0; x < oc; x++) if (l->cells[x].ch != 0 || l->cells[x].bg != 0) { empty = false; break; }
            if (!empty) { lastKeep = r; break; }
        }
        int nlog = 0, logCap = 64; Logical *logs = malloc(sizeof(Logical) * (size_t)logCap);
        int curLogical = 0, curOffset = 0;
        TMCell *acc = NULL; int accLen = 0, accCap = 0;
        for (int r = 0; r <= lastKeep; r++) {
            Line *l = r < e->sbCount ? sb_at(e, r) : e->primary[r - e->sbCount];
            int len = oc;
            if (!l->wrapped) { while (len > 0 && l->cells[len - 1].ch == 0 && l->cells[len - 1].bg == 0 && !(l->cells[len - 1].attr & TM_WIDE_CONT)) len--; }
            if (r == e->sbCount + e->cy) { curLogical = nlog; curOffset = accLen + (e->cx < len || len == oc ? e->cx : e->cx); if (len < e->cx + 1 && !l->wrapped) len = e->cx + 1 <= oc ? e->cx + 1 : oc; }
            if (accLen + len > accCap) { accCap = (accLen + len) * 2 + 16; acc = realloc(acc, sizeof(TMCell) * (size_t)accCap); }
            memcpy(acc + accLen, l->cells, sizeof(TMCell) * (size_t)len); accLen += len;
            if (!l->wrapped) {
                if (nlog == logCap) { logCap *= 2; logs = realloc(logs, sizeof(Logical) * (size_t)logCap); }
                logs[nlog].cells = acc; logs[nlog].len = accLen; nlog++; acc = NULL; accLen = 0; accCap = 0;
            }
        }
        if (accLen > 0 || nlog == 0 || (lastKeep >= 0 && 0)) {
            if (nlog == logCap) { logCap *= 2; logs = realloc(logs, sizeof(Logical) * (size_t)logCap); }
            logs[nlog].cells = acc; logs[nlog].len = accLen; nlog++; acc = NULL;
        } else free(acc);
        // новые физические строки
        int outCap = 256, outN = 0; Line **out = malloc(sizeof(Line *) * (size_t)outCap);
        int newCurRow = 0, newCurCol = 0; TMCell z = {0, 0, 0, 0, 0};
        for (int li = 0; li < nlog; li++) {
            Logical *lg = &logs[li]; int pos = 0;
            do {
                int take = lg->len - pos; if (take > cols) take = cols;
                // не разрезаем широкий символ
                if (pos + take < lg->len && take > 0 && (lg->cells[pos + take - 1].attr & TM_WIDE)) take--;
                if (outN == outCap) { outCap *= 2; out = realloc(out, sizeof(Line *) * (size_t)outCap); }
                Line *l = line_new(cols, z);
                if (take > 0) memcpy(l->cells, lg->cells + pos, sizeof(TMCell) * (size_t)take);
                l->wrapped = pos + take < lg->len;
                if (li == curLogical && curOffset >= pos && (curOffset < pos + take || pos + take >= lg->len || (!l->wrapped))) {
                    if (!(curOffset >= pos + take && l->wrapped)) { newCurRow = outN; newCurCol = curOffset - pos; if (newCurCol >= cols) newCurCol = cols - 1; }
                }
                out[outN++] = l; pos += take;
                if (take == 0) break;
            } while (pos < lg->len);
            free(lg->cells);
        }
        free(logs);
        // освободить старые
        for (int i = 0; i < orows; i++) line_free(e->primary[i]);
        free(e->primary);
        for (int i = 0; i < e->sbCount; i++) line_free(sb_at(e, i));
        e->sbCount = 0; e->sbHead = 0;
        // экран — последние rows строк (с учётом курсора)
        int topRow = outN > rows ? outN - rows : 0;
        if (newCurRow < topRow) topRow = newCurRow;
        if (newCurRow >= topRow + rows) topRow = newCurRow - rows + 1;
        e->primary = malloc(sizeof(Line *) * (size_t)rows);
        for (int y = 0; y < rows; y++) { int r = topRow + y; e->primary[y] = r < outN ? out[r] : line_new(cols, z); }
        for (int r = 0; r < topRow; r++) sb_push(e, out[r]);
        for (int r = topRow + rows; r < outN; r++) line_free(out[r]);
        free(out);
        e->screen = e->primary;
        e->cols = cols; e->rows = rows;
        e->cy = newCurRow - topRow; e->cx = newCurCol;
        if (e->cy < 0) e->cy = 0; if (e->cy >= rows) e->cy = rows - 1;
    }
    e->cols = cols; e->rows = rows;
    free(e->tabs); e->tabs = calloc((size_t)cols, sizeof(bool)); set_tabs(e);
    free(e->dirtyRow); e->dirtyRow = calloc((size_t)rows, sizeof(bool));
    e->top = 0; e->bot = rows - 1; e->pending = false;
    clamp_cursor(e);
    mark_all(e);
}
