import CoreGraphics
import XCTest
@testable import DockPinCore

/// The user's desk: LG | Odyssey | PHL in a row, the laptop below the Odyssey; built-in currently main.
let builtIn = Display(uuid: "B", name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1728, height: 1117))
let odyssey = Display(uuid: "O", name: "Odyssey", frame: CGRect(x: -97, y: -1080, width: 1920, height: 1080))
let lg = Display(uuid: "L", name: "LG", frame: CGRect(x: -2017, y: -1080, width: 1920, height: 1080))
let phl = Display(uuid: "P", name: "PHL", frame: CGRect(x: 1823, y: -1080, width: 1920, height: 1080))
let desk = [builtIn, odyssey, lg, phl]

final class LayoutPlannerTests: XCTestCase {
    func testCenterIsTheDisplayWithNeighboursOnBothSides() {
        XCTAssertEqual(LayoutPlanner.centerDisplay(in: desk)?.uuid, "O")
    }

    func testPlanMakesTargetMainAndLiftsLeftDisplaysAboveIt() throws {
        let plan = try XCTUnwrap(LayoutPlanner.plan(for: desk, targetUUID: "O"))
        let pinned = Dictionary(uniqueKeysWithValues: plan.pinned.map { ($0.uuid, $0.frame.origin) })
        XCTAssertEqual(pinned["O"], CGPoint(x: 0, y: 0))
        XCTAssertEqual(pinned["L"], CGPoint(x: -1920, y: -1080))
        XCTAssertEqual(pinned["P"], CGPoint(x: 1920, y: 0))
        XCTAssertEqual(pinned["B"], CGPoint(x: 97, y: 1080))
        XCTAssertFalse(plan.pinned.contains { LayoutPlanner.touchesOnLeft(of: CGRect(x: 0, y: 0, width: 1920, height: 1080), $0.frame) })
    }

    func testPlanIsIdempotentWhenLeftEdgeAlreadyFree() throws {
        let plan = try XCTUnwrap(LayoutPlanner.plan(for: desk, targetUUID: "O"))
        let again = try XCTUnwrap(LayoutPlanner.plan(for: plan.pinned, targetUUID: "O"))
        XCTAssertEqual(again.pinned, plan.pinned)
    }
}

final class PointerRulesTests: XCTestCase {
    var rules: PointerRules!

    override func setUpWithError() throws {
        rules = PointerRules(plan: try XCTUnwrap(LayoutPlanner.plan(for: desk, targetUUID: "O")))
    }

    func testLeavingOdysseyLeftwardsLandsOnLGAtTheSameHeight() {
        XCTAssertEqual(rules.warpTarget(for: CGPoint(x: 0, y: 500), delta: CGVector(dx: -3, dy: 0)), CGPoint(x: -1, y: -580))
    }

    func testLeavingLGRightwardsLandsOnOdysseyAtTheSameHeight() {
        XCTAssertEqual(rules.warpTarget(for: CGPoint(x: -0.5, y: -580), delta: CGVector(dx: 3, dy: 0)), CGPoint(x: 0, y: 500))
    }

    func testMovingInsideADisplayDoesNothing() {
        XCTAssertNil(rules.warpTarget(for: CGPoint(x: 900, y: 500), delta: CGVector(dx: -3, dy: 0)))
        XCTAssertNil(rules.warpTarget(for: CGPoint(x: 1919.5, y: 500), delta: CGVector(dx: 3, dy: 0)), "Odyssey -> PHL is a real edge")
    }

    func testFreeLeftEdgesOfOtherDisplaysAreGuarded() {
        XCTAssertEqual(rules.warpTarget(for: CGPoint(x: -1920, y: -500), delta: CGVector(dx: -3, dy: 0)), CGPoint(x: -1919, y: -500))
        XCTAssertEqual(rules.warpTarget(for: CGPoint(x: 97, y: 1500), delta: CGVector(dx: -3, dy: 0)), CGPoint(x: 98, y: 1500))
    }
}
