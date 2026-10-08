import AppKit
import DockPinCore

/// Watches pointer movement (no permission needed) and warps it where `PointerRules` says.
final class PointerGuard {
    var rules: PointerRules?
    private var monitors: [Any] = []
    private let movement: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    /// After a crossing, a small wobble back must not bounce the pointer across again.
    private let reverseCooldown: TimeInterval = 0.2
    private var lastCrossing: (at: Date, direction: CGVector)?

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
        guard let warp = rules.warp(for: location, delta: delta) else { return }
        if case .seam(_, let direction) = warp {
            if isBounce(direction) { return }
            lastCrossing = (Date(), direction)
            log.debug("crossed seam \(location.debugDescription, privacy: .public) -> \(warp.point.debugDescription, privacy: .public), delta \(delta.dx), \(delta.dy)")
        }
        CGWarpMouseCursorPosition(warp.point)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func isBounce(_ direction: CGVector) -> Bool {
        guard let last = lastCrossing, Date().timeIntervalSince(last.at) < reverseCooldown else { return false }
        return direction.dx * last.direction.dx < 0 || direction.dy * last.direction.dy < 0
    }
}
