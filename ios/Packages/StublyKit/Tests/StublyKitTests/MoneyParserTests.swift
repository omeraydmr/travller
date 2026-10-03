import XCTest
@testable import StublyKit

final class MoneyParserTests: XCTestCase {
    func testTurkishFormats() {
        XCTAssertEqual(MoneyParser.minorUnits(from: "1600"), 160_000)
        XCTAssertEqual(MoneyParser.minorUnits(from: "1.600"), 160_000)
        XCTAssertEqual(MoneyParser.minorUnits(from: "12,50"), 1_250)
        XCTAssertEqual(MoneyParser.minorUnits(from: "1.250,75"), 125_075)
        XCTAssertEqual(MoneyParser.minorUnits(from: "1.250.000"), 125_000_000)
        XCTAssertEqual(MoneyParser.minorUnits(from: " 42 "), 4_200)
    }

    func testDotAsDecimal() {
        XCTAssertEqual(MoneyParser.minorUnits(from: "12.5"), 1_250)
        XCTAssertEqual(MoneyParser.minorUnits(from: "12.05"), 1_205)
    }

    func testInvalid() {
        XCTAssertNil(MoneyParser.minorUnits(from: ""))
        XCTAssertNil(MoneyParser.minorUnits(from: "abc"))
        XCTAssertNil(MoneyParser.minorUnits(from: "-5"))
        XCTAssertNil(MoneyParser.minorUnits(from: "1,2,3"))
    }
}
