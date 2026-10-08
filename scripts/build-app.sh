#!/bin/sh
# Builds build/DockPin.app (release). Usage: scripts/build-app.sh [--install]
#   --install            also copy it to ~/Applications and (re)start it.
# Env:
#   DOCKPIN_IDENTITY     codesign identity (default "-": ad-hoc, for local use only)
#   DOCKPIN_UNIVERSAL=1  build for arm64 and x86_64
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/build/DockPin.app"
identity="${DOCKPIN_IDENTITY:--}"

if [ "${DOCKPIN_UNIVERSAL:-0}" = 1 ]; then
    swift build -c release --arch arm64 --arch x86_64 --package-path "$root"
    binary="$root/.build/apple/Products/Release/DockPin"
else
    swift build -c release --package-path "$root"
    binary="$root/.build/release/DockPin"
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/DockPin"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$root/Resources/MenuBarIcon.png" "$root/Resources/MenuBarIcon@2x.png" "$app/Contents/Resources/"

if [ "$identity" = "-" ]; then
    codesign --force --options runtime --sign - "$app"
else
    codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
codesign --verify --strict "$app"
echo "built $app (signed by: $identity)"

if [ "${1:-}" = "--install" ]; then
    pkill -x DockPin && sleep 2 || true
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/DockPin.app"
    cp -R "$app" "$HOME/Applications/DockPin.app"
    open "$HOME/Applications/DockPin.app"
    echo "installed and started ~/Applications/DockPin.app"
fi
