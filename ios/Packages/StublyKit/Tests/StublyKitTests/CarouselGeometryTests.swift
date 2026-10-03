import XCTest
@testable import StublyKit

final class CarouselGeometryTests: XCTestCase {
    let geometry = CarouselGeometry()

    func testFrontCardIsCenteredAndSharp() {
        let t = geometry.transform(relative: 0)
        XCTAssertEqual(t.x, 0, accuracy: 0.001)
        XCTAssertEqual(t.y, 0, accuracy: 0.001)
        XCTAssertEqual(t.scale, 1)
        XCTAssertEqual(t.blur, 0)
        XCTAssertEqual(t.opacity, 1)
    }

    func testCardsFollowAnArcSymmetrically() {
        let right = geometry.transform(relative: 1)
        let left = geometry.transform(relative: -1)
        XCTAssertGreaterThan(right.x, 0)
        XCTAssertEqual(right.x, -left.x, accuracy: 0.001)
        XCTAssertEqual(right.y, left.y, accuracy: 0.001)
        XCTAssertGreaterThan(right.y, 0, "yan kartlar yay boyunca aşağı iner")
        XCTAssertGreaterThan(geometry.transform(relative: 2).y - right.y, right.y, "eğim uzaklaştıkça artar")
        XCTAssertLessThan(right.zIndex, 0)
        XCTAssertGreaterThan(right.blur, 0)
        XCTAssertLessThanOrEqual(geometry.transform(relative: 5).blur, geometry.maxBlur)
    }

    func testFarCardsFadeOut() {
        XCTAssertTrue(geometry.isVisible(2))
        XCTAssertFalse(geometry.isVisible(3))
        XCTAssertLessThan(geometry.transform(relative: 2.5).opacity, 1)
    }

    func testSettleMovesAtMostOneCard() {
        XCTAssertEqual(CarouselGeometry.settle(from: 0, predictedProgress: 3.4, count: 5), 1)
        XCTAssertEqual(CarouselGeometry.settle(from: 0, predictedProgress: 0.3, count: 5), 0)
        XCTAssertEqual(CarouselGeometry.settle(from: 1, predictedProgress: 1.7, count: 5), 2)
        XCTAssertEqual(CarouselGeometry.settle(from: 1, predictedProgress: -2, count: 5), 0)
        XCTAssertEqual(CarouselGeometry.settle(from: 3, predictedProgress: 6, count: 4), 3)
        XCTAssertEqual(CarouselGeometry.settle(from: 0, predictedProgress: -1, count: 4), 0)
        XCTAssertEqual(CarouselGeometry.settle(from: 0, predictedProgress: 0, count: 0), 0)
    }
}
