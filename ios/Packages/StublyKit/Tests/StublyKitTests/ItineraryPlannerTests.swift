import XCTest
@testable import StublyKit

final class ItineraryPlannerTests: XCTestCase {
    let cal = TestCalendar.calendar
    // Lizbon: batı (Belém) ve doğu (Alfama) kümeleri ~7 km arayla.
    let west = Coordinate(latitude: 38.6916, longitude: -9.2160)
    let east = Coordinate(latitude: 38.7139, longitude: -9.1300)

    func near(_ c: Coordinate, _ step: Double) -> Coordinate {
        Coordinate(latitude: c.latitude + step * 0.001, longitude: c.longitude + step * 0.001)
    }

    func trip(days: Int = 2) -> Trip {
        Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"),
             startDate: TestCalendar.date(2026, 10, 20), endDate: TestCalendar.date(2026, 10, 19 + days))
    }

    func idea(_ name: String, _ c: Coordinate, duration: Int = 60, hours: String? = nil) -> Stop {
        Stop(day: TestCalendar.date(2026, 10, 20), order: 0, name: name, kind: .sight, durationMinutes: duration,
             coordinate: c, openingHours: hours)
    }

    func testNearbyPlacesGoToTheSameDay() {
        var value = trip()
        value.ideas = [idea("Belém 1", near(west, 0)), idea("Alfama 1", near(east, 0)),
                       idea("Belém 2", near(west, 1)), idea("Alfama 2", near(east, 1))]
        let plan = ItineraryPlanner.plan(value, calendar: cal)
        XCTAssertEqual(plan.addedCount, 4)
        XCTAssertTrue(plan.unscheduled.isEmpty)
        let names = plan.days.map { day in Set(day.added.compactMap { id in value.ideas?.first { $0.id == id }?.name }) }
        XCTAssertTrue(names.contains(["Belém 1", "Belém 2"]), "\(names)")
        XCTAssertTrue(names.contains(["Alfama 1", "Alfama 2"]), "\(names)")
    }

    func testClosedDayIsAvoided() {
        // 20 Eki 2026 Salı, 21 Eki Çarşamba. Müze salı kapalı.
        var value = trip()
        value.ideas = [idea("Müze", near(east, 0), hours: "We-Su 10:00-18:00; Tu off")]
        let plan = ItineraryPlanner.plan(value, calendar: cal)
        let day = plan.days.first { !$0.added.isEmpty }
        XCTAssertEqual(cal.component(.day, from: day!.day), 21)
        XCTAssertGreaterThanOrEqual(day!.starts.values.first!, 10 * 60, "Açılıştan önce başlamaz")
    }

    func testOverflowIsLeftUnscheduled() {
        var value = trip(days: 1)
        value.ideas = (0..<8).map { idea("Yer \($0)", near(east, Double($0)), duration: 120) }
        let plan = ItineraryPlanner.plan(value, calendar: cal)
        XCTAssertGreaterThan(plan.unscheduled.count, 0)
        XCTAssertLessThanOrEqual(plan.days[0].endMinutes, 19 * 60 + 30)
    }

    func testArrivalFlightShortensFirstDay() {
        var value = trip()
        var istanbul = Calendar(identifier: .gregorian)
        istanbul.timeZone = cal.timeZone
        let arrival = istanbul.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 15))!
        value.flights = [FlightSegment(flightNumber: "TK1", fromCode: "IST", fromCity: "İstanbul", toCode: "LIS",
                                       toCity: "Lizbon", departure: arrival.addingTimeInterval(-4 * 3600), arrival: arrival)]
        let window = ItineraryPlanner.window(for: TestCalendar.date(2026, 10, 20), trip: value,
                                             settings: .init(), calendar: cal)
        XCTAssertEqual(window.start, 17 * 60)
        XCTAssertEqual(ItineraryPlanner.window(for: TestCalendar.date(2026, 10, 21), trip: value, settings: .init(),
                                               calendar: cal).start, 9 * 60)
    }

    func testApplyMovesIdeasIntoDaysKeepingExisting() {
        var value = trip()
        let fixed = Stop(day: TestCalendar.date(2026, 10, 20), order: 0, name: "Rezervasyonlu yemek", kind: .food,
                         startMinutes: 13 * 60, durationMinutes: 90, coordinate: near(east, 2))
        value.stops = [fixed]
        value.ideas = [idea("Alfama", near(east, 0)), idea("Yeri yok", east)]
        value.ideas?[1].coordinate = nil
        let plan = ItineraryPlanner.plan(value, calendar: cal)
        ItineraryPlanner.apply(plan, to: &value, calendar: cal)
        XCTAssertEqual(value.ideaList.map(\.name), ["Yeri yok"])
        XCTAssertEqual(value.stops.count, 2)
        XCTAssertEqual(value.stops.first { $0.name == "Rezervasyonlu yemek" }?.startMinutes, 13 * 60)
        XCTAssertNotNil(value.stops.first { $0.name == "Alfama" }?.startMinutes)
    }
}

final class PlaceSuggestionsTests: XCTestCase {
    func page(_ id: Int, _ title: String, _ description: String, lat: Double, views: [Int?], tr: String? = nil) -> String {
        let pv = views.enumerated().map { "\"2026-09-0\($0.offset + 1)\":\($0.element.map(String.init) ?? "null")" }.joined(separator: ",")
        let links = tr.map { ",\"langlinks\":[{\"lang\":\"tr\",\"title\":\"\($0)\"}]" } ?? ""
        return "{\"pageid\":\(id),\"title\":\"\(title)\",\"description\":\"\(description)\",\"coordinates\":[{\"lat\":\(lat),\"lon\":-9.13}],\"pageviews\":{\(pv)}\(links)}"
    }

    func testDecodeRanksByViewsFiltersNonPlacesAndMerges() {
        let first = """
        {"query":{"pages":[
          \(page(1, "Lisbon", "Capital and largest city of Portugal", lat: 38.72, views: [9000]))
          ,\(page(2, "São Jorge Castle", "Historic castle in Lisbon, Portugal", lat: 38.7139, views: [3000, 2000], tr: "São Jorge Kalesi"))
          ,\(page(3, "Rossio railway station", "Railway station in Portugal", lat: 38.714, views: [700]))
          ,\(page(4, "Santa Justa Lift", "Municipal elevator in Lisbon, Portugal", lat: 38.7121, views: [3700]))
          ,\(page(5, "Miradouro de Santa Luzia", "Viewpoint in Lisbon", lat: 38.7116, views: [nil, 400]))
        ]}}
        """
        let second = """
        {"query":{"pages":[
          \(page(2, "São Jorge Castle", "Historic castle in Lisbon, Portugal", lat: 38.7139, views: [5000]))
          ,\(page(6, "Calouste Gulbenkian Museum", "Art museum in Lisbon, Portugal", lat: 38.737, views: [1200]))
        ]}}
        """
        let planned = Stop(day: Date(), order: 0, name: "Miradouro de Santa Luzia", kind: .sight)
        let result = PlaceSuggestions.decode([Data(first.utf8), Data(second.utf8)], excluding: [planned])
        XCTAssertEqual(result.map(\.name), ["São Jorge Kalesi", "Santa Justa Lift", "Calouste Gulbenkian Museum"])
        XCTAssertEqual(result[0].score, 5000, "Aynı sayfa ilk yanıttaki haliyle bir kez sayılır")
        XCTAssertEqual(result[0].category, "Kale / saray")
        XCTAssertEqual(result[2].duration, 120)
        XCTAssertEqual(PlaceSuggestions.decode([Data(first.utf8)], language: "en").first?.name, "São Jorge Castle")
    }

    func testClassification() {
        XCTAssertNil(PlaceSuggestions.classify("Portuguese book retailer"))
        XCTAssertNil(PlaceSuggestions.classify("1147 Second Crusade battle"))
        XCTAssertEqual(PlaceSuggestions.classify("Neighborhood of Lisbon")?.category, "Semt")
        XCTAssertEqual(PlaceSuggestions.classify("Café in Lisbon, in the old quarter Chiado")?.kind, .food)
        XCTAssertNil(PlaceSuggestions.classify("Portuguese architect"))
    }

    func testSearchURLsCoverFivePoints() {
        let urls = PlaceSuggestions.searchURLs(center: Coordinate(latitude: 38.72, longitude: -9.14))
        XCTAssertEqual(urls.count, 5)
        XCTAssertTrue(urls[0].absoluteString.contains("ggscoord=38.72000%7C-9.14000"))
    }
}

final class ItineraryClusteringTests: XCTestCase {
    func testSameNeighbourhoodIsNotSplitAcrossDays() {
        let cal = TestCalendar.calendar
        var trip = Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"),
                        startDate: TestCalendar.date(2026, 10, 20), endDate: TestCalendar.date(2026, 10, 23))
        func idea(_ name: String, _ lat: Double, _ lon: Double, _ minutes: Int) -> Stop {
            Stop(day: trip.startDate, order: 0, name: name, kind: .sight, durationMinutes: minutes,
                 coordinate: Coordinate(latitude: lat, longitude: lon))
        }
        trip.ideas = [
            idea("Padrão", 38.6936, -9.2057, 20), idea("Ajuda", 38.7077, -9.1979, 90),
            idea("Castelo", 38.7139, -9.1335, 90), idea("Santa Justa", 38.7121, -9.1394, 30),
            idea("Carmo", 38.7120, -9.1407, 40), idea("Gulbenkian", 38.7370, -9.1540, 120),
        ]
        let plan = ItineraryPlanner.plan(trip, calendar: cal)
        func day(of name: String) -> Date? {
            let id = trip.ideas!.first { $0.name == name }!.id
            return plan.days.first { $0.added.contains(id) }?.day
        }
        XCTAssertEqual(day(of: "Padrão"), day(of: "Ajuda"))
        XCTAssertEqual(day(of: "Castelo"), day(of: "Santa Justa"))
        XCTAssertEqual(day(of: "Castelo"), day(of: "Carmo"))
        XCTAssertNotEqual(day(of: "Padrão"), day(of: "Castelo"))
        XCTAssertTrue(plan.unscheduled.isEmpty)
    }
}
