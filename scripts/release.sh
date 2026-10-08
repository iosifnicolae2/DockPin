#!/bin/sh
# Builds a signed, notarized, stapled dist/DockPin-<version>.zip (+ .sha256) ready to attach to a GitHub release,
# plus dist/DockPin.zip, the same file under a stable name so .../releases/latest/download/DockPin.zip always works.
# Usage: scripts/release.sh            (version = CFBundleShortVersionString in Resources/Info.plist)
# Needs, in the keychain (never in this repo):
#   - a "Developer ID Application" certificate (DOCKPIN_IDENTITY overrides which one)
#   - a notarytool profile (DOCKPIN_NOTARY_PROFILE, default "DockPin-notary"), made once with:
#       xcrun notarytool store-credentials DockPin-notary --key <AuthKey.p8> --key-id <key id> --issuer <issuer id>
#     (an App Store Connect Team API key; an Apple ID + app-specific password works too)
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$root/Resources/Info.plist")
profile="${DOCKPIN_NOTARY_PROFILE:-DockPin-notary}"
identity="${DOCKPIN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
[ -n "$identity" ] || { echo "no Developer ID Application certificate in the keychain" >&2; exit 1; }

dist="$root/dist"
zip="$dist/DockPin-$version.zip"
mkdir -p "$dist"
rm -f "$zip" "$zip.sha256" "$dist/DockPin.zip"

DOCKPIN_IDENTITY="$identity" DOCKPIN_UNIVERSAL=1 "$root/scripts/build-app.sh"
app="$root/build/DockPin.app"

echo "notarizing (profile $profile)..."
ditto -c -k --keepParent "$app" "$dist/notarize.zip"
xcrun notarytool submit "$dist/notarize.zip" --keychain-profile "$profile" --wait
rm -f "$dist/notarize.zip"
xcrun stapler staple "$app"

spctl --assess --type execute --verbose=2 "$app"
ditto -c -k --keepParent "$app" "$zip"
(cd "$dist" && shasum -a 256 "DockPin-$version.zip" > "DockPin-$version.zip.sha256")
cp "$zip" "$dist/DockPin.zip"
echo "release ready: $zip (and $dist/DockPin.zip)"
