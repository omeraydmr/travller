import XCTest
@testable import StublyKit

final class PlaceMatchTests: XCTestCase {
    let lisbon = Coordinate(latitude: 38.7223, longitude: -9.1393)

    func testSimilarityIgnoresCaseAccentsAndTypos() {
        XCTAssertEqual(PlaceMatch.similarity("jeronimos", "Mosteiro dos Jerónimos"), 0.8)
        XCTAssertEqual(PlaceMatch.similarity("Belém", "belem tower"), 0.9)
        XCTAssertEqual(PlaceMatch.similarity("İstiklal", "Istiklal Caddesi"), 0.9)
        XCTAssertGreaterThan(PlaceMatch.similarity("jeronimo manastir", "Jerónimos Manastırı"),
                             PlaceMatch.similarity("jeronimo manastir", "Santa Justa Asansörü"))
        XCTAssertGreaterThan(PlaceMatch.similarity("pasteis belem", "Pastéis de Belém"), 0.6)
        XCTAssertEqual(PlaceMatch.similarity("", "x"), 0)
    }

    func testRankDropsOtherCountriesAndFarPlaces() {
        let candidates = [
            PlaceMatch.Candidate(name: "Belém", coordinate: .init(latitude: -1.4558, longitude: -48.4902), countryCode: "BR"),
            PlaceMatch.Candidate(name: "Belém Tower", coordinate: .init(latitude: 38.6916, longitude: -9.2160), countryCode: "PT"),
            PlaceMatch.Candidate(name: "Belém", coordinate: .init(latitude: 38.6970, longitude: -9.2063), countryCode: "PT"),
            PlaceMatch.Candidate(name: "Belém Café", coordinate: .init(latitude: 41.1496, longitude: -8.6109), countryCode: "PT"),
        ]
        let ranked = PlaceMatch.rank(candidates, query: "belem", center: lisbon, countryCode: "pt")
        XCTAssertEqual(ranked.map(\.name), ["Belém", "Belém Tower"], "Brezilya ve 270 km uzaktaki Porto elenir")
    }

    func testRankFallsBackWhenNothingIsNearAndDedupes() {
        let porto = PlaceMatch.Candidate(name: "Ribeira", coordinate: .init(latitude: 41.1407, longitude: -8.6129), countryCode: "PT")
        XCTAssertEqual(PlaceMatch.rank([porto, porto], query: "ribeira", center: lisbon, countryCode: "PT").count, 1)
        let unknown = PlaceMatch.Candidate(name: "Ribeira", coordinate: porto.coordinate, countryCode: nil)
        XCTAssertEqual(PlaceMatch.rank([unknown], query: "ribeira", center: nil, countryCode: "PT").count, 1)
    }

    func testQueryVariantsFoldTurkishAndTranslatePlaceWords() {
        XCTAssertEqual(PlaceMatch.queryVariants("jeronımo manastır"), ["jeronımo manastır", "jeronimo manastir", "jeronimo monastery"])
        XCTAssertEqual(PlaceMatch.queryVariants("Belém Kulesi"), ["Belém Kulesi", "belem kulesi", "belem tower"])
        XCTAssertEqual(PlaceMatch.queryVariants("time out"), ["time out"])
        XCTAssertEqual(PlaceMatch.queryVariants("  "), [])
    }

    func testRankUsesTranslatedVariant() {
        let candidates = [
            PlaceMatch.Candidate(name: "Rua dos Jerónimos", coordinate: .init(latitude: 38.6985, longitude: -9.2050), countryCode: "PT"),
            PlaceMatch.Candidate(name: "Mosteiro dos Jerónimos", coordinate: .init(latitude: 38.6979, longitude: -9.2068), countryCode: "PT"),
            PlaceMatch.Candidate(name: "Belém Tower", coordinate: .init(latitude: 38.6916, longitude: -9.2160), countryCode: "PT"),
        ]
        XCTAssertEqual(PlaceMatch.rank(candidates, query: "belem kulesi", center: lisbon, countryCode: "PT").first?.name, "Belém Tower")
    }
}
