import CoreGraphics

/// The user's own arrangement behind the live one, which may still be (partly) a layout DockPin pinned.
///
/// A pinned layout outlives DockPin: macOS saves it as its own arrangement (it comes back after a restart
/// and shows in System Settings), keeps it when DockPin crashes or the Mac panics before it could put the
/// real one back, and keeps the other displays where they were when one goes away. Taking such a layout
/// for the real one would pin the pinned layout again and steer the pointer by it.
public struct RealArrangement: Equatable {
    public var displays: [Display]
    /// The display the user had as main (at (0, 0)), if known.
    public var mainUUID: String?

    public init(displays: [Display], mainUUID: String?) {
        self.displays = displays
        self.mainUUID = mainUUID
    }

    /// `saved`: the plan saved for exactly these displays. `last`: the plan DockPin used last, for any displays.
    public static func behind(_ live: [Display], saved: LayoutPlan?, last: LayoutPlan?) -> RealArrangement {
        if let saved, sameOrigins(live, saved.pinned) {
            return RealArrangement(displays: saved.real, mainUUID: saved.mainUUID)
        }
        for plan in [saved, last].compactMap({ $0 }) {
            if let real = undoingMoves(of: plan, in: live) { return real }
        }
        return RealArrangement(displays: live, mainUUID: live.first { $0.frame.origin == .zero }?.uuid)
    }

    /// True when every display in `live` is where `layout` puts it, and nothing else is connected.
    public static func sameOrigins(_ live: [Display], _ layout: [Display]) -> Bool {
        let origins = Dictionary(layout.map { ($0.uuid, $0.frame.origin) }, uniquingKeysWith: { a, _ in a })
        return live.count == layout.count && live.allSatisfy { origins[$0.uuid] == $0.frame.origin }
    }

    /// Puts each display that is still exactly where `plan` moved it back where it really belongs. Positions are
    /// compared relative to the displays the plan left in place, since macOS may shift the whole arrangement.
    /// Nil when no display is still where the plan moved it.
    static func undoingMoves(of plan: LayoutPlan, in live: [Display]) -> RealArrangement? {
        let offsets = plan.offsetByUUID
        let pairs = live.compactMap { d in counterpart(of: d, in: plan.pinned).map { (live: d, pinned: $0) } }
        let isMoved = { (d: Display) in (offsets[d.uuid] ?? .zero) != .zero }
        guard let shift = commonShift(pairs.filter { !isMoved($0.pinned) }, preferring: plan.targetUUID) else { return nil }

        var undone = false
        let real = live.map { d -> Display in
            guard let p = pairs.first(where: { $0.live == d })?.pinned, isMoved(p),
                  d.frame.origin == CGPoint(x: p.frame.minX + shift.dx, y: p.frame.minY + shift.dy),
                  let offset = offsets[p.uuid] else { return d }
            undone = true
            return d.moved(by: CGVector(dx: -offset.dx, dy: -offset.dy))
        }
        guard undone, !hasOverlap(real) else { return nil }
        let main = plan.mainUUID.flatMap { uuid in pairs.first { $0.pinned.uuid == uuid }?.live.uuid }
        return RealArrangement(displays: real, mainUUID: main)
    }

    /// The same display in `layout`: same UUID, else (macOS sometimes gives a monitor a new UUID) the only
    /// one with its name and size.
    static func counterpart(of d: Display, in layout: [Display]) -> Display? {
        if let same = layout.first(where: { $0.uuid == d.uuid }) { return same }
        let lookalikes = layout.filter { $0.name == d.name && $0.frame.size == d.frame.size }
        return lookalikes.count == 1 ? lookalikes[0] : nil
    }

    /// How far the live arrangement sits from the plan's, by the displays the plan didn't move: the target's
    /// shift if it's there, else the one most of them agree on.
    static func commonShift(_ unmoved: [(live: Display, pinned: Display)], preferring targetUUID: String) -> CGVector? {
        let shift = { (pair: (live: Display, pinned: Display)) in
            CGVector(dx: pair.live.frame.minX - pair.pinned.frame.minX, dy: pair.live.frame.minY - pair.pinned.frame.minY)
        }
        if let target = unmoved.first(where: { $0.pinned.uuid == targetUUID }) { return shift(target) }
        let shifts = unmoved.map(shift)
        return shifts.max { a, b in shifts.filter { $0 == a }.count < shifts.filter { $0 == b }.count }
    }

    static func hasOverlap(_ displays: [Display]) -> Bool {
        displays.indices.contains { i in
            displays.indices.contains { j in i < j && LayoutPlanner.overlapsInside(displays[i].frame, displays[j].frame) }
        }
    }
}
