import XCTest
@testable import StublyKit

final class SyncMergeTests: XCTestCase {
    func base() -> Trip {
        let me = Member(name: "Ben")
        return Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"), startDate: .now, endDate: .now,
                    members: [me], packing: [PackingItem(title: "Pasaport")])
    }

    func testUnionKeepsAdditionsFromBothSides() {
        var local = base()
        var remote = local
        local.packing.append(PackingItem(title: "Şarj aleti"))
        local.updatedAt = Date(timeIntervalSince1970: 200)
        remote.packing.append(PackingItem(title: "Güneş kremi"))
        remote.name = "Lizbon 2026"
        remote.updatedAt = Date(timeIntervalSince1970: 300)

        let merged = local.merged(with: remote)
        XCTAssertEqual(merged.name, "Lizbon 2026", "daha yeni kopyanın alanları")
        XCTAssertEqual(Set(merged.packing.map(\.title)), ["Pasaport", "Şarj aleti", "Güneş kremi"])
        XCTAssertEqual(merged, remote.merged(with: local), "sıra fark etmez")
    }

    func testDeletionsDoNotComeBack() {
        let original = base()
        var local = original
        local.packing.removeAll()
        local.recordDeletions(since: original)
        local.updatedAt = Date(timeIntervalSince1970: 100)
        var remote = original
        remote.updatedAt = Date(timeIntervalSince1970: 500)

        let merged = local.merged(with: remote)
        XCTAssertTrue(merged.packing.isEmpty)
        XCTAssertEqual(merged.tombstones?.count, 1)
    }

    func testCommonItemTakesNewerVersion() {
        var local = base()
        var remote = local
        local.packing[0].isPacked = true
        local.updatedAt = Date(timeIntervalSince1970: 900)
        remote.updatedAt = Date(timeIntervalSince1970: 100)
        XCTAssertTrue(local.merged(with: remote).packing[0].isPacked)
    }
}

final class NotificationPlannerTests: XCTestCase {
    let cal = TestCalendar.calendar

    func testPlan() {
        let start = cal.startOfDay(for: TestCalendar.date(2026, 10, 12))
        let day2 = cal.startOfDay(for: TestCalendar.date(2026, 10, 13))
        let departure = cal.date(bySettingHour: 7, minute: 40, second: 0, of: start)!
        let trip = Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"),
                        startDate: start, endDate: day2,
                        flights: [FlightSegment(flightNumber: "TK1759", fromCode: "IST", fromCity: "İstanbul", toCode: "LIS",
                                                toCity: "Lizbon", departure: departure, arrival: departure.addingTimeInterval(16_500),
                                                gate: "F7", seat: "14C")],
                        stops: [Stop(day: day2, order: 0, name: "Pena Sarayı", kind: .sight, startMinutes: 600,
                                     note: "Biletler önceden alınmalı")],
                        packing: [PackingItem(title: "Pasaport"), PackingItem(title: "Şarj", isPacked: true)])

        let plan = NotificationPlanner.plan(for: trip, now: TestCalendar.date(2026, 10, 1), calendar: cal)
        XCTAssertEqual(plan.map { $0.id.components(separatedBy: "-").last! }, ["eve", "flight", "day1", plan.last!.id.components(separatedBy: "-").last!])
        XCTAssertEqual(plan[0].title, "Yarın Lizbon!")
        XCTAssertEqual(plan[0].body, "Valizde 1 madde eksik. Son kontrol için iyi bir zaman.")
        XCTAssertEqual(plan[1].body, "IST → LIS · kapı F7 · koltuk 14C")
        XCTAssertEqual(cal.component(.hour, from: plan[1].date), 4)
        XCTAssertEqual(plan[2].body, "1 durak · ilk durak Pena Sarayı, 10:00")
        XCTAssertEqual(plan[3].title, "45 dk sonra: Pena Sarayı")
        XCTAssertEqual(cal.component(.minute, from: plan[3].date), 15)
    }

    func testPastAndDraftTripsAreSkipped() {
        var trip = Trip(name: "T", destination: Destination(countryCode: "PT", city: "Lizbon"),
                        startDate: TestCalendar.date(2026, 10, 12), endDate: TestCalendar.date(2026, 10, 13))
        XCTAssertTrue(NotificationPlanner.plan(for: trip, now: TestCalendar.date(2026, 11, 1), calendar: cal).isEmpty)
        trip.status = .draft
        XCTAssertTrue(NotificationPlanner.plan(for: trip, now: TestCalendar.date(2026, 10, 1), calendar: cal).isEmpty)
    }
}
