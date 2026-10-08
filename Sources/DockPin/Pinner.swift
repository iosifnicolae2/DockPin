import AppKit
import DockPinCore
import os

let log = Logger(subsystem: "io.bringes.DockPin", category: "pin")

/// Keeps the pinned arrangement applied for whatever set of displays is connected.
final class Pinner {
    private let defaults = UserDefaults.standard
    private let pointer = PointerGuard()
    private(set) var activePlan: LayoutPlan?
    var onChange: (() -> Void)?

    var targetName: String? {
        activePlan.flatMap { plan in plan.pinned.first { $0.uuid == plan.targetUUID }?.name }
    }

    func start() {
        pointer.start()
        reconcile()
    }

    func reconcile() {
        let live = Displays.current()
        let key = Displays.setKey(live)

        if let saved = savedPlan(for: key), Displays.matches(live, saved.pinned) {
            use(saved)
            return
        }
        guard let target = chooseTarget(in: live), let plan = LayoutPlanner.plan(for: live, targetUUID: target.uuid) else {
            log.notice("no center display among \(live.count) displays; nothing to pin")
            use(nil)
            return
        }
        save(plan, for: key)
        if !Displays.matches(live, plan.pinned) {
            let ok = Displays.arrange(plan.pinned)
            log.notice("pinned the Dock to \(target.name, privacy: .public): \(ok ? "applied" : "failed", privacy: .public)")
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
        activePlan = plan
        pointer.rules = plan.map(PointerRules.init)
        onChange?()
    }

    private func chooseTarget(in displays: [Display]) -> Display? {
        let wanted = defaults.string(forKey: "targetDisplay") ?? defaults.string(forKey: "lastTarget")
        let target = displays.first { $0.name == wanted } ?? LayoutPlanner.centerDisplay(in: displays)
        if let target { defaults.set(target.name, forKey: "lastTarget") }
        return target
    }

    private func savedPlan(for key: String) -> LayoutPlan? {
        defaults.data(forKey: "plan." + key).flatMap { try? JSONDecoder().decode(LayoutPlan.self, from: $0) }
    }

    private func save(_ plan: LayoutPlan, for key: String) {
        defaults.set(try? JSONEncoder().encode(plan), forKey: "plan." + key)
    }
}
