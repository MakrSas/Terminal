#!/bin/sh
# Сборка и запуск проверок эмулятора на Mac
set -e
cd "$(dirname "$0")"
mkdir -p ../build
clang -O1 -g -fsanitize=address,undefined -Wall -Wextra -Wno-unused-parameter -Wno-misleading-indentation ../Emulator/TMEmu.c emu_test.c -o ../build/emu_test
../build/emu_test
