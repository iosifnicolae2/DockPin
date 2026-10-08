import AppKit
import DockPinCore

/// Watches pointer movement (no permission needed) and warps it where `PointerRules` says.
final class PointerGuard {
    var rules: PointerRules?
    private var monitors: [Any] = []
    private let movement: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

    func start() {
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
        guard let target = rules.warpTarget(for: location, delta: delta) else { return }
        CGWarpMouseCursorPosition(target)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
