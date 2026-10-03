import XCTest
@testable import StublyKit

final class DocumentRemindersTests: XCTestCase {
    let cal = TestCalendar.calendar
    let now = TestCalendar.date(2026, 10, 3)

    func testPassportExpiryRemindersAt6_3_1Months() {
        let passport = Passport(expiresOn: TestCalendar.date(2027, 6, 15))
        let plan = DocumentReminders.plan(passport: passport, trips: [], now: now, calendar: cal)
        XCTAssertEqual(plan.map(\.id), ["doc-passport-6m", "doc-passport-3m", "doc-passport-1m"])
        XCTAssertEqual(plan.map { cal.dateComponents([.year, .month, .day, .hour], from: $0.date) },
                       [DateComponents(year: 2026, month: 12, day: 15, hour: 9), DateComponents(year: 2027, month: 3, day: 15, hour: 9),
                        DateComponents(year: 2027, month: 5, day: 15, hour: 9)])
        XCTAssertNil(plan.first?.link, "Yaklaşan seyahat yoksa uygulama açılır")
    }

    func testPastRemindersAreSkipped() {
        let passport = Passport(expiresOn: TestCalendar.date(2026, 12, 1))
        XCTAssertEqual(DocumentReminders.plan(passport: passport, trips: [], now: now, calendar: cal).map(\.id),
                       ["doc-passport-1m"], "6 ve 3 ay öncesi geçti")
        XCTAssertTrue(DocumentReminders.plan(passport: nil, trips: [], now: now, calendar: cal).isEmpty)
    }

    func testPassportTooShortForUpcomingTrip() throws {
        // Lizbon (Schengen: dönüşten sonra 3 ay zorunlu); pasaport dönüşten 1 ay sonra bitiyor.
        let trip = Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"),
                        startDate: TestCalendar.date(2027, 3, 1), endDate: TestCalendar.date(2027, 3, 8))
        let passport = Passport(expiresOn: TestCalendar.date(2027, 4, 8))
        let plan = DocumentReminders.plan(passport: passport, trips: [trip], now: now, calendar: cal)
        let warning = try XCTUnwrap(plan.first { $0.id == "doc-passport-trip-\(trip.id.uuidString)" })
        XCTAssertEqual(cal.dateComponents([.month, .day], from: warning.date), DateComponents(month: 12, day: 31), "Gidişten 60 gün önce")
        XCTAssertEqual(warning.link, TripLink(tripID: trip.id, section: "visa"))
        XCTAssertEqual(plan.first { $0.id == "doc-passport-6m" }?.link, TripLink(tripID: trip.id, section: "visa"))
    }

    func testHeldVisaReminders() {
        let visa = HeldVisa(zone: .schengen, validUntil: TestCalendar.date(2027, 2, 1))
        let passport = Passport(expiresOn: TestCalendar.date(2035, 1, 1), heldVisas: [visa])
        let plan = DocumentReminders.plan(passport: passport, trips: [], now: now, calendar: cal).filter { $0.id.contains("visa") }
        XCTAssertEqual(plan.count, 2)
        XCTAssertTrue(plan[0].title.contains("Schengen"))
        XCTAssertEqual(cal.dateComponents([.month, .day], from: plan[1].date), DateComponents(month: 1, day: 18))
    }
}
