<img src="Resources/AppIcon-preview.png" width="128" alt="DockPin icon">

# DockPin

Keeps the macOS Dock on your center monitor.

![Three monitors in a row and a laptop below; the Dock sits on the center monitor](docs/dockpin-screens.png)

With several monitors, macOS puts the Dock wherever it likes and moves it whenever the pointer
lingers at another screen's edge. DockPin keeps it on the monitor in the middle, whether the Dock
sits on the left, the bottom or the right, through sleep, display changes and every login.
It lives in the menu bar.

## Install

1. Download `DockPin-<version>.zip` from Releases, unzip it, and move `DockPin.app` to Applications.
2. Open it. Its icon appears in the menu bar, and it opens at login from then on.
3. macOS asks to give DockPin Accessibility access: allow it in System Settings > Privacy &
   Security > Accessibility. DockPin notices and switches over by itself. It only watches pointer
   movement; it never reads keystrokes, windows or the screen.

From its menu you can pick:

- **Pin Dock To**: the center display (automatic) or any connected monitor.
- **Dock Position**: left, bottom or right (the same setting as in System Settings).

To stop it, choose Quit: your display arrangement goes back to how it was.

## How it works

macOS only puts the Dock on a display whose whole Dock edge touches no other display. On a
center monitor that edge always touches a neighbour, so the Dock can't stay there. Measured with
a left Dock on macOS 27:

| Arrangement (center display is main)       | Where the Dock goes |
|---------------------------------------------|---------------------|
| Left monitor right next to the center one   | left monitor        |
| Left monitor raised 300 px (edge partly free) | left monitor      |
| Left monitor touching only at a corner      | center monitor      |

So DockPin, for the current login session only:

1. Makes the center display the main one, and slides whatever touches its Dock edge along that
   edge until they only meet at a corner. macOS then moves the Dock to the center by itself.
2. Replays every pointer move in your real arrangement, so crossing a moved border lands exactly
   where the real border leads, at the same height and speed.
3. Keeps the pointer one pixel away from the other displays' Dock edges, so the Dock can't be
   pulled away.
4. Does it again after displays change, wake, or a change of the Dock's position.

## Why Accessibility

With it, DockPin corrects each pointer move inside the same input event (an event tap), before
macOS draws the pointer or tells any app, so a moved border feels like any other and dragged
windows follow. Without it, DockPin falls back to watching moves afterwards, which needs no
permission but lets the pointer touch the edge for about a millisecond first. Measured on an
M5 Pro, moving the pointer 200 times a second:

| Mode                     | Correction after the move | CPU while moving    | CPU idle |
|--------------------------|---------------------------|---------------------|----------|
| Accessibility (event tap) | 0.1 to 0.3 ms, within the event | 74 µs a move (1.5% of a core) | 0.003% |
| Without (passive monitor) | about 1 ms (p95 3.8 ms), after the event | 99 to 160 µs a move (2 to 3%) | 0%     |

## Trade-offs

- System Settings > Displays shows the moved arrangement while DockPin runs. To change your
  arrangement, quit DockPin, change it, and open DockPin again.
- The outermost pixel row or column on the other displays' Dock edges can't be reached.

## Develop

```sh
swift test                         # layout and pointer rules
scripts/build-app.sh --install     # build/DockPin.app (ad-hoc signed) into ~/Applications, and start it
swift scripts/pointer-test.swift   # drives the real pointer: every crossing, and the Dock stays put
swift scripts/drag-test.swift DIR  # drags a Finder window across the moved border and back
```

Logs: `/usr/bin/log show --last 1h --predicate 'subsystem == "io.bringes.DockPin"'`.
The icon and the picture above are drawn by `scripts/make-icon.py` and `scripts/make-readme-image.py`.

## Release

1. Bump `CFBundleShortVersionString` in `Resources/Info.plist` and add `docs/releases/v<version>.md`.
2. `scripts/audit.sh` must print "no sensitive matches".
3. Push the tag `v<version>`. `.github/workflows/release.yml` tests, signs with Developer ID,
   notarizes and publishes `DockPin-<version>.zip` with its `.sha256`; its header lists the secrets
   it needs. `scripts/release.sh` does the same locally into `dist/`, using the keychain's
   Developer ID certificate and the `DockPin-notary` notarytool profile.
