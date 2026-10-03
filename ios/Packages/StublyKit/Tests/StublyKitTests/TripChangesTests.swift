import XCTest
@testable import StublyKit

final class TripChangesTests: XCTestCase {
    let me = Member(name: "Ben")
    let elif = Member(name: "Elif")
    func money(_ minor: Int, _ code: String) -> String { "\(code) \(minor / 100)" }

    func base() -> Trip {
        Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"), startDate: .now, endDate: .now,
             currency: "EUR", members: [me, elif], packing: [PackingItem(title: "Pasaport", assignee: elif.id)])
    }

    func testDescribesOthersChanges() {
        let old = base()
        var new = old
        new.expenses.append(Expense(title: "Akşam yemeği", amount: 8_600, category: .food, paidBy: elif.id,
                                    splitAmong: [me.id, elif.id], date: .now))
        new.stops.append(Stop(day: .now, order: 0, name: "Pena Sarayı", kind: .sight))
        new.packing[0].isPacked = true

        let summary = TripChanges.summarize(old: old, new: new, me: me.id, money: money)
        XCTAssertEqual(summary?.title, "Lizbon")
        XCTAssertEqual(summary?.lines, ["Elif bir harcama ekledi: Akşam yemeği · EUR 86", "Plana eklendi: Pena Sarayı",
                                        "Valize konuldu: Pasaport"])
    }

    func testIgnoresOwnChangesAndNoOps() {
        let old = base()
        var new = old
        new.expenses.append(Expense(title: "Taksi", amount: 1_000, category: .transport, paidBy: me.id,
                                    splitAmong: [me.id], date: .now))
        XCTAssertNil(TripChanges.summarize(old: old, new: new, me: me.id, money: money))
        XCTAssertNil(TripChanges.summarize(old: old, new: old, me: me.id, money: money))
    }

    func testNewSharedTrip() {
        XCTAssertEqual(TripChanges.summarize(old: nil, new: base(), me: me.id, money: money)?.lines, ["Seyahat seninle paylaşıldı."])
    }
}
