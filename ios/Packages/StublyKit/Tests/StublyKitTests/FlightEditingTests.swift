import XCTest
@testable import StublyKit

final class FlightEditingTests: XCTestCase {
    var istanbul: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    func testWallClockRoundTripsThroughAirportZone() {
        // Cihaz İstanbul'da; seçicide 12 Eki 10:15 seçildi, varış Lizbon saatiyle.
        let picked = istanbul.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 10, minute: 15))!
        let instant = FlightClock.instant(wallClock: picked, timeZone: "Europe/Lisbon", device: istanbul)
        var lisbon = Calendar(identifier: .gregorian)
        lisbon.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        XCTAssertEqual(lisbon.dateComponents([.hour, .minute], from: instant), DateComponents(hour: 10, minute: 15))
        XCTAssertEqual(instant.timeIntervalSince(picked), 2 * 3600, "Lizbon İstanbul'un 2 saat gerisinde")
        XCTAssertEqual(FlightClock.wallClock(for: instant, timeZone: "Europe/Lisbon", device: istanbul), picked)
    }

    func testUnknownZoneKeepsDeviceTime() {
        let picked = istanbul.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 7, minute: 40))!
        XCTAssertEqual(FlightClock.instant(wallClock: picked, timeZone: nil, device: istanbul), picked)
        XCTAssertEqual(FlightClock.instant(wallClock: picked, timeZone: "Nowhere/City", device: istanbul), picked)
    }

    func testDeletedFlightStaysDeletedAfterMerge() {
        let start = istanbul.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        let outbound = FlightSegment(flightNumber: "TK1759", fromCode: "IST", fromCity: "İstanbul", toCode: "LIS",
                                     toCity: "Lizbon", departure: start, arrival: start.addingTimeInterval(4 * 3600))
        let back = FlightSegment(flightNumber: "TK1760", fromCode: "LIS", fromCity: "Lizbon", toCode: "IST",
                                 toCity: "İstanbul", departure: start.addingTimeInterval(6 * 86400),
                                 arrival: start.addingTimeInterval(6 * 86400 + 4 * 3600))
        var base = Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"),
                        startDate: start, endDate: start.addingTimeInterval(6 * 86400), flights: [outbound, back])
        base.updatedAt = start

        // Bu cihazda dönüş uçuşu silindi; diğer cihazdaki kopya daha yeni ama eski listeyi taşıyor.
        var local = base
        local.flights.removeAll { $0.id == back.id }
        local.recordDeletions(since: base)
        var remote = base
        remote.name = "Lizbon!"
        remote.updatedAt = start.addingTimeInterval(60)

        let merged = local.merged(with: remote)
        XCTAssertEqual(merged.flights.map(\.flightNumber), ["TK1759"])
        XCTAssertEqual(merged.name, "Lizbon!")

        // Diğer cihazda eklenen uçuş korunur.
        var added = base
        let extra = FlightSegment(flightNumber: "PC1171", fromCode: "SAW", fromCity: "İstanbul", toCode: "LIS",
                                  toCity: "Lizbon", departure: start.addingTimeInterval(3600), arrival: start.addingTimeInterval(5 * 3600))
        added.flights.append(extra)
        XCTAssertEqual(base.merged(with: added).flights.map(\.flightNumber), ["TK1759", "PC1171", "TK1760"])
    }
}
