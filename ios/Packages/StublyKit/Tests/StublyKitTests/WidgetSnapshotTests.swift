import XCTest
@testable import StublyKit

final class WidgetSnapshotTests: XCTestCase {
    let calendar = TestCalendar.calendar

    func snapshot(now: Date) -> WidgetSnapshot {
        let day1 = TestCalendar.date(2026, 10, 3, 0)
        let day2 = TestCalendar.date(2026, 10, 4, 0)
        var lisbon = Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"),
                          startDate: day1, endDate: TestCalendar.date(2026, 10, 6, 0))
        lisbon.stops = [
            Stop(day: day2, order: 1, name: "Pena Sarayı", kind: .sight, startMinutes: 13 * 60, durationMinutes: 120),
            Stop(day: day2, order: 0, name: "Belém", kind: .sight, startMinutes: 9 * 60, durationMinutes: 90),
            Stop(day: day2, order: 2, name: "Akşam yemeği", kind: .food),
        ]
        let past = Trip(name: "Roma", destination: Destination(countryCode: "IT", city: "Roma"),
                        startDate: TestCalendar.date(2026, 5, 1, 0), endDate: TestCalendar.date(2026, 5, 4, 0))
        let later = Trip(name: "Tiflis", destination: Destination(countryCode: "GE", city: "Tiflis"),
                         startDate: TestCalendar.date(2026, 11, 20, 0), endDate: TestCalendar.date(2026, 11, 23, 0))
        return WidgetSnapshot(trips: [later, past, lisbon], now: now, calendar: calendar,
                              flag: { $0 }, tint: { _ in 0xFF0000 }, symbol: { $0.rawValue }, flightLabel: { $0.flightNumber })
    }

    func testUpcomingCountsCalendarDays() {
        let now = TestCalendar.date(2026, 10, 1, 23)
        let snapshot = snapshot(now: now)
        XCTAssertEqual(snapshot.items.map(\.name), ["Lizbon", "Tiflis"])
        guard case let .upcoming(item, days) = snapshot.state(at: now, calendar: calendar) else { return XCTFail() }
        XCTAssertEqual(item.name, "Lizbon")
        XCTAssertEqual(days, 2)
    }

    func testOngoingPicksNextStop() {
        let morning = TestCalendar.date(2026, 10, 4, 8)
        let snapshot = snapshot(now: morning)
        guard case let .ongoing(_, day, total, stop, isFirst, remaining) = snapshot.state(at: morning, calendar: calendar) else {
            return XCTFail()
        }
        XCTAssertEqual(day, 2)
        XCTAssertEqual(total, 4)
        XCTAssertEqual(stop?.name, "Belém")
        XCTAssertTrue(isFirst)
        XCTAssertEqual(remaining, 3)

        // 11:00'de Belém bitmiş: sıradaki Pena Sarayı.
        let late = TestCalendar.date(2026, 10, 4, 11)
        guard case let .ongoing(_, _, _, next, first, left) = snapshot.state(at: late, calendar: calendar) else { return XCTFail() }
        XCTAssertEqual(next?.name, "Pena Sarayı")
        XCTAssertFalse(first)
        XCTAssertEqual(left, 2)
    }

    func testRefreshDatesIncludeMidnightsAndStopEnds() {
        let now = TestCalendar.date(2026, 10, 4, 8)
        let dates = snapshot(now: now).refreshDates(after: now, calendar: calendar, days: 2)
        XCTAssertTrue(dates.contains(TestCalendar.date(2026, 10, 5, 0)))
        XCTAssertTrue(dates.contains(calendar.date(bySettingHour: 10, minute: 30, second: 0, of: now)!))
        XCTAssertTrue(dates.contains(TestCalendar.date(2026, 10, 4, 15)))
        XCTAssertEqual(dates, dates.sorted())
    }

    func testTripLinkRoundTrip() throws {
        let link = TripLink(tripID: UUID(), section: "money")
        XCTAssertEqual(TripLink(url: link.url), link)
        XCTAssertEqual(TripLink(userInfo: link.userInfo), link)
        XCTAssertNil(TripLink(url: URL(string: "stubly://other/x")!))
        let plain = TripLink(tripID: UUID())
        XCTAssertEqual(TripLink(url: plain.url), plain)
    }
}
