# Terminal

> ⚠️ **Vibe-coded / Вайбкод.** This project was written almost entirely by an AI assistant (Claude) with a human only testing and steering it. It is not audited and may have bugs. Root tabs run a shell as the superuser — use at your own risk.
> Проект почти целиком написан ИИ-ассистентом (Claude), человек его только тестировал и направлял. Код не аудирован, возможны ошибки. Вкладки root запускают оболочку от суперпользователя — на свой страх и риск.

A fast native terminal for jailbroken iOS 15–16 (rootless, tested on iPhone 8 / iOS 16.7.16, Dopamine).
Быстрый нативный терминал для джейлбрейка iOS 15–16 (rootless).

- **Root tabs.** Long-press **+** → *New root tab* (or enable "New tabs as root" in settings). Root tabs are marked with a red **#**.
- Own VT/xterm emulator in C (`Emulator/`, tested on Mac): 256 and true colours, alternate screen, scroll regions, mouse reporting, bracketed paste, wide characters and emoji, line drawing, reflow on rotation.
- Core Text renderer: JetBrains Mono (bundled, OFL), SF Mono, Menlo; box-drawing and block characters are drawn pixel-exact.
- Tabs, key bar (Esc, Tab, sticky Ctrl/Alt, arrows with auto-repeat, symbols, F1–F12), hardware keyboard shortcuts (⌘T, ⌘W, ⌘K, ⌘1…9, ⌘+/−), pinch to zoom, selection (long-press, double/triple tap), copy/paste.
- 10 colour themes, cursor styles, scrollback size, haptic bell. Interface in English and Russian.

## How root works
`mtsh` (a small setuid-root helper in the app bundle) starts the shell on a pseudo-terminal. It refuses to give root to anyone but this app (it checks the parent process path), and drops privileges for normal tabs.

## Build
Xcode (iPhoneOS SDK), `ldid`, `dpkg`:
```sh
scripts/build.sh            # → packages/com.makr.terminal_<version>_iphoneos-arm64.deb
scripts/build.sh debug      # adds debug notifications (screenshot, text input) — never ship this
Tests/run.sh                # emulator tests on Mac (clang + sanitizers)
```

## Icon
The icon is the macOS Terminal icon (© Apple), reframed as a full-bleed square for iOS. It is not part of the open-source licence of this project; replace `Resources/Icon/*.png` to use your own.

## Licences
JetBrains Mono — SIL OFL 1.1 (`licenses/`).
