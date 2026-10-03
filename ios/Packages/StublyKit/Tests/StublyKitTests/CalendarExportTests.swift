import XCTest
@testable import StublyKit

final class CalendarExportTests: XCTestCase {
    func testEventsForFlightsStaysAndTimedStops() throws {
        let cal = TestCalendar.calendar
        let day = TestCalendar.date(2026, 10, 12)
        var trip = Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"),
                        startDate: day, endDate: TestCalendar.date(2026, 10, 15))
        trip.flights = [FlightSegment(flightNumber: "TK1759", fromCode: "IST", fromCity: "İstanbul", toCode: "LIS", toCity: "Lizbon",
                                      departure: day.addingTimeInterval(7 * 3600), arrival: day.addingTimeInterval(12 * 3600),
                                      departureTimeZone: "Europe/Istanbul", seat: "14C")]
        trip.lodgings = [Lodging(name: "Hotel Alfama", address: "Rua 1", checkIn: day.addingTimeInterval(15 * 3600),
                                 checkOut: TestCalendar.date(2026, 10, 15).addingTimeInterval(11 * 3600), confirmation: "123")]
        trip.stops = [
            Stop(day: TestCalendar.date(2026, 10, 13), order: 0, name: "Belém", kind: .sight, startMinutes: 600, durationMinutes: 90),
            Stop(day: TestCalendar.date(2026, 10, 13), order: 1, name: "Saatsiz", kind: .sight),
            Stop(day: TestCalendar.date(2026, 10, 13), order: 2, name: "Metro", kind: .transport, startMinutes: 700),
        ]
        let events = CalendarExport.events(for: trip, calendar: cal)
        XCTAssertEqual(events.map(\.title), ["✈︎ TK1759 IST → LIS", "Otel girişi: Hotel Alfama", "Belém", "Otel çıkışı: Hotel Alfama"])
        XCTAssertEqual(events[0].timeZone, "Europe/Istanbul")
        XCTAssertEqual(events[0].notes, "Koltuk 14C")
        XCTAssertEqual(events[1].location, "Hotel Alfama, Rua 1")
        let stop = try XCTUnwrap(events.first { $0.title == "Belém" })
        XCTAssertEqual(cal.dateComponents([.day, .hour], from: stop.start), DateComponents(day: 13, hour: 10))
        XCTAssertEqual(stop.end.timeIntervalSince(stop.start), 90 * 60)
        XCTAssertEqual(Set(events.map(\.key)).count, events.count, "Anahtarlar benzersiz")
    }
}
