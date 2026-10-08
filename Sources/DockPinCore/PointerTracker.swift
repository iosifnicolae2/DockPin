import CoreGraphics
import Foundation

/// Follows the pointer event by event and says what to do with each move, including the moments right
/// after DockPin jumped the pointer across a moved border.
///
/// After such a jump, macOS keeps computing real mouse moves from its own (old) idea of the pointer
/// position for a few tens of milliseconds, then sends a catch-up event that carries the whole jump.
/// Passing the stale moves on would pull the pointer back across; so until macOS has caught up, the
/// pointer is moved from where it really is by each event's movement.
public struct PointerTracker {
    public enum Action: Equatable {
        /// Leave the event as it is.
        case pass
        /// Same display: give the event this location.
        case move(CGPoint)
        /// Another display: drop the event and put the pointer here.
        case jump(CGPoint)
    }

    public let rules: PointerRules
    private(set) var previous: CGPoint?
    /// Where the pointer really is while macOS's own position is still catching up after a jump.
    private(set) var pending: (spot: CGPoint, deadline: TimeInterval, retries: Int)?
    static let catchUpWindow: TimeInterval = 0.3

    public init(rules: PointerRules) {
        self.rules = rules
    }

    public mutating func handle(location: CGPoint, delta: CGVector, time: TimeInterval) -> Action {
        if pending != nil { return followUntilCaughtUp(location: location, delta: delta, time: time) }
        guard let fixed = rules.correction(from: previous, to: location, delta: delta) else {
            previous = location
            return .pass
        }
        previous = fixed
        if rules.onSameDisplay(location, fixed) { return .move(fixed) }
        pending = (fixed, time + Self.catchUpWindow, 0)
        return .jump(fixed)
    }

    private mutating func followUntilCaughtUp(location: CGPoint, delta: CGVector, time: TimeInterval) -> Action {
        guard var p = pending else { return .pass }
        let expected = CGPoint(x: p.spot.x + delta.dx, y: p.spot.y + delta.dy)
        let near = { (a: CGPoint, b: CGPoint, within: CGFloat) in hypot(a.x - b.x, a.y - b.y) <= within }
        // Caught up: macOS reports the pointer where it really is (where it was put, or that plus this move).
        if rules.onSameDisplay(location, p.spot), near(location, p.spot, 2) || near(location, expected, 4) {
            pending = nil
            previous = location
            return .pass
        }
        let isCatchUp = hypot(delta.dx, delta.dy) > PointerRules.largestHandMove
        if isCatchUp || time > p.deadline {
            // The catch-up landed elsewhere (stuck at a corner, or short by the movement the old edge swallowed),
            // or never came: put the pointer where it is meant to be again, so macOS catches up once more.
            guard p.retries < 3 else { pending = nil; previous = location; return .pass }
            p.retries += 1
            p.deadline = time + Self.catchUpWindow
            pending = p
            return .jump(p.spot)
        }
        // Still stale: move the pointer by this event's movement from where it really is.
        let natural = rules.clampedOntoDisplay(expected, near: p.spot)
        let next = rules.correction(from: p.spot, to: natural, delta: delta) ?? natural
        previous = next
        if rules.onSameDisplay(next, p.spot) {
            p.spot = next
            pending = p
            return .move(next)
        }
        pending = (next, time + Self.catchUpWindow, 0)
        return .jump(next)
    }
}
