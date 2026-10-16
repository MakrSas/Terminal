// Эмулятор терминала VT/xterm: разбор потока байт, экранные буферы, история, режимы.
// Чистый C без зависимостей от UIKit — проверяется тестами на Mac (Tests/emu_test.c).
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

// Цвет: 0 — по умолчанию (цвет темы); 0x01000000|i — палитра 0…255; 0x02000000|0xRRGGBB — полноцветный
typedef uint32_t TMColor;
#define TM_COLOR_DEFAULT 0u
#define TM_COLOR_INDEXED(i) (0x01000000u | (uint32_t)(i))
#define TM_COLOR_RGB(r, g, b) (0x02000000u | ((uint32_t)(r) << 16) | ((uint32_t)(g) << 8) | (uint32_t)(b))
static inline bool tm_color_is_indexed(TMColor c) { return (c >> 24) == 1; }
static inline bool tm_color_is_rgb(TMColor c) { return (c >> 24) == 2; }

enum {
    TM_BOLD = 1 << 0, TM_DIM = 1 << 1, TM_ITALIC = 1 << 2, TM_UNDERLINE = 1 << 3, TM_BLINK = 1 << 4, TM_INVERSE = 1 << 5,
    TM_INVISIBLE = 1 << 6, TM_STRIKE = 1 << 7, TM_WIDE = 1 << 8, TM_WIDE_CONT = 1 << 9, TM_DOUBLE_UL = 1 << 10, TM_CURLY_UL = 1 << 11
};

typedef struct { uint32_t ch; TMColor fg, bg; uint16_t attr; uint16_t pad; } TMCell;   // ch == 0 — пустая ячейка

typedef struct TMEmu TMEmu;

typedef struct {
    void *ctx;
    void (*write)(void *ctx, const uint8_t *data, size_t len);   // ответы терминала (позиция курсора, DA и т. п.)
    void (*title)(void *ctx, const char *title);
    void (*bell)(void *ctx);
    void (*modes)(void *ctx);                                    // изменились режимы (мышь, курсорные клавиши, альтернативный экран…)
    void (*cwd)(void *ctx, const char *uri);
    void (*clipboard)(void *ctx, const char *text);              // OSC 52: установить буфер обмена
} TMEmuCallbacks;

typedef enum { TM_MOUSE_NONE = 0, TM_MOUSE_X10 = 9, TM_MOUSE_NORMAL = 1000, TM_MOUSE_BUTTON = 1002, TM_MOUSE_ANY = 1003 } TMMouseMode;

TMEmu *tm_emu_new(int cols, int rows, int scrollback, TMEmuCallbacks cb);
void tm_emu_free(TMEmu *e);
void tm_emu_feed(TMEmu *e, const uint8_t *data, size_t len);
void tm_emu_resize(TMEmu *e, int cols, int rows);
void tm_emu_set_scrollback(TMEmu *e, int lines);
void tm_emu_reset(TMEmu *e);

int tm_emu_cols(const TMEmu *e);
int tm_emu_rows(const TMEmu *e);
// Строки с учётом истории: 0 … total-1; последние rows — экран. Для пустых мест — NULL не возвращается.
int tm_emu_total_lines(const TMEmu *e);
const TMCell *tm_emu_line(const TMEmu *e, int absRow, bool *wrapped);
int tm_emu_scrollback_count(const TMEmu *e);

// Курсор (координаты экрана)
int tm_emu_cursor_x(const TMEmu *e);
int tm_emu_cursor_y(const TMEmu *e);
bool tm_emu_cursor_visible(const TMEmu *e);
int tm_emu_cursor_style(const TMEmu *e);       // 0/1 блок, 2/3 подчёркивание, 4/5 линия (DECSCUSR); чётные мигают… 0 — по умолчанию
bool tm_emu_cursor_blink(const TMEmu *e);

// Режимы, нужные приложению
bool tm_emu_app_cursor(const TMEmu *e);
bool tm_emu_app_keypad(const TMEmu *e);
bool tm_emu_bracketed_paste(const TMEmu *e);
bool tm_emu_alt_screen(const TMEmu *e);
bool tm_emu_reverse_video(const TMEmu *e);
bool tm_emu_focus_events(const TMEmu *e);
bool tm_emu_alt_scroll(const TMEmu *e);
TMMouseMode tm_emu_mouse_mode(const TMEmu *e);
// Кодирует событие мыши по текущему режиму/кодировке. button: 0/1/2 — кнопки, 3 — отпускание, 64/65 — колесо вверх/вниз;
// mods: 4 shift, 8 alt, 16 ctrl; motion: движение с нажатой кнопкой. x, y — ячейка с нуля. Возвращает длину (0 — не нужно слать).
size_t tm_emu_encode_mouse(const TMEmu *e, int button, int x, int y, int mods, bool motion, bool release, uint8_t *out, size_t cap);

// Метки изменений: диапазон изменённых строк экрана с прошлого вызова (false — ничего не менялось); all — нужна полная перерисовка
bool tm_emu_take_dirty(TMEmu *e, int *firstRow, int *lastRow, bool *all);

// Текст диапазона (абсолютные строки/колонки, включительно) для копирования; вызывающий освобождает через free()
char *tm_emu_text(const TMEmu *e, int row0, int col0, int row1, int col1);
const char *tm_emu_title(const TMEmu *e);

// Ширина символа в ячейках: 0, 1 или 2
int tm_wcwidth(uint32_t cp);

// Цвета темы — только чтобы отвечать на запросы OSC 10/11 (0xRRGGBB)
void tm_emu_set_default_colors(TMEmu *e, uint32_t fg, uint32_t bg);
