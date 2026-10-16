// Проверки эмулятора на Mac: Tests/run.sh
#include "../Emulator/TMEmu.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int fails, checks;
static char resp[4096]; static size_t respLen;
static void on_write(void *c, const uint8_t *d, size_t n) { if (respLen + n < sizeof resp) { memcpy(resp + respLen, d, n); respLen += n; resp[respLen] = 0; } }
static int bells, modesCalls; static char title[256];
static void on_bell(void *c) { bells++; }
static void on_modes(void *c) { modesCalls++; }
static void on_title(void *c, const char *t) { snprintf(title, sizeof title, "%s", t); }

static TMEmu *mk(int cols, int rows) {
    TMEmuCallbacks cb = {NULL, on_write, on_title, on_bell, on_modes, NULL, NULL};
    respLen = 0; resp[0] = 0;
    return tm_emu_new(cols, rows, 100, cb);
}
static void feed(TMEmu *e, const char *s) { tm_emu_feed(e, (const uint8_t *)s, strlen(s)); }

static void row_text(TMEmu *e, int screenRow, char *out, size_t cap) {
    int sbn = tm_emu_scrollback_count(e);
    char *t = tm_emu_text(e, sbn + screenRow, 0, sbn + screenRow, tm_emu_cols(e) - 1);
    snprintf(out, cap, "%s", t); free(t);
}
static void expect_row(TMEmu *e, int r, const char *want, const char *what) {
    char got[512]; row_text(e, r, got, sizeof got); checks++;
    if (strcmp(got, want) != 0) { fails++; printf("FAIL %s: row %d = \"%s\", want \"%s\"\n", what, r, got, want); }
}
static void expect_int(int got, int want, const char *what) { checks++; if (got != want) { fails++; printf("FAIL %s: got %d, want %d\n", what, got, want); } }
static void expect_str(const char *got, const char *want, const char *what) { checks++; if (strcmp(got, want) != 0) { fails++; printf("FAIL %s: got \"%s\", want \"%s\"\n", what, got, want); } }
static void dump(TMEmu *e) { for (int r = 0; r < tm_emu_rows(e); r++) { char b[512]; row_text(e, r, b, sizeof b); printf("  |%s\n", b); } }

int main(void) {
    TMEmu *e;
    // 1. печать, переводы строк, перенос
    e = mk(10, 4); feed(e, "hello\r\nworld"); expect_row(e, 0, "hello", "print1"); expect_row(e, 1, "world", "print2");
    expect_int(tm_emu_cursor_x(e), 5, "cursor x"); expect_int(tm_emu_cursor_y(e), 1, "cursor y"); tm_emu_free(e);
    e = mk(5, 3); feed(e, "abcdefgh"); expect_row(e, 0, "abcdeabcde"[0] ? "abcde" : "", "wrap row0"); expect_row(e, 1, "fgh", "wrap row1"); tm_emu_free(e);
    e = mk(5, 3); feed(e, "abcde"); expect_int(tm_emu_cursor_x(e), 4, "deferred wrap x"); feed(e, "f"); expect_row(e, 1, "f", "deferred wrap char"); tm_emu_free(e);
    // 2. прокрутка и история
    e = mk(6, 3); feed(e, "1\r\n2\r\n3\r\n4\r\n5"); expect_row(e, 0, "3", "scroll r0"); expect_row(e, 2, "5", "scroll r2"); expect_int(tm_emu_scrollback_count(e), 2, "scrollback count");
    char *t = tm_emu_text(e, 0, 0, 1, 5); expect_str(t, "1\n2", "scrollback text"); free(t); tm_emu_free(e);
    // 3. курсор, стирание
    e = mk(10, 4); feed(e, "aaaaaaaaaa\r\nbbbbbbbbbb\r\ncccccccccc"); feed(e, "\x1b[2;4H"); feed(e, "\x1b[K"); expect_row(e, 1, "bbb", "EL0");
    feed(e, "\x1b[1;1H\x1b[1K"); expect_row(e, 0, "  aaaaaaaa"[0] ? " aaaaaaaaa" : "", "EL1 (cursor col1)"); tm_emu_free(e);
    e = mk(10, 3); feed(e, "xxxxxxxxxx\r\nyyyyyyyyyy"); feed(e, "\x1b[2J"); expect_row(e, 0, "", "ED2 r0"); expect_row(e, 1, "", "ED2 r1"); tm_emu_free(e);
    // 4. SGR
    e = mk(10, 2); feed(e, "\x1b[1;31mA\x1b[0mB\x1b[38;5;200mC\x1b[48;2;1;2;3mD\x1b[39;49mE");
    { bool w; const TMCell *c = tm_emu_line(e, 0, &w);
      expect_int((c[0].attr & TM_BOLD) != 0, 1, "bold"); expect_int((int)c[0].fg, (int)TM_COLOR_INDEXED(1), "fg red"); expect_int(c[1].attr, 0, "reset attr"); expect_int((int)c[1].fg, 0, "reset fg");
      expect_int((int)c[2].fg, (int)TM_COLOR_INDEXED(200), "256 color"); expect_int((int)c[3].bg, (int)TM_COLOR_RGB(1, 2, 3), "rgb bg"); expect_int((int)c[4].bg, 0, "default bg"); }
    feed(e, "\x1b[38:2::10:20:30mF"); { bool w; const TMCell *c = tm_emu_line(e, 0, &w); expect_int((int)c[5].fg, (int)TM_COLOR_RGB(10, 20, 30), "colon rgb"); }
    tm_emu_free(e);
    // 5. область прокрутки, IL/DL
    e = mk(5, 5); feed(e, "1\r\n2\r\n3\r\n4\r\n5"); feed(e, "\x1b[2;4r"); feed(e, "\x1b[4;1H\n"); expect_row(e, 0, "1", "region keeps top"); expect_row(e, 1, "3", "region scrolled"); expect_row(e, 3, "", "region new line"); expect_row(e, 4, "5", "region keeps bottom");
    feed(e, "\x1b[2;1H\x1b[L"); expect_row(e, 1, "", "IL blank"); expect_row(e, 2, "3", "IL shift"); feed(e, "\x1b[M"); expect_row(e, 1, "3", "DL"); tm_emu_free(e);
    // 6. UTF-8 и широкие символы
    e = mk(10, 2); feed(e, "\xd0\x9f\xd1\x80\xd0\xb8\xd0\xb2\xd0\xb5\xd1\x82"); expect_row(e, 0, "Привет", "cyrillic");
    feed(e, "\r\n\xe4\xbd\xa0\xe5\xa5\xbd" "A"); expect_row(e, 1, "你好A", "wide"); expect_int(tm_emu_cursor_x(e), 5, "wide cursor"); tm_emu_free(e);
    e = mk(10, 2); feed(e, "\xff\xfe" "ok"); expect_row(e, 0, "ok", "invalid utf8 ignored"); tm_emu_free(e);
    // 7. альтернативный экран
    e = mk(10, 3); feed(e, "main"); feed(e, "\x1b[?1049h"); expect_int(tm_emu_alt_screen(e), 1, "alt on"); expect_row(e, 0, "", "alt clean"); feed(e, "alt!"); feed(e, "\x1b[?1049l"); expect_row(e, 0, "main", "alt restore"); expect_int(tm_emu_cursor_x(e), 4, "cursor restored"); tm_emu_free(e);
    // 8. табуляция, backspace, CR
    e = mk(20, 2); feed(e, "a\tb\tc"); expect_row(e, 0, "a       b       c", "tabs"); feed(e, "\rXY"); expect_row(e, 0, "XY      b       c", "CR overwrite"); tm_emu_free(e);
    // 9. ответы
    e = mk(10, 5); feed(e, "\x1b[3;4H\x1b[6n"); expect_str(resp, "\x1b[3;4R", "CPR"); respLen = 0; resp[0] = 0;
    feed(e, "\x1b[c"); expect_str(resp, "\x1b[?62;22c", "DA1"); respLen = 0; resp[0] = 0; feed(e, "\x1b[18t"); expect_str(resp, "\x1b[8;5;10t", "size report"); tm_emu_free(e);
    // 10. режимы и мышь
    e = mk(10, 3); feed(e, "\x1b[?1h\x1b[?2004h\x1b[?1000h\x1b[?1006h"); expect_int(tm_emu_app_cursor(e), 1, "appcursor"); expect_int(tm_emu_bracketed_paste(e), 1, "bracketed"); expect_int(tm_emu_mouse_mode(e), 1000, "mouse");
    { uint8_t b[64]; size_t n = tm_emu_encode_mouse(e, 0, 4, 2, 0, false, false, b, sizeof b); b[n] = 0; expect_str((char *)b, "\x1b[<0;5;3M", "sgr mouse"); n = tm_emu_encode_mouse(e, 0, 4, 2, 0, false, true, b, sizeof b); b[n] = 0; expect_str((char *)b, "\x1b[<0;5;3m", "sgr release"); }
    feed(e, "\x1b[?1006l"); { uint8_t b[64]; size_t n = tm_emu_encode_mouse(e, 0, 0, 0, 0, false, false, b, sizeof b); b[n] = 0; expect_str((char *)b, "\x1b[M !!", "x10 mouse"); } tm_emu_free(e);
    // 11. заголовок, звонок
    e = mk(10, 2); feed(e, "\x1b]0;My Title\x07"); expect_str(title, "My Title", "osc title bel"); feed(e, "\x1b]2;Second\x1b\\"); expect_str(title, "Second", "osc title st"); feed(e, "\a"); expect_int(bells, 1, "bell"); tm_emu_free(e);
    // 12. вставка/удаление символов, REP, ECH
    e = mk(10, 2); feed(e, "abcdef\x1b[1;3H\x1b[2@"); expect_row(e, 0, "ab  cdef", "ICH"); feed(e, "\x1b[2P"); expect_row(e, 0, "abcdef", "DCH"); feed(e, "\x1b[1;1H\x1b[3X"); expect_row(e, 0, "   def", "ECH");
    feed(e, "\x1b[2J\x1b[Hz\x1b[3b"); expect_row(e, 0, "zzzz", "REP"); tm_emu_free(e);
    // 13. DEC-графика
    e = mk(10, 2); feed(e, "\x1b(0lqk\x1b(B"); expect_row(e, 0, "┌─┐", "line drawing"); tm_emu_free(e);
    // 14. сохранение/восстановление курсора, origin mode
    e = mk(10, 5); feed(e, "\x1b[2;3H\x1b" "7\x1b[5;5H\x1b" "8"); expect_int(tm_emu_cursor_x(e), 2, "DECRC x"); expect_int(tm_emu_cursor_y(e), 1, "DECRC y");
    feed(e, "\x1b[2;4r\x1b[?6h\x1b[1;1H"); expect_int(tm_emu_cursor_y(e), 1, "origin mode"); tm_emu_free(e);
    // 15. перенос строк при изменении ширины
    e = mk(10, 4); feed(e, "0123456789ABCDE"); tm_emu_resize(e, 5, 4);
    expect_row(e, 0, "01234", "reflow narrow 0"); expect_row(e, 1, "56789", "reflow narrow 1"); expect_row(e, 2, "ABCDE", "reflow narrow 2");
    tm_emu_resize(e, 15, 4); expect_row(e, 0, "0123456789ABCDE", "reflow wide"); tm_emu_free(e);
    e = mk(10, 3); feed(e, "line1\r\nline2\r\nline3\r\nline4"); tm_emu_resize(e, 10, 5); expect_row(e, 3, "line4", "grow rows keeps order");
    { int cy = tm_emu_cursor_y(e); expect_int(cy, 3, "cursor after grow"); }
    tm_emu_resize(e, 10, 2); expect_row(e, 1, "line4", "shrink rows"); tm_emu_free(e);
    // 16. очистка истории, Ctrl-L поведение
    e = mk(5, 2); feed(e, "a\r\nb\r\nc\r\nd"); feed(e, "\x1b[3J"); expect_int(tm_emu_scrollback_count(e), 0, "ED3"); tm_emu_free(e);
    // 17. длинный вывод и производительность
    e = mk(80, 24); for (int i = 0; i < 20000; i++) feed(e, "The quick brown fox jumps over the lazy dog 0123456789 \x1b[1;32mgreen\x1b[0m text\r\n"); expect_int(tm_emu_scrollback_count(e) <= 100, 1, "scrollback cap"); tm_emu_free(e);

    printf("%d проверок, %d ошибок\n", checks, fails);
    return fails ? 1 : 0;
}
