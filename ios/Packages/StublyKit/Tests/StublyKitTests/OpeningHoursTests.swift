import XCTest
@testable import StublyKit

final class OpeningHoursTests: XCTestCase {
    func testParseCommonFormats() throws {
        let hours = try XCTUnwrap(OpeningHours("Mo-Fr 09:00-18:00; Sa 10:00-14:00; Su off"))
        XCTAssertEqual(hours.intervals(onDay: 0), [.init(start: 540, end: 1080)])
        XCTAssertEqual(hours.intervals(onDay: 5), [.init(start: 600, end: 840)])
        XCTAssertTrue(hours.intervals(onDay: 6).isEmpty)
        XCTAssertEqual(hours.turkishSummary, "Pzt–Cum 09:00–18:00 · Cmt 10:00–14:00 · Paz kapalı")

        let split = try XCTUnwrap(OpeningHours("Tu-Su 10:00-13:00, 14:00-18:00; Mo off; PH off"))
        XCTAssertEqual(split.intervals(onDay: 2).count, 2)
        XCTAssertTrue(split.intervals(onDay: 0).isEmpty)

        XCTAssertEqual(OpeningHours("24/7")?.turkishSummary, "Her gün 24 saat")
        XCTAssertEqual(OpeningHours("08:00-20:00")?.intervals(onDay: 3), [.init(start: 480, end: 1200)])
        XCTAssertEqual(OpeningHours("Fr-Mo 18:00-02:00")?.intervals(onDay: 6), [.init(start: 1080, end: 1440)])
        XCTAssertNil(OpeningHours("sunrise-sunset"))
        XCTAssertNil(OpeningHours(""))
    }

    func testStatus() throws {
        let hours = try XCTUnwrap(OpeningHours("Tu-Su 10:00-18:00; Mo off"))
        XCTAssertEqual(hours.status(day: 0, startMinutes: 600, duration: 60), .closedAllDay)
        XCTAssertEqual(hours.status(day: 1, startMinutes: 570, duration: 60), .opensLater(at: 600))
        XCTAssertEqual(hours.status(day: 1, startMinutes: 1050, duration: 60), .closesDuringVisit(at: 1080))
        XCTAssertEqual(hours.status(day: 1, startMinutes: 1110, duration: 30), .alreadyClosed(at: 1080))
        XCTAssertEqual(hours.status(day: 1, startMinutes: 720, duration: 60), .open(until: 1080))
        XCTAssertFalse(hours.status(day: 1, startMinutes: nil, duration: 60).isWarning)
        XCTAssertEqual(OpeningHours.dayIndex(calendarWeekday: 1), 6, "Pazar")
        XCTAssertEqual(OpeningHours.dayIndex(calendarWeekday: 2), 0, "Pazartesi")
    }

    func testTripHoursStatusUsesStopDay() {
        let cal = TestCalendar.calendar
        // 12 Ekim 2026 Pazartesi
        let monday = cal.startOfDay(for: TestCalendar.date(2026, 10, 12))
        let stop = Stop(day: monday, order: 0, name: "Torre de Belém", kind: .sight, startMinutes: 600,
                        openingHours: "Tu-Su 10:00-18:00; Mo off")
        let trip = Trip(name: "T", destination: Destination(countryCode: "PT", city: "Lizbon"),
                        startDate: monday, endDate: monday, stops: [stop])
        XCTAssertEqual(trip.hoursStatus(of: stop, calendar: cal), .closedAllDay)
    }

    func testLookupPicksMatchingName() throws {
        let json = #"{"elements":[{"type":"node","tags":{"name":"Pastelaria Aloma","opening_hours":"Mo-Su 08:00-20:00"}},{"type":"node","tags":{"name":"Pastéis de Belém","opening_hours":"Mo-Su 08:00-23:00"}},{"type":"node"}]}"#
        let candidates = try OpeningHoursLookup.decodeCandidates(Data(json.utf8))
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(OpeningHoursLookup.bestMatch(for: "Pasteis de Belem", in: candidates)?.openingHours, "Mo-Su 08:00-23:00")
        XCTAssertNil(OpeningHoursLookup.bestMatch(for: "Torre de Belém Müzesi Kafe Yok", in: [candidates[0]]))
    }
}
