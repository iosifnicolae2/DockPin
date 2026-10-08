import CoreGraphics

/// Makes the pinned arrangement move like the real one: every move is replayed in the real arrangement
/// and mapped back, so borders that only exist in the real arrangement still cross at the same height,
/// and borders that only exist in the pinned one don't. It also keeps the pointer off the other
/// displays' free Dock edges, where pushing would pull the Dock away.
public struct PointerRules {
    let plan: LayoutPlan
    let offsets: [String: CGVector]
    let guarded: [Display]
    /// The pointer's arrow is drawn right of and below its tip, up to this many points.
    let cursorSize: CGFloat

    static let largestHandMove: CGFloat = 300

    /// True when both points are on the same display (of the pinned layout).
    public func onSameDisplay(_ a: CGPoint, _ b: CGPoint) -> Bool {
        display(near: a) == display(near: b)
    }

    public init(plan: LayoutPlan, cursorSize: CGFloat = 32) {
        self.plan = plan
        self.offsets = plan.offsetByUUID
        self.guarded = LayoutPlanner.freeEdgeDisplays(in: plan.pinned, edge: plan.edge).filter { $0.uuid != plan.targetUUID }
        self.cursorSize = cursorSize
    }

    /// Where the pointer should be instead of `current`, or nil when macOS already put it right.
    /// `previous` is where it was after the last event, `delta` this event's movement.
    public func correction(from previous: CGPoint?, to current: CGPoint, delta: CGVector) -> CGPoint? {
        // No hand moves the pointer this far in one event: it's macOS catching up after a warp (its event
        // carries the whole jump as its delta) or another app moving the pointer. Replaying it would land
        // somewhere random, so leave such events alone.
        guard hypot(delta.dx, delta.dy) <= Self.largestHandMove else { return nil }
        let start = previous.flatMap { isContinuous(from: $0, to: current, delta: delta) ? $0 : nil } ?? estimatedStart(current, delta)
        var replayed = replayInRealArrangement(from: start, to: current, delta: delta) ?? current
        // Mouse deltas are whole pixels while the pointer moves in fractions, so a replay that stays on the
        // same display a pixel or so from where macOS put it is rounding, not a real difference.
        if hypot(replayed.x - current.x, replayed.y - current.y) < 2, display(near: replayed) == display(near: current) {
            replayed = current
        }
        let kept = keepArrowOffMovedNeighbours(keepOffDockEdges(replayed), delta: delta)
        return hypot(kept.x - current.x, kept.y - current.y) >= 0.5 ? kept : nil
    }

    /// The part of the arrow that, on a real border, would show on the neighbouring screen but has nowhere to
    /// go in the pinned layout (the neighbour was moved). `frame` is where that piece belongs (global, pinned
    /// coordinates); `arrowOrigin` is where the whole arrow image would start, so the piece can be cut from it.
    public func hiddenArrowPart(at p: CGPoint, arrow: CGSize, hotSpot: CGPoint) -> (frame: CGRect, arrowOrigin: CGPoint)? {
        guard let here = display(near: p) else { return nil }
        let arrowRect = CGRect(x: p.x - hotSpot.x, y: p.y - hotSpot.y, width: arrow.width, height: arrow.height)
        guard !here.frame.contains(arrowRect) else { return nil }
        let offHere = offset(here)
        let realArrow = arrowRect.offsetBy(dx: -offHere.dx, dy: -offHere.dy)
        for neighbour in plan.real where neighbour.uuid != here.uuid {
            let off = offset(neighbour)
            guard off != offHere else { continue }  // a border both layouts share: macOS draws it
            let part = realArrow.intersection(neighbour.frame)
            guard !part.isNull, part.width > 0, part.height > 0 else { continue }
            return (part.offsetBy(dx: off.dx, dy: off.dy), CGPoint(x: realArrow.minX + off.dx, y: realArrow.minY + off.dy))
        }
        return nil
    }

    /// Without a trustworthy previous spot, the move started at `current - delta`, on the display there.
    private func estimatedStart(_ current: CGPoint, _ delta: CGVector) -> CGPoint {
        let guess = CGPoint(x: current.x - delta.dx, y: current.y - delta.dy)
        guard let d = display(near: guess) else { return guess }
        return clamp(guess, into: d.frame)
    }

    /// macOS draws the arrow on every display it overlaps. Where a moved display only touches this one in
    /// the pinned layout (the corner left behind by the slide), that would show part of the arrow on a
    /// screen that isn't next to it in reality, so keep the arrow clear of it.
    private func keepArrowOffMovedNeighbours(_ p: CGPoint, delta: CGVector) -> CGPoint {
        guard let here = display(near: p) else { return p }
        for other in plan.pinned where other != here && offset(other) != offset(here) {
            let arrow = CGRect(x: p.x, y: p.y, width: cursorSize, height: cursorSize)
            guard LayoutPlanner.overlapsInside(arrow, other.frame) else { continue }
            // Heading for the edge: cross now, at the same height, wherever the real border leads.
            if let across = crossEarly(p, on: here, delta: delta) { return across }
            // Otherwise step out of the way, without pushing against the movement.
            let pushLeft = arrow.maxX - other.frame.minX, pushUp = arrow.maxY - other.frame.minY
            let left = CGPoint(x: p.x - pushLeft, y: p.y), up = CGPoint(x: p.x, y: p.y - pushUp)
            if delta.dx > 0 && delta.dy <= 0 { return up }
            if delta.dy > 0 && delta.dx <= 0 { return left }
            return pushLeft <= pushUp ? left : up
        }
        return p
    }

    /// The spot just across the edge the move heads for (its main direction), if a display is there in reality.
    private func crossEarly(_ p: CGPoint, on here: Display, delta: CGVector) -> CGPoint? {
        let off = offset(here)
        let realFrame = here.frame.offsetBy(dx: -off.dx, dy: -off.dy)
        var real = CGPoint(x: p.x - off.dx, y: p.y - off.dy)
        if abs(delta.dx) >= abs(delta.dy) && delta.dx != 0 {
            real.x = delta.dx > 0 ? realFrame.maxX : realFrame.minX - 1
        } else if delta.dy != 0 {
            real.y = delta.dy > 0 ? realFrame.maxY : realFrame.minY - 1
        } else {
            return nil
        }
        guard let landing = plan.real.first(where: { $0.uuid != here.uuid && $0.frame.contains(real) }) else { return nil }
        let o = offset(landing)
        return CGPoint(x: real.x + o.dx, y: real.y + o.dy)
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
