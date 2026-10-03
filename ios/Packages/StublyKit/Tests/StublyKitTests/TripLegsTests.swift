import XCTest
@testable import StublyKit

final class TripLegsTests: XCTestCase {
    let cal = TestCalendar.calendar

    func portugal() -> Trip {
        var trip = Trip(name: "Portekiz", destination: Destination(countryCode: "PT", city: "Lizbon"),
                        startDate: TestCalendar.date(2026, 9, 30), endDate: TestCalendar.date(2026, 10, 6))
        trip.setLegs([
            TripLeg(destination: Destination(countryCode: "PT", city: "Porto"), arrival: TestCalendar.date(2026, 10, 3)),
            TripLeg(destination: Destination(countryCode: "PT", city: "Lizbon"), arrival: TestCalendar.date(2026, 9, 28)),
        ], calendar: cal)
        return trip
    }

    func testSingleCityTripActsAsOneLeg() {
        let trip = Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"),
                        startDate: TestCalendar.date(2026, 9, 30), endDate: TestCalendar.date(2026, 10, 3))
        XCTAssertFalse(trip.isMultiCity)
        XCTAssertEqual(trip.cityLegs.map(\.destination.city), ["Lizbon"])
        XCTAssertEqual(trip.destination(on: TestCalendar.date(2026, 10, 2), calendar: cal).city, "Lizbon")
        XCTAssertFalse(trip.isTransition(TestCalendar.date(2026, 10, 1), calendar: cal))
        XCTAssertEqual(trip.cityTitle, "Lizbon")
    }

    func testLegsAreSortedAndFirstStartsWithTrip() {
        let trip = portugal()
        XCTAssertTrue(trip.isMultiCity)
        XCTAssertEqual(trip.cityLegs.map(\.destination.city), ["Lizbon", "Porto"])
        XCTAssertEqual(trip.cityLegs[0].arrival, cal.startOfDay(for: TestCalendar.date(2026, 9, 30)), "İlk şehir seyahat başında başlar")
        XCTAssertEqual(trip.destination.city, "Lizbon", "destination ilk şehirdir")
        XCTAssertEqual(trip.cityTitle, "Lizbon → Porto")
        XCTAssertEqual(trip.countryCodes, ["PT"])
    }

    func testTransitionDayBelongsToArrivalCity() {
        let trip = portugal()
        XCTAssertEqual(trip.destination(on: TestCalendar.date(2026, 10, 2), calendar: cal).city, "Lizbon")
        XCTAssertEqual(trip.destination(on: TestCalendar.date(2026, 10, 3), calendar: cal).city, "Porto")
        XCTAssertTrue(trip.isTransition(TestCalendar.date(2026, 10, 3), calendar: cal))
        XCTAssertFalse(trip.isTransition(TestCalendar.date(2026, 9, 30), calendar: cal))
        let lisbon = trip.cityLegs[0], porto = trip.cityLegs[1]
        XCTAssertEqual(trip.days(in: lisbon, calendar: cal).count, 3)
        XCTAssertEqual(trip.days(in: porto, calendar: cal).count, 4)
        XCTAssertTrue(cal.isDate(trip.dateRange(of: porto, calendar: cal).end, inSameDayAs: TestCalendar.date(2026, 10, 6)))
    }

    func testRemovingAllButOneCityClearsLegs() {
        var trip = portugal()
        trip.setLegs([trip.cityLegs[1]], calendar: cal)
        XCTAssertNil(trip.legs)
        XCTAssertEqual(trip.destination.city, "Porto")
    }

    func testCountriesInOrder() {
        var trip = portugal()
        trip.setLegs(trip.cityLegs + [TripLeg(destination: Destination(countryCode: "es", city: "Madrid"),
                                              arrival: TestCalendar.date(2026, 10, 5))], calendar: cal)
        XCTAssertEqual(trip.countryCodes, ["PT", "ES"])
    }

    func testAutoPlanKeepsIdeasInTheirCity() throws {
        var trip = Trip(name: "Portekiz", destination: Destination(countryCode: "PT", city: "Lizbon",
                                                                   coordinate: .init(latitude: 38.72, longitude: -9.14)),
                        startDate: TestCalendar.date(2026, 9, 30), endDate: TestCalendar.date(2026, 10, 5))
        trip.setLegs([
            TripLeg(destination: trip.destination, arrival: trip.startDate),
            TripLeg(destination: Destination(countryCode: "PT", city: "Porto", coordinate: .init(latitude: 41.15, longitude: -8.61)),
                    arrival: TestCalendar.date(2026, 10, 3)),
        ], calendar: cal)
        func idea(_ name: String, _ lat: Double, _ lon: Double) -> Stop {
            Stop(day: trip.startDate, order: 0, name: name, kind: .sight, durationMinutes: 90, coordinate: .init(latitude: lat, longitude: lon))
        }
        let lisbon = [idea("Belém", 38.6916, -9.2160), idea("Alfama", 38.7139, -9.1300)]
        let porto = [idea("Ribeira", 41.1407, -8.6129), idea("Livraria Lello", 41.1469, -8.6149)]
        trip.ideas = lisbon + porto
        let plan = ItineraryPlanner.plan(trip, calendar: cal)
        XCTAssertTrue(plan.unscheduled.isEmpty)
        for day in plan.days {
            let city = trip.destination(on: day.day, calendar: cal).city
            for id in day.order {
                let name = trip.ideaList.first { $0.id == id }?.name
                if lisbon.contains(where: { $0.id == id }) { XCTAssertEqual(city, "Lizbon", name ?? "") }
                if porto.contains(where: { $0.id == id }) { XCTAssertEqual(city, "Porto", name ?? "") }
            }
        }
    }

    func testPackingAndChecklistCoverEveryCountry() {
        var trip = Trip(name: "İber", destination: Destination(countryCode: "GB", city: "Londra"),
                        startDate: TestCalendar.date(2026, 9, 30), endDate: TestCalendar.date(2026, 10, 6))
        trip.setLegs([TripLeg(destination: trip.destination, arrival: trip.startDate),
                      TripLeg(destination: Destination(countryCode: "PT", city: "Lizbon"), arrival: TestCalendar.date(2026, 10, 3))],
                     calendar: cal)
        let packing = PackingAdvisor.suggestions(for: trip, calendar: cal)
        XCTAssertTrue(packing.contains { $0.contains("G") && $0.contains("Tip") }, "İngiltere prizi")
        XCTAssertTrue(packing.contains("Seyahat sağlık sigortası poliçesi"), "Portekiz Schengen")
    }

    func testCountryAndSchengenRanges() throws {
        // İstanbul → Lizbon → Londra: Schengen yalnızca Lizbon günleri.
        var trip = Trip(name: "Tur", destination: Destination(countryCode: "TR", city: "İstanbul"),
                        startDate: TestCalendar.date(2026, 9, 30), endDate: TestCalendar.date(2026, 10, 8))
        trip.setLegs(trip.cityLegs + [
            TripLeg(destination: Destination(countryCode: "PT", city: "Lizbon"), arrival: TestCalendar.date(2026, 10, 2)),
            TripLeg(destination: Destination(countryCode: "GB", city: "Londra"), arrival: TestCalendar.date(2026, 10, 5)),
        ], calendar: cal)
        let portugal = try XCTUnwrap(trip.dateRange(ofCountry: "pt", calendar: cal))
        XCTAssertTrue(cal.isDate(portugal.start, inSameDayAs: TestCalendar.date(2026, 10, 2)))
        XCTAssertTrue(cal.isDate(portugal.end, inSameDayAs: TestCalendar.date(2026, 10, 4)))
        let schengen = try XCTUnwrap(trip.schengenRange(calendar: cal))
        XCTAssertEqual(schengen.start, portugal.start)
        XCTAssertEqual(schengen.end, portugal.end)
        XCTAssertNil(trip.dateRange(ofCountry: "FR", calendar: cal))
    }

    func testCombinedWeather() {
        let cold = WeatherSummary(minTemperature: 4, maxTemperature: 12, rainyDays: 2, dayCount: 3, source: .forecast)
        let warm = WeatherSummary(minTemperature: 15, maxTemperature: 27, rainyDays: 0, dayCount: 4, source: .lastYear)
        let both = WeatherSummary.combined([cold, warm])
        XCTAssertEqual(both, WeatherSummary(minTemperature: 4, maxTemperature: 27, rainyDays: 2, dayCount: 7, source: .lastYear))
        XCTAssertNil(WeatherSummary.combined([]))
    }
}
