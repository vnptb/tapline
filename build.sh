#!/bin/bash
# Builds the app, installs it into /Applications and opens it.
#   ./build.sh                build, install, open
#   ./build.sh --no-install   build into ./build only
set -euo pipefail
cd "$(dirname "$0")"

NAME="Tapline"
BUILD="build"
APP="$BUILD/$NAME.app"

rm -rf "$APP"
mkdir -p "$BUILD/obj" "$APP/Contents/MacOS" "$APP/Contents/Resources"

for c in Sources/CUSB/*.c; do
    clang -O2 -Wall -Wno-deprecated-declarations -c "$c" -o "$BUILD/obj/$(basename "${c%.c}").o"
done

swiftc -O -parse-as-library \
    -import-objc-header Sources/CUSB/bridge.h \
    Sources/App/*.swift "$BUILD"/obj/*.o \
    -framework IOKit -framework Cocoa -framework SwiftUI -framework ServiceManagement -framework Carbon \
    -o "$APP/Contents/MacOS/$NAME"

cp Info.plist "$APP/Contents/Info.plist"
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
# Ad hoc by default. With SIGN_IDENTITY set to a code-signing certificate (even a self-signed one),
# macOS keeps the Accessibility permission across rebuilds.
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"

if [ "${1:-}" != "--no-install" ]; then
    pkill -x "$NAME" 2>/dev/null || true
    rm -rf "/Applications/$NAME.app"
    cp -R "$APP" "/Applications/$NAME.app"
    echo "Installed: /Applications/$NAME.app"
    open "/Applications/$NAME.app"
else
    echo "Built: $APP"
fi
