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
    try XCTUnwrap(LayoutPlanner.plan(for: desk, targetUUID: "O", edge: edge))
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

    func testEveryPlanLeavesTheDockEdgeFree() throws {
        for edge in DockEdge.allCases {
            let p = try plan(edge)
            XCTAssertTrue(LayoutPlanner.freeEdgeDisplays(in: p.pinned, edge: edge).contains { $0.uuid == "O" }, "\(edge)")
        }
    }

    func testNothingToMoveWhenTheEdgeIsAlreadyFree() throws {
        let p = try plan(.left)
        let again = try XCTUnwrap(LayoutPlanner.plan(for: p.pinned, targetUUID: "O", edge: .left))
        XCTAssertEqual(again.pinned, p.pinned)
    }

    func testSlideAvoidsLandingOnAnotherDisplay() throws {
        // The display right of the target reaches below it, right where the shorter slide would put the
        // display underneath, so that one goes the longer way instead.
        let target = Display(uuid: "T", name: "T", frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let below = Display(uuid: "U", name: "U", frame: CGRect(x: 150, y: 1000, width: 800, height: 600))
        let right = Display(uuid: "R", name: "R", frame: CGRect(x: 1000, y: 500, width: 1000, height: 1000))
        let p = try XCTUnwrap(LayoutPlanner.plan(for: [target, below, right], targetUUID: "T", edge: .bottom))
        XCTAssertEqual(origins(p)["U"], CGPoint(x: -800, y: 1000))
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
        let rules = PointerRules(plan: try XCTUnwrap(LayoutPlanner.plan(for: [o, b, l], targetUUID: "O", edge: .right)))
        XCTAssertNil(rules.correction(from: CGPoint(x: 864, y: 1074), to: CGPoint(x: 864, y: 1080), delta: CGVector(dx: 0, dy: 6)))
    }

    func testBottomDockGuardsTheOtherDisplaysBottomEdges() throws {
        let rules = PointerRules(plan: try plan(.bottom))
        XCTAssertEqual(rules.correction(from: CGPoint(x: -1000, y: 1076), to: CGPoint(x: -1000, y: 1079), delta: CGVector(dx: 0, dy: 3)),
                       CGPoint(x: -1000, y: 1078))
    }
}
