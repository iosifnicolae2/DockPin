import CoreGraphics
import DockPinCore
import Foundation

/// Diagnostic capture of every pointer move, for reproducing a crossing that went wrong with a real hand.
/// Off unless `defaults write io.bringes.DockPin traceMoves -bool YES`; then read ~/Library/Logs/DockPin/moves.log
/// (scripts/analyze-moves.py). One line per event: ms, event type, event location, live pointer, delta (int and
/// fractional), what DockPin did (pass, move or jump) and where to. Lines are buffered and written off the
/// main thread, so tracing doesn't slow the pointer.
final class MoveTrace {
    private let handle: FileHandle
    private let start = ProcessInfo.processInfo.systemUptime
    private let disk = DispatchQueue(label: "io.bringes.DockPin.trace")
    private var buffer: [String] = []

    init?() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DockPin")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("moves.log")
        if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: file) else { return nil }
        handle.seekToEndOfFile()
        self.handle = handle
        buffer.append(String(format: "# started at %.3f (Unix time); columns: ms type x y live_x live_y dx dy fdx fdy action to_x to_y",
                             Date().timeIntervalSince1970))
    }

    deinit { flush() }

    func record(event: CGEvent?, location: CGPoint, delta: CGVector, action: PointerTracker.Action) {
        let live = CGEvent(source: nil)?.location ?? .zero
        let fdx = event?.getDoubleValueField(.mouseEventDeltaX) ?? 0
        let fdy = event?.getDoubleValueField(.mouseEventDeltaY) ?? 0
        let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
        let f = { (v: CGFloat?) in v.map { String(format: "%.2f", $0) } ?? "-" }
        let (kind, to): (String, CGPoint?) = switch action {
        case .pass: ("pass", nil)
        case .move(let p): ("move", p)
        case .jump(let p): ("jump", p)
        }
        buffer.append(String(format: "%.1f %d ", ms, Int(event?.type.rawValue ?? 0))
                      + [location.x, location.y, live.x, live.y, delta.dx, delta.dy, fdx, fdy].map { f($0) }.joined(separator: " ")
                      + " \(kind) \(f(to?.x)) \(f(to?.y))")
        if buffer.count >= 200 { flush() }
    }

    func flush() {
        guard !buffer.isEmpty else { return }
        let data = (buffer.joined(separator: "\n") + "\n").data(using: .utf8)!
        buffer.removeAll(keepingCapacity: true)
        let handle = self.handle
        disk.async { handle.write(data) }
    }
}
