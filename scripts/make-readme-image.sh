#!/bin/sh
# Draws docs/dockpin-screens.png, the README picture: a macOS desktop on three monitors and a laptop, the Dock on
# the center one. It is a rendering (scripts/readme-image/page.html in headless Chrome at 2x), not a screenshot, so
# nothing personal is in it. App icons and SF Symbols come from this Mac and are never committed.
# Usage: scripts/make-readme-image.sh   (needs Google Chrome and Xcode's swift)
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
work=$(mktemp -d)
trap 'rm -rf "$work" 2>/dev/null || true' EXIT

cp "$root/scripts/readme-image/page.html" "$work/"
swift "$root/scripts/readme-image/assets.swift" "$work/assets" >/dev/null
cp "/System/Library/CoreServices/Dock.app/Contents/Resources/trashempty2@2x.png" "$work/assets/Trash.png"
cp "$root/Resources/MenuBarIcon@2x.png" "$work/assets/"

out="$root/docs/dockpin-screens.png"
rm -f "$out"
# Headless Chrome can linger after writing the file, so it is stopped once the picture exists.
"$chrome" --headless=new --user-data-dir="$work/profile" --hide-scrollbars --default-background-color=00000000 \
    --force-device-scale-factor=2 --window-size=1600,740 --allow-file-access-from-files \
    --virtual-time-budget=3000 --screenshot="$out" "file://$work/page.html" >/dev/null 2>&1 &
pid=$!
for _ in $(seq 60); do [ -s "$out" ] && break; sleep 1; done
sleep 1
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
[ -s "$out" ] || { echo "Chrome wrote no picture" >&2; exit 1; }
echo "wrote docs/dockpin-screens.png"
