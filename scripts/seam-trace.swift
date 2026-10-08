// Traces one crossing like a real mouse (6 px every 8 ms) and prints where the pointer is after each step.
// Usage: swift scripts/seam-trace.swift <startX> <startY> <dx per step> [steps]
import AppKit

let a = CommandLine.arguments
var p = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
let step = Double(a[3])!
let steps = a.count > 4 ? Int(a[4])! : 40
let saved = CGEvent(source: nil)!.location
let hid = a.contains("--hid") ? CGEventSource(stateID: .hidSystemState) : nil

func post(_ p: CGPoint, dx: Int64) {
    let e = CGEvent(mouseEventSource: hid, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!
    e.setIntegerValueField(.mouseEventDeltaX, value: dx)
    e.post(tap: .cghidEventTap)
}

post(p, dx: 0)
usleep(200_000)
let start = Date()
for i in 0..<steps {
    let now = CGEvent(source: nil)!.location
    p = CGPoint(x: now.x + step, y: now.y)
    post(p, dx: Int64(step))
    usleep(8_000)
    let after = CGEvent(source: nil)!.location
    print(String(format: "%3d t=%4.0fms asked x=%7.1f -> at (%7.1f, %7.1f)", i, Date().timeIntervalSince(start) * 1000, p.x, after.x, after.y))
}
usleep(300_000)
CGWarpMouseCursorPosition(saved)
