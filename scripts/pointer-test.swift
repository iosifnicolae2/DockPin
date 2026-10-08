// Functional test on the real displays: drives the pointer with synthetic moves while DockPin runs
// and checks the seam crossings and that the Dock stays on the center display.
// Usage: swift scripts/pointer-test.swift   (needs DockPin running; the calling terminal needs Accessibility)
import AppKit

func move(to p: CGPoint, dx: Int64 = 0, dy: Int64 = 0) {
    let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!
    e.setIntegerValueField(.mouseEventDeltaX, value: dx)
    e.setIntegerValueField(.mouseEventDeltaY, value: dy)
    e.post(tap: .cghidEventTap)
    usleep(30_000)
}

var cursor: CGPoint { CGEvent(source: nil)!.location }

func dockFrame() -> CGRect? {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[String: Any]]
    let dock = windows.first { $0["kCGWindowOwnerName"] as? String == "Dock" && $0["kCGWindowLayer"] as? Int == 20 }
    return (dock?["kCGWindowBounds"] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
}

func screen(named name: String) -> CGRect {
    let s = NSScreen.screens.first { $0.localizedName == name }!
    return CGDisplayBounds(s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID)
}

/// Pushes the pointer leftwards against the left edge of `frame` at height `y`, like a user would.
func pushLeft(on frame: CGRect, y: CGFloat, times: Int) {
    move(to: CGPoint(x: frame.minX + 40, y: y))
    for _ in 0..<times { move(to: CGPoint(x: cursor.x - 6, y: y), dx: -6) }
}

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "PASS" : "FAIL", what)
    if !ok { failures += 1 }
}

let saved = cursor
let center = screen(named: CommandLine.arguments.dropFirst().first ?? "Odyssey G81SF")
let dockAtStart = dockFrame()
check(dockAtStart?.minX == center.minX, "Dock starts on the center display (\(dockAtStart.map { "\($0)" } ?? "none"))")

pushLeft(on: center, y: center.midY, times: 12)
check(cursor.x < center.minX, "leaving the center leftwards lands left of it: \(cursor)")
let onLeft = cursor
check(NSScreen.screens.contains { CGDisplayBounds($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID).contains(onLeft) }, "landing point is on a display")

for _ in 0..<12 { move(to: CGPoint(x: cursor.x + 6, y: cursor.y), dx: 6) }
check(center.contains(cursor) && abs(cursor.y - center.midY) < 2, "coming back rightwards returns at the same height: \(cursor)")

for s in NSScreen.screens {
    let frame = CGDisplayBounds(s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID)
    guard frame != center else { continue }
    pushLeft(on: frame, y: frame.midY, times: 60)
    usleep(800_000)
    check(dockFrame()?.minX == center.minX, "Dock stays on the center after pushing at \(s.localizedName)'s left edge (pointer \(cursor))")
}

move(to: saved)
print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
