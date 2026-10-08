import CoreGraphics

/// A pointer jump DockPin should make.
public enum Warp: Equatable {
    /// Crossing a border that only exists in the real arrangement; `direction` is the movement that caused it.
    case seam(to: CGPoint, direction: CGVector)
    /// Stepping back from a free left edge that would pull the Dock away.
    case edgeGuard(to: CGPoint)

    public var point: CGPoint {
        switch self {
        case .seam(let p, _), .edgeGuard(let p): return p
        }
    }
}

/// Decides where the pointer should jump so the pinned arrangement still feels like the real one:
/// crossing an edge that was shared in the real arrangement continues on the neighbour it had there,
/// and the free left edges of the other displays can't be touched (that would pull the Dock away).
public struct PointerRules {
    let plan: LayoutPlan
    let shifts: [String: CGFloat]
    let guardedLeftEdges: [Display]

    public init(plan: LayoutPlan) {
        self.plan = plan
        self.shifts = plan.shiftByUUID
        self.guardedLeftEdges = LayoutPlanner.freeLeftEdgeDisplays(in: plan.pinned).filter { $0.uuid != plan.targetUUID }
    }

    /// `point` is the pointer in global (pinned) coordinates, `delta` the movement that brought it there.
    public func warp(for point: CGPoint, delta: CGVector) -> Warp? {
        guard let current = display(containingOrNearest: point) else { return nil }
        return seamCrossing(from: current, at: point, delta: delta) ?? leftEdgeGuard(on: current, at: point)
    }

    /// Synthetic or very fast moves can report a point just outside every display; it belongs to the nearest one.
    private func display(containingOrNearest point: CGPoint) -> Display? {
        plan.pinned.first { $0.frame.contains(point) } ?? plan.pinned.min { distance(point, $0.frame) < distance(point, $1.frame) }
    }

    private func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }

    private func seamCrossing(from current: Display, at point: CGPoint, delta: CGVector) -> Warp? {
        let shift = shifts[current.uuid] ?? 0
        let realFrame = current.frame.offsetBy(dx: 0, dy: -shift)
        let real = CGPoint(x: point.x, y: point.y - shift)
        let beyond: CGPoint
        if delta.dx < 0, real.x < realFrame.minX + 1 { beyond = CGPoint(x: realFrame.minX - 1, y: real.y) }
        else if delta.dx > 0, real.x >= realFrame.maxX - 1 { beyond = CGPoint(x: realFrame.maxX, y: real.y) }
        else if delta.dy < 0, real.y < realFrame.minY + 1 { beyond = CGPoint(x: real.x, y: realFrame.minY - 1) }
        else if delta.dy > 0, real.y >= realFrame.maxY - 1 { beyond = CGPoint(x: real.x, y: realFrame.maxY) }
        else { return nil }

        guard let neighbour = plan.real.first(where: { $0.uuid != current.uuid && $0.frame.contains(beyond) }) else { return nil }
        let neighbourShift = shifts[neighbour.uuid] ?? 0
        guard neighbourShift != shift else { return nil }
        // Carry the movement the edge swallowed, so the pointer lands inside the neighbour rather than on its border.
        let carried = CGPoint(x: beyond.x + delta.dx, y: beyond.y + delta.dy)
        let landing = clamp(carried, into: neighbour.frame)
        return .seam(to: CGPoint(x: landing.x, y: landing.y + neighbourShift), direction: delta)
    }

    private func leftEdgeGuard(on current: Display, at point: CGPoint) -> Warp? {
        guard guardedLeftEdges.contains(current), point.x < current.frame.minX + 1 else { return nil }
        return .edgeGuard(to: CGPoint(x: current.frame.minX + 1, y: point.y))
    }

    private func clamp(_ p: CGPoint, into frame: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, frame.minX + 1), frame.maxX - 2), y: min(max(p.y, frame.minY), frame.maxY - 1))
    }
}
