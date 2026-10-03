import XCTest
@testable import StublyKit

final class StopMoveTests: XCTestCase {
    let cal = TestCalendar.calendar

    func makeTrip() -> (Trip, [UUID]) {
        let day1 = cal.startOfDay(for: TestCalendar.date(2026, 10, 12))
        let day2 = cal.startOfDay(for: TestCalendar.date(2026, 10, 13))
        let stops = [
            Stop(day: day1, order: 0, name: "A", kind: .sight),
            Stop(day: day1, order: 1, name: "B", kind: .sight),
            Stop(day: day1, order: 2, name: "C", kind: .sight),
            Stop(day: day2, order: 0, name: "D", kind: .sight),
        ]
        let trip = Trip(name: "T", destination: Destination(countryCode: "PT", city: "Lizbon"),
                        startDate: day1, endDate: day2, stops: stops)
        return (trip, stops.map(\.id))
    }

    func names(_ trip: Trip, _ day: Date) -> [String] {
        trip.stops(on: day, calendar: cal).map(\.name)
    }

    func testReorderWithinDay() {
        var (trip, ids) = makeTrip()
        let day1 = trip.startDate
        trip.moveStop(ids[2], before: ids[0], on: day1, calendar: cal)
        XCTAssertEqual(names(trip, day1), ["C", "A", "B"])
        trip.moveStop(ids[2], before: nil, on: day1, calendar: cal)
        XCTAssertEqual(names(trip, day1), ["A", "B", "C"])
        XCTAssertEqual(trip.stops(on: day1, calendar: cal).map(\.order), [0, 1, 2])
    }

    func testMoveToAnotherDay() {
        var (trip, ids) = makeTrip()
        trip.moveStop(ids[1], before: ids[3], on: trip.endDate, calendar: cal)
        XCTAssertEqual(names(trip, trip.startDate), ["A", "C"])
        XCTAssertEqual(names(trip, trip.endDate), ["B", "D"])
        XCTAssertEqual(trip.stops(on: trip.startDate, calendar: cal).map(\.order), [0, 1])
    }

    func testDroppingOnItselfIsNoOp() {
        var (trip, ids) = makeTrip()
        let before = trip
        trip.moveStop(ids[1], before: ids[1], on: trip.startDate, calendar: cal)
        XCTAssertEqual(trip, before)
    }
}
