# DockPin

A menu-bar app that keeps a left-side macOS Dock on the center display of a row of monitors.
Open this to install, use or change it.

## Why an app is needed

macOS only places a left Dock on a display whose whole left edge borders no other display.
In a row like `LG | Odyssey | PHL` the center display's left edge touches the LG, so the Dock
always lands on the LG, even when the center display is the main one. Measured on macOS 27:

| Arrangement (Odyssey main)                | Where the left Dock goes |
|-------------------------------------------|--------------------------|
| LG right next to the Odyssey              | LG                       |
| LG raised 300 px (edge partly free)       | LG                       |
| LG above-left, touching only at a corner  | Odyssey                  |

No setting changes this (turning off "Displays have separate Spaces" pins the Dock to the main
display, but it still needs a free edge, and it costs separate Spaces and per-display menu bars).

## What DockPin does

1. Picks the center display: the one with a display touching it on both sides
   (or the one named in `defaults write io.bringes.DockPin targetDisplay "<name>"`).
2. Makes it the main display and lifts every display left of it above its top edge, for this
   login session only (`CGConfigureDisplayOrigin` with `.forSession`). Its left edge is now free,
   so macOS moves the Dock there by itself.
3. Warps the pointer across the now-missing border, so moving between the LG and the center
   display feels like the real arrangement.
4. Keeps the pointer one pixel away from the other displays' free left edges, so the Dock
   can't be pulled away from the center.
5. Does it again after displays change, wake, or a user switch. Quitting puts the real
   arrangement back.

It needs no permissions: it watches pointer movement with a global `NSEvent` monitor and moves
the pointer with `CGWarpMouseCursorPosition`.

## Trade-offs

- In System Settings > Displays you see the lifted arrangement while DockPin runs. To change the
  arrangement, quit DockPin first, change it, and start DockPin again.
- The pointer crosses the LG/center border by a jump, so a window dragged across it can lag a frame.
- The leftmost pixel column of the other displays with a free left edge can't be reached.

## Build, install, test

```sh
scripts/build-app.sh             # build/DockPin.app (release, ad-hoc signed)
scripts/build-app.sh --install   # also copy to ~/Applications and start it
swift test                       # unit tests for the layout and pointer rules
swift scripts/pointer-test.swift # moves the real pointer: seam crossings + Dock stays put
```

Open at Login: the DockPin menu-bar icon > Open at Login.
Logs: `/usr/bin/log show --last 1h --predicate 'subsystem == "io.bringes.DockPin"'`.

`set-main-display.swift "<name>" [--apply]` makes a display the main one permanently (dry run
without `--apply`); DockPin does this itself for the session, so it's only a manual helper.
