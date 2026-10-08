# How DockPin works

What DockPin does under the hood, why it needs Accessibility, what it costs and its trade-offs.
Open it when you want the details behind the [README](../README.md), or before changing the pointer code.

## Moving the Dock to the center

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
   edge until it no longer does (it keeps a 96 pt overlap on the next edge, the "bridge", see below).
   macOS then moves the Dock to the center by itself.
2. Replays every pointer move in your real arrangement, so crossing a moved border lands exactly
   where the real border leads, at the same height, and nothing crosses where your real displays
   don't share an edge (not even at a corner where they only touch).
3. Keeps the pointer one point away from the other displays' Dock edges, so the Dock can't be
   pulled away.
4. Does it again after displays change, wake, or a change of the Dock's position.

The pointer behaves on every edge of every display as in your System Settings arrangement: a test
checks each edge, corners included, for every Dock position (`EdgeAuditTests`).

## Why Accessibility

With it, DockPin handles each pointer move inside the same input event (an event tap), before macOS
draws the pointer or tells any app, and moves the pointer by posting an event of its own. That keeps
macOS's own idea of the pointer in step: moving it any other way (a "warp") makes macOS catch up
later in one big jump across the moved display, which can pull the pointer to the wrong spot and
which macOS's shake-to-locate takes for a shake (it enlarges the pointer). Dragged windows follow.

Without Accessibility, DockPin watches moves afterwards and warps: no permission, but the pointer
can touch the edge for about a millisecond before it is carried across.

Measured on an M5 Pro:

| Load                                | Pointer delay                  | DockPin CPU      |
|-------------------------------------|--------------------------------|------------------|
| Moving around, 200 moves a second   | 0.1 to 0.3 ms, inside the event | 1.5% of one core |
| Fast crossings, 485 a second, 15 s  | median 0.14 ms, worst under 9 ms, flat | about 10% of one core |
| Idle                                | -                              | 0.003%           |

## Trade-offs

- System Settings > Displays shows the moved arrangement while DockPin runs. To change your
  arrangement, quit DockPin, change it, and open DockPin again.
- The outermost point row or column on the other displays' Dock edges can't be reached.
- Near the bridge (about 128 by 32 pt at the moved display's corner), part of the pointer's arrow
  can show on the center display too: macOS draws the pointer itself and a background app can't
  hide it. Moving the pointer elsewhere instead would put it off its real position.
- Where a moved border cuts the arrow off, DockPin draws the missing piece on the neighbouring
  screen, so the arrow looks whole.
