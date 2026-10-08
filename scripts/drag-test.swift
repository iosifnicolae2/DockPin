// Drags a Finder window by its title bar from the center display across its moved left border and back,
// with DockPin running, and checks, in the real arrangement, that the window followed the pointer.
// Usage: swift scripts/drag-test.swift <folder to open>   (the calling terminal needs Accessibility)
import AppKit

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

/// A pinned-layout point in the real arrangement.
func real(_ p: CGPoint, _ plan: Plan) -> CGPoint {
    guard let d = plan.pinned.first(where: { $0.frame.contains(p) }), let r = plan.real.first(where: { $0.uuid == d.uuid }) else { return p }
    return CGPoint(x: p.x - d.frame.minX + r.frame.minX, y: p.y - d.frame.minY + r.frame.minY)
}

func osa(_ script: String) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", script]
    let out = Pipe()
    p.standardOutput = out
    try! p.run()
    p.waitUntilExit()
    return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
}

func windowBounds() -> CGRect {
    let v = osa("tell application \"Finder\" to get bounds of front Finder window").split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces))! }
    return CGRect(x: v[0], y: v[1], width: v[2] - v[0], height: v[3] - v[1])
}

func post(_ type: CGEventType, _ p: CGPoint, dx: Int64 = 0) {
    let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!
    e.setIntegerValueField(.mouseEventDeltaX, value: dx)
    e.post(tap: .cghidEventTap)
    usleep(12_000)
}

var cursor: CGPoint { CGEvent(source: nil)!.location }
guard let plan = activePlan() else { print("FAIL no active DockPin plan"); exit(1) }
let folder = CommandLine.arguments[1]

_ = osa("""
tell application "Finder"
    activate
    set w to make new Finder window to (POSIX file "\(folder)" as alias)
    set bounds of w to {60, 300, 560, 600}
end tell
""")
sleep(1)
let start = windowBounds()
CGWarpMouseCursorPosition(CGPoint(x: start.midX, y: start.minY + 14)); usleep(300_000)
post(.leftMouseDown, cursor)
for _ in 0..<80 { post(.leftMouseDragged, CGPoint(x: cursor.x - 6, y: cursor.y), dx: -6) }
post(.leftMouseUp, cursor)
usleep(400_000)
let across = windowBounds()
CGWarpMouseCursorPosition(CGPoint(x: across.midX, y: across.minY + 14)); usleep(300_000)
post(.leftMouseDown, cursor)
for _ in 0..<80 { post(.leftMouseDragged, CGPoint(x: cursor.x + 6, y: cursor.y), dx: 6) }
post(.leftMouseUp, cursor)
usleep(400_000)
let back = windowBounds()
_ = osa("tell application \"Finder\" to close front Finder window")

let startReal = real(start.origin, plan), acrossReal = real(CGPoint(x: across.midX, y: across.minY), plan)
print("start  \(start)\nacross \(across) (real top-centre \(acrossReal))\nback   \(back)")
let onLeft = plan.pinned.first { $0.frame.contains(CGPoint(x: across.midX, y: across.minY)) }?.uuid != plan.targetUUID
let movedLeft = abs((acrossReal.x - across.width / 2) - (startReal.x - 480)) < 16
let sameHeight = abs(acrossReal.y - startReal.y) < 4
let returned = abs(back.minX - start.minX) < 16 && abs(back.minY - start.minY) < 4
print(onLeft && movedLeft ? "PASS" : "FAIL", "dragged 480 pt left, onto the left display")
print(sameHeight ? "PASS" : "FAIL", "at the same height in the real arrangement")
print(returned ? "PASS" : "FAIL", "dragged back to where it started")
exit(onLeft && movedLeft && sameHeight && returned ? 0 : 1)
