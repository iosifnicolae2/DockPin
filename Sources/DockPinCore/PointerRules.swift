import CoreGraphics

/// Makes the pinned arrangement move like the real one: every move is replayed in the real arrangement
/// and mapped back, so borders that only exist in the real arrangement still cross at the same height,
/// and borders that only exist in the pinned one don't. It also keeps the pointer off the other
/// displays' free Dock edges, where pushing would pull the Dock away.
public struct PointerRules {
    let plan: LayoutPlan
    let offsets: [String: CGVector]
    let guarded: [Display]

    public static let largestHandMove: CGFloat = 300

    /// Where macOS would leave a move from `from` that ends at `p`: on a display there, else stopped at the
    /// edge of the display it started on.
    public func clampedOntoDisplay(_ p: CGPoint, near from: CGPoint) -> CGPoint {
        if plan.pinned.contains(where: { $0.frame.contains(p) }) { return p }
        guard let d = display(near: from) else { return p }
        return clamp(p, into: d.frame)
    }

    /// Whether macOS's catch-up after putting the pointer at `b` can get there from its own old position `a`.
    /// It moves in a straight line that may only pass between displays where they share an edge (a bridge);
    /// through anything else it stops at the edge (the pointer then "jumps to the top").
    public func catchUpCanPass(from a: CGPoint, to b: CGPoint) -> Bool {
        guard let da = display(near: a)?.frame, let db = display(near: b)?.frame else { return false }
        if da == db { return true }
        // The shared edge: horizontal (one above the other) or vertical (side by side), with its range.
        let crossing: (along: CGFloat, range: ClosedRange<CGFloat>)?
        if da.maxY == db.minY || da.minY == db.maxY {
            let y = da.maxY == db.minY ? da.maxY : da.minY
            let t = (y - a.y) / (b.y - a.y)
            crossing = (a.x + (b.x - a.x) * t, max(da.minX, db.minX)...min(da.maxX, db.maxX))
        } else if da.maxX == db.minX || da.minX == db.maxX {
            let x = da.maxX == db.minX ? da.maxX : da.minX
            let t = (x - a.x) / (b.x - a.x)
            crossing = (a.y + (b.y - a.y) * t, max(da.minY, db.minY)...min(da.maxY, db.maxY))
        } else {
            crossing = nil
        }
        guard let crossing, crossing.range.upperBound - crossing.range.lowerBound >= 1 else { return false }
        return crossing.range.contains(crossing.along)
    }

    /// For a crossing that lands at `target`, the spot on the same display right across the real border it
    /// came over from `start` (same height for a side border): the nearest landing macOS's catch-up can reach.
    public func borderPoint(for target: CGPoint, from start: CGPoint) -> CGPoint {
        guard let to = display(near: target), let from = display(near: start),
              let t = plan.real.first(where: { $0.uuid == to.uuid })?.frame,
              let f = plan.real.first(where: { $0.uuid == from.uuid })?.frame else { return target }
        let off = offset(to)
        var p = CGPoint(x: target.x - off.dx, y: target.y - off.dy)
        if t.maxX <= f.minX { p.x = t.maxX - 1 } else if t.minX >= f.maxX { p.x = t.minX }
        else if t.maxY <= f.minY { p.y = t.maxY - 1 } else if t.minY >= f.maxY { p.y = t.minY }
        return CGPoint(x: p.x + off.dx, y: p.y + off.dy)
    }

    /// True when both points are on the same display (of the pinned layout).
    public func onSameDisplay(_ a: CGPoint, _ b: CGPoint) -> Bool {
        display(near: a) == display(near: b)
    }

    public init(plan: LayoutPlan) {
        self.plan = plan
        self.offsets = plan.offsetByUUID
        self.guarded = LayoutPlanner.freeEdgeDisplays(in: plan.pinned, edge: plan.edge).filter { $0.uuid != plan.targetUUID }
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
        let kept = keepOffDockEdges(replayed)
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

    /// The strip along the edge of the display that holds `piece`, `depth` deep, where arrow pieces for that
    /// border are drawn (so one fixed overlay window per border serves every pointer position).
    public func borderStrip(containing piece: CGRect, depth: CGFloat) -> CGRect? {
        guard let d = plan.pinned.first(where: { $0.frame.intersects(piece.insetBy(dx: 0.5, dy: 0.5)) })?.frame else { return nil }
        if piece.minX <= d.minX + 0.5 { return CGRect(x: d.minX, y: d.minY, width: depth, height: d.height) }
        if piece.maxX >= d.maxX - 0.5 { return CGRect(x: d.maxX - depth, y: d.minY, width: depth, height: d.height) }
        if piece.minY <= d.minY + 0.5 { return CGRect(x: d.minX, y: d.minY, width: d.width, height: depth) }
        return CGRect(x: d.minX, y: d.maxY - depth, width: d.width, height: depth)
    }

    /// Without a trustworthy previous spot, the move started at `current - delta`, on the display there.
    private func estimatedStart(_ current: CGPoint, _ delta: CGVector) -> CGPoint {
        let guess = CGPoint(x: current.x - delta.dx, y: current.y - delta.dy)
        guard let d = display(near: guess) else { return guess }
        return clamp(guess, into: d.frame)
    }

    /// Where a move ending at `p` (real arrangement) lands when it starts on `from`: on `from` itself, or on a
    /// display that shares a stretch of edge with it right where the move leaves it. Like macOS, never
    /// through a point where two displays only meet at their corners.
    private func realDisplay(at p: CGPoint, leaving from: Display) -> Display? {
        guard let a = plan.real.first(where: { $0.uuid == from.uuid })?.frame else { return nil }
        if a.contains(p) { return plan.real.first { $0.uuid == from.uuid } }
        guard let b = plan.real.first(where: { $0.uuid != from.uuid && $0.frame.contains(p) }) else { return nil }
        let f = b.frame
        if f.maxX == a.minX || f.minX == a.maxX { return p.y >= max(a.minY, f.minY) && p.y < min(a.maxY, f.maxY) ? b : nil }
        if f.maxY == a.minY || f.minY == a.maxY { return p.x >= max(a.minX, f.minX) && p.x < min(a.maxX, f.maxX) ? b : nil }
        return nil
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
            if let landing = realDisplay(at: p, leaving: from) {
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
