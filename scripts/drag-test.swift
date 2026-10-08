// Drags a Finder window by its title bar from the center display across its moved left border and back,
// with DockPin running, and checks the window follows the pointer at the same height both ways.
// Usage: swift scripts/drag-test.swift <folder to open>   (the calling terminal needs Accessibility)
import AppKit

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
let grab = CGPoint(x: start.midX, y: start.minY + 14)  // the title bar
CGWarpMouseCursorPosition(grab); usleep(300_000)
post(.leftMouseDown, grab)
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

print("start  \(start)")
print("across \(across)")
print("back   \(back)")
let movedLeft = across.minX < 0 && abs(across.minX - (start.minX - 480)) < 12
let sameHeightReal = abs((across.minY + 1080) - start.minY) < 12 || abs(across.minY - start.minY) < 12
let returned = abs(back.minX - start.minX) < 12 && abs(back.minY - start.minY) < 12
print(movedLeft ? "PASS" : "FAIL", "dragged 480 px left, onto the left display")
print(sameHeightReal ? "PASS" : "FAIL", "at the same height in the real arrangement")
print(returned ? "PASS" : "FAIL", "dragged back to where it started")
exit(movedLeft && sameHeightReal && returned ? 0 : 1)
