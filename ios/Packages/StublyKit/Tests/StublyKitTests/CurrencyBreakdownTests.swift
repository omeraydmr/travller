import XCTest
@testable import StublyKit

final class CurrencyBreakdownTests: XCTestCase {
    func testGroupsByOriginalCurrency() {
        let me = Member(name: "Ben")
        let trip = Trip(name: "T", destination: Destination(countryCode: "PT", city: "Lizbon"), startDate: .now, endDate: .now,
                        currency: "EUR", members: [me], expenses: [
                            Expense(title: "Otel", amount: 50_000, category: .stays, paidBy: me.id, splitAmong: [me.id], date: .now),
                            Expense(title: "Döner", amount: 1_000, category: .food, paidBy: me.id, splitAmong: [me.id], date: .now,
                                    originalAmount: 37_000, originalCurrency: "TRY"),
                            Expense(title: "Taksi", amount: 2_000, category: .transport, paidBy: me.id, splitAmong: [me.id],
                                    date: .now, originalAmount: 74_000, originalCurrency: "TRY"),
                            Expense(title: "Hesaplaşma", amount: 9_999, category: .other, paidBy: me.id, splitAmong: [me.id],
                                    date: .now, isTransfer: true),
                        ])
        let breakdown = Budget.currencyBreakdown(for: trip)
        XCTAssertEqual(breakdown.map(\.currency), ["EUR", "TRY"])
        XCTAssertEqual(breakdown[0].convertedTotal, 50_000)
        XCTAssertEqual(breakdown[1].originalTotal, 111_000)
        XCTAssertEqual(breakdown[1].convertedTotal, 3_000)
        XCTAssertEqual(breakdown[1].count, 2)
    }
}
