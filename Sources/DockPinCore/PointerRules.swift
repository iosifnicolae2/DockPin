import CoreGraphics

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
    public func warpTarget(for point: CGPoint, delta: CGVector) -> CGPoint? {
        guard let current = plan.pinned.first(where: { $0.frame.contains(point) }) else { return nil }
        return seamCrossing(from: current, at: point, delta: delta) ?? leftEdgeGuard(on: current, at: point)
    }

    private func seamCrossing(from current: Display, at point: CGPoint, delta: CGVector) -> CGPoint? {
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
        return CGPoint(x: beyond.x, y: beyond.y + neighbourShift)
    }

    private func leftEdgeGuard(on current: Display, at point: CGPoint) -> CGPoint? {
        guard guardedLeftEdges.contains(current), point.x < current.frame.minX + 1 else { return nil }
        return CGPoint(x: current.frame.minX + 1, y: point.y)
    }
}
