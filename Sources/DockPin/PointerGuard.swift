import AppKit
import ApplicationServices
import DockPinCore

/// Applies `PointerRules` to every pointer move.
///
/// With Accessibility it uses an event tap: the move is corrected inside the same input event, before
/// anything is drawn or delivered, so a crossing looks and drags like a real display border.
/// Without it, a passive monitor (no permission) corrects the pointer right after the move.
final class PointerGuard {
    enum Mode: String { case off, monitor, tap }

    var rules: PointerRules? { didSet { previous = nil } }
    private(set) var mode = Mode.off
    private var previous: CGPoint?
    private var tap: CFMachPort?
    private var monitors: [Any] = []
    private let movement: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

    func start() {
        // A warp normally ignores real mouse input for ~0.25 s; don't.
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
        if AXIsProcessTrusted(), startTap() { mode = .tap } else { startMonitor(); mode = .monitor }
        log.notice("pointer guard: \(self.mode.rawValue, privacy: .public)")
    }

    /// Switches to the event tap once Accessibility has been granted.
    func upgradeIfTrusted() {
        guard mode == .monitor, AXIsProcessTrusted(), startTap() else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        mode = .tap
        log.notice("pointer guard: tap")
    }

    private func correct(_ location: CGPoint, delta: CGVector) -> CGPoint? {
        guard let rules else { return nil }
        let fixed = rules.correction(from: previous, to: location, delta: delta)
        previous = fixed ?? location
        return fixed
    }

    // MARK: Event tap

    private func startTap() -> Bool {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, info in
            let me = Unmanaged<PointerGuard>.fromOpaque(info!).takeUnretainedValue()
            return me.handleTap(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    private func handleTap(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if let fixed = correct(event.location, delta: delta(of: event)) {
            event.location = fixed
            CGWarpMouseCursorPosition(fixed)
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: Passive monitor

    private func startMonitor() {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: movement, handler: { [weak self] in self?.handleMonitor($0) }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: movement, handler: { [weak self] in self?.handleMonitor($0); return $0 }) {
            monitors.append(local)
        }
    }

    private func handleMonitor(_ event: NSEvent) {
        guard let cg = event.cgEvent, let location = CGEvent(source: nil)?.location,
              let fixed = correct(location, delta: delta(of: cg)) else { return }
        CGWarpMouseCursorPosition(fixed)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func delta(of event: CGEvent) -> CGVector {
        CGVector(dx: Double(event.getIntegerValueField(.mouseEventDeltaX)), dy: Double(event.getIntegerValueField(.mouseEventDeltaY)))
    }
}
