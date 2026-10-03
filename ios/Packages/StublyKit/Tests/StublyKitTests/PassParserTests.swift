import Compression
import XCTest
@testable import StublyKit

final class PassParserTests: XCTestCase {
    let cal = TestCalendar.calendar
    let now = TestCalendar.date(2026, 9, 1)

    func components(_ date: Date, _ zone: String) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.dateComponents([.month, .day, .hour, .minute], from: date)
    }

    let semanticPass = """
    {
      "formatVersion": 1,
      "description": "Boarding pass",
      "relevantDate": "2026-10-12T07:00+03:00",
      "semantics": {
        "airlineCode": "TK", "flightNumber": 1759, "flightCode": "TK 1759",
        "departureAirportCode": "IST", "destinationAirportCode": "LIS",
        "originalDepartureDate": "2026-10-12T07:40:00+03:00",
        "originalArrivalDate": "2026-10-12T10:15:00+01:00",
        "seats": [{ "seatIdentifier": "14c" }]
      },
      "boardingPass": { "transitType": "PKTransitTypeAir" }
    }
    """

    func testSemanticTagsGiveFlight() throws {
        let result = try XCTUnwrap(PassParser.parse(passJSON: Data(semanticPass.utf8), now: now, calendar: cal))
        let flight = try XCTUnwrap(result.flights.first)
        XCTAssertEqual(flight.flightNumber, "TK1759")
        XCTAssertEqual(flight.fromCode, "IST")
        XCTAssertEqual(flight.toCode, "LIS")
        XCTAssertEqual(flight.seat, "14C")
        XCTAssertTrue(flight.hasTimes)
        let dep = components(flight.departure, "Europe/Istanbul")
        XCTAssertEqual([dep.month, dep.day, dep.hour, dep.minute], [10, 12, 7, 40])
        let arr = components(flight.arrival, "Europe/Lisbon")
        XCTAssertEqual([arr.hour, arr.minute], [10, 15])
    }

    func testFieldsWithoutSemantics() throws {
        let json = """
        {
          "relevantDate": "2026-11-11T09:10+03:00",
          "boardingPass": {
            "headerFields": [{ "key": "flight", "label": "UÇUŞ", "value": "PC 1171" }],
            "primaryFields": [
              { "key": "origin", "label": "İstanbul", "value": "SAW" },
              { "key": "destination", "label": "Osaka", "value": "KIX" }
            ],
            "auxiliaryFields": [
              { "key": "departs", "label": "KALKIŞ", "value": "2026-11-11T09:55+03:00", "timeStyle": "PKDateStyleShort" },
              { "key": "seat", "label": "KOLTUK", "value": "21A" }
            ]
          }
        }
        """
        let result = try XCTUnwrap(PassParser.parse(passJSON: Data(json.utf8), now: now, calendar: cal))
        let flight = try XCTUnwrap(result.flights.first)
        XCTAssertEqual(flight.flightNumber, "PC1171")
        XCTAssertEqual([flight.fromCode, flight.toCode], ["SAW", "KIX"])
        XCTAssertEqual(flight.seat, "21A")
        // Varış saati yok: kontrol edilmesi istenir.
        XCTAssertFalse(flight.hasTimes)
        let dep = components(flight.departure, "Europe/Istanbul")
        XCTAssertEqual([dep.hour, dep.minute], [9, 55])
    }

    func testUnknownStructureFallsBackToText() throws {
        let json = """
        {
          "description": "TK 1760 IST - LIS",
          "generic": { "primaryFields": [{ "key": "when", "label": "Tarih", "value": "18 Eki 2026 11:20 - 17:05" }] }
        }
        """
        let result = try XCTUnwrap(PassParser.parse(passJSON: Data(json.utf8), now: now, calendar: cal))
        XCTAssertEqual(result.flights.first?.flightNumber, "TK1760")
    }

    func testInvalidJSONIsNil() {
        XCTAssertNil(PassParser.parse(passJSON: Data("nope".utf8)))
    }

    func testReadsPkpassArchiveWithStoredAndDeflatedEntries() throws {
        let manifest = Data(#"{"pass.json":"0"}"#.utf8)
        for deflate in [false, true] {
            let archive = TestZip.make([("manifest.json", manifest), ("pass.json", Data(semanticPass.utf8))], deflate: deflate)
            let zip = try XCTUnwrap(ZipArchive(data: archive))
            XCTAssertEqual(zip.entries.map(\.name), ["manifest.json", "pass.json"])
            XCTAssertEqual(zip.contents(of: "manifest.json"), manifest)
            let result = try XCTUnwrap(PassParser.parse(pkpass: archive, now: now, calendar: cal))
            XCTAssertEqual(result.flights.first?.flightNumber, "TK1759")
        }
    }

    func testNonZipIsNil() {
        XCTAssertNil(ZipArchive(data: Data("not a zip".utf8)))
        XCTAssertNil(PassParser.parse(pkpass: Data(repeating: 0, count: 40)))
    }
}

/// Testler için en küçük ZIP yazıcı (CRC doğrulanmadığı için 0 yazılır).
enum TestZip {
    static func make(_ files: [(String, Data)], deflate: Bool) -> Data {
        // Uzun "+" zincirleri derleyicinin tür çıkarımını çok yavaşlatıyor; parça parça eklenir.
        var body = Data()
        var central = Data()
        for (name, content) in files {
            let payload = deflate ? compress(content) : content
            let method: UInt16 = deflate ? 8 : 0
            let offset = UInt32(body.count)
            let nameBytes = Data(name.utf8)
            let sizes: [Data] = [le32(0), le32(UInt32(payload.count)), le32(UInt32(content.count)),
                                 le16(UInt16(nameBytes.count))]

            let local: [Data] = [le32(0x0403_4B50), le16(20), le16(0), le16(method), le16(0), le16(0)]
            local.forEach { body.append($0) }
            sizes.forEach { body.append($0) }
            body.append(le16(0))
            body.append(nameBytes)
            body.append(payload)

            let header: [Data] = [le32(0x0201_4B50), le16(20), le16(20), le16(0), le16(method), le16(0), le16(0)]
            header.forEach { central.append($0) }
            sizes.forEach { central.append($0) }
            let tail: [Data] = [le16(0), le16(0), le16(0), le16(0), le32(0), le32(offset)]
            tail.forEach { central.append($0) }
            central.append(nameBytes)
        }
        var archive = body
        archive.append(central)
        let end: [Data] = [le32(0x0605_4B50), le16(0), le16(0), le16(UInt16(files.count)), le16(UInt16(files.count)),
                           le32(UInt32(central.count)), le32(UInt32(body.count)), le16(0)]
        end.forEach { archive.append($0) }
        return archive
    }

    static func compress(_ data: Data) -> Data {
        let source = [UInt8](data)
        var output = [UInt8](repeating: 0, count: source.count + 1024)
        let size = source.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                compression_encode_buffer(dst.baseAddress!, dst.count, src.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        return Data(output.prefix(size))
    }

    static func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    static func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
}
