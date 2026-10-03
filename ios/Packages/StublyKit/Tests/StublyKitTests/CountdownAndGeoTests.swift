import XCTest
@testable import StublyKit

final class CountdownAndGeoTests: XCTestCase {
    let cal = TestCalendar.calendar
    let now = TestCalendar.date(2026, 10, 1, 9)

    func testCountdown() {
        XCTAssertEqual(Countdown.make(start: TestCalendar.date(2026, 11, 11), end: TestCalendar.date(2026, 11, 20),
                                      now: now, calendar: cal), .days(41))
        XCTAssertEqual(Countdown.make(start: TestCalendar.date(2027, 1, 29), end: TestCalendar.date(2027, 2, 2),
                                      now: now, calendar: cal), .months(4))
        XCTAssertEqual(Countdown.make(start: TestCalendar.date(2026, 9, 30), end: TestCalendar.date(2026, 10, 3),
                                      now: now, calendar: cal), .ongoing(day: 2, of: 4))
        XCTAssertEqual(Countdown.make(start: TestCalendar.date(2026, 9, 1), end: TestCalendar.date(2026, 9, 5),
                                      now: now, calendar: cal), .past)
    }

    func testDistance() {
        // Miradouro da Graça → Torre de Belém ≈ 7,8 km kuş uçuşu
        let graca = Coordinate(latitude: 38.7166, longitude: -9.1316)
        let belem = Coordinate(latitude: 38.6916, longitude: -9.2160)
        XCTAssertEqual(Geo.distance(graca, belem), 7_800, accuracy: 600)
        XCTAssertEqual(Geo.routeDistance([graca]), 0)
        XCTAssertEqual(Geo.walkingMinutes(meters: 640), 10)
    }
}

final class RouteOptimizerTests: XCTestCase {
    func testOrderShortensZigZagRoute() {
        // Doğu-batı doğrultusunda karışık sırayla verilmiş duraklar.
        let points = [0.0, 0.03, 0.01, 0.04, 0.02].map { Coordinate(latitude: 38.7, longitude: -9.2 + $0) }
        let order = RouteOptimizer.order(points)
        XCTAssertEqual(order, [0, 2, 4, 1, 3])
        XCTAssertLessThan(RouteOptimizer.length(order, points), RouteOptimizer.length(Array(points.indices), points))
    }

    func testSmallInputsAreUnchanged() {
        let points = [Coordinate(latitude: 1, longitude: 1), Coordinate(latitude: 2, longitude: 2)]
        XCTAssertEqual(RouteOptimizer.order(points), [0, 1])
        XCTAssertEqual(RouteOptimizer.order([]), [])
    }
}

final class GeoBoundsTests: XCTestCase {
    func testBoundsPadAndCenter() {
        let bounds = Geo.bounds([Coordinate(latitude: 38.70, longitude: -9.20), Coordinate(latitude: 38.72, longitude: -9.10)])
        XCTAssertEqual(bounds.center.latitude, 38.71, accuracy: 0.0001)
        XCTAssertEqual(bounds.center.longitude, -9.15, accuracy: 0.0001)
        XCTAssertEqual(bounds.latitudeSpan, 0.032, accuracy: 0.0001)
        XCTAssertEqual(bounds.longitudeSpan, 0.16, accuracy: 0.0001)
        XCTAssertEqual(Geo.bounds([Coordinate(latitude: 1, longitude: 1)]).latitudeSpan, 0.01, "tek nokta için en küçük alan")
    }
}
