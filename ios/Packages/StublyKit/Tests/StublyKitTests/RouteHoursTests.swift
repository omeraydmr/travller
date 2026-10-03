import XCTest
@testable import StublyKit

final class RouteHoursTests: XCTestCase {
    // Doğu-batı hattında 0,01° ≈ 870 m aralıklı noktalar (Lizbon enlemi).
    func point(_ step: Double) -> Coordinate { Coordinate(latitude: 38.7, longitude: -9.2 + step * 0.01) }
    func open(_ from: Int, _ to: Int) -> [OpeningHours.Interval] { [OpeningHours.Interval(start: from * 60, end: to * 60)] }

    func testWithoutHoursMatchesShortestWalk() {
        let visits = [0.0, 2, 1].map { RouteOptimizer.Visit(coordinate: point($0), duration: 60) }
        XCTAssertEqual(RouteOptimizer.order(visits, from: nil, dayStart: 540),
                       RouteOptimizer.order(visits.map(\.coordinate)))
    }

    func testLateOpeningStopMovesToEnd() {
        let hotel = point(-1)
        // En kısa sıra 0,1,2 olurdu; ama 0 (müze) 14:00'te açılıyor ve 15:00'te kapanıyor.
        let visits = [
            RouteOptimizer.Visit(coordinate: point(0), duration: 60, open: open(14, 15)),
            RouteOptimizer.Visit(coordinate: point(1), duration: 90),
            RouteOptimizer.Visit(coordinate: point(2), duration: 90),
        ]
        let shortest = RouteOptimizer.order(visits.map(\.coordinate), from: hotel)
        XCTAssertEqual(shortest, [0, 1, 2])
        XCTAssertEqual(RouteOptimizer.schedule(shortest, visits: visits, from: hotel, dayStart: 540).conflicts, 0,
                       "Açılışı beklemek çakışma değildir")

        // Kapanmadan önce varılamıyorsa yer değiştirir: sabah açık olan durak ilk sıraya.
        let morning = [
            RouteOptimizer.Visit(coordinate: point(0), duration: 120),
            RouteOptimizer.Visit(coordinate: point(1), duration: 60, open: open(9, 11)),
            RouteOptimizer.Visit(coordinate: point(2), duration: 60),
        ]
        let order = RouteOptimizer.order(morning, from: hotel, dayStart: 540)
        XCTAssertEqual(order.first, 1)
        XCTAssertEqual(RouteOptimizer.schedule(order, visits: morning, from: hotel, dayStart: 540).conflicts, 0)
    }

    func testScheduleWaitsForOpeningAndCountsConflicts() {
        let visits = [
            RouteOptimizer.Visit(coordinate: point(0), duration: 60, open: open(10, 18)),
            RouteOptimizer.Visit(coordinate: point(0), duration: 60, open: []),
        ]
        let schedule = RouteOptimizer.schedule([0, 1], visits: visits, from: nil, dayStart: 540)
        XCTAssertEqual(schedule.starts[0], 600, "09:00'da varılır, 10:00 açılış beklenir")
        XCTAssertEqual(schedule.starts[1], 660)
        XCTAssertEqual(schedule.conflicts, 1, "Bütün gün kapalı durak çakışmadır")
    }

    func testTimedStopsKeepTheirTimeOrder() {
        let hotel = point(-1)
        // En kısa yürüyüş akşam yemeğini (19:30) öğle yemeğinden (13:00) önce koyardı.
        let visits = [
            RouteOptimizer.Visit(coordinate: point(0), duration: 90, fixedStart: 19 * 60 + 30),
            RouteOptimizer.Visit(coordinate: point(1), duration: 60),
            RouteOptimizer.Visit(coordinate: point(3), duration: 60, fixedStart: 13 * 60),
        ]
        XCTAssertEqual(RouteOptimizer.order(visits.map(\.coordinate), from: hotel), [0, 1, 2])
        let order = RouteOptimizer.order(visits, from: hotel, dayStart: 540)
        let schedule = RouteOptimizer.schedule(order, visits: visits, from: hotel, dayStart: 540)
        XCTAssertEqual(schedule.conflicts, 0)
        XCTAssertLessThan(order.firstIndex(of: 2)!, order.firstIndex(of: 0)!, "13:00 durağı 19:30'dan önce")
        XCTAssertEqual(schedule.starts[0], 19 * 60 + 30, "Saatli durak kendi saatinde başlar")
    }

    func testEmptyInput() {
        XCTAssertEqual(RouteOptimizer.order([], from: nil, dayStart: 540), [])
    }
}
