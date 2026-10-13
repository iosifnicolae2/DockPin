// Drags a window by the middle of its title bar across every border of the real arrangement (and at the
// borders that only exist in the pinned one), with DockPin running, and measures, step by step, where the
// pointer is against where the real arrangement leads, and how far the window is from the pointer.
// Usage: swift scripts/drag-test.swift [--driver hid|cg] [--speed slow|normal|fast] [--only <name part>] [--baseline FILE]
//   --driver hid (default) moves like a real mouse: relative HID events, positioned by macOS itself.
//            cg posts absolute CoreGraphics events, as other apps do.
//   --baseline FILE, run once with DockPin quit, then with it running: a crossing no worse than macOS alone passes.
//   DRAG_TRACE=<file> writes every step (crossing, step, pointer, expected, window) for drawing it later.
// The calling terminal needs Accessibility. Each line: PASS/FAIL, crossing, then the worst errors in points.
import AppKit
import IOKit.hidsystem

// MARK: DockPin's plan (mirror of DockPinCore.LayoutPlan)

struct Display: Codable { var uuid: String; var name: String; var frame: CGRect }
struct Plan: Codable { var real: [Display]; var pinned: [Display]; var targetUUID: String; var edge: String }

func liveFrames() -> [String: CGRect] {
    Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { s in
        let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
        return CGDisplayCreateUUIDFromDisplayID(id).map { (CFUUIDCreateString(nil, $0.takeRetainedValue()) as String, CGDisplayBounds(id)) }
    })
}

/// DockPin's plan for the live displays; with DockPin quit (the real arrangement is live), the same plan with
/// nothing moved, so the same drags measure macOS on its own.
func activePlan() -> Plan? {
    let live = liveFrames()
    let stored = UserDefaults(suiteName: "io.bringes.DockPin")?.dictionaryRepresentation() ?? [:]
    let plans = stored.filter { $0.key.hasPrefix("plan.") }.compactMap { ($0.value as? Data).flatMap { try? JSONDecoder().decode(Plan.self, from: $0) } }
    if let pinned = plans.first(where: { p in p.pinned.count == live.count && p.pinned.allSatisfy { live[$0.uuid] == $0.frame } }) { return pinned }
    return plans.first { p in p.real.count == live.count && p.real.allSatisfy { live[$0.uuid] == $0.frame } }.map { p in
        var alone = p
        alone.pinned = p.real
        return alone
    }
}

let arguments = CommandLine.arguments
func option(_ name: String) -> String? { arguments.firstIndex(of: name).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil } }
let useHID = option("--driver") != "cg"
let stepLength: CGFloat = ["slow": 2, "fast": 24][option("--speed") ?? ""] ?? 6
let only = option("--only")

guard let plan = activePlan() else { print("FAIL no active DockPin plan for these displays"); exit(1) }
let realFrames = Dictionary(uniqueKeysWithValues: plan.real.map { ($0.uuid, $0.frame) })
let offsets = Dictionary(uniqueKeysWithValues: plan.pinned.map { d in
    (d.uuid, CGVector(dx: d.frame.minX - realFrames[d.uuid]!.minX, dy: d.frame.minY - realFrames[d.uuid]!.minY))
})
let names = Dictionary(uniqueKeysWithValues: plan.real.map { ($0.uuid, $0.name) })

func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
    hypot(max(r.minX - p.x, 0, p.x - r.maxX - 1), max(r.minY - p.y, 0, p.y - r.maxY - 1))
}
func pinnedDisplay(_ p: CGPoint) -> Display { plan.pinned.min { distance(p, $0.frame) < distance(p, $1.frame) }! }
func toReal(_ p: CGPoint) -> CGPoint { let o = offsets[pinnedDisplay(p).uuid]!; return CGPoint(x: p.x - o.dx, y: p.y - o.dy) }
func realDisplay(_ p: CGPoint) -> Display { plan.real.min { distance(p, $0.frame) < distance(p, $1.frame) }! }
func toPinned(_ p: CGPoint) -> CGPoint { let o = offsets[realDisplay(p).uuid]!; return CGPoint(x: p.x + o.dx, y: p.y + o.dy) }

/// Where a move by `d` from `s` (on `from`) ends in `displays`: across only where two displays share a
/// stretch of edge, else sliding along or stopped at the edge (as EdgeAuditTests models macOS).
func land(_ s: CGPoint, _ d: CGVector, on from: CGRect, among displays: [CGRect]) -> (CGRect, CGPoint) {
    func entered(_ p: CGPoint) -> CGRect? {
        if from.contains(p) { return from }
        guard let b = displays.first(where: { $0 != from && $0.contains(p) }) else { return nil }
        if b.maxX == from.minX || b.minX == from.maxX { return p.y >= max(from.minY, b.minY) && p.y < min(from.maxY, b.maxY) ? b : nil }
        if b.maxY == from.minY || b.minY == from.maxY { return p.x >= max(from.minX, b.minX) && p.x < min(from.maxX, b.maxX) ? b : nil }
        return nil
    }
    let t = CGPoint(x: s.x + d.dx, y: s.y + d.dy)
    let clamped = CGPoint(x: min(max(t.x, from.minX), from.maxX - 1), y: min(max(t.y, from.minY), from.maxY - 1))
    for p in [t, CGPoint(x: t.x, y: clamped.y), CGPoint(x: clamped.x, y: t.y)] {
        if let r = entered(p) { return (r, p) }
    }
    return (from, clamped)
}

// MARK: Pointer drivers

var cursor: CGPoint { CGEvent(source: nil)!.location }

var hid: io_connect_t = 0
IOServiceOpen(IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass)), mach_task_self_,
              UInt32(kIOHIDParamConnectType), &hid)

/// A real mouse's move: macOS adds it to its own idea of where the pointer is.
func hidEvent(_ type: Int32, _ d: CGVector) {
    var data = NXEventData()
    if type == NX_LMOUSEDOWN || type == NX_LMOUSEUP {
        data.mouse.buttonNumber = 0
        data.mouse.click = 1
        data.mouse.pressure = type == NX_LMOUSEDOWN ? 255 : 0
    } else {
        data.mouseMove.dx = Int32(d.dx)
        data.mouseMove.dy = Int32(d.dy)
    }
    IOHIDPostEvent(hid, UInt32(type), IOGPoint(x: 0, y: 0), &data, UInt32(kNXEventDataVersion), 0, IOOptionBits(kIOHIDSetRelativeCursorPosition))
}

/// Hardware moves stop at the display edge; synthetic ones don't, so stop them the same way.
func clampedLikeHardware(_ p: CGPoint) -> CGPoint {
    let frames = Array(liveFrames().values)
    if frames.contains(where: { $0.contains(p) }) { return p }
    guard let f = frames.first(where: { $0.contains(cursor) }) else { return p }
    return CGPoint(x: min(max(p.x, f.minX), f.maxX - 1), y: min(max(p.y, f.minY), f.maxY - 1))
}

func cgEvent(_ type: CGEventType, _ d: CGVector) {
    let p = clampedLikeHardware(CGPoint(x: cursor.x + d.dx, y: cursor.y + d.dy))
    let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!
    e.setIntegerValueField(.mouseEventDeltaX, value: Int64(d.dx))
    e.setIntegerValueField(.mouseEventDeltaY, value: Int64(d.dy))
    e.post(tap: .cghidEventTap)
}

func press() { useHID ? hidEvent(NX_LMOUSEDOWN, .zero) : cgEvent(.leftMouseDown, .zero) }
func release() { useHID ? hidEvent(NX_LMOUSEUP, .zero) : cgEvent(.leftMouseUp, .zero) }
func drag(_ d: CGVector) { useHID ? hidEvent(NX_LMOUSEDRAGGED, d) : cgEvent(.leftMouseDragged, d) }
func move(_ d: CGVector) { useHID ? hidEvent(NX_MOUSEMOVED, d) : cgEvent(.mouseMoved, d) }
/// Puts the pointer at `p` without a drag. With the HID driver macOS's own position goes there too: after a
/// warp, the first move would carry the warp in its delta, and DockPin would take it for the hand's. Placed
/// in jumps no hand makes (over 300 pt, by way of a far display's centre), so DockPin doesn't replay them.
func put(_ p: CGPoint) {
    guard useHID else { CGWarpMouseCursorPosition(p); CGAssociateMouseAndMouseCursorPosition(1); return }
    func absolute(_ q: CGPoint) {
        var data = NXEventData()
        IOHIDPostEvent(hid, UInt32(NX_MOUSEMOVED), IOGPoint(x: Int16(q.x), y: Int16(q.y)), &data, UInt32(kNXEventDataVersion), 0,
                       IOOptionBits(kIOHIDSetCursorPosition))
        usleep(50_000)
    }
    let far = { (a: CGPoint, b: CGPoint) in hypot(a.x - b.x, a.y - b.y) > 400 }
    if let via = plan.pinned.map({ CGPoint(x: $0.frame.midX, y: $0.frame.midY) }).first(where: { far($0, p) && far($0, cursor) }) { absolute(via) }
    absolute(p)
}

// MARK: The window

let helper = Process()
helper.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
helper.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("drag-window.swift").path]
let toHelper = Pipe(), fromHelper = Pipe()
helper.standardInput = toHelper
helper.standardOutput = fromHelper
try! helper.run()

func helperLine() -> String {
    var line = Data()
    while true {
        let byte = fromHelper.fileHandleForReading.readData(ofLength: 1)
        if byte.isEmpty || byte == Data([10]) { return String(data: line, encoding: .utf8)! }
        line.append(byte)
    }
}
let ready = helperLine().split(separator: " ")
guard ready.first == "ready", let windowNumber = UInt32(ready[1]) else { print("FAIL no test window"); exit(1) }

func windowFrame() -> CGRect {
    let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowNumber) as! [[String: Any]]
    return CGRect(dictionaryRepresentation: info.first![kCGWindowBounds as String] as! CFDictionary)!
}

func placeWindow(titleBarMiddle p: CGPoint) {
    toHelper.fileHandleForWriting.write("place \(p.x) \(p.y)\n".data(using: .utf8)!)
    _ = helperLine()
    usleep(250_000)
}

// MARK: Crossings

struct Crossing {
    var name: String
    var start: CGPoint                      // real arrangement
    var legs: [(step: CGVector, count: Int)]  // the hand's moves
    var drags = true                        // false: the pointer alone, no button held

    init(name: String, start: CGPoint, step: CGVector, travel: CGFloat, drags: Bool = true) {
        self.name = name
        self.start = start
        self.legs = [(step, Int(travel / hypot(step.dx, step.dy)))]
        self.drags = drags
    }
}

/// Where a title-bar drag can start near `p` (real): the title bar below the menu bar, and most of the window on
/// the display (with separate Spaces, a window shows, and can be grabbed, only on the display holding most of it).
func roomForTitleBar(_ p: CGPoint, on r: CGRect) -> CGPoint {
    CGPoint(x: min(max(p.x, r.minX + 40), r.maxX - 40), y: min(max(p.y, r.minY + 70), r.maxY - 130))
}

func crossings() -> [Crossing] {
    var list: [Crossing] = []
    let reach: CGFloat = 150
    for a in plan.real {
        for b in plan.real where b.uuid != a.uuid {
            let f = a.frame, g = b.frame
            // A shared stretch of edge, and the step that leaves `a` through it.
            let side: (lo: CGFloat, hi: CGFloat, at: (CGFloat) -> CGPoint, step: CGVector)?
            if g.minX == f.maxX { side = (max(f.minY, g.minY), min(f.maxY, g.maxY), { CGPoint(x: f.maxX - reach, y: $0) }, CGVector(dx: 1, dy: 0)) }
            else if g.maxX == f.minX { side = (max(f.minY, g.minY), min(f.maxY, g.maxY), { CGPoint(x: f.minX + reach, y: $0) }, CGVector(dx: -1, dy: 0)) }
            else if g.minY == f.maxY { side = (max(f.minX, g.minX), min(f.maxX, g.maxX), { CGPoint(x: $0, y: f.maxY - reach) }, CGVector(dx: 0, dy: 1)) }
            else if g.maxY == f.minY { side = (max(f.minX, g.minX), min(f.maxX, g.maxX), { CGPoint(x: $0, y: f.minY + reach) }, CGVector(dx: 0, dy: -1)) }
            else { side = nil }
            guard let side, side.hi - side.lo >= 1 else { continue }
            let moved = offsets[a.uuid] != offsets[b.uuid]
            for (label, t) in [("near start", 0.06), ("middle", 0.5), ("near end", 0.94)] {
                let along = side.lo + (side.hi - side.lo) * t
                let start = roomForTitleBar(side.at(along), on: f)
                let step = CGVector(dx: side.step.dx * stepLength, dy: side.step.dy * stepLength)
                list.append(Crossing(name: "\(a.name) -> \(b.name) \(label)\(moved ? " (moved border)" : "")", start: start, step: step, travel: 2 * reach))
            }
            if moved {
                // Diagonally, toward the far corner of the border.
                let diagonal = side.step.dx != 0 ? CGVector(dx: side.step.dx, dy: -0.5) : CGVector(dx: -0.5, dy: side.step.dy)
                let start = roomForTitleBar(side.at(side.lo + (side.hi - side.lo) * 0.25), on: f)
                list.append(Crossing(name: "\(a.name) -> \(b.name) diagonal (moved border)", start: start,
                                     step: CGVector(dx: diagonal.dx * stepLength, dy: diagonal.dy * stepLength), travel: 2 * reach))
            }
        }
    }
    // Borders that only exist in the pinned layout (the bridge): the drag must stop there, as in reality.
    for a in plan.pinned {
        for b in plan.pinned where b.uuid != a.uuid && offsets[a.uuid] != offsets[b.uuid] {
            let f = a.frame, g = b.frame
            let mid: CGPoint, step: CGVector
            if g.minY == f.maxY, min(f.maxX, g.maxX) - max(f.minX, g.minX) >= 1 {
                mid = CGPoint(x: (max(f.minX, g.minX) + min(f.maxX, g.maxX)) / 2, y: f.maxY - 150); step = CGVector(dx: 0, dy: stepLength)
            } else if g.maxY == f.minY, min(f.maxX, g.maxX) - max(f.minX, g.minX) >= 1 {
                mid = CGPoint(x: (max(f.minX, g.minX) + min(f.maxX, g.maxX)) / 2, y: f.minY + 150); step = CGVector(dx: 0, dy: -stepLength)
            } else if g.minX == f.maxX, min(f.maxY, g.maxY) - max(f.minY, g.minY) >= 1 {
                mid = CGPoint(x: f.maxX - 150, y: (max(f.minY, g.minY) + min(f.maxY, g.maxY)) / 2); step = CGVector(dx: stepLength, dy: 0)
            } else if g.maxX == f.minX, min(f.maxY, g.maxY) - max(f.minY, g.minY) >= 1 {
                mid = CGPoint(x: f.minX + 150, y: (max(f.minY, g.minY) + min(f.maxY, g.maxY)) / 2); step = CGVector(dx: -stepLength, dy: 0)
            } else { continue }
            // Pushed for over a second (past the tracker's retries), then back. Upward without a window: a window
            // dragged into a top edge opens Mission Control, with or without DockPin.
            let drags = step.dy <= 0 ? false : true
            let start = drags ? roomForTitleBar(toReal(mid), on: realFrames[a.uuid]!) : toReal(mid)
            var push = Crossing(name: "\(a.name) toward \(b.name) at the bridge (only pinned\(drags ? "" : ", pointer alone"))",
                                start: start, step: step, travel: 150 + 70 * stepLength, drags: !(step.dy < 0))
            push.legs.append((CGVector(dx: -step.dx, dy: -step.dy), 20))
            list.append(push)
        }
    }
    return list.filter { c in only.map { c.name.localizedCaseInsensitiveContains($0) } ?? true }
}

struct Result { var pointer: CGFloat = 0; var window: CGFloat = 0; var stalls = 0; var backward = 0; var endPointer: CGFloat = 0; var endWindow: CGFloat = 0; var hitTop = false }

let traceFile = ProcessInfo.processInfo.environment["DRAG_TRACE"].flatMap { path -> FileHandle? in
    FileManager.default.createFile(atPath: path, contents: "crossing step pointer_x pointer_y expected_x expected_y window_x window_y\n".data(using: .utf8))
    return FileHandle(forWritingAtPath: path)
}

/// Waits for the event to be handled: the pointer moves, or 25 ms pass (it was held).
func settle(after before: CGPoint) {
    let start = Date()
    while cursor == before && Date().timeIntervalSince(start) < 0.025 { usleep(500) }
}

/// The window once it is at `grab` from the pointer `p`, or as it is after 30 ms (two frames): later than that,
/// the eye sees it trail.
func windowReaching(_ p: CGPoint, _ grab: CGPoint) -> CGRect {
    let start = Date()
    var w = windowFrame()
    while hypot(p.x - w.minX - grab.x, p.y - w.minY - grab.y) > 0.5 && Date().timeIntervalSince(start) < 0.03 {
        usleep(1_000)
        w = windowFrame()
    }
    return w
}

/// `--baseline FILE`: with DockPin quit, saves each crossing's numbers there; with DockPin running, a crossing
/// also passes when it is no worse than macOS alone was (macOS keeps a title bar below a menu bar, for one).
let baselineFile = option("--baseline")
let baseline: [String: [CGFloat]] = baselineFile.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }.map { text in
    Dictionary(text.split(separator: "\n").compactMap { line -> (String, [CGFloat])? in
        let f = line.split(separator: "\t").map(String.init)
        return f.count == 7 ? (f[0], f.dropFirst().compactMap { Double($0).map { CGFloat($0) } }) : nil
    }, uniquingKeysWith: { a, _ in a })
} ?? [:]
func key(_ c: Crossing) -> String { c.name.replacingOccurrences(of: " (moved border)", with: "") }
func numbers(_ r: Result) -> [CGFloat] { [r.pointer, r.window, CGFloat(r.stalls), CGFloat(r.backward), r.endPointer, r.endWindow] }

func run(_ c: Crossing) -> Result {
    var r = Result()
    let startPinned = toPinned(c.start)
    var grip = startPinned
    if c.drags {
        placeWindow(titleBarMiddle: startPinned)
        let placed = windowFrame()
        grip = CGPoint(x: placed.midX, y: placed.minY + 14)
        if hypot(grip.x - startPinned.x, grip.y - startPinned.y) > 3 { print("  (the window went to \(placed.origin), not where it was put)") }
    }
    put(grip)
    usleep(300_000)
    if c.drags { press() }
    usleep(200_000)
    var grab = CGPoint.zero  // the pointer's spot on the window once the drag has started
    var expected = toReal(grip), expectedFrame = realDisplay(expected).frame
    var last = toReal(cursor)
    let reals = plan.real.map(\.frame)
    var i = 0
    legs: for leg in c.legs {
        for _ in 0..<leg.count {
            let before = cursor
            c.drags ? drag(leg.step) : move(leg.step)
            (expectedFrame, expected) = land(expected, leg.step, on: expectedFrame, among: reals)
            settle(after: before)
            if i == 3 { usleep(60_000) }  // the drag has started: let the window settle before taking the grip
            let p = cursor, real = toReal(p)
            let w = c.drags && i > 3 ? windowReaching(p, grab) : windowFrame()
            defer { i += 1; last = real }
            // A window pushed against a display's free top edge opens Mission Control: let go before that.
            let top = pinnedDisplay(p).frame.minY
            if c.drags, leg.step.dy < 0, p.y < top + 4, !plan.pinned.contains(where: { $0.frame.contains(CGPoint(x: p.x, y: top - 1)) }) {
                r.hitTop = true
                break legs
            }
            traceFile?.write("\(c.name.replacingOccurrences(of: " ", with: "_")) \(i) \(p.x) \(p.y) \(expected.x) \(expected.y) \(w.minX) \(w.minY)\n".data(using: .utf8)!)
            // macOS starts a title-bar drag only once the pointer has moved a little: measure from there.
            if i == 3 { grab = CGPoint(x: p.x - w.minX, y: p.y - w.minY) }
            guard i > 3 else { continue }
            r.pointer = max(r.pointer, hypot(real.x - expected.x, real.y - expected.y))
            if c.drags { r.window = max(r.window, hypot(p.x - w.minX - grab.x, p.y - w.minY - grab.y)) }
            if (real.x - last.x) * leg.step.dx + (real.y - last.y) * leg.step.dy < 0 { r.backward += 1 }
            if hypot(real.x - last.x, real.y - last.y) < 0.5, expectedFrame.contains(expected), hypot(expected.x - real.x, expected.y - real.y) > 1 { r.stalls += 1 }
        }
    }
    if c.drags { release() }
    usleep(300_000)
    let p = cursor, w = windowFrame(), real = toReal(p)
    r.endPointer = hypot(real.x - expected.x, real.y - expected.y)
    if c.drags { r.endWindow = hypot(p.x - w.minX - grab.x, p.y - w.minY - grab.y) }
    return r
}

let saved = cursor
let alone = plan.pinned.map(\.frame) == plan.real.map(\.frame)
print("\(alone ? "macOS alone (DockPin isn't running)" : "DockPin"), Dock: \(plan.edge), driver: \(useHID ? "hid (like a real mouse)" : "cg (absolute events)"), \(stepLength) pt per step")
var failures = 0
var baselineLines: [String] = []
for c in crossings() {
    let r = run(c)
    let limits: [CGFloat] = [3, 3, 0, 0, 2, 2]
    let macOS = alone ? nil : baseline[key(c)]
    let ok = !r.hitTop && zip(numbers(r), limits).enumerated().allSatisfy { i, pair in pair.0 <= max(pair.1, (macOS?[i]).map { $0 + 1 } ?? 0) }
    if alone { baselineLines.append(([key(c)] + numbers(r).map { String(format: "%.1f", $0) }).joined(separator: "\t")) }
    if !ok { failures += 1 }
    print(String(format: "%@ %@: pointer off its real path by %.0f (end %.0f), window off the pointer by %.0f (end %.0f), %d stalls, %d steps back%@",
                 ok ? (macOS != nil && !zip(numbers(r), limits).allSatisfy { $0 <= $1 } ? "PASS (as macOS alone)" : "PASS") : "FAIL", c.name, r.pointer, r.endPointer, r.window, r.endWindow, r.stalls, r.backward, r.hitTop ? ", reached a top edge (stopped)" : ""))
}
if alone, let baselineFile { try! baselineLines.joined(separator: "\n").write(toFile: baselineFile, atomically: true, encoding: .utf8) }
toHelper.fileHandleForWriting.write("quit\n".data(using: .utf8)!)
put(saved)
print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
