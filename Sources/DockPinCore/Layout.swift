import CoreGraphics

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
}

/// The real arrangement the user set up, and the "pinned" one DockPin applies so a left Dock can sit on `target`.
public struct LayoutPlan: Equatable, Codable {
    public var real: [Display]
    public var pinned: [Display]
    public var targetUUID: String

    /// Vertical offset (pinned minus real) per display uuid, after both are normalised so the target is at (0, 0).
    public var shiftByUUID: [String: CGFloat] {
        var shifts: [String: CGFloat] = [:]
        let realByUUID = Dictionary(uniqueKeysWithValues: Self.normalised(real, on: targetUUID).map { ($0.uuid, $0.frame) })
        for display in pinned {
            guard let realFrame = realByUUID[display.uuid] else { continue }
            shifts[display.uuid] = display.frame.minY - realFrame.minY
        }
        return shifts
    }

    static func normalised(_ displays: [Display], on targetUUID: String) -> [Display] {
        guard let origin = displays.first(where: { $0.uuid == targetUUID })?.frame.origin else { return displays }
        return displays.map { d in
            var moved = d
            moved.frame = d.frame.offsetBy(dx: -origin.x, dy: -origin.y)
            return moved
        }
    }
}

public enum LayoutPlanner {
    /// The display the user means by "center": one with a display touching it on both its left and right side.
    public static func centerDisplay(in displays: [Display]) -> Display? {
        displays.first { d in
            displays.contains { touchesOnLeft(of: d.frame, $0.frame) } && displays.contains { touchesOnLeft(of: $0.frame, d.frame) }
        }
    }

    /// Makes `target` the main display and lifts every display left of it above its top edge,
    /// so the target's whole left edge is free (macOS only puts a left Dock on such a display).
    public static func plan(for displays: [Display], targetUUID: String) -> LayoutPlan? {
        guard let target = displays.first(where: { $0.uuid == targetUUID }) else { return nil }
        let real = LayoutPlan.normalised(displays, on: targetUUID)
        let targetFrame = CGRect(origin: .zero, size: target.frame.size)

        let leftGroup = real.filter { $0.frame.maxX <= targetFrame.minX }
        let blockers = leftGroup.filter { overlapsVertically($0.frame, targetFrame) }
        guard let lowestBlockerBottom = blockers.map(\.frame.maxY).max() else {
            return LayoutPlan(real: real, pinned: real, targetUUID: targetUUID)
        }
        let lift = targetFrame.minY - lowestBlockerBottom
        let pinned = real.map { d in
            guard leftGroup.contains(d) else { return d }
            var moved = d
            moved.frame = d.frame.offsetBy(dx: 0, dy: lift)
            return moved
        }
        return LayoutPlan(real: real, pinned: pinned, targetUUID: targetUUID)
    }

    /// True when `right` sits directly right of `left`, sharing part of an edge.
    static func touchesOnLeft(of right: CGRect, _ left: CGRect) -> Bool {
        left.maxX == right.minX && overlapsVertically(left, right)
    }

    static func overlapsVertically(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minY < b.maxY && b.minY < a.maxY
    }

    /// Left edges no other display touches: pushing the pointer there would pull a left Dock onto that display.
    public static func freeLeftEdgeDisplays(in displays: [Display]) -> [Display] {
        displays.filter { d in !displays.contains { touchesOnLeft(of: d.frame, $0.frame) } }
    }
}
