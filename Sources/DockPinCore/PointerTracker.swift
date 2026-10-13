import CoreGraphics
import Foundation

/// Follows the pointer event by event and says what to do with each move, including the moments right
/// after DockPin jumped the pointer across a moved border.
///
/// After such a jump, macOS keeps computing real mouse moves from its own (old) idea of the pointer
/// position for a few milliseconds (up to a few tens), then catches up: from then on its moves start where
/// the pointer was put, and the catch-up event's delta holds the whole jump plus that event's hand move.
/// Its position follows a straight line that can only pass where displays share an edge. So:
/// - a crossing lands where that line can reach (just across the border for a fast flick; the rest of the
///   flick is added once macOS has caught up);
/// - until then, the stale moves aren't passed on (they would pull the pointer back across); the pointer
///   follows the hand from where it really is, as far as the catch-up can still reach;
/// - once caught up, every event is passed on as it is, so the pointer and a dragged window move with the
///   hand from the first event on (DockPin posting a corrected copy of each would leave macOS a step behind
///   again, and the pointer would crawl at half speed).
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
        var stale: CGPoint          // where macOS still thinks it is (the last event's location)
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
        pending = Pending(spot: landing, stale: base, remainder: rest, deadline: time + Self.catchUpWindow, retries: 0)
        previous = landing
        return .jump(landing)
    }

    private mutating func followUntilCaughtUp(location: CGPoint, delta: CGVector, time: TimeInterval) -> Action {
        guard var p = pending else { return .pass }
        if hasCaughtUp(location, p) {
            pending = nil
            previous = location
            guard p.remainder != .zero else { return .pass }
            // Now add the rest of the flick: a jump within this display, which macOS follows directly.
            let target = rules.clampedOntoDisplay(CGPoint(x: location.x + p.remainder.dx, y: location.y + p.remainder.dy), near: location)
            pending = Pending(spot: target, stale: location, remainder: .zero, deadline: time + Self.catchUpWindow, retries: 0)
            previous = target
            return .jump(target)
        }
        p.stale = location
        let isCatchUp = hypot(delta.dx, delta.dy) > PointerRules.largestHandMove
        if isCatchUp || time > p.deadline {
            // The catch-up landed elsewhere, or never came: put the pointer back where it belongs, so macOS
            // catches up once more.
            guard p.retries < 3 else {
                // Still no catch-up: take this as an ordinary move from where the pointer is. (Passing it on would
                // let a pointer held at the bridge through, after a second of pushing.)
                pending = nil
                previous = p.spot
                return handle(location: location, delta: delta, time: time)
            }
            p.retries += 1
            p.deadline = time + Self.catchUpWindow
            pending = p
            return .jump(p.spot)
        }
        // A stale move: follow the hand from where the pointer really is.
        let expected = CGPoint(x: p.spot.x + delta.dx, y: p.spot.y + delta.dy)
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

    /// macOS now computes moves from where the pointer was put: this event's location is that spot plus at
    /// most a hand's move, on the same display, and nearer to it than to macOS's old position.
    private func hasCaughtUp(_ location: CGPoint, _ p: Pending) -> Bool {
        let fromSpot = hypot(location.x - p.spot.x, location.y - p.spot.y)
        let fromStale = hypot(location.x - p.stale.x, location.y - p.stale.y)
        return rules.onSameDisplay(location, p.spot) && fromSpot <= PointerRules.largestHandMove && (fromSpot < fromStale || fromSpot <= 2)
    }
}
