#!/bin/sh
# Сборка Terminal (rootless, iphoneos-arm64, iOS 15+): scripts/build.sh [debug]
# debug добавляет отладочные уведомления (снимок экрана, ввод текста) — в релиз не попадает.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MODE=${1:-release}
VER=$(grep '^Version:' layout/DEBIAN/control | cut -d' ' -f2)
OUT="$ROOT/build"; APP="$OUT/pkg/var/jb/Applications/Terminal.app"
rm -rf "$OUT"; mkdir -p "$APP"
CC="xcrun -sdk iphoneos clang -arch arm64 -miphoneos-version-min=15.0 -fobjc-arc -O2 -Wall -Wno-unguarded-availability-new -Wno-deprecated-declarations"
[ "$MODE" = debug ] && CC="$CC -DTM_DEBUG"
$CC -IEmulator Sources/*.m Emulator/TMEmu.c -framework UIKit -framework CoreText -framework Foundation -framework CoreGraphics -framework QuartzCore -o "$APP/Terminal"
xcrun -sdk iphoneos clang -arch arm64 -miphoneos-version-min=15.0 -O2 -Wall Helper/mtsh.c -o "$APP/mtsh"
ldid -SResources/ent.plist "$APP/Terminal"
ldid -SHelper/ent.plist "$APP/mtsh"
sed "s/@VERSION@/$VER/g" Resources/Info.plist > "$APP/Info.plist"
cp -R Resources/shell Resources/fonts "$APP/"
cp Resources/Icon/AppIcon60x60@2x.png Resources/Icon/AppIcon60x60@3x.png "$APP/"
cp "Resources/Icon/AppIcon76x76@2x~ipad.png" "$APP/"
mkdir -p "$APP/licenses"; cp licenses/* "$APP/licenses/"
cp -R layout/DEBIAN "$OUT/pkg/DEBIAN"
printf 'Icon: file:///var/jb/Applications/Terminal.app/AppIcon60x60@3x.png\n' >> "$OUT/pkg/DEBIAN/control"
find "$OUT/pkg" -name .DS_Store -delete
chmod 4755 "$APP/mtsh"
mkdir -p "$ROOT/packages"
DEB="$ROOT/packages/com.makr.terminal_${VER}${MODE:+_$MODE}_iphoneos-arm64.deb"
[ "$MODE" = release ] && DEB="$ROOT/packages/com.makr.terminal_${VER}_iphoneos-arm64.deb"
dpkg-deb --root-owner-group -Zgzip -b "$OUT/pkg" "$DEB" >/dev/null
echo "Готово: $DEB"
