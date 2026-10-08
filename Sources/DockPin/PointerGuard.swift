import AppKit
import ApplicationServices
import DockPinCore

/// Applies `PointerTracker` to every pointer move.
///
/// With Accessibility it uses an event tap: each move is handled inside the same input event, before
/// macOS draws the pointer or delivers the event, so a moved border crosses like a real one and dragged
/// windows follow. Without it, a passive monitor (no permission) hears about the move about a
/// millisecond later and moves the pointer then.
final class PointerGuard {
    enum Mode: String { case tap, monitor }

    var rules: PointerRules? {
        didSet {
            tracker = rules.map(PointerTracker.init)
            tail.reset()
        }
    }
    private(set) var mode = Mode.monitor
    private var tracker: PointerTracker?
    private var tap: CFMachPort?
    private var monitors: [Any] = []
    private let tail = CursorTail()
    private let movement: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    /// Set from `defaults write io.bringes.DockPin traceMoves -bool YES`: every move goes to a file.
    var trace: MoveTrace?

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

    private func decide(_ location: CGPoint, _ event: CGEvent) -> PointerTracker.Action {
        guard var tracker else { return .pass }
        let delta = CGVector(dx: Double(event.getIntegerValueField(.mouseEventDeltaX)), dy: Double(event.getIntegerValueField(.mouseEventDeltaY)))
        let action = tracker.handle(location: location, delta: delta, time: ProcessInfo.processInfo.systemUptime)
        self.tracker = tracker
        trace?.record(event: event, location: location, delta: delta, action: action)
        switch action {
        case .pass: tail.update(pointer: location, rules: rules)
        case .move(let p), .jump(let p):
            tail.update(pointer: p, rules: rules)
            if case .jump = action { log.notice("jumped pointer \(location.debugDescription, privacy: .public) -> \(p.debugDescription, privacy: .public) [\(self.mode.rawValue, privacy: .public)]") }
        }
        return action
    }

    /// Puts the pointer at `p` and has macOS's own position follow it.
    private func warp(_ p: CGPoint) {
        CGWarpMouseCursorPosition(p)
        CGAssociateMouseAndMouseCursorPosition(1)
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
            log.notice("event tap disabled by macOS (\(type == .tapDisabledByTimeout ? "too slow" : "user input", privacy: .public)); re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.ownEvent { return Unmanaged.passUnretained(event) }
        switch decide(event.location, event) {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .move(let p), .jump(let p):
            // Neither rewriting the event nor warping is enough with a real mouse: a rewrite doesn't move the
            // pointer, and after a warp macOS catches its own position up later in one big jump (1080 pt
            // between the moved displays), which its shake-to-locate takes for a shake and enlarges the pointer.
            // A posted event moves the pointer and macOS's position together, directly, across any displays.
            post(p, replacing: event)
            return nil
        }
    }

    /// Tags the events DockPin posts, so its own tap lets them through untouched.
    private static let ownEvent: Int64 = 0x0D0C_0B1E
    private let postSource = CGEventSource(stateID: .hidSystemState)

    /// Replaces `original` (dropped by the caller) with the same kind of event at `p`: a move, or a drag with
    /// the same button, so a dragged window follows.
    private func post(_ p: CGPoint, replacing original: CGEvent) {
        let button = CGMouseButton(rawValue: UInt32(original.getIntegerValueField(.mouseEventButtonNumber))) ?? .left
        guard let event = CGEvent(mouseEventSource: postSource, mouseType: original.type, mouseCursorPosition: p, mouseButton: button) else {
            return warp(p)
        }
        event.flags = original.flags
        event.setIntegerValueField(.mouseEventDeltaX, value: original.getIntegerValueField(.mouseEventDeltaX))
        event.setIntegerValueField(.mouseEventDeltaY, value: original.getIntegerValueField(.mouseEventDeltaY))
        event.setIntegerValueField(.eventSourceUserData, value: Self.ownEvent)
        event.post(tap: .cghidEventTap)
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
        guard let cg = event.cgEvent, let location = CGEvent(source: nil)?.location else { return }
        switch decide(location, cg) {
        case .pass: break
        case .move(let p), .jump(let p): warp(p)
        }
    }
}
