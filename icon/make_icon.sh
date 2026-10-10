#!/bin/bash
# Собирает icon/AppIcon.icns из icon/icon.svg.
# Если есть icon/small/icon.svg — он используется для слотов 16 и 32 px (упрощённый вариант для мелких размеров).
set -euo pipefail
cd "$(dirname "$0")"

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

swiftc -O svg2png.swift -o "$BUILD/svg2png"
SET="$BUILD/AppIcon.iconset"
mkdir -p "$SET"

SMALL=icon.svg
[ -f small/icon.svg ] && SMALL=small/icon.svg

render() { "$BUILD/svg2png" "$1" "$SET/$2" "$3" >/dev/null; }
render "$SMALL" icon_16x16.png 16
render "$SMALL" icon_16x16@2x.png 32
render "$SMALL" icon_32x32.png 32
render icon.svg icon_32x32@2x.png 64
render icon.svg icon_128x128.png 128
render icon.svg icon_128x128@2x.png 256
render icon.svg icon_256x256.png 256
render icon.svg icon_256x256@2x.png 512
render icon.svg icon_512x512.png 512
render icon.svg icon_512x512@2x.png 1024

iconutil -c icns "$SET" -o AppIcon.icns
echo "Готово: $(pwd)/AppIcon.icns"
