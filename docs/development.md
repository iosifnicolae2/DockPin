# Developing DockPin

How to build, test, debug and release DockPin from source.
Open it when you work on the code or cut a release.

## Build and test

```sh
swift test                           # layout, pointer rules, edge audit, replays of real captures
scripts/build-app.sh --install       # build/DockPin.app (ad-hoc signed) into ~/Applications, and start it
swift scripts/pointer-test.swift     # drives the real pointer: every crossing, and the Dock stays put
swift scripts/drag-test.swift DIR    # drags a Finder window across the moved border and back
swift scripts/stress-test.swift 15   # sustained fast crossings: pointer delay and DockPin CPU per second
```

To capture real moves for a bug report: `defaults write io.bringes.DockPin traceMoves -bool YES`,
reproduce, `defaults delete io.bringes.DockPin traceMoves`, then
`python3 scripts/analyze-moves.py ~/Library/Logs/DockPin/moves.log` flags bad crossings.
Logs: `/usr/bin/log show --last 1h --predicate 'subsystem == "io.bringes.DockPin"'`.
The app icon is drawn by `scripts/make-icon.py`, and the README picture by `scripts/make-readme-image.sh`
(a macOS desktop rendered from `scripts/readme-image/page.html`; no screenshot, nothing personal).

## Release

1. Bump `CFBundleShortVersionString` in `Resources/Info.plist` and add `docs/releases/v<version>.md`.
2. `scripts/audit.sh` must print "no sensitive matches".
3. Push the tag `v<version>`. `.github/workflows/release.yml` tests, signs with Developer ID,
   notarizes and publishes `DockPin-<version>.zip` with its `.sha256`, plus the same zip as `DockPin.zip`
   so `releases/latest/download/DockPin.zip` always points to the newest; its header lists the secrets
   it needs. `scripts/release.sh` does the same locally into `dist/`, using the keychain's
   Developer ID certificate and the `DockPin-notary` notarytool profile.
