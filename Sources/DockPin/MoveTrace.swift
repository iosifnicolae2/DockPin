import CoreGraphics
import Foundation

/// Diagnostic capture of every pointer move, for reproducing a crossing that went wrong with a real hand:
/// `defaults write io.bringes.DockPin traceMoves -bool YES`, move, then read ~/Library/Logs/DockPin/moves.log.
/// One line per event: ms, event type, event location, live pointer, delta (int and fractional),
/// previous spot, DockPin's correction ("-" for none).
final class MoveTrace {
    private let handle: FileHandle
    private let start = ProcessInfo.processInfo.systemUptime

    init?() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DockPin")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("moves.log")
        if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: file) else { return nil }
        handle.seekToEndOfFile()
        self.handle = handle
        write("# started; columns: ms type x y live_x live_y dx dy fdx fdy prev_x prev_y fixed_x fixed_y")
    }

    func record(event: CGEvent?, location: CGPoint, delta: CGVector, previous: CGPoint?, fixed: CGPoint?) {
        let live = CGEvent(source: nil)?.location ?? .zero
        let fdx = event?.getDoubleValueField(.mouseEventDeltaX) ?? 0
        let fdy = event?.getDoubleValueField(.mouseEventDeltaY) ?? 0
        let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
        let f = { (v: CGFloat?) in v.map { String(format: "%.2f", $0) } ?? "-" }
        write(String(format: "%.1f %d ", ms, Int(event?.type.rawValue ?? 0))
              + [location.x, location.y, live.x, live.y, delta.dx, delta.dy, fdx, fdy].map { f($0) }.joined(separator: " ")
              + " \(f(previous?.x)) \(f(previous?.y)) \(f(fixed?.x)) \(f(fixed?.y))")
    }

    private func write(_ line: String) {
        handle.write((line + "\n").data(using: .utf8)!)
    }
}
