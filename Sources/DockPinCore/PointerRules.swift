import CoreGraphics

/// Makes the pinned arrangement move like the real one: every move is replayed in the real arrangement
/// and mapped back, so borders that only exist in the real arrangement still cross at the same height,
/// and borders that only exist in the pinned one don't. It also keeps the pointer off the other
/// displays' free Dock edges, where pushing would pull the Dock away.
public struct PointerRules {
    let plan: LayoutPlan
    let offsets: [String: CGVector]
    let guarded: [Display]

    public init(plan: LayoutPlan) {
        self.plan = plan
        self.offsets = plan.offsetByUUID
        self.guarded = LayoutPlanner.freeEdgeDisplays(in: plan.pinned, edge: plan.edge).filter { $0.uuid != plan.targetUUID }
    }

    /// Where the pointer should be instead of `current`, or nil when macOS already put it right.
    /// `previous` is where it was after the last event, `delta` this event's movement.
    public func correction(from previous: CGPoint?, to current: CGPoint, delta: CGVector) -> CGPoint? {
        let known = previous.flatMap { isContinuous(from: $0, to: current, delta: delta) ? $0 : nil }
        let replayed = known.flatMap { replayInRealArrangement(from: $0, to: current, delta: delta) } ?? current
        let kept = keepOffDockEdges(replayed)
        return hypot(kept.x - current.x, kept.y - current.y) >= 0.5 ? kept : nil
    }

    private func replayInRealArrangement(from previous: CGPoint, to current: CGPoint, delta: CGVector) -> CGPoint? {
        guard let from = display(near: previous), let now = display(near: current) else { return nil }
        let offFrom = offset(from), offNow = offset(now)
        let pushedAgainstEdge = now == from && isPushing(current, against: from.frame, delta)
        if now == from && !pushedAgainstEdge { return nil }  // an ordinary move inside one display
        if now != from && offFrom == offNow { return nil }    // a border both arrangements share

        // Where the move would have taken the pointer in the real arrangement. Replaying from the previous
        // spot carries exactly what the edge swallowed (nothing, if the pointer only reached the edge).
        let real = CGPoint(x: previous.x - offFrom.dx + delta.dx, y: previous.y - offFrom.dy + delta.dy)
        let fromReal = from.frame.offsetBy(dx: -offFrom.dx, dy: -offFrom.dy)
        // Where macOS would put it in the real arrangement: the full move, else the move with one axis
        // stopped by the edge (the pointer slides along it), else stopped at the edge.
        let attempts = [real, CGPoint(x: real.x, y: clamp(real, into: fromReal).y), CGPoint(x: clamp(real, into: fromReal).x, y: real.y)]
        for p in attempts {
            if let landing = plan.real.first(where: { $0.frame.contains(p) }) {
                let off = offset(landing)
                return CGPoint(x: p.x + off.dx, y: p.y + off.dy)
            }
        }
        let stopped = clamp(real, into: fromReal)
        return CGPoint(x: stopped.x + offFrom.dx, y: stopped.y + offFrom.dy)
    }

    /// A move never carries the pointer farther than its own delta; if it did, something else (another
    /// app, a display change) put the pointer there, and the previous position no longer applies.
    private func isContinuous(from previous: CGPoint, to current: CGPoint, delta: CGVector) -> Bool {
        hypot(current.x - previous.x, current.y - previous.y) <= hypot(delta.dx, delta.dy) + 40
    }

    private func keepOffDockEdges(_ p: CGPoint) -> CGPoint {
        guard let d = guarded.first(where: { $0.frame.contains(p) }) else { return p }
        switch plan.edge {
        case .left: return CGPoint(x: max(p.x, d.frame.minX + 1), y: p.y)
        case .right: return CGPoint(x: min(p.x, d.frame.maxX - 2), y: p.y)
        case .bottom: return CGPoint(x: p.x, y: min(p.y, d.frame.maxY - 2))
        }
    }

    private func isPushing(_ p: CGPoint, against f: CGRect, _ delta: CGVector) -> Bool {
        (delta.dx < 0 && p.x < f.minX + 1) || (delta.dx > 0 && p.x >= f.maxX - 1)
            || (delta.dy < 0 && p.y < f.minY + 1) || (delta.dy > 0 && p.y >= f.maxY - 1)
    }

    private func offset(_ d: Display) -> CGVector { offsets[d.uuid] ?? .zero }

    /// Synthetic or very fast moves can report a point just outside every display; it belongs to the nearest one.
    private func display(near p: CGPoint) -> Display? {
        plan.pinned.first { $0.frame.contains(p) } ?? plan.pinned.min { distance(p, $0.frame) < distance(p, $1.frame) }
    }

    private func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }

    private func clamp(_ p: CGPoint, into r: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, r.minX), r.maxX - 1), y: min(max(p.y, r.minY), r.maxY - 1))
    }
}
