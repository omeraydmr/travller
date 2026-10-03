import XCTest
@testable import StublyKit

final class AmountEntryTests: XCTestCase {
    private func entry(_ keys: String) -> AmountEntry {
        var entry = AmountEntry()
        for key in keys {
            switch key {
            case ",": entry.appendDecimalSeparator()
            case "<": entry.backspace()
            default: entry.append(digit: Int(String(key))!)
            }
        }
        return entry
    }

    func testTypingWholeAmounts() {
        XCTAssertEqual(entry("1250").display, "1.250")
        XCTAssertEqual(entry("1250").minorUnits, 125_000)
        XCTAssertEqual(entry("1234567").display, "1.234.567")
        XCTAssertEqual(AmountEntry().display, "0")
        XCTAssertTrue(AmountEntry().isEmpty)
    }

    func testDecimals() {
        XCTAssertEqual(entry("12,5").display, "12,5")
        XCTAssertEqual(entry("12,5").minorUnits, 1_250)
        XCTAssertEqual(entry("12,567").display, "12,56", "en fazla iki ondalık")
        XCTAssertEqual(entry(",5").display, "0,5")
        XCTAssertEqual(entry("12,,5").display, "12,5")
        XCTAssertEqual(entry("12,").display, "12,")
    }

    func testLeadingZerosAndLimits() {
        XCTAssertEqual(entry("0007").display, "7")
        XCTAssertEqual(entry("00").display, "0")
        XCTAssertEqual(entry("1234567890").display, "123.456.789")
    }

    func testBackspace() {
        XCTAssertEqual(entry("12,5<").display, "12,")
        XCTAssertEqual(entry("12,5<<").display, "12")
        XCTAssertEqual(entry(",<").display, "0")
        XCTAssertTrue(entry(",<").isEmpty)
        XCTAssertEqual(entry("1<<<").display, "0")
    }

    func testInitFromMinorUnits() {
        XCTAssertEqual(AmountEntry(minorUnits: 125_050).display, "1.250,5")
        XCTAssertEqual(AmountEntry(minorUnits: 125_005).display, "1.250,05")
        XCTAssertEqual(AmountEntry(minorUnits: 4_200).display, "42")
        XCTAssertEqual(AmountEntry(minorUnits: 4_200).minorUnits, 4_200)
        XCTAssertEqual(AmountEntry(minorUnits: 0).display, "0")
    }
}
