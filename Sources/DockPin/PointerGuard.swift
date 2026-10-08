import AppKit
import DockPinCore

/// Applies `PointerRules` to every pointer move. It watches moves with a passive monitor, which needs
/// no permission; the price is that it hears about a move just after macOS made it, so at a moved
/// border the pointer touches the edge for that moment before DockPin carries it across.
final class PointerGuard {
    var rules: PointerRules? { didSet { previous = nil } }
    private var previous: CGPoint?
    private var monitors: [Any] = []
    private let movement: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

    func start() {
        // A warp normally ignores real mouse input for a moment afterwards; don't.
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
        if let global = NSEvent.addGlobalMonitorForEvents(matching: movement, handler: { [weak self] in self?.handle($0) }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: movement, handler: { [weak self] in self?.handle($0); return $0 }) {
            monitors.append(local)
        }
    }

    private func handle(_ event: NSEvent) {
        guard let rules, let cg = event.cgEvent, let location = CGEvent(source: nil)?.location else { return }
        let delta = CGVector(dx: Double(cg.getIntegerValueField(.mouseEventDeltaX)), dy: Double(cg.getIntegerValueField(.mouseEventDeltaY)))
        let fixed = rules.correction(from: previous, to: location, delta: delta)
        previous = fixed ?? location
        guard let fixed else { return }
        CGWarpMouseCursorPosition(fixed)
        CGAssociateMouseAndMouseCursorPosition(1)
        let lagMs = (ProcessInfo.processInfo.systemUptime - event.timestamp) * 1000
        log.notice("moved pointer \(location.debugDescription, privacy: .public) -> \(fixed.debugDescription, privacy: .public), \(lagMs, format: .fixed(precision: 1)) ms after the event")
    }
}
