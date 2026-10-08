import CoreGraphics
import Foundation

/// Follows the pointer event by event and says what to do with each move, including the moments right
/// after DockPin jumped the pointer across a moved border.
///
/// After such a jump, macOS keeps computing real mouse moves from its own (old) idea of the pointer
/// position for a few tens of milliseconds, then catches up with an event that carries the whole jump,
/// moving its position in a straight line that can only pass where displays share an edge. So:
/// - a crossing lands where that line can reach (just across the border for a fast flick; the rest of the
///   flick is added once macOS has caught up);
/// - until then, the stale moves aren't passed on (they would pull the pointer back across); the pointer
///   follows the hand from where it really is, as far as the catch-up can still reach.
public struct PointerTracker {
    public enum Action: Equatable {
        /// Leave the event as it is.
        case pass
        /// Same display: put the pointer here (and give the event this location).
        case move(CGPoint)
        /// Another display: drop the event and put the pointer here.
        case jump(CGPoint)
    }

    struct Pending {
        var spot: CGPoint           // where the pointer really is
        var remainder: CGVector     // movement still to add once macOS has caught up
        var deadline: TimeInterval
        var retries: Int
    }

    public let rules: PointerRules
    private(set) var previous: CGPoint?
    private(set) var pending: Pending?
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
        return jump(to: fixed, from: location, time: time)
    }

    private mutating func jump(to target: CGPoint, from base: CGPoint, time: TimeInterval) -> Action {
        var landing = target
        var rest = CGVector.zero
        if !rules.catchUpCanPass(from: base, to: target) {
            landing = rules.borderPoint(for: target, from: base)
            rest = CGVector(dx: target.x - landing.x, dy: target.y - landing.y)
        }
        pending = Pending(spot: landing, remainder: rest, deadline: time + Self.catchUpWindow, retries: 0)
        previous = landing
        return .jump(landing)
    }

    private mutating func followUntilCaughtUp(location: CGPoint, delta: CGVector, time: TimeInterval) -> Action {
        guard var p = pending else { return .pass }
        let expected = CGPoint(x: p.spot.x + delta.dx, y: p.spot.y + delta.dy)
        let near = { (a: CGPoint, b: CGPoint, within: CGFloat) in hypot(a.x - b.x, a.y - b.y) <= within }
        // Caught up: macOS reports the pointer where it really is (where it was put, or that plus this move).
        if rules.onSameDisplay(location, p.spot), near(location, p.spot, 2) || near(location, expected, 4) {
            pending = nil
            previous = location
            guard p.remainder != .zero else { return .pass }
            // Now add the rest of the flick: a jump within this display, which macOS follows directly.
            let target = rules.clampedOntoDisplay(CGPoint(x: location.x + p.remainder.dx, y: location.y + p.remainder.dy), near: location)
            pending = Pending(spot: target, remainder: .zero, deadline: time + Self.catchUpWindow, retries: 0)
            previous = target
            return .jump(target)
        }
        let isCatchUp = hypot(delta.dx, delta.dy) > PointerRules.largestHandMove
        if isCatchUp || time > p.deadline {
            // The catch-up landed elsewhere, or never came: put the pointer back where it belongs, so macOS
            // catches up once more.
            guard p.retries < 3 else { pending = nil; previous = location; return .pass }
            p.retries += 1
            p.deadline = time + Self.catchUpWindow
            pending = p
            return .jump(p.spot)
        }
        // A stale move: follow the hand from where the pointer really is.
        let natural = rules.clampedOntoDisplay(expected, near: p.spot)
        let next = rules.correction(from: p.spot, to: natural, delta: delta) ?? natural
        if !rules.onSameDisplay(next, p.spot) {
            return jump(to: next, from: location, time: time)  // crossed again (e.g. straight back)
        }
        if rules.catchUpCanPass(from: location, to: next) {
            p.spot = next
            previous = next
        } else {
            p.remainder.dx += delta.dx  // beyond what the catch-up can reach: add it once caught up
            p.remainder.dy += delta.dy
        }
        pending = p
        return .move(p.spot)
    }
}
