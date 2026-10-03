import XCTest
@testable import StublyKit

final class BudgetTests: XCTestCase {
    let cal = TestCalendar.calendar

    func makeTrip(spentFood: Int) -> Trip {
        let me = Member(name: "Ömer", role: .owner)
        return Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"),
                    startDate: TestCalendar.date(2026, 10, 12), endDate: TestCalendar.date(2026, 10, 17),
                    members: [me],
                    budget: [BudgetLine(category: .food, limit: 60000)],
                    expenses: [
                        Expense(title: "Yemek", amount: spentFood, category: .food, paidBy: me.id, splitAmong: [me.id],
                                date: TestCalendar.date(2026, 10, 12)),
                        Expense(title: "Hesaplaşma", amount: 99999, category: .other, paidBy: me.id, splitAmong: [me.id],
                                date: TestCalendar.date(2026, 10, 12), isTransfer: true),
                    ])
    }

    func testTransfersAreExcludedFromSpending() {
        let summary = Budget.summary(for: makeTrip(spentFood: 30000), now: TestCalendar.date(2026, 10, 14), calendar: cal)
        XCTAssertEqual(summary.spent, 30000)
        XCTAssertEqual(summary.limit, 60000)
        XCTAssertEqual(summary.categories.map(\.category), [.food])
    }

    func testPace() {
        // 6 günlük seyahatin 3. günü → beklenen 30000.
        let day3 = TestCalendar.date(2026, 10, 14)
        XCTAssertEqual(Budget.summary(for: makeTrip(spentFood: 30000), now: day3, calendar: cal).pace, .onTrack(day: 3, of: 6))
        XCTAssertEqual(Budget.summary(for: makeTrip(spentFood: 40000), now: day3, calendar: cal).pace, .ahead(day: 3, of: 6))
        XCTAssertEqual(Budget.summary(for: makeTrip(spentFood: 10000), now: day3, calendar: cal).pace, .under(day: 3, of: 6))
        XCTAssertEqual(Budget.summary(for: makeTrip(spentFood: 0), now: TestCalendar.date(2026, 10, 1), calendar: cal).pace,
                       .notStarted)
        XCTAssertEqual(Budget.summary(for: makeTrip(spentFood: 0), now: TestCalendar.date(2026, 10, 20), calendar: cal).pace,
                       .finished)
    }

    func testTripDaysAndNights() {
        let trip = makeTrip(spentFood: 0)
        XCTAssertEqual(trip.days(calendar: cal).count, 6)
        XCTAssertEqual(trip.nights(calendar: cal), 5)
    }
}
