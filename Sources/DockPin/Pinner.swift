import AppKit
import DockPinCore
import os

let log = Logger(subsystem: "io.bringes.DockPin", category: "pin")

/// Keeps the pinned arrangement applied for whatever displays are connected and wherever the Dock sits.
final class Pinner {
    private let defaults = UserDefaults.standard
    let pointer = PointerGuard()
    private(set) var activePlan: LayoutPlan?
    var onChange: (() -> Void)?

    var targetName: String? {
        activePlan.flatMap { plan in plan.pinned.first { $0.uuid == plan.targetUUID }?.name }
    }

    /// The display picked in the menu, or nil for "the center display".
    var chosenTargetName: String? {
        get { defaults.string(forKey: "targetDisplay") }
        set {
            defaults.set(newValue, forKey: "targetDisplay")
            reconcile()
        }
    }

    var displayNames: [String] { (activePlan?.real ?? Displays.current()).map(\.name) }

    func start() {
        pointer.start()
        reconcile()
    }

    func reconcile() {
        let live = Displays.current()
        let key = Displays.setKey(live)
        let edge = DockPrefs.edge()

        // If what's live is our own pinned layout, the user's real one is the one we saved with it.
        let saved = savedPlan(for: key)
        let real = saved.flatMap { Displays.matches(live, $0.pinned) ? $0.real : nil } ?? live

        guard let target = chooseTarget(in: real), let plan = LayoutPlanner.plan(for: real, targetUUID: target.uuid, edge: edge) else {
            log.notice("no center display among \(live.count) displays; nothing to pin")
            use(nil)
            return
        }
        if plan != saved || !Displays.matches(live, plan.pinned) {
            save(plan, for: key)
        }
        if !Displays.matches(live, plan.pinned) {
            let ok = Displays.arrange(plan.pinned)
            log.notice("pinned the \(edge.rawValue, privacy: .public) Dock to \(target.name, privacy: .public): \(ok ? "applied" : "failed", privacy: .public)")
        }
        use(plan)
    }

    /// Puts the real arrangement back (the Dock then goes wherever macOS wants it).
    func restore() {
        pointer.rules = nil
        guard let plan = activePlan else { return }
        Displays.arrange(plan.real)
        log.notice("restored the real arrangement")
    }

    private func use(_ plan: LayoutPlan?) {
        // Unchanged plan: keep the pointer guard's state (where the pointer was) as it is.
        if plan != activePlan || pointer.rules == nil {
            pointer.rules = plan.map { PointerRules(plan: $0, cursorSize: Self.cursorSize()) }
        }
        activePlan = plan
        onChange?()
    }

    /// The arrow's size, enlarged by Accessibility > Display > Pointer size when set.
    private static func cursorSize() -> CGFloat {
        let scale = UserDefaults(suiteName: "com.apple.universalaccess")?.double(forKey: "mouseDriverCursorSize") ?? 0
        return 32 * max(1, scale)
    }

    /// The display picked in the menu if it's connected, else the center one.
    private func chooseTarget(in displays: [Display]) -> Display? {
        displays.first { $0.name == chosenTargetName } ?? LayoutPlanner.centerDisplay(in: displays)
    }

    private func savedPlan(for key: String) -> LayoutPlan? {
        defaults.data(forKey: "plan." + key).flatMap { try? JSONDecoder().decode(LayoutPlan.self, from: $0) }
    }

    private func save(_ plan: LayoutPlan, for key: String) {
        defaults.set(try? JSONEncoder().encode(plan), forKey: "plan." + key)
    }
}
