import AppKit
import ApplicationServices
import DockPinCore

/// Applies `PointerRules` to every pointer move.
///
/// With Accessibility it uses an event tap: each move is corrected inside the same input event, before
/// macOS draws the pointer or delivers the event, so a moved border crosses like a real one and dragged
/// windows follow. Without it, a passive monitor (no permission) hears about the move about a
/// millisecond later and moves the pointer then, so it can touch the edge for that moment.
final class PointerGuard {
    enum Mode: String { case tap, monitor }

    var rules: PointerRules? { didSet { previous = nil } }
    private(set) var mode = Mode.monitor
    private var previous: CGPoint?
    private var tap: CFMachPort?
    private var monitors: [Any] = []
    private var warpedAt: TimeInterval?
    private let movement: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

    func start() {
        // A warp normally ignores real mouse input for a moment afterwards; don't.
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
        if AXIsProcessTrusted(), startTap() { mode = .tap } else { startMonitor() }
        log.notice("pointer guard: \(self.mode.rawValue, privacy: .public)")
    }

    /// Switches to the event tap once Accessibility has been granted; returns true if it switched.
    @discardableResult
    func upgradeIfTrusted() -> Bool {
        guard mode == .monitor, AXIsProcessTrusted(), startTap() else { return false }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        mode = .tap
        log.notice("pointer guard: tap")
        return true
    }

    private func correct(_ location: CGPoint, delta: CGVector) -> CGPoint? {
        guard let rules else { return nil }
        let fixed = rules.correction(from: previous, to: location, delta: delta)
        previous = fixed ?? location
        return fixed
    }

    private func delta(of event: CGEvent) -> CGVector {
        CGVector(dx: Double(event.getIntegerValueField(.mouseEventDeltaX)), dy: Double(event.getIntegerValueField(.mouseEventDeltaY)))
    }

    private func logMove(_ from: CGPoint, _ to: CGPoint, lagMs: Double) {
        log.notice("moved pointer \(from.debugDescription, privacy: .public) -> \(to.debugDescription, privacy: .public) [\(self.mode.rawValue, privacy: .public)], \(lagMs, format: .fixed(precision: 2)) ms after the event")
    }

    // MARK: Event tap (Accessibility)

    private func startTap() -> Bool {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, info in
            let me = Unmanaged<PointerGuard>.fromOpaque(info!).takeUnretainedValue()
            return me.handleTap(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    private func handleTap(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let location = event.location
        if let fixed = correct(location, delta: delta(of: event)) {
            event.location = fixed  // apps (and a dragged window) see the corrected position
            CGWarpMouseCursorPosition(fixed)
            let lagMs = Double(Int64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) - Int64(event.timestamp)) / 1e6
            logMove(location, fixed, lagMs: lagMs)
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: Passive monitor (no permission)

    private func startMonitor() {
        mode = .monitor
        if let global = NSEvent.addGlobalMonitorForEvents(matching: movement, handler: { [weak self] in self?.handleMonitor($0) }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: movement, handler: { [weak self] in self?.handleMonitor($0); return $0 }) {
            monitors.append(local)
        }
    }

    private func handleMonitor(_ event: NSEvent) {
        if let warpedAt {
            log.notice("next move \((event.timestamp - warpedAt) * 1000, format: .fixed(precision: 1)) ms after the warp")
            self.warpedAt = nil
        }
        guard let cg = event.cgEvent, let location = CGEvent(source: nil)?.location,
              let fixed = correct(location, delta: delta(of: cg)) else { return }
        CGWarpMouseCursorPosition(fixed)
        CGAssociateMouseAndMouseCursorPosition(1)
        warpedAt = ProcessInfo.processInfo.systemUptime
        logMove(location, fixed, lagMs: (ProcessInfo.processInfo.systemUptime - event.timestamp) * 1000)
    }
}
