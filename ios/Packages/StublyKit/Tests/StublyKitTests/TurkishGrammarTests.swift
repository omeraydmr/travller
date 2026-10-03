import XCTest
@testable import StublyKit

final class TurkishGrammarTests: XCTestCase {
    func testPossessiveSuffix() {
        let expected: [Int: String] = [
            0: "0'ı", 1: "1'i", 2: "2'si", 3: "3'ü", 4: "4'ü", 5: "5'i", 6: "6'sı", 7: "7'si", 8: "8'i", 9: "9'u",
            10: "10'u", 12: "12'si", 20: "20'si", 30: "30'u", 40: "40'ı", 50: "50'si", 60: "60'ı", 70: "70'i",
            80: "80'i", 90: "90'ı", 100: "100'ü", 300: "300'ü", 1000: "1000'i", 2000000: "2000000'u",
        ]
        for (number, text) in expected {
            XCTAssertEqual(TurkishGrammar.withPossessive(number), text, "\(number)")
        }
    }
}
