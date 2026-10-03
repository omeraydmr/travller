import XCTest
@testable import StublyKit

final class ReceiptParserTests: XCTestCase {
    func testTurkishReceipt() {
        let lines = ["MIGROS TİCARET A.Ş.", "TARİH: 12.10.2026  SAAT: 19:42", "EKMEK            12,50",
                     "PEYNİR          189,90", "ARA TOPLAM      202,40", "TOPKDV            2,02", "TOPLAM          *202,40",
                     "NAKİT           250,00", "PARA ÜSTÜ        47,60"]
        let result = ReceiptParser.parse(lines: lines)
        XCTAssertEqual(result?.amount, 20_240)
        XCTAssertEqual(result?.isConfident, true)
    }

    func testEnglishReceiptWithCurrency() {
        let lines = ["Pastéis de Belém", "2x Pastel de nata  €2.60", "1x Galão  €1.80", "Subtotal  €4.40",
                     "VAT 13%  €0.51", "TOTAL  €4.40", "Card  €4.40"]
        let result = ReceiptParser.parse(lines: lines)
        XCTAssertEqual(result?.amount, 440)
        XCTAssertEqual(result?.currency, "EUR")
    }

    func testTotalOnNextLineAndThousands() {
        let result = ReceiptParser.parse(lines: ["GENEL TOPLAM", "1.250,75 TL"])
        XCTAssertEqual(result?.amount, 125_075)
        XCTAssertEqual(result?.currency, "TRY")
        XCTAssertEqual(ReceiptParser.parse(lines: ["Total due", "$1,250.75"])?.amount, 125_075)
    }

    func testFallbackToLargestDecimalAmount() {
        let result = ReceiptParser.parse(lines: ["Café Central 2026", "Melange 4,90", "Torte 5,60", "10,50"])
        XCTAssertEqual(result?.amount, 1_050)
        XCTAssertEqual(result?.isConfident, false)
        XCTAssertNil(ReceiptParser.parse(lines: ["Teşekkürler", "Yine bekleriz"]))
    }
}
