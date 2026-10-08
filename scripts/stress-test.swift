// Sustained fast crossings over the center display's moved left border, ~1000 events/s, for N seconds.
// Per second: events sent, how long the pointer took to reflect each move (median / worst), DockPin's CPU.
// If anything builds up (lag, tap timeouts), it shows as growing numbers. Usage: swift scripts/stress-test.swift [seconds]
import AppKit
import Darwin

func dockPinCPU() -> Double {
    guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "io.bringes.DockPin").first?.processIdentifier else { return -1 }
    var info = rusage_info_current()
    let ok = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) } }
    guard ok == 0 else { return -1 }
    var tb = mach_timebase_info_data_t()
    mach_timebase_info(&tb)
    return Double(info.ri_user_time + info.ri_system_time) * Double(tb.numer) / Double(tb.denom) / 1e9
}

var cursor: CGPoint { CGEvent(source: nil)!.location }
let frames = NSScreen.screens.map { CGDisplayBounds($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID) }

/// Like hardware: a move that would leave every display stops at the edge of the one it's on.
func clamped(_ p: CGPoint) -> CGPoint {
    if frames.contains(where: { $0.contains(p) }) { return p }
    guard let f = frames.first(where: { $0.contains(cursor) }) else { return p }
    return CGPoint(x: min(max(p.x, f.minX), f.maxX - 1), y: min(max(p.y, f.minY), f.maxY - 1))
}

let seconds = Int(CommandLine.arguments.dropFirst().first ?? "20")!
let saved = cursor
CGWarpMouseCursorPosition(CGPoint(x: 150, y: 540)); usleep(300_000)
var dir: CGFloat = -15
var travelled: CGFloat = 0
print("second  sent  median_ms  worst_ms  dockpin_cpu_%")
for s in 0..<seconds {
    var waits: [Double] = []
    let cpu0 = dockPinCPU(), t0 = Date()
    while Date().timeIntervalSince(t0) < 1 {
        let before = cursor
        let p = clamped(CGPoint(x: before.x + dir, y: before.y))
        let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!
        e.setIntegerValueField(.mouseEventDeltaX, value: Int64(dir))
        let sent = Date()
        e.post(tap: .cghidEventTap)
        while cursor == before && Date().timeIntervalSince(sent) < 0.05 { usleep(100) }
        waits.append(Date().timeIntervalSince(sent) * 1000)
        travelled += abs(dir)
        if travelled >= 300 { dir = -dir; travelled = 0 }  // 300 pt each way: crosses the border every trip
        usleep(800)
    }
    let cpu = (dockPinCPU() - cpu0) / Date().timeIntervalSince(t0) * 100
    let sorted = waits.sorted()
    print(String(format: "%6d  %4d  %9.2f  %8.2f  %13.1f", s, waits.count, sorted[sorted.count / 2], sorted.last!, cpu))
}
CGWarpMouseCursorPosition(saved)
