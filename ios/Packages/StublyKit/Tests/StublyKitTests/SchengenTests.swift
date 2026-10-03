import XCTest
@testable import StublyKit

final class SchengenTests: XCTestCase {
    let cal = TestCalendar.calendar

    func d(_ m: Int, _ day: Int, _ y: Int = 2026) -> Date { TestCalendar.date(y, m, day, 0) }

    func stay(_ start: Date, _ end: Date, _ label: String = "") -> Schengen.Stay {
        Schengen.Stay(start: start, end: end, label: label)
    }

    func testEntryAndExitDaysCountAndOverlapsCountOnce() {
        let days = Schengen.days(of: [stay(d(3, 1), d(3, 5)), stay(d(3, 4), d(3, 6))], calendar: cal)
        XCTAssertEqual(days.count, 6)
        XCTAssertEqual(stay(d(3, 1), d(3, 5)).days(calendar: cal), 5)
    }

    func testWindowIs180DaysIncludingToday() {
        let days = Schengen.days(of: [stay(d(1, 1), d(1, 10))], calendar: cal)
        // 1 Ocak, 29 Haziran'dan geriye 180 günlük pencerenin ilk günü.
        XCTAssertEqual(Schengen.used(on: d(6, 29), days: days, calendar: cal), 10)
        XCTAssertEqual(Schengen.used(on: d(6, 30), days: days, calendar: cal), 9)
        XCTAssertEqual(Schengen.used(on: d(7, 9), days: days, calendar: cal), 0)
    }

    func testTripWithinLimit() {
        let previous = stay(d(3, 1), d(3, 30)) // 30 gün
        let trip = stay(d(5, 1), d(5, 20))     // 20 gün
        let result = Schengen.evaluate(trip, others: [previous], calendar: cal)
        XCTAssertTrue(result.isWithinLimit)
        XCTAssertEqual(result.usedOnExit, 50)
        XCTAssertEqual(result.remainingAfterExit, 40)
    }

    func testOverstayFindsFirstDayAndLatestExit() {
        let previous = stay(d(2, 1), d(4, 1))  // 60 gün
        let trip = stay(d(5, 1), d(6, 9))      // 40 gün
        let result = Schengen.evaluate(trip, others: [previous], calendar: cal)
        XCTAssertFalse(result.isWithinLimit)
        // 60 + 30 = 90: 30 Mayıs son geçerli gün, 31 Mayıs ilk aşım günü.
        XCTAssertEqual(result.firstOverstayDay, d(5, 31))
        XCTAssertEqual(result.latestExit, d(5, 30))
        XCTAssertEqual(result.overstayDays, 10)
    }

    func testOldStaysDropOutOfWindowDuringTrip() {
        // Eski kalış pencereden düştükçe yer açılır: 90 gün dolu iken 180 gün sonra yeniden girilebilir.
        let previous = stay(d(1, 1), d(3, 31)) // 90 gün
        let entry = Schengen.earliestEntry(forDays: 10, from: d(4, 1), others: [previous], calendar: cal)
        XCTAssertNotNil(entry)
        let result = Schengen.evaluate(stay(entry!, cal.date(byAdding: .day, value: 9, to: entry!)!), others: [previous],
                                       calendar: cal)
        XCTAssertTrue(result.isWithinLimit)
        // Bir gün önce girilseydi kural aşılırdı.
        let dayBefore = cal.date(byAdding: .day, value: -1, to: entry!)!
        XCTAssertFalse(Schengen.evaluate(stay(dayBefore, cal.date(byAdding: .day, value: 9, to: dayBefore)!),
                                         others: [previous], calendar: cal).isWithinLimit)
    }

    func testStaysInWindowAreClipped() {
        let stays = [stay(d(1, 1), d(1, 20), "Eski"), stay(d(5, 1), d(5, 3), "Yeni"), stay(d(9, 1), d(9, 3), "Sonra")]
        let clipped = Schengen.stays(stays, inWindowEnding: d(7, 15), calendar: cal)
        XCTAssertEqual(clipped.map(\.label), ["Eski", "Yeni"])
        // Pencere 17 Ocak'ta başlar.
        XCTAssertEqual(clipped[0].start, d(1, 17))
    }

    func testAdvisorWarnsOnOverstay() {
        let passport = Passport(expiresOn: d(1, 1, 2030),
                                heldVisas: [HeldVisa(zone: .schengen, validUntil: d(12, 31))])
        let result = VisaAdvisor.assess(countryCode: "PT", passport: passport, tripStart: d(5, 1), tripEnd: d(6, 9),
                                        otherSchengenStays: [stay(d(2, 1), d(4, 1))], calendar: cal)
        XCTAssertTrue(result.needsAction)
        XCTAssertTrue(result.warnings.contains(.schengenOverstay(firstDay: d(5, 31), latestExit: d(5, 30), days: 10)))

        // Diğer kalışlar olmadan sorun yok.
        let clean = VisaAdvisor.assess(countryCode: "PT", passport: passport, tripStart: d(5, 1), tripEnd: d(6, 9),
                                       calendar: cal)
        XCTAssertFalse(clean.needsAction)
    }
}
