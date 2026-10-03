import XCTest
@testable import StublyKit

final class AirportsTests: XCTestCase {
    func testDatasetCoversSmallAndFarAirports() throws {
        XCTAssertGreaterThan(Airports.table.count, 3_500)
        let gazipasa = try XCTUnwrap(Airports.airport("GZP"))
        XCTAssertEqual(gazipasa.countryCode, "TR")
        XCTAssertEqual(gazipasa.timeZone, "Europe/Istanbul")
        XCTAssertEqual(Airports.airport("akl")?.timeZone, "Pacific/Auckland")
        XCTAssertEqual(Airports.airport("DPS")?.timeZone, "Asia/Makassar")
        XCTAssertNotNil(TimeZone(identifier: try XCTUnwrap(Airports.airport("CPT")).timeZone))
    }

    func testCommonAirportsKeepTurkishNamesAndGainCoordinates() throws {
        let istanbul = try XCTUnwrap(Airports.airport("IST"))
        XCTAssertEqual(istanbul.city, "İstanbul")
        let coordinate = try XCTUnwrap(istanbul.coordinate)
        XCTAssertEqual(coordinate.latitude, 41.27, accuracy: 0.05)
        XCTAssertEqual(Airports.airport("LIS")?.city, "Lizbon")
        XCTAssertTrue(Airports.isCommon("SAW"))
        XCTAssertFalse(Airports.isCommon("GZP"))
    }

    func testEveryTimeZoneIsValid() {
        let invalid = Airports.table.values.filter { TimeZone(identifier: $0.timeZone) == nil }.map(\.code)
        XCTAssertTrue(invalid.isEmpty, "Geçersiz saat dilimi: \(invalid.prefix(10))")
    }

    func testFlightDurationEstimate() throws {
        // SAW–CPH ~2.050 km → ~3 sa; IST–LIS ~3.200 km → ~4,5 sa
        let short = try XCTUnwrap(Airports.estimatedFlightMinutes(from: "SAW", to: "CPH"))
        XCTAssertTrue((170...200).contains(short), "\(short)")
        let long = try XCTUnwrap(Airports.estimatedFlightMinutes(from: "IST", to: "LIS"))
        XCTAssertTrue((260...300).contains(long), "\(long)")
        XCTAssertNil(Airports.estimatedFlightMinutes(from: "IST", to: "XXX"))
    }

    func testRouteHeuristicIgnoresRandomCodePairs() {
        XCTAssertTrue(BookingParser.looksLikeRoute("IST", "GZP"))
        XCTAssertTrue(BookingParser.looksLikeRoute("GZP", "AKL"), "İkisi de bilinen havalimanı")
        XCTAssertFalse(BookingParser.looksLikeRoute("ZZQ", "QQZ"))
    }
}
