import XCTest
@testable import StublyKit

final class PackingTests: XCTestCase {
    func trip(_ country: String, month: Int, packing: [PackingItem] = []) -> Trip {
        Trip(name: "Test", destination: Destination(countryCode: country, city: "Şehir"),
             startDate: TestCalendar.date(2026, month, 1), endDate: TestCalendar.date(2026, month, 7), packing: packing)
    }

    func testAdapterOnlyWhenHomePlugsDoNotFit() {
        XCTAssertEqual(PackingAdvisor.adapterTypes(for: "GB"), ["G"])
        XCTAssertEqual(PackingAdvisor.adapterTypes(for: "JP"), ["A", "B"])
        XCTAssertNil(PackingAdvisor.adapterTypes(for: "PT"))
        XCTAssertNil(PackingAdvisor.adapterTypes(for: "IT"))
    }

    func testSuggestions() {
        let cal = TestCalendar.calendar
        let lisbon = PackingAdvisor.suggestions(for: trip("PT", month: 7), calendar: cal)
        XCTAssertTrue(lisbon.contains("Seyahat sağlık sigortası poliçesi"))
        XCTAssertTrue(lisbon.contains("Güneş kremi"))
        XCTAssertFalse(lisbon.contains { $0.hasPrefix("Priz adaptörü") })

        let london = PackingAdvisor.suggestions(for: trip("GB", month: 1), calendar: cal)
        XCTAssertTrue(london.contains("Priz adaptörü · Tip G"))
        XCTAssertTrue(london.contains("Bere ve eldiven"))

        let tbilisi = PackingAdvisor.suggestions(for: trip("GE", month: 4), calendar: cal)
        XCTAssertTrue(tbilisi.contains("Kimlik kartı"))
    }

    func testExistingItemsAreSkipped() {
        let suggestions = PackingAdvisor.suggestions(for: trip("PT", month: 7, packing: [PackingItem(title: "  pasaport ")]),
                                                     calendar: TestCalendar.calendar)
        XCTAssertFalse(suggestions.contains("Pasaport"))
    }
}
