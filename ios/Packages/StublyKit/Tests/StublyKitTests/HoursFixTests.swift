import XCTest
@testable import StublyKit

final class HoursFixTests: XCTestCase {
    let cal = TestCalendar.calendar

    /// 12 Ekim 2026 Pazartesi … 16 Ekim Cuma.
    func trip(_ stop: Stop) -> Trip {
        Trip(name: "T", destination: Destination(countryCode: "PT", city: "Lizbon"),
             startDate: cal.startOfDay(for: TestCalendar.date(2026, 10, 12)),
             endDate: cal.startOfDay(for: TestCalendar.date(2026, 10, 16)), stops: [stop])
    }

    func day(_ d: Int) -> Date { cal.startOfDay(for: TestCalendar.date(2026, 10, d)) }

    func testOpensLaterSuggestsOpeningTime() {
        let stop = Stop(day: day(13), order: 0, name: "Müze", kind: .sight, startMinutes: 9 * 60, durationMinutes: 60,
                        openingHours: "Tu-Su 10:00-18:00; Mo off")
        XCTAssertEqual(trip(stop).hoursFix(for: stop, calendar: cal), .setStart(minutes: 600))
    }

    func testClosesDuringVisitSuggestsEarlierStart() {
        let stop = Stop(day: day(13), order: 0, name: "Müze", kind: .sight, startMinutes: 17 * 60 + 30, durationMinutes: 60,
                        openingHours: "Tu-Su 10:00-18:00")
        XCTAssertEqual(trip(stop).hoursFix(for: stop, calendar: cal), .setStart(minutes: 17 * 60))
    }

    func testClosedDayMovesToNearestOpenDay() {
        // Pazartesi kapalı → en yakın açık gün Salı (13).
        let stop = Stop(day: day(12), order: 0, name: "Torre", kind: .sight, startMinutes: 600, durationMinutes: 60,
                        openingHours: "Tu-Su 10:00-17:30; Mo off")
        XCTAssertEqual(trip(stop).hoursFix(for: stop, calendar: cal), .moveTo(day: day(13)))
    }

    func testPrefersLaterDayOnTie() {
        // Çarşamba kapalı; Salı ve Perşembe eşit uzaklıkta → Perşembe.
        let stop = Stop(day: day(14), order: 0, name: "Pazar", kind: .food, startMinutes: 600, durationMinutes: 60,
                        openingHours: "Mo-Su 09:00-18:00; We off")
        XCTAssertEqual(trip(stop).hoursFix(for: stop, calendar: cal), .moveTo(day: day(15)))
    }

    func testNoFixWhenFineOrImpossible() {
        let fine = Stop(day: day(13), order: 0, name: "Kafe", kind: .food, startMinutes: 600, durationMinutes: 60,
                        openingHours: "Mo-Su 08:00-20:00")
        XCTAssertNil(trip(fine).hoursFix(for: fine, calendar: cal))
        let never = Stop(day: day(13), order: 0, name: "Kapalı", kind: .sight, startMinutes: 600, durationMinutes: 60,
                         openingHours: "Sa-Su 10:00-12:00")
        XCTAssertNil(trip(never).hoursFix(for: never, calendar: cal))
    }
}
