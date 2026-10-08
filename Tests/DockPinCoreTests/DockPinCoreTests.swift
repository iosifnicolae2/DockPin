import CoreGraphics
import XCTest
@testable import DockPinCore

/// The user's desk: LG | Odyssey | PHL in a row, the laptop below the Odyssey; the laptop is main.
let builtIn = Display(uuid: "B", name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1728, height: 1117))
let odyssey = Display(uuid: "O", name: "Odyssey", frame: CGRect(x: -97, y: -1080, width: 1920, height: 1080))
let lg = Display(uuid: "L", name: "LG", frame: CGRect(x: -2017, y: -1080, width: 1920, height: 1080))
let phl = Display(uuid: "P", name: "PHL", frame: CGRect(x: 1823, y: -1080, width: 1920, height: 1080))
let desk = [builtIn, odyssey, lg, phl]

func plan(_ edge: DockEdge) throws -> LayoutPlan {
    try XCTUnwrap(LayoutPlanner.plan(for: desk, targetUUID: "O", edge: edge, bridge: 0))
}

func origins(_ plan: LayoutPlan) -> [String: CGPoint] {
    Dictionary(uniqueKeysWithValues: plan.pinned.map { ($0.uuid, $0.frame.origin) })
}

final class LayoutPlannerTests: XCTestCase {
    func testCenterIsTheDisplayWithNeighboursOnBothSides() {
        XCTAssertEqual(LayoutPlanner.centerDisplay(in: desk)?.uuid, "O")
    }

    func testWithOneSideUnpluggedTheCenterIsTheBestConnectedDisplay() {
        XCTAssertEqual(LayoutPlanner.centerDisplay(in: [builtIn, odyssey, lg])?.uuid, "O", "touches the LG and the laptop")
    }

    func testLeftDockLiftsTheLeftDisplayAboveTheCenter() throws {
        let o = origins(try plan(.left))
        XCTAssertEqual(o["O"], CGPoint(x: 0, y: 0), "the center becomes main")
        XCTAssertEqual(o["L"], CGPoint(x: -1920, y: -1080))
        XCTAssertEqual(o["P"], CGPoint(x: 1920, y: 0))
        XCTAssertEqual(o["B"], CGPoint(x: 97, y: 1080))
    }

    func testRightDockLiftsTheRightDisplay() throws {
        let o = origins(try plan(.right))
        XCTAssertEqual(o["P"], CGPoint(x: 1920, y: -1080))
        XCTAssertEqual(o["L"], CGPoint(x: -1920, y: 0))
    }

    func testBottomDockSlidesTheLaptopSidewaysTheShorterWay() throws {
        let o = origins(try plan(.bottom))
        XCTAssertEqual(o["B"], CGPoint(x: 1920, y: 1080), "1823 px right beats 1825 px left")
        XCTAssertEqual(o["L"], CGPoint(x: -1920, y: 0))
    }

    func testSlidePrefersEmptySpaceOverTuckingUnderAnotherDisplay() throws {
        // Today's desk without the PHL: left would put the laptop under the LG (a long shared edge),
        // right leaves it touching nothing but a corner, so right wins although it's 192 px longer.
        let o = Display(uuid: "O", name: "Odyssey", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let b = Display(uuid: "B", name: "Built-in", frame: CGRect(x: 0, y: 1080, width: 1728, height: 1117))
        let l = Display(uuid: "L", name: "LG", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        let p = try XCTUnwrap(LayoutPlanner.plan(for: [o, b, l], targetUUID: "O", edge: .bottom, bridge: 0))
        XCTAssertEqual(origins(p)["B"], CGPoint(x: 1920, y: 1080))
    }

    func testTheBridgeLetsMacOSFollowAJumpAcrossInAStraightLine() throws {
        // Left Dock: the LG shares 96 pt of the Odyssey's top edge instead of a bare corner,
        // and still leaves the Odyssey's left edge free.
        let left = try XCTUnwrap(LayoutPlanner.plan(for: desk, targetUUID: "O", edge: .left))
        XCTAssertEqual(origins(left)["L"], CGPoint(x: -1824, y: -1080))
        XCTAssertTrue(LayoutPlanner.freeEdgeDisplays(in: left.pinned, edge: .left).contains { $0.uuid == "O" })
        // Bottom Dock without the PHL: the laptop shares 96 pt of the Odyssey's right edge.
        let o = Display(uuid: "O", name: "Odyssey", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let b = Display(uuid: "B", name: "Built-in", frame: CGRect(x: 0, y: 1080, width: 1728, height: 1117))
        let l = Display(uuid: "L", name: "LG", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        let bottom = try XCTUnwrap(LayoutPlanner.plan(for: [o, b, l], targetUUID: "O", edge: .bottom))
        XCTAssertEqual(origins(bottom)["B"], CGPoint(x: 1920, y: 984))
        XCTAssertTrue(LayoutPlanner.freeEdgeDisplays(in: bottom.pinned, edge: .bottom).contains { $0.uuid == "O" })
    }

    func testNoBridgeWhereItWouldLandOnAnotherDisplay() throws {
        // With the PHL connected, nudging the laptop up would put it on the PHL.
        let bottom = try XCTUnwrap(LayoutPlanner.plan(for: desk, targetUUID: "O", edge: .bottom))
        XCTAssertEqual(origins(bottom)["B"], CGPoint(x: 1920, y: 1080))
    }

    func testEveryPlanLeavesTheDockEdgeFree() throws {
        for edge in DockEdge.allCases {
            let p = try plan(edge)
            XCTAssertTrue(LayoutPlanner.freeEdgeDisplays(in: p.pinned, edge: edge).contains { $0.uuid == "O" }, "\(edge)")
        }
    }

    func testNothingToMoveWhenTheEdgeIsAlreadyFree() throws {
        let p = try plan(.left)
        let again = try XCTUnwrap(LayoutPlanner.plan(for: p.pinned, targetUUID: "O", edge: .left, bridge: 0))
        XCTAssertEqual(again.pinned, p.pinned)
    }

    func testSlideAvoidsLandingOnAnotherDisplay() throws {
        // The display right of the target reaches below it, right where the shorter slide would put the
        // display underneath, so that one goes the longer way instead.
        let target = Display(uuid: "T", name: "T", frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let below = Display(uuid: "U", name: "U", frame: CGRect(x: 150, y: 1000, width: 800, height: 600))
        let right = Display(uuid: "R", name: "R", frame: CGRect(x: 1000, y: 500, width: 1000, height: 1000))
        let p = try XCTUnwrap(LayoutPlanner.plan(for: [target, below, right], targetUUID: "T", edge: .bottom, bridge: 0))
        XCTAssertEqual(origins(p)["U"], CGPoint(x: -800, y: 1000))
    }
}

/// Every edge of every display must behave as in the user's real arrangement (System Settings > Displays):
/// a move crosses only where two displays share a stretch of edge, never through a bare corner, and
/// otherwise stops at the edge (sliding along it). Checked for every Dock position, with and without the
/// bridge, on the desk with and without the PHL, by simulating macOS in the pinned layout plus DockPin.
final class EdgeAuditTests: XCTestCase {
    struct Side { let name: String; let point: (CGRect, CGFloat) -> CGPoint; let out: CGVector; let along: CGVector }
    let sides = [
        Side(name: "left", point: { r, t in CGPoint(x: r.minX + 1, y: r.minY + t * r.height) }, out: CGVector(dx: -3, dy: 0), along: CGVector(dx: 0, dy: 1)),
        Side(name: "right", point: { r, t in CGPoint(x: r.maxX - 1.5, y: r.minY + t * r.height) }, out: CGVector(dx: 3, dy: 0), along: CGVector(dx: 0, dy: 1)),
        Side(name: "top", point: { r, t in CGPoint(x: r.minX + t * r.width, y: r.minY + 1) }, out: CGVector(dx: 0, dy: -3), along: CGVector(dx: 1, dy: 0)),
        Side(name: "bottom", point: { r, t in CGPoint(x: r.minX + t * r.width, y: r.maxY - 1.5) }, out: CGVector(dx: 0, dy: 3), along: CGVector(dx: 1, dy: 0)),
    ]

    /// Where a move from `s` (on `from`) by `d` ends, given `displays`: crossing only through a shared stretch of edge.
    static func land(_ s: CGPoint, _ d: CGVector, on from: CGRect, among displays: [CGRect]) -> (CGRect, CGPoint) {
        func entered(_ p: CGPoint) -> CGRect? {
            if from.contains(p) { return from }
            guard let b = displays.first(where: { $0 != from && $0.contains(p) }) else { return nil }
            if b.maxX == from.minX || b.minX == from.maxX { return p.y >= max(from.minY, b.minY) && p.y < min(from.maxY, b.maxY) ? b : nil }
            if b.maxY == from.minY || b.minY == from.maxY { return p.x >= max(from.minX, b.minX) && p.x < min(from.maxX, b.maxX) ? b : nil }
            return nil
        }
        let t = CGPoint(x: s.x + d.dx, y: s.y + d.dy)
        let clamped = CGPoint(x: min(max(t.x, from.minX), from.maxX - 1), y: min(max(t.y, from.minY), from.maxY - 1))
        for p in [t, CGPoint(x: t.x, y: clamped.y), CGPoint(x: clamped.x, y: t.y)] {
            if let r = entered(p) { return (r, p) }
        }
        return (from, clamped)
    }

    func audit(_ displays: [Display], edge: DockEdge, bridge: CGFloat, file: StaticString = #filePath, line: UInt = #line) throws {
        let plan = try XCTUnwrap(LayoutPlanner.plan(for: displays, targetUUID: "O", edge: edge, bridge: bridge))
        let rules = PointerRules(plan: plan)
        let real = Dictionary(uniqueKeysWithValues: plan.real.map { ($0.uuid, $0.frame) })
        let pinned = Dictionary(uniqueKeysWithValues: plan.pinned.map { ($0.uuid, $0.frame) })
        let off = { (u: String) in CGVector(dx: pinned[u]!.minX - real[u]!.minX, dy: pinned[u]!.minY - real[u]!.minY) }
        var checked = 0
        for d in plan.real {
            for side in sides {
                for i in 0...36 {
                    let length = side.along.dx != 0 ? d.frame.width : d.frame.height
                    let t = (2 + CGFloat(i) / 36 * (length - 4)) / length  // the whole edge, corners included
                    let s = side.point(d.frame, t)
                    let sp = CGPoint(x: s.x + off(d.uuid).dx, y: s.y + off(d.uuid).dy)
                    for wobble: CGFloat in [0, 1, -1] {
                        let move = CGVector(dx: side.out.dx + side.along.dx * wobble, dy: side.out.dy + side.along.dy * wobble)
                        let (expectedFrame, expected) = Self.land(s, move, on: d.frame, among: plan.real.map(\.frame))
                        let (_, native) = Self.land(sp, move, on: pinned[d.uuid]!, among: plan.pinned.map(\.frame))
                        let fixed = rules.correction(from: sp, to: native, delta: move) ?? native
                        guard let landed = plan.pinned.first(where: { $0.frame.contains(fixed) }) else {
                            XCTFail("\(edge) bridge \(bridge): \(d.name) \(side.name) at \(s): pointer left every display (\(fixed))", file: file, line: line)
                            continue
                        }
                        let finalReal = CGPoint(x: fixed.x - off(landed.uuid).dx, y: fixed.y - off(landed.uuid).dy)
                        let onScreen = real[landed.uuid] == expectedFrame
                        let spot = hypot(finalReal.x - expected.x, finalReal.y - expected.y) <= 1.5
                        if !(onScreen && spot) {
                            XCTFail("\(edge) bridge \(bridge): \(d.name) \(side.name) at \(s) moving \(move): ended on \(landed.name) at \(finalReal) (real), expected \(expected)", file: file, line: line)
                        }
                        checked += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 0, file: file, line: line)
    }

    func testEveryEdgeOfTheFullDeskBehavesAsInTheRealArrangement() throws {
        for edge in DockEdge.allCases {
            for bridge in [0, LayoutPlanner.defaultBridge] { try audit(desk, edge: edge, bridge: bridge) }
        }
    }

    func testEveryEdgeWithThePHLUnpluggedBehavesAsInTheRealArrangement() throws {
        // Today's desk: in reality the LG's bottom-right corner touches the laptop's top-left corner, which
        // must not let the pointer from the laptop over to the LG (the user's report).
        let o = Display(uuid: "O", name: "Odyssey", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let b = Display(uuid: "B", name: "Built-in", frame: CGRect(x: 0, y: 1080, width: 1728, height: 1117))
        let l = Display(uuid: "L", name: "LG", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        for edge in DockEdge.allCases {
            for bridge in [0, LayoutPlanner.defaultBridge] { try audit([o, b, l], edge: edge, bridge: bridge) }
        }
    }

    func testMovingLeftAlongTheLaptopsTopRowStaysOnTheLaptop() throws {
        // The reported case exactly: a tiny upward wobble at the laptop's top-left must not cross to the LG.
        let o = Display(uuid: "O", name: "Odyssey", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let b = Display(uuid: "B", name: "Built-in", frame: CGRect(x: 0, y: 1080, width: 1728, height: 1117))
        let l = Display(uuid: "L", name: "LG", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        let rules = PointerRules(plan: try XCTUnwrap(LayoutPlanner.plan(for: [o, b, l], targetUUID: "O", edge: .left)))
        let lg = CGRect(x: -1824, y: -1080, width: 1920, height: 1080)  // the LG in the pinned layout
        let wobbly = rules.correction(from: CGPoint(x: 1, y: 1080.4), to: CGPoint(x: 1, y: 1080), delta: CGVector(dx: -2, dy: -1))
        XCTAssertFalse(lg.contains(wobbly ?? .zero), "never onto the LG through the corner: \(String(describing: wobbly))")
        XCTAssertEqual(wobbly, CGPoint(x: 0, y: 1079.4), "the upward part slides onto the Odyssey above, as in reality")
        let straight = rules.correction(from: CGPoint(x: 1, y: 1080.4), to: CGPoint(x: 0, y: 1080.4), delta: CGVector(dx: -2, dy: 0))
        XCTAssertEqual(straight, CGPoint(x: 1, y: 1080.4), "straight left: stays at the laptop's edge (1 pt off it, so the Dock isn't pulled there)")
    }
}

/// Events from the user's real-mouse capture (~/Library/Logs/DockPin/moves.log), on today's three displays.
final class RealCaptureTests: XCTestCase {
    var rules: PointerRules!

    override func setUpWithError() throws {
        let o = Display(uuid: "O", name: "Odyssey", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let b = Display(uuid: "B", name: "Built-in", frame: CGRect(x: 0, y: 1080, width: 1728, height: 1117))
        let l = Display(uuid: "L", name: "LG", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        rules = PointerRules(plan: try XCTUnwrap(LayoutPlanner.plan(for: [o, b, l], targetUUID: "O", edge: .left, bridge: 0)))
    }

    func testARealMouseCrossingAtTheEdgeLandsAtTheSameHeight() {
        // 25981.4: sub-pixel motion, integer delta -1 at the Odyssey's left edge.
        XCTAssertEqual(rules.correction(from: CGPoint(x: 0.39, y: 806.10), to: CGPoint(x: 0.16, y: 806.10), delta: CGVector(dx: -1, dy: 0)),
                       CGPoint(x: -0.61, y: -273.90))
    }

    // Regression: after a crossing, macOS sends its own catch-up event carrying the whole jump as its delta.
    // Replayed as a hand movement it sent the pointer to the LG's top row (25988.1) ...
    func testTheCatchUpEventAfterAWarpIsNotReplayedToTheTop() {
        XCTAssertNil(rules.correction(from: CGPoint(x: 0, y: 806.10), to: CGPoint(x: 0, y: 0), delta: CGVector(dx: 0, dy: -806)))
    }

    // ... or onto another screen: the LG's corner zone (26566.1) and then the laptop (26576.5).
    func testTheCatchUpEventAfterAWarpIsNotReplayedOntoAnotherScreen() {
        XCTAssertNil(rules.correction(from: CGPoint(x: -0.02, y: -1073.55), to: CGPoint(x: 0.23, y: 6.23), delta: CGVector(dx: 0, dy: 1080)))
        XCTAssertNil(rules.correction(from: CGPoint(x: 0, y: 1079.46), to: CGPoint(x: 0.23, y: 1079), delta: CGVector(dx: 30, dy: 1079)))
    }
}

final class FastFlickTests: XCTestCase {
    // Third real capture: a 71 pt flick put the pointer where macOS's catch-up line missed the bridge, so it
    // never caught up and the pointer lagged. Now the flick lands just across the border first, and the rest
    // follows once macOS has caught up.
    func testAFastFlickLandsAtTheBorderThenAddsTheRest() throws {
        var tracker = PointerTracker(rules: PointerRules(plan: try XCTUnwrap(LayoutPlanner.plan(for: desk, targetUUID: "O", edge: .left))))
        XCTAssertEqual(tracker.handle(location: CGPoint(x: 5, y: 572), delta: .zero, time: 0), .pass)  // 5 pt from the edge
        let first = tracker.handle(location: CGPoint(x: 0, y: 572), delta: CGVector(dx: -105, dy: 0), time: 0.001)
        XCTAssertEqual(first, .jump(CGPoint(x: 95, y: -508)), "just across the real border, same height")
        // macOS catches up (its event carries the jump) at that spot: now the rest of the flick.
        let rest = tracker.handle(location: CGPoint(x: 95, y: -508), delta: CGVector(dx: 95, dy: -1080), time: 0.012)
        XCTAssertEqual(rest, .jump(CGPoint(x: -4, y: -508)), "the whole 105 pt, in the end")
        XCTAssertEqual(tracker.handle(location: CGPoint(x: -4, y: -508), delta: CGVector(dx: -99, dy: 0), time: 0.02), .pass)
        XCTAssertEqual(tracker.handle(location: CGPoint(x: -10, y: -508), delta: CGVector(dx: -6, dy: 0), time: 0.03), .pass, "back to normal")
    }
}

/// Second real-mouse capture, replayed event by event (ms, location, integer delta) through the tracker.
final class RealCaptureTrackerTests: XCTestCase {
    var tracker: PointerTracker!
    let lg = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)

    override func setUpWithError() throws {
        let o = Display(uuid: "O", name: "Odyssey", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let b = Display(uuid: "B", name: "Built-in", frame: CGRect(x: 0, y: 1080, width: 1728, height: 1117))
        let l = Display(uuid: "L", name: "LG", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        let plan = try XCTUnwrap(LayoutPlanner.plan(for: [o, b, l], targetUUID: "O", edge: .left, bridge: 0))
        tracker = PointerTracker(rules: PointerRules(plan: plan))
    }

    func feed(_ events: [(Double, CGFloat, CGFloat, CGFloat, CGFloat)]) -> [PointerTracker.Action] {
        events.map { ms, x, y, dx, dy in tracker.handle(location: CGPoint(x: x, y: y), delta: CGVector(dx: dx, dy: dy), time: ms / 1000) }
    }

    func spot(_ a: PointerTracker.Action) -> CGPoint? {
        switch a {
        case .pass: return nil
        case .move(let p), .jump(let p): return p
        }
    }

    // Regression: "on fast moves it sometimes doesn't switch screens". After the jump to the LG, macOS kept
    // reporting the pointer at the Odyssey's edge (its old position) for ~40 ms; passed on, those moves
    // pulled the pointer back across, again and again.
    func testStaleMovesAfterAJumpDoNotPullThePointerBack() {
        let actions = feed([
            (674262.0, 6.77, 572.54, -1, 0), (674267.6, 0.00, 572.54, -9, 0),           // crossing
            (674278.4, 0.00, 572.54, -2, 0), (674289.2, 0.00, 572.54, 0, 0),            // stale
            (674292.8, 0.00, 572.54, -2, 0), (674293.3, 0.00, 572.54, -3, 0),
            (674293.8, 0.00, 572.54, -1, 0), (674295.0, 0.00, 572.54, -1, 0),
            (674302.7, 0.00, 572.54, -1, 0), (674307.1, 0.00, 572.54, 0, 0),
        ])
        XCTAssertEqual(actions[0], .pass)
        guard case .jump(let landing) = actions[1] else { return XCTFail("expected a jump, got \(actions[1])") }
        XCTAssertTrue(lg.contains(landing), "jumped onto the LG: \(landing)")
        for a in actions.dropFirst(2) {
            guard let p = spot(a) else { return XCTFail("a stale move was passed on: it would pull the pointer back") }
            XCTAssertTrue(lg.contains(p), "stays on the LG: \(p)")
            XCTAssertEqual(p.y, landing.y, accuracy: 0.01, "same height")
        }
    }

    // Regression: "on slow moves it jumps to the top". macOS's catch-up after the jump stopped at the
    // Odyssey's top-left corner (0, 0); the next move then crossed into the LG's top row.
    func testACatchUpStuckAtTheCornerDoesNotSendThePointerToTheTop() {
        let actions = feed([
            (675941.1, 0.82, 575.17, 0, 0), (675945.0, 0.59, 575.39, -1, 0),           // slow crossing
            (675953.5, 0.00, 0.00, -1, -574),                                           // catch-up, stuck at the corner
            (675957.4, 0.00, 0.00, 0, 0), (675965.6, 0.00, 0.00, 0, 0),
            (675988.4, 0.00, 0.00, -1, 0),                                              // used to cross to the LG's top
        ])
        guard case .jump(let landing) = actions[1] else { return XCTFail("expected a jump, got \(actions[1])") }
        XCTAssertEqual(landing.y, 575.17 - 1080, accuracy: 0.01, "replayed from the previous spot, as in the capture")
        XCTAssertEqual(actions[2], .jump(landing), "the pointer is put back where it belongs")
        for a in actions.dropFirst(3) {
            guard let p = spot(a) else { return XCTFail("a move from the stuck corner was passed on") }
            XCTAssertTrue(lg.contains(p) && p.y > -1000, "on the LG at its height, not its top row: \(p)")
        }
    }
}

final class PointerRulesTests: XCTestCase {
    func testLeavingTheCenterLeftwardsLandsOnTheLGAtTheSameHeight() throws {
        let rules = PointerRules(plan: try plan(.left))
        XCTAssertEqual(rules.correction(from: CGPoint(x: 2, y: 500), to: CGPoint(x: 0, y: 500), delta: CGVector(dx: -5, dy: 0)),
                       CGPoint(x: -3, y: -580), "carries on with the 3 px the edge swallowed")
    }

    func testLeavingTheLGRightwardsReturnsAtTheSameHeight() throws {
        let rules = PointerRules(plan: try plan(.left))
        XCTAssertEqual(rules.correction(from: CGPoint(x: -2, y: -580), to: CGPoint(x: -1, y: -580), delta: CGVector(dx: 3, dy: 0)),
                       CGPoint(x: 1, y: 500))
    }

    func testReachingAMovedBorderWithoutPushingPastItIsLeftAlone() throws {
        // The move ends exactly on the edge: nothing was swallowed, so nothing to carry across yet.
        let rules = PointerRules(plan: try plan(.left))
        XCTAssertNil(rules.correction(from: CGPoint(x: 6, y: 500), to: CGPoint(x: 0, y: 500), delta: CGVector(dx: -6, dy: 0)))
    }

    func testSubPixelRoundingAlongAnEdgeIsLeftAlone() throws {
        // A real mouse sliding down the Odyssey's left edge: integer deltas, fractional positions.
        let rules = PointerRules(plan: try plan(.left))
        XCTAssertNil(rules.correction(from: CGPoint(x: 1, y: 1010.3), to: CGPoint(x: 0, y: 1011.86), delta: CGVector(dx: -1, dy: 2)))
    }

    func testOrdinaryMovesAndSharedBordersAreLeftAlone() throws {
        let rules = PointerRules(plan: try plan(.left))
        XCTAssertNil(rules.correction(from: CGPoint(x: 903, y: 500), to: CGPoint(x: 900, y: 500), delta: CGVector(dx: -3, dy: 0)))
        XCTAssertNil(rules.correction(from: CGPoint(x: 1918, y: 500), to: CGPoint(x: 1921, y: 500), delta: CGVector(dx: 3, dy: 0)),
                     "Odyssey -> PHL is a real border")
        XCTAssertNil(rules.correction(from: CGPoint(x: 5, y: 500), to: CGPoint(x: 0, y: 1079), delta: CGVector(dx: 0, dy: 0)))
    }

    func testThePinnedOnlyCornerDoesNotLetThePointerThrough() throws {
        // In the pinned layout the LG touches the Odyssey's top-left corner; in reality the LG is beside it.
        let rules = PointerRules(plan: try plan(.left))
        let fixed = rules.correction(from: CGPoint(x: 1, y: 1), to: CGPoint(x: -1, y: -1), delta: CGVector(dx: -2, dy: -2))
        XCTAssertEqual(fixed, CGPoint(x: -1, y: -1080), "crosses the real border onto the LG's top row, as macOS would")
    }

    // Regression: "sometimes the pointer jumps to the top instead of the matching height". Through the
    // pinned-only corner, a move with no known previous spot was left to macOS: the LG's bottom row
    // came out at the Odyssey's top row.
    func testCornerCrossingWithoutAKnownPreviousSpotKeepsTheHeight() throws {
        let rules = PointerRules(plan: try plan(.left))
        // From the LG's bottom row (pinned y -1 = real y 1079) moving right, through the corner.
        let fixed = rules.correction(from: nil, to: CGPoint(x: 1, y: 1), delta: CGVector(dx: 3, dy: 0))
        XCTAssertEqual(fixed, CGPoint(x: 1, y: 1079), "the real border leads to the Odyssey's bottom row, not its top")
    }

    func testCornerCrossingAfterAStaleSpotKeepsTheHeight() throws {
        let rules = PointerRules(plan: try plan(.left))
        let fixed = rules.correction(from: CGPoint(x: 900, y: 500), to: CGPoint(x: 1, y: 1), delta: CGVector(dx: 3, dy: 0))
        XCTAssertEqual(fixed, CGPoint(x: 1, y: 1079))
    }

    // Every position is where the real arrangement puts it, also next to the corner where the moved LG
    // touches the Odyssey: no pushing the pointer aside (that made real crossings land 30 pt off).
    func testNoPointerIsPushedAsideNearTheMovedCorner() throws {
        let rules = PointerRules(plan: try plan(.left))
        XCTAssertNil(rules.correction(from: CGPoint(x: -14, y: -10), to: CGPoint(x: -10, y: -10), delta: CGVector(dx: 4, dy: 0)))
        XCTAssertNil(rules.correction(from: CGPoint(x: -10, y: -14), to: CGPoint(x: -10, y: -10), delta: CGVector(dx: 0, dy: 4)))
    }

    func testMacOSsCatchUpLineOnlyPassesWhereDisplaysShareAnEdge() throws {
        let rules = PointerRules(plan: try XCTUnwrap(LayoutPlanner.plan(for: desk, targetUUID: "O", edge: .left)))
        // With the 96 pt bridge the LG (real x -1920..0) sits at x -1824..96 above the Odyssey.
        XCTAssertTrue(rules.catchUpCanPass(from: CGPoint(x: 0, y: 572), to: CGPoint(x: 66, y: -508)), "an ordinary crossing")
        XCTAssertFalse(rules.catchUpCanPass(from: CGPoint(x: 0, y: 572), to: CGPoint(x: -104, y: -508)), "a fast flick passes beside the bridge")
        XCTAssertFalse(rules.catchUpCanPass(from: CGPoint(x: 0, y: 572), to: CGPoint(x: -2, y: -508)),
                       "without a bridge (corner only) it can't pass either")
        XCTAssertEqual(rules.borderPoint(for: CGPoint(x: -104, y: -508), from: CGPoint(x: 0, y: 572)), CGPoint(x: 95, y: -508),
                       "just across the real border, same height")
        XCTAssertTrue(rules.catchUpCanPass(from: CGPoint(x: 0, y: 572), to: CGPoint(x: 95, y: -508)))
    }

    // Regression: "half of the cursor is cut off at the border". Just left of the moved border the arrow
    // overhangs into empty space; the piece the Odyssey would show on a real border is drawn there instead.
    func testTheArrowPieceCutOffAtAMovedBorderBelongsOnTheRealNeighbour() throws {
        let rules = PointerRules(plan: try plan(.left))
        let piece = try XCTUnwrap(rules.hiddenArrowPart(at: CGPoint(x: -6, y: -540), arrow: CGSize(width: 20, height: 30), hotSpot: CGPoint(x: 2, y: 2)))
        XCTAssertEqual(piece.frame, CGRect(x: 0, y: 538, width: 12, height: 30), "on the Odyssey, at the LG's real height")
        XCTAssertEqual(piece.arrowOrigin, CGPoint(x: -8, y: 538))
    }

    func testNoPieceWhenTheArrowFitsOrTheBorderIsReal() throws {
        let rules = PointerRules(plan: try plan(.left))
        XCTAssertNil(rules.hiddenArrowPart(at: CGPoint(x: -500, y: -540), arrow: CGSize(width: 20, height: 30), hotSpot: .zero), "fits")
        XCTAssertNil(rules.hiddenArrowPart(at: CGPoint(x: 1910, y: 500), arrow: CGSize(width: 20, height: 30), hotSpot: .zero),
                     "Odyssey -> PHL is a real border; macOS draws both halves")
    }

    func testTheArrowMayOverlapARealNeighbour() throws {
        // LG -> Odyssey is a real border (bottom plan leaves the LG in place): the arrow may span it.
        let rules = PointerRules(plan: try plan(.bottom))
        XCTAssertNil(rules.correction(from: CGPoint(x: -20, y: 500), to: CGPoint(x: -10, y: 500), delta: CGVector(dx: 10, dy: 0)))
    }

    func testFreeLeftEdgesOfOtherDisplaysAreGuarded() throws {
        let rules = PointerRules(plan: try plan(.left))
        XCTAssertEqual(rules.correction(from: CGPoint(x: -1915, y: -500), to: CGPoint(x: -1920, y: -500), delta: CGVector(dx: -5, dy: 0)),
                       CGPoint(x: -1919, y: -500))
        XCTAssertEqual(rules.correction(from: CGPoint(x: 100, y: 1500), to: CGPoint(x: 97, y: 1500), delta: CGVector(dx: -3, dy: 0)),
                       CGPoint(x: 98, y: 1500))
    }

    func testBottomDockCrossingsFollowTheRealArrangement() throws {
        let rules = PointerRules(plan: try plan(.bottom))
        XCTAssertEqual(rules.correction(from: CGPoint(x: 900, y: 1077), to: CGPoint(x: 900, y: 1079), delta: CGVector(dx: 0, dy: 3)),
                       CGPoint(x: 2723, y: 1080), "down from the Odyssey lands on the laptop, wherever it was slid to")
        XCTAssertEqual(rules.correction(from: CGPoint(x: 2723, y: 1081), to: CGPoint(x: 2723, y: 1078), delta: CGVector(dx: 0, dy: -3)),
                       CGPoint(x: 900, y: 1078), "up from the laptop returns to the Odyssey, not the PHL it now touches")
    }

    func testAPointerMovedBySomethingElseIsNotReplayedFromItsOldSpot() throws {
        // Another app warped the pointer from the Odyssey onto the laptop; the next real move is local.
        let rules = PointerRules(plan: try plan(.bottom))
        XCTAssertNil(rules.correction(from: CGPoint(x: 24, y: 540), to: CGPoint(x: 2600, y: 1500), delta: CGVector(dx: 0, dy: 6)))
    }

    func testRightDockLeavesARealBorderBelowAlone() throws {
        // Today's desk without the PHL: nothing touches the Odyssey's right edge, so nothing moves.
        let o = Display(uuid: "O", name: "Odyssey", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let b = Display(uuid: "B", name: "Built-in", frame: CGRect(x: 0, y: 1080, width: 1728, height: 1117))
        let l = Display(uuid: "L", name: "LG", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        let rules = PointerRules(plan: try XCTUnwrap(LayoutPlanner.plan(for: [o, b, l], targetUUID: "O", edge: .right, bridge: 0)))
        XCTAssertNil(rules.correction(from: CGPoint(x: 864, y: 1074), to: CGPoint(x: 864, y: 1080), delta: CGVector(dx: 0, dy: 6)))
    }

    func testBottomDockGuardsTheOtherDisplaysBottomEdges() throws {
        let rules = PointerRules(plan: try plan(.bottom))
        XCTAssertEqual(rules.correction(from: CGPoint(x: -1000, y: 1076), to: CGPoint(x: -1000, y: 1079), delta: CGVector(dx: 0, dy: 3)),
                       CGPoint(x: -1000, y: 1078))
    }
}
