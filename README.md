<img src="Resources/AppIcon-preview.png" width="128" alt="DockPin icon">

# DockPin

A menu-bar app that keeps the macOS Dock on the center display of your monitors, whether the
Dock sits on the left, bottom or right. Open this to install, use or change it.

## Why an app is needed

macOS only places the Dock on a display whose whole Dock edge borders no other display.
In a row like `LG | Odyssey | PHL`, a left Dock can't sit on the Odyssey because its left edge
touches the LG, even when the Odyssey is the main display. Measured on macOS 27:

| Arrangement (Odyssey main)                | Where the left Dock goes |
|-------------------------------------------|--------------------------|
| LG right next to the Odyssey              | LG                       |
| LG raised 300 px (edge partly free)       | LG                       |
| LG above-left, touching only at a corner  | Odyssey                  |

The same holds for a bottom Dock and a display below, or a right Dock and a display to the right.
No setting changes this (turning off "Displays have separate Spaces" pins the Dock to the main
display, but it still needs a free edge, and it costs separate Spaces and per-display menu bars).

## What DockPin does

1. Picks the center display: the one with a display touching it on both sides
   (or the one named in `defaults write io.bringes.DockPin targetDisplay "<name>"`).
2. Makes it the main display and slides whatever touches its Dock edge along that edge, the
   shorter way, until they only meet at a corner. This is for the login session only
   (`CGConfigureDisplayOrigin` with `.forSession`). The Dock edge is now free, so macOS moves the
   Dock there by itself.
3. Replays every pointer move in your real arrangement and maps it back, so crossing a border
   that was moved lands exactly where the real border leads, and borders that only exist in the
   moved layout don't let the pointer through.
4. Keeps the pointer one pixel away from the other displays' free Dock edges, so the Dock can't
   be pulled away from the center.
5. Does it again after displays change, wake, a user switch, or a change of the Dock's position.
   Quitting puts the real arrangement back.

**Seamless crossings need Accessibility.** With it (menu-bar icon > Make Crossings Seamless),
DockPin corrects each move inside the same input event with an event tap, before anything is
drawn: no stop at the edge, and dragged windows follow. Without it, DockPin uses a passive monitor
(no permission) and moves the pointer right after macOS stopped it at the edge, which can show as
a brief stop.

## Trade-offs

- In System Settings > Displays you see the moved arrangement while DockPin runs. To change the
  arrangement, quit DockPin first, change it, and start DockPin again.
- The outermost pixel row or column on the other displays' free Dock edges can't be reached.

## Build, install, test

```sh
scripts/build-app.sh             # build/DockPin.app (release, ad-hoc signed)
scripts/build-app.sh --install   # also copy to ~/Applications and start it
swift test                       # unit tests for the layout and pointer rules
swift scripts/pointer-test.swift # moves the real pointer: every crossing + the Dock stays put
```

Open at Login: the DockPin menu-bar icon > Open at Login.
Logs: `/usr/bin/log show --last 1h --predicate 'subsystem == "io.bringes.DockPin"'`.

## Release

1. Bump `CFBundleShortVersionString` in `Resources/Info.plist`, add `docs/releases/v<version>.md`.
2. `scripts/audit.sh` must print "no sensitive matches".
3. Push a tag `v<version>`: `.github/workflows/release.yml` tests, signs with Developer ID, notarizes,
   staples and publishes `DockPin-<version>.zip` (+ `.sha256`). Its header lists the secrets it needs.
   Locally, `scripts/release.sh` does the same into `dist/`, using the keychain's Developer ID
   certificate and the `DockPin-notary` notarytool profile.

The icons are drawn by `scripts/make-icon.py` (Pillow); edit it and rerun to change them.

`set-main-display.swift "<name>" [--apply]` makes a display the main one permanently (dry run
without `--apply`); DockPin does this itself for the session, so it's only a manual helper.
