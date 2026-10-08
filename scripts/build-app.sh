#!/bin/sh
# Builds build/DockPin.app (release, ad-hoc signed). Usage: scripts/build-app.sh [--install]
#   --install  also copies it to ~/Applications and (re)starts it.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/build/DockPin.app"

swift build -c release --package-path "$root"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$root/.build/release/DockPin" "$app/Contents/MacOS/DockPin"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "built $app"

if [ "${1:-}" = "--install" ]; then
    pkill -x DockPin && sleep 2 || true
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/DockPin.app"
    cp -R "$app" "$HOME/Applications/DockPin.app"
    open "$HOME/Applications/DockPin.app"
    echo "installed and started ~/Applications/DockPin.app"
fi
