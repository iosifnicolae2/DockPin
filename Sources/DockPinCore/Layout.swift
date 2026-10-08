import CoreGraphics

/// The screen edge the Dock sits on (System Settings > Desktop & Dock > Position on screen).
public enum DockEdge: String, Codable, CaseIterable {
    case left, bottom, right
}

/// One display in the global arrangement, in CoreGraphics coordinates (origin top-left of the main display, y down).
public struct Display: Equatable, Codable {
    public var uuid: String
    public var name: String
    public var frame: CGRect

    public init(uuid: String, name: String, frame: CGRect) {
        self.uuid = uuid
        self.name = name
        self.frame = frame
    }

    func moved(by offset: CGVector) -> Display {
        var d = self
        d.frame = frame.offsetBy(dx: offset.dx, dy: offset.dy)
        return d
    }
}

/// The real arrangement the user set up, and the "pinned" one DockPin applies so the Dock can sit on `target`.
/// Both are normalised so the target is at (0, 0), which also makes it the main display.
public struct LayoutPlan: Equatable, Codable {
    public var real: [Display]
    public var pinned: [Display]
    public var targetUUID: String
    public var edge: DockEdge

    /// How far each display was moved (pinned minus real).
    public var offsetByUUID: [String: CGVector] {
        let realByUUID = Dictionary(uniqueKeysWithValues: real.map { ($0.uuid, $0.frame.origin) })
        return Dictionary(uniqueKeysWithValues: pinned.compactMap { d in
            realByUUID[d.uuid].map { (d.uuid, CGVector(dx: d.frame.minX - $0.x, dy: d.frame.minY - $0.y)) }
        })
    }

    static func normalised(_ displays: [Display], on targetUUID: String) -> [Display] {
        guard let origin = displays.first(where: { $0.uuid == targetUUID })?.frame.origin else { return displays }
        return displays.map { $0.moved(by: CGVector(dx: -origin.x, dy: -origin.y)) }
    }
}

public enum LayoutPlanner {
    /// The display the user means by "center": one with a display touching it on both its left and right
    /// side; failing that (say one side's monitor is unplugged), the one touching the most displays.
    public static func centerDisplay(in displays: [Display]) -> Display? {
        let between = displays.first { d in
            displays.contains { touches(d.frame, on: .left, $0.frame) } && displays.contains { touches(d.frame, on: .right, $0.frame) }
        }
        return between ?? displays.max { neighbourCount($0, in: displays) < neighbourCount($1, in: displays) }
    }

    static func neighbourCount(_ d: Display, in displays: [Display]) -> Int {
        displays.filter { o in
            o != d && (touches(d.frame, on: .left, o.frame) || touches(d.frame, on: .right, o.frame)
                || touches(d.frame, on: .bottom, o.frame) || touches(o.frame, on: .bottom, d.frame))
        }.count
    }

    /// macOS only puts the Dock on a display whose whole Dock edge borders no other display.
    /// This makes `target` the main display and slides everything beyond that edge along it,
    /// just far enough that nothing touches the edge any more (they keep touching at a corner).
    public static func plan(for displays: [Display], targetUUID: String, edge: DockEdge) -> LayoutPlan? {
        guard displays.contains(where: { $0.uuid == targetUUID }) else { return nil }
        let real = LayoutPlan.normalised(displays, on: targetUUID)
        let target = real.first { $0.uuid == targetUUID }!.frame

        let beyond = real.filter { isBeyond($0.frame, edge, of: target) }
        let blockers = beyond.filter { touches(target, on: edge, $0.frame) }
        guard !blockers.isEmpty else { return LayoutPlan(real: real, pinned: real, targetUUID: targetUUID, edge: edge) }

        let others = real.filter { d in !beyond.contains(d) }
        let slide = slideClearing(blockers.map(\.frame), of: target, edge: edge, group: beyond.map(\.frame), others: others.map(\.frame))
        let pinned = real.map { beyond.contains($0) ? $0.moved(by: slide) : $0 }
        return LayoutPlan(real: real, pinned: pinned, targetUUID: targetUUID, edge: edge)
    }

    /// Displays whose `edge` no other display touches: pushing the pointer there would pull the Dock onto them.
    public static func freeEdgeDisplays(in displays: [Display], edge: DockEdge) -> [Display] {
        displays.filter { d in !displays.contains { $0 != d && touches(d.frame, on: edge, $0.frame) } }
    }

    // MARK: - Geometry

    /// True when `other` sits directly against `frame`'s `edge`, sharing part of it.
    static func touches(_ frame: CGRect, on edge: DockEdge, _ other: CGRect) -> Bool {
        switch edge {
        case .left: return other.maxX == frame.minX && overlaps(other.minY...other.maxY, frame.minY...frame.maxY)
        case .right: return other.minX == frame.maxX && overlaps(other.minY...other.maxY, frame.minY...frame.maxY)
        case .bottom: return other.minY == frame.maxY && overlaps(other.minX...other.maxX, frame.minX...frame.maxX)
        }
    }

    static func isBeyond(_ other: CGRect, _ edge: DockEdge, of frame: CGRect) -> Bool {
        switch edge {
        case .left: return other.maxX <= frame.minX
        case .right: return other.minX >= frame.maxX
        case .bottom: return other.minY >= frame.maxY
        }
    }

    /// Strict overlap: ranges that only meet at an end don't count.
    static func overlaps(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> Bool {
        a.lowerBound < b.upperBound && b.lowerBound < a.upperBound
    }

    /// Two displays cover the same pixels (merely touching doesn't count).
    static func overlapsInside(_ a: CGRect, _ b: CGRect) -> Bool {
        overlaps(a.minX...a.maxX, b.minX...b.maxX) && overlaps(a.minY...a.maxY, b.minY...b.maxY)
    }

    /// The smallest slide along the edge that clears it, without the moved group landing on another display.
    static func slideClearing(_ blockers: [CGRect], of target: CGRect, edge: DockEdge, group: [CGRect], others: [CGRect]) -> CGVector {
        let alongY = edge != .bottom
        let lo = blockers.map { alongY ? $0.minY : $0.minX }.min()!
        let hi = blockers.map { alongY ? $0.maxY : $0.maxX }.max()!
        let towardStart = (alongY ? target.minY : target.minX) - hi
        let towardEnd = (alongY ? target.maxY : target.maxX) - lo
        let vector = { (amount: CGFloat) in alongY ? CGVector(dx: 0, dy: amount) : CGVector(dx: amount, dy: 0) }
        let collides = { (amount: CGFloat) in
            group.contains { g in others.contains { overlapsInside($0, g.offsetBy(dx: vector(amount).dx, dy: vector(amount).dy)) } }
        }
        // Shorter slide first; on a tie, up (or left).
        let candidates = abs(towardEnd) < abs(towardStart) ? [towardEnd, towardStart] : [towardStart, towardEnd]
        for amount in candidates where !collides(amount) { return vector(amount) }
        // Both nearest spots are taken: keep sliding the shorter way until the group fits.
        var amount = candidates[0]
        let step: CGFloat = amount < 0 ? -40 : 40
        while collides(amount), abs(amount) < 20_000 { amount += step }
        return vector(amount)
    }
}
