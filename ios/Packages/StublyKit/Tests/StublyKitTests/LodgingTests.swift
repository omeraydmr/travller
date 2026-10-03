import XCTest
@testable import StublyKit

final class LodgingTests: XCTestCase {
    let cal = TestCalendar.calendar

    func trip() -> Trip {
        var trip = Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"),
                        startDate: TestCalendar.date(2026, 10, 12, 0), endDate: TestCalendar.date(2026, 10, 16, 0))
        trip.lodgings = [
            Lodging(name: "Alfama", checkIn: TestCalendar.date(2026, 10, 12, 15), checkOut: TestCalendar.date(2026, 10, 14, 11)),
            Lodging(name: "Sintra Ev", checkIn: TestCalendar.date(2026, 10, 14, 16), checkOut: TestCalendar.date(2026, 10, 15, 10)),
        ]
        return trip
    }

    func testMorningLodgingAndUncoveredNights() {
        let trip = trip()
        XCTAssertEqual(trip.lodging(forMorningOf: TestCalendar.date(2026, 10, 12), calendar: cal)?.name, "Alfama")
        XCTAssertEqual(trip.lodging(forMorningOf: TestCalendar.date(2026, 10, 13), calendar: cal)?.name, "Alfama")
        // Çıkış günü sabahı hâlâ önceki otelde uyanılır.
        XCTAssertEqual(trip.lodging(forMorningOf: TestCalendar.date(2026, 10, 14), calendar: cal)?.name, "Alfama")
        XCTAssertEqual(trip.lodging(forMorningOf: TestCalendar.date(2026, 10, 15), calendar: cal)?.name, "Sintra Ev")
        XCTAssertEqual(trip.nightsWithoutLodging(calendar: cal), [TestCalendar.date(2026, 10, 15, 0)])
        XCTAssertEqual(trip.lodgingList.first?.nights(calendar: cal), 2)
    }

    func testMergeKeepsLodgingsAndIdeasFromBothCopies() {
        var a = trip()
        a.updatedAt = TestCalendar.date(2026, 10, 1)
        var b = a
        b.updatedAt = TestCalendar.date(2026, 10, 2)
        a.ideas = [Stop(day: a.startDate, order: 0, name: "LX Factory", kind: .sight)]
        b.lodgings?.append(Lodging(name: "Porto Otel", checkIn: TestCalendar.date(2026, 10, 15, 14),
                                   checkOut: TestCalendar.date(2026, 10, 16, 11)))
        let merged = a.merged(with: b)
        XCTAssertEqual(merged.lodgingList.count, 3)
        XCTAssertEqual(merged.ideaList.map(\.name), ["LX Factory"])

        // Silinen konaklama geri gelmez.
        var c = merged
        let removed = c.lodgingList[0]
        c.lodgings?.removeAll { $0.id == removed.id }
        c.recordDeletions(since: merged)
        c.updatedAt = TestCalendar.date(2026, 10, 3)
        XCTAssertFalse(c.merged(with: b).lodgingList.contains { $0.id == removed.id })
    }

    func testCheckInNotifications() {
        var trip = trip()
        trip.status = .planned
        let plan = NotificationPlanner.plan(for: trip, now: TestCalendar.date(2026, 10, 1), calendar: cal)
        XCTAssertTrue(plan.contains { $0.title == "Bugün otel girişi: Alfama" && $0.body.hasPrefix("Giriş saati 15:00") })
        XCTAssertTrue(plan.contains { $0.title == "Bugün çıkış: Sintra Ev" })
    }

    func testOptimizerStartsFromHotel() {
        let hotel = Coordinate(latitude: 38.71, longitude: -9.13)
        let far = Coordinate(latitude: 38.80, longitude: -9.40)
        let near = Coordinate(latitude: 38.712, longitude: -9.132)
        XCTAssertEqual(RouteOptimizer.order([far, near], from: hotel), [1, 0])
        XCTAssertEqual(RouteOptimizer.order([], from: hotel), [])
    }
}
