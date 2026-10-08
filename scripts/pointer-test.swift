// Functional test on the real displays, with DockPin running: drives the pointer with synthetic moves.
// For every display that borders the center one in the REAL arrangement it crosses there and back
// (checking where the pointer lands), and it pushes at every other display's free Dock edge
// (checking the Dock stays on the center display).
// Usage: swift scripts/pointer-test.swift   (the calling terminal needs Accessibility to post events)
import AppKit

// MARK: DockPin's saved plan (mirror of DockPinCore.LayoutPlan)

struct Display: Codable { var uuid: String; var name: String; var frame: CGRect }
struct Plan: Codable { var real: [Display]; var pinned: [Display]; var targetUUID: String; var edge: String }

func liveFrames() -> [String: CGRect] {
    Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { s in
        let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
        return CGDisplayCreateUUIDFromDisplayID(id).map { (CFUUIDCreateString(nil, $0.takeRetainedValue()) as String, CGDisplayBounds(id)) }
    })
}

func activePlan() -> Plan? {
    let live = liveFrames()
    let stored = UserDefaults(suiteName: "io.bringes.DockPin")?.dictionaryRepresentation() ?? [:]
    return stored.filter { $0.key.hasPrefix("plan.") }.compactMap { ($0.value as? Data).flatMap { try? JSONDecoder().decode(Plan.self, from: $0) } }
        .first { p in p.pinned.count == live.count && p.pinned.allSatisfy { live[$0.uuid] == $0.frame } }
}

// MARK: Pointer

var cursor: CGPoint { CGEvent(source: nil)!.location }

/// Hardware moves stop at the display edge; synthetic ones don't, so stop them the same way.
func clampedLikeHardware(_ p: CGPoint) -> CGPoint {
    let frames = Array(liveFrames().values)
    if frames.contains(where: { $0.contains(p) }) { return p }
    guard let f = frames.first(where: { $0.contains(cursor) }) else { return p }
    return CGPoint(x: min(max(p.x, f.minX), f.maxX - 1), y: min(max(p.y, f.minY), f.maxY - 1))
}

func move(by d: CGVector) {
    let p = clampedLikeHardware(CGPoint(x: cursor.x + d.dx, y: cursor.y + d.dy))
    let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!
    e.setIntegerValueField(.mouseEventDeltaX, value: Int64(d.dx))
    e.setIntegerValueField(.mouseEventDeltaY, value: Int64(d.dy))
    e.post(tap: .cghidEventTap)
    usleep(12_000)
    trace(cursor)
}

/// DOCKPIN_TRACE=<file>: append every pointer position, for drawing the path afterwards.
let traceFile = ProcessInfo.processInfo.environment["DOCKPIN_TRACE"].flatMap { path -> FileHandle? in
    FileManager.default.createFile(atPath: path, contents: nil)
    return FileHandle(forWritingAtPath: path)
}
func trace(_ p: CGPoint) { traceFile?.write("\(p.x) \(p.y)\n".data(using: .utf8)!) }

func place(_ p: CGPoint) { CGWarpMouseCursorPosition(p); usleep(300_000); traceFile?.write("jump\n".data(using: .utf8)!); trace(p) }

/// The display that reserves room for the Dock on `edge` (its visible frame is inset there).
func dockDisplayUUID(edge: String) -> String? {
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))  // take in pending screen updates
    let screen = NSScreen.screens.first { s in
        let f = s.frame, v = s.visibleFrame
        switch edge {
        case "left": return v.minX - f.minX > 20
        case "right": return f.maxX - v.maxX > 20
        default: return v.minY - f.minY > 20
        }
    }
    guard let id = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
          let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
    return CFUUIDCreateString(nil, uuid) as String
}

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "PASS" : "FAIL", what)
    if !ok { failures += 1 }
}

// MARK: Test

guard let plan = activePlan() else { print("FAIL no active DockPin plan for these displays"); exit(1) }
let offsets = Dictionary(uniqueKeysWithValues: plan.pinned.map { d in
    (d.uuid, CGVector(dx: d.frame.minX - plan.real.first { $0.uuid == d.uuid }!.frame.minX,
                      dy: d.frame.minY - plan.real.first { $0.uuid == d.uuid }!.frame.minY))
})
let target = plan.pinned.first { $0.uuid == plan.targetUUID }!
let targetReal = plan.real.first { $0.uuid == plan.targetUUID }!.frame
let saved = cursor
print("Dock: \(plan.edge), center: \(target.name)")
check(dockDisplayUUID(edge: plan.edge) == target.uuid, "the Dock is on \(target.name)")

/// Crosses from the center into `neighbour` through their shared real border and back.
func crossing(to neighbour: Display) {
    let n = neighbour.frame
    let t = targetReal
    let (step, startReal): (CGVector, CGPoint) = {
        if n.maxX == t.minX { return (CGVector(dx: -6, dy: 0), CGPoint(x: t.minX + 30, y: (max(n.minY, t.minY) + min(n.maxY, t.maxY)) / 2)) }
        if n.minX == t.maxX { return (CGVector(dx: 6, dy: 0), CGPoint(x: t.maxX - 30, y: (max(n.minY, t.minY) + min(n.maxY, t.maxY)) / 2)) }
        if n.minY == t.maxY { return (CGVector(dx: 0, dy: 6), CGPoint(x: (max(n.minX, t.minX) + min(n.maxX, t.maxX)) / 2, y: t.maxY - 30)) }
        return (CGVector(dx: 0, dy: -6), CGPoint(x: (max(n.minX, t.minX) + min(n.maxX, t.maxX)) / 2, y: t.minY + 30))
    }()
    place(startReal)  // the target isn't moved, so real == pinned here
    for _ in 0..<10 { move(by: step) }
    let off = offsets[neighbour.uuid]!
    let expected = CGPoint(x: startReal.x + step.dx * 10 + off.dx, y: startReal.y + step.dy * 10 + off.dy)
    let landed = cursor
    check(neighbour.frame.offsetBy(dx: off.dx, dy: off.dy).contains(landed) && hypot(landed.x - expected.x, landed.y - expected.y) < 8,
          "\(target.name) -> \(neighbour.name) lands where the real border leads: \(landed) (expected ~\(expected))")
    move(by: CGVector(dx: -step.dx / 6, dy: -step.dy / 6))
    move(by: CGVector(dx: step.dx / 6, dy: step.dy / 6))
    check(!target.frame.contains(cursor), "a 1 px wobble right after crossing stays on \(neighbour.name)")
    for _ in 0..<10 { move(by: CGVector(dx: -step.dx, dy: -step.dy)) }
    check(target.frame.contains(cursor) && hypot(cursor.x - startReal.x, cursor.y - startReal.y) < 8,
          "\(neighbour.name) -> \(target.name) comes back to the same spot: \(cursor)")
}

for neighbour in plan.real where neighbour.uuid != plan.targetUUID {
    let n = neighbour.frame, t = targetReal
    let sharesBorder = ((n.maxX == t.minX || n.minX == t.maxX) && n.minY < t.maxY && t.minY < n.maxY)
        || ((n.minY == t.maxY || n.maxY == t.minY) && n.minX < t.maxX && t.minX < n.maxX)
    if sharesBorder { crossing(to: neighbour) }
}

/// Pushes at a display's Dock edge like a user summoning the Dock there.
for d in plan.pinned where d.uuid != plan.targetUUID {
    let f = d.frame
    let (start, step): (CGPoint, CGVector) = switch plan.edge {
    case "left": (CGPoint(x: f.minX + 40, y: f.midY), CGVector(dx: -6, dy: 0))
    case "right": (CGPoint(x: f.maxX - 40, y: f.midY), CGVector(dx: 6, dy: 0))
    default: (CGPoint(x: f.midX, y: f.maxY - 40), CGVector(dx: 0, dy: 6))
    }
    place(start)
    for _ in 0..<60 { move(by: step) }
    usleep(800_000)
    check(dockDisplayUUID(edge: plan.edge) == target.uuid, "the Dock stays on \(target.name) after pushing at \(d.name)'s \(plan.edge) edge")
}

place(saved)
print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
