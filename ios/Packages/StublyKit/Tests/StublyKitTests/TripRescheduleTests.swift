import XCTest
@testable import StublyKit

final class TripRescheduleTests: XCTestCase {
    let cal = TestCalendar.calendar

    func trip() -> Trip {
        var trip = Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"),
                        startDate: TestCalendar.date(2026, 10, 10), endDate: TestCalendar.date(2026, 10, 13))
        trip.stops = [
            Stop(day: TestCalendar.date(2026, 10, 10), order: 0, name: "Alfama", kind: .sight, startMinutes: 600),
            Stop(day: TestCalendar.date(2026, 10, 13), order: 0, name: "Belém", kind: .sight, startMinutes: 540),
        ]
        return trip
    }

    func testShiftingKeepsThePlanTogether() {
        var value = trip()
        let moved = value.reschedule(start: TestCalendar.date(2026, 10, 17), end: TestCalendar.date(2026, 10, 20),
                                     shiftPlan: true, calendar: cal)
        XCTAssertEqual(moved, 0)
        XCTAssertEqual(value.stops.map { cal.component(.day, from: $0.day) }, [17, 20])
        XCTAssertEqual(value.stops.first?.startMinutes, 600, "Saatler korunur")
    }

    func testShorterTripMovesOverflowToIdeas() {
        var value = trip()
        let original = value.stops[1].id
        let moved = value.reschedule(start: TestCalendar.date(2026, 10, 10), end: TestCalendar.date(2026, 10, 11),
                                     shiftPlan: true, calendar: cal)
        XCTAssertEqual(moved, 1)
        XCTAssertEqual(value.stops.map(\.name), ["Alfama"])
        XCTAssertEqual(value.ideaList.map(\.name), ["Belém"])
        XCTAssertNil(value.ideaList.first?.startMinutes)
        XCTAssertNotEqual(value.ideaList.first?.id, original, "Fikir yeni kimlik alır")
        XCTAssertEqual(cal.component(.day, from: value.endDate), 11)
    }

    func testWithoutShiftOldDaysOutsideRangeBecomeIdeas() {
        var value = trip()
        let moved = value.reschedule(start: TestCalendar.date(2026, 10, 12), end: TestCalendar.date(2026, 10, 15),
                                     shiftPlan: false, calendar: cal)
        XCTAssertEqual(moved, 1)
        XCTAssertEqual(value.stops.map(\.name), ["Belém"])
    }

    func testEndBeforeStartIsClamped() {
        var value = trip()
        value.reschedule(start: TestCalendar.date(2026, 10, 10), end: TestCalendar.date(2026, 10, 1), shiftPlan: false, calendar: cal)
        XCTAssertEqual(value.endDate, value.startDate)
    }
}
