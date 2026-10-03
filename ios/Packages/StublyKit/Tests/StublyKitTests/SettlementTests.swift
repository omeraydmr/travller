import XCTest
@testable import StublyKit

final class SettlementTests: XCTestCase {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    func testSplitKeepsEveryCent() {
        XCTAssertEqual(Settlement.split(1000, into: 3), [334, 333, 333])
        XCTAssertEqual(Settlement.split(1000, into: 3).reduce(0, +), 1000)
        XCTAssertEqual(Settlement.split(5, into: 0), [])
    }

    func testBalancesSumToZero() {
        let expenses = [
            Expense(title: "Otel", amount: 60000, category: .stays, paidBy: a, splitAmong: [a, b, c], date: .now),
            Expense(title: "Akşam yemeği", amount: 10001, category: .food, paidBy: b, splitAmong: [a, b, c, d], date: .now),
        ]
        let balances = Settlement.balances(expenses: expenses, members: [a, b, c, d])
        XCTAssertEqual(balances.values.reduce(0, +), 0)
        XCTAssertEqual(balances[a], 60000 - 20000 - 2501)
    }

    func testTransfersSettleEveryone() {
        let expenses = [
            Expense(title: "Uçak", amount: 90000, category: .transport, paidBy: d, splitAmong: [a, b, c, d], date: .now),
            Expense(title: "Ev", amount: 40000, category: .stays, paidBy: a, splitAmong: [a, b, c, d], date: .now),
        ]
        let balances = Settlement.balances(expenses: expenses, members: [a, b, c, d])
        let transfers = Settlement.transfers(balances: balances)

        var after = balances
        for transfer in transfers {
            after[transfer.from, default: 0] += transfer.amount
            after[transfer.to, default: 0] -= transfer.amount
        }
        XCTAssertTrue(after.values.allSatisfy { $0 == 0 })
        XCTAssertLessThanOrEqual(transfers.count, 3)
    }

    func testTransferExpenseClearsDebt() {
        var expenses = [Expense(title: "Taksi", amount: 2000, category: .transport, paidBy: a, splitAmong: [a, b], date: .now)]
        XCTAssertEqual(Settlement.transfers(balances: Settlement.balances(expenses: expenses, members: [a, b])),
                       [Transfer(from: b, to: a, amount: 1000)])

        expenses.append(Expense(title: "Hesaplaşma", amount: 1000, category: .other, paidBy: b, splitAmong: [a],
                                date: .now, isTransfer: true))
        XCTAssertTrue(Settlement.transfers(balances: Settlement.balances(expenses: expenses, members: [a, b])).isEmpty)
    }
}
