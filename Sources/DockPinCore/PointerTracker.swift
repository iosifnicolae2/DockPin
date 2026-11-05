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
///
/// macOS's delta is always the distance from its previous event's location, so the catch-up event's delta holds
/// DockPin's own correction too: the hand's move in it is the location minus where the pointer was put. Where the
/// jump is short (a pointer held at the bridge is put back a few points), a stale move and the catch-up land
/// about as far from the spot: the one whose hand move goes on like the hand's previous one is taken. Taking a
/// catch-up for a stale move there added DockPin's correction to the next spot, again and again, and sent a
/// pointer held at the bridge up the display at a real mouse's rate.
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
        var hand: CGVector          // the hand's last move
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
        return jump(to: fixed, from: location, hand: delta, time: time)
    }

    private mutating func jump(to target: CGPoint, from base: CGPoint, hand: CGVector, time: TimeInterval) -> Action {
        var landing = target
        var rest = CGVector.zero
        if !rules.catchUpCanPass(from: base, to: target) {
            landing = rules.borderPoint(for: target, from: base)
            rest = CGVector(dx: target.x - landing.x, dy: target.y - landing.y)
        }
        pending = Pending(spot: landing, stale: base, remainder: rest, hand: hand, deadline: time + Self.catchUpWindow, retries: 0)
        previous = landing
        return .jump(landing)
    }

    private mutating func followUntilCaughtUp(location: CGPoint, delta: CGVector, time: TimeInterval) -> Action {
        guard var p = pending else { return .pass }
        let hand = CGVector(dx: location.x - p.spot.x, dy: location.y - p.spot.y)  // if macOS has caught up
        if hasCaughtUp(location, hand: hand, delta: delta, p) {
            pending = nil
            if p.remainder != .zero, rules.onSameDisplay(location, p.spot) {
                // Now add the rest of the flick: a jump within this display, which macOS follows directly.
                let target = rules.clampedOntoDisplay(CGPoint(x: location.x + p.remainder.dx, y: location.y + p.remainder.dy), near: location)
                pending = Pending(spot: target, stale: location, remainder: .zero, hand: hand, deadline: time + Self.catchUpWindow, retries: 0)
                previous = target
                return .jump(target)
            }
            // An ordinary move by the hand from where the pointer was put (passed on as it is, unless it crosses
            // where the real arrangement doesn't: pushed on at the bridge, it is held there again).
            previous = p.spot
            return handle(location: location, delta: hand, time: time)
        }
        p.stale = location
        p.hand = delta
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
            return jump(to: next, from: location, hand: delta, time: time)  // crossed again (e.g. straight back)
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

    /// macOS now computes moves from where the pointer was put: this event's location is that spot plus at most
    /// a hand's move (`hand`), and that move goes on like the hand's last one at least as well as the stale reading
    /// (the event's delta, from macOS's old position) does. After a long jump the two are a jump apart; after a short
    /// one (at the bridge) only the hand's own pace tells them apart.
    private func hasCaughtUp(_ location: CGPoint, hand: CGVector, delta: CGVector, _ p: Pending) -> Bool {
        let fromSpot = hypot(hand.dx, hand.dy)
        guard fromSpot <= PointerRules.largestHandMove else { return false }
        if fromSpot <= 2 { return true }
        let asCaughtUp = hypot(hand.dx - p.hand.dx, hand.dy - p.hand.dy)
        let asStale = hypot(delta.dx - p.hand.dx, delta.dy - p.hand.dy)
        return asCaughtUp <= asStale
    }
}
