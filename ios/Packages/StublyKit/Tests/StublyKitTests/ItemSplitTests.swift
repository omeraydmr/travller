import XCTest
@testable import StublyKit

final class ItemSplitTests: XCTestCase {
    let a = UUID(), b = UUID(), c = UUID()

    func testReceiptItems() {
        let lines = ["Pastéis de Belém", "Mesa 4  12.10.2026 13:05", "2x Pastel de nata  €2.60", "1x Galão  €1.80",
                     "Sumo laranja ...... €3.50", "Subtotal  €7.90", "IVA 13%  €0.91", "TOTAL  €7.90", "Card  €7.90"]
        let items = ReceiptParser.items(lines: lines)
        XCTAssertEqual(items.map(\.name), ["2x Pastel de nata", "1x Galão", "Sumo laranja"])
        XCTAssertEqual(items.map(\.amount), [260, 180, 350])
        XCTAssertEqual(items.map(\.id), [0, 1, 2])
    }

    func testTurkishItems() {
        let lines = ["MIGROS", "EKMEK            12,50", "PEYNİR          189,90", "ARA TOPLAM      202,40",
                     "TOPKDV            2,02", "TOPLAM          *202,40"]
        XCTAssertEqual(ReceiptParser.items(lines: lines).map(\.name), ["EKMEK", "PEYNİR"])
    }

    func testSharesSplitPerItemAndKeepTotal() {
        let items = [ReceiptItem(id: 0, name: "Şarap", amount: 3_000), ReceiptItem(id: 1, name: "Salata", amount: 1_000)]
        let shares = ItemSplit.shares(items: items, assignments: [0: [a, b], 1: [c]], total: 4_000)
        XCTAssertEqual(shares[a], 1_500)
        XCTAssertEqual(shares[b], 1_500)
        XCTAssertEqual(shares[c], 1_000)
    }

    func testSharesScaleToConvertedTotal() {
        // ₺1.000 → €27,75 gibi farklı toplam; kuruşlar kaybolmamalı.
        let items = [ReceiptItem(id: 0, name: "X", amount: 70_000), ReceiptItem(id: 1, name: "Y", amount: 30_001)]
        let shares = ItemSplit.shares(items: items, assignments: [0: [a], 1: [b, c]], total: 2_775)
        XCTAssertEqual(shares.values.reduce(0, +), 2_775)
        XCTAssertEqual(shares[a], 1_943, "en büyük kalan a’da")
        XCTAssertEqual(ItemSplit.shares(items: items, assignments: [:], total: 100), [:])
    }

    func testSettlementUsesCustomShares() {
        let expense = Expense(title: "Akşam yemeği", amount: 4_000, category: .food, paidBy: c, splitAmong: [a, b, c],
                              date: .now, shares: [a: 1_500, b: 1_500, c: 1_000])
        let balances = Settlement.balances(expenses: [expense], members: [a, b, c])
        XCTAssertEqual(balances[a], -1_500)
        XCTAssertEqual(balances[c], 3_000)
        XCTAssertEqual(balances.values.reduce(0, +), 0)
    }
}
