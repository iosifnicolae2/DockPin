#!/bin/sh
# Builds the DockPin icon: writes Resources/AppIcon.icon (scripts/make-icon.py), compiles it with Xcode's actool into
# Resources/Assets.car (Liquid Glass, macOS 26+) and Resources/AppIcon.icns (older macOS), and saves how macOS draws
# it as Resources/AppIcon-preview.png for the README. The compiled files are committed, so builds need no Xcode 26.
# Usage: scripts/make-icon.sh   (needs Xcode 26+ and Pillow)
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
res="$root/Resources"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

python3 "$root/scripts/make-icon.py"
xcrun actool "$res/AppIcon.icon" --compile "$work" --platform macosx --minimum-deployment-target 14.0 \
    --app-icon AppIcon --output-partial-info-plist "$work/partial.plist" >/dev/null
cp "$work/Assets.car" "$work/AppIcon.icns" "$res/"

# A throwaway bundle with a unique id, so macOS draws the fresh icon rather than a cached one.
probe="$work/IconPreview.app"
mkdir -p "$probe/Contents/MacOS" "$probe/Contents/Resources"
cp "$res/Assets.car" "$res/AppIcon.icns" "$probe/Contents/Resources/"
cp /usr/bin/true "$probe/Contents/MacOS/IconPreview"
cat > "$probe/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>io.bringes.DockPin.iconpreview.$(date +%s)</string>
    <key>CFBundleExecutable</key><string>IconPreview</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
EOF
swift "$root/scripts/icon-preview.swift" "$probe" "$res/AppIcon-preview.png" 512
echo "wrote Resources/Assets.car, AppIcon.icns, AppIcon-preview.png"
