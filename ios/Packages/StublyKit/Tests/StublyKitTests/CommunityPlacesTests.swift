import XCTest
@testable import StublyKit

final class CommunityPlacesTests: XCTestCase {
    let cal = TestCalendar.calendar

    func trip() -> Trip {
        let d1 = TestCalendar.date(2026, 9, 10), d2 = TestCalendar.date(2026, 9, 11)
        var trip = Trip(name: "Lizbon · Ayşe'nin doğum günü", destination: Destination(countryCode: "pt", city: "Lizbon"),
                        startDate: d1, endDate: d2)
        trip.stops = [
            Stop(day: d1, order: 0, name: "São Jorge Kalesi", kind: .sight, coordinate: .init(latitude: 38.713912, longitude: -9.133512),
                 note: "Kale / saray"),
            Stop(day: d1, order: 1, name: "Santa Justa", kind: .sight, coordinate: .init(latitude: 38.7121, longitude: -9.1394),
                 note: "Kapı kodu 4512, Elif'le buluş"),
            Stop(day: d1, order: 2, name: "Otel", kind: .stay, coordinate: .init(latitude: 38.71, longitude: -9.14)),
            Stop(day: d1, order: 3, name: "Pastéis", kind: .food, coordinate: .init(latitude: 38.6975, longitude: -9.2032)),
            Stop(day: d2, order: 0, name: "Konumsuz yer", kind: .sight),
            Stop(day: d2, order: 1, name: "Gulbenkian", kind: .sight, coordinate: .init(latitude: 38.737, longitude: -9.154)),
        ]
        return trip
    }

    func testContributionSharesOnlyPlacesAndSameDayPairs() throws {
        let value = trip()
        let castle = value.stops[0].id, lift = value.stops[1].id, pastry = value.stops[3].id
        let c = try XCTUnwrap(CommunityPlaces.contribution(for: value, ratings: [castle: 1, lift: -1, pastry: 5],
                                                            verified: [castle], excluded: [], calendar: cal))
        XCTAssertEqual(c.country, "PT")
        XCTAssertEqual(c.places.map(\.name), ["São Jorge Kalesi", "Santa Justa", "Pastéis", "Gulbenkian"])
        XCTAssertEqual(c.places.map(\.liked), [1, -1, 1, 0])
        XCTAssertEqual(c.places.map(\.verified), [true, false, false, false])
        XCTAssertEqual(c.places[0].lat, 38.71391)
        XCTAssertEqual(c.places[0].category, "Kale / saray")
        XCTAssertEqual(c.places[1].category, "", "Kişisel not paylaşılmaz")
        XCTAssertEqual(c.transitions, [["p0", "p1"], ["p1", "p2"]], "Otel atlanır; günler arası geçiş yok")

        let json = String(decoding: try JSONEncoder().encode(c), as: UTF8.self)
        XCTAssertFalse(json.contains("doğum"), "Seyahat adı gitmez")
        XCTAssertFalse(json.contains("2026"), "Tarih gitmez")
        XCTAssertFalse(json.contains(castle.uuidString), "Durak kimliği gitmez")
    }

    func testExcludedStopsAreLeftOut() throws {
        let value = trip()
        let c = try XCTUnwrap(CommunityPlaces.contribution(for: value, ratings: [:], verified: [],
                                                            excluded: [value.stops[1].id], calendar: cal))
        XCTAssertEqual(c.places.map(\.name), ["São Jorge Kalesi", "Pastéis", "Gulbenkian"])
        XCTAssertEqual(c.transitions, [["p0", "p1"]])
    }

    func testEligibility() {
        XCTAssertTrue(CommunityPlaces.canContribute(trip(), now: TestCalendar.date(2026, 9, 20), calendar: cal))
        XCTAssertFalse(CommunityPlaces.canContribute(trip(), now: TestCalendar.date(2026, 9, 10), calendar: cal), "Seyahat bitmeden olmaz")
    }

    func testDecodeAndMerge() {
        let json = #"{"places":[{"id":7,"name":"Café A Brasileira","lat":38.7107,"lon":-9.1424,"kind":"food","category":"Kafe / restoran","contributors":4,"likes":3,"dislikes":0,"verified":2,"score":19}]}"#
        let community = CommunityPlaces.decode(Data(json.utf8))
        XCTAssertEqual(community.first?.contributors, 4)
        XCTAssertEqual(community.first?.kind, .food)
        let wiki = [
            PlaceSuggestions.Suggestion(id: "wiki/1", name: "A Brasileira", kind: .food, category: "Kafe / restoran",
                                        coordinate: .init(latitude: 38.71072, longitude: -9.14241), openingHours: nil, duration: 45, score: 800),
            PlaceSuggestions.Suggestion(id: "wiki/2", name: "Santa Justa", kind: .sight, category: "Simge yapı",
                                        coordinate: .init(latitude: 38.7121, longitude: -9.1394), openingHours: nil, duration: 30, score: 3700),
        ]
        XCTAssertEqual(CommunityPlaces.merge(community: community, wikipedia: wiki).map(\.id), ["community/7", "wiki/2"])
        XCTAssertTrue(CommunityPlaces.decode(Data("oops".utf8)).isEmpty)
    }

    func testVerifiedStopsNeedSameDayPhotosNearby() {
        let value = trip()
        let near = PhotoClusterer.Moment(photoIDs: ["a"], start: TestCalendar.date(2026, 9, 10).addingTimeInterval(3600 * 11),
                                         end: TestCalendar.date(2026, 9, 10).addingTimeInterval(3600 * 12),
                                         center: .init(latitude: 38.7140, longitude: -9.1336), stopName: nil)
        var otherDay = near
        otherDay.start = TestCalendar.date(2026, 9, 11).addingTimeInterval(3600 * 11)
        otherDay.center = .init(latitude: 38.6975, longitude: -9.2032)
        XCTAssertEqual(CommunityPlaces.verifiedStops(in: value, moments: [near, otherDay], calendar: cal), [value.stops[0].id])
    }
}
