import XCTest
@testable import StublyKit

final class CurrencyAndWeatherTests: XCTestCase {
    func testConvert() {
        XCTAssertEqual(CurrencyConverter.convert(minorUnits: 10_000, rate: Decimal(string: "0.0265")!), 265)
        XCTAssertEqual(CurrencyConverter.convert(minorUnits: 1_999, rate: Decimal(string: "0.5")!), 1_000)
        XCTAssertEqual(CurrencyConverter.convert(minorUnits: 0, rate: 3), 0)
        XCTAssertTrue(CurrencyConverter.isSupported("try"))
        XCTAssertFalse(CurrencyConverter.isSupported("AMD"))
    }

    func testDecodeQuote() throws {
        let json = #"{"amount":1.0,"base":"TRY","date":"2026-09-30","rates":{"EUR":0.0265}}"#
        let quote = try CurrencyConverter.decodeQuote(Data(json.utf8), to: "eur")
        XCTAssertEqual(quote.from, "TRY")
        XCTAssertEqual(quote.to, "EUR")
        XCTAssertEqual(quote.rate, Decimal(string: "0.0265"))
        XCTAssertEqual(quote.date, "2026-09-30")
        XCTAssertThrowsError(try CurrencyConverter.decodeQuote(Data(json.utf8), to: "USD"))
    }

    func testForecastSummary() throws {
        let json = #"{"daily":{"time":["2026-10-02","2026-10-03","2026-10-04"],"temperature_2m_max":[26.1,24.0,null],"temperature_2m_min":[15.2,13.9,14.0],"precipitation_probability_max":[10,70,55]}}"#
        let summary = try WeatherService.decodeSummary(Data(json.utf8), source: .forecast)
        XCTAssertEqual(summary.maxTemperature, 26.1)
        XCTAssertEqual(summary.minTemperature, 13.9)
        XCTAssertEqual(summary.rainyDays, 2)
        XCTAssertEqual(summary.dayCount, 2)
    }

    func testArchiveSummary() throws {
        let json = #"{"daily":{"temperature_2m_max":[3.0,1.5],"temperature_2m_min":[-2.0,-4.5],"precipitation_sum":[0.2,4.0]}}"#
        let summary = try WeatherService.decodeSummary(Data(json.utf8), source: .lastYear)
        XCTAssertEqual(summary.rainyDays, 1)
        XCTAssertEqual(summary.minTemperature, -4.5)
    }

    func testRequestChoosesForecastOrLastYear() {
        let cal = TestCalendar.calendar
        let now = TestCalendar.date(2026, 10, 1)
        let soon = WeatherService.requestURL(latitude: 38.7, longitude: -9.1, start: TestCalendar.date(2026, 10, 5),
                                             end: TestCalendar.date(2026, 10, 9), now: now, calendar: cal)
        XCTAssertEqual(soon?.source, .forecast)
        XCTAssertTrue(soon?.url.absoluteString.contains("api.open-meteo.com/v1/forecast") ?? false)
        XCTAssertTrue(soon?.url.absoluteString.contains("start_date=2026-10-05") ?? false)

        let later = WeatherService.requestURL(latitude: 64.1, longitude: -21.9, start: TestCalendar.date(2027, 1, 29),
                                              end: TestCalendar.date(2027, 2, 2), now: now, calendar: cal)
        XCTAssertEqual(later?.source, .lastYear)
        XCTAssertTrue(later?.url.absoluteString.contains("start_date=2026-01-29") ?? false)
        XCTAssertTrue(later?.url.absoluteString.contains("archive-api") ?? false)
    }

    func testWeatherPackingItems() {
        let hot = WeatherSummary(minTemperature: 18, maxTemperature: 31, rainyDays: 0, dayCount: 5, source: .forecast)
        XCTAssertTrue(PackingAdvisor.weatherItems(hot).contains("Matara"))
        XCTAssertTrue(PackingAdvisor.weatherItems(hot).contains("Güneş kremi"))
        XCTAssertFalse(PackingAdvisor.weatherItems(hot).contains("Mont"))

        let coldWet = WeatherSummary(minTemperature: -2, maxTemperature: 4, rainyDays: 3, dayCount: 5, source: .lastYear)
        let items = PackingAdvisor.weatherItems(coldWet)
        XCTAssertTrue(items.contains("Mont"))
        XCTAssertTrue(items.contains("Bere ve eldiven"))
        XCTAssertTrue(items.contains("Yağmurluk"))

        let trip = Trip(name: "T", destination: Destination(countryCode: "IS", city: "Reykjavík"),
                        startDate: TestCalendar.date(2027, 7, 1), endDate: TestCalendar.date(2027, 7, 4))
        let suggestions = PackingAdvisor.suggestions(for: trip, weather: coldWet, calendar: TestCalendar.calendar)
        XCTAssertFalse(suggestions.contains("Güneş kremi"), "hava verisi varsa ay tahmini kullanılmaz")
        XCTAssertTrue(suggestions.contains("Mont"))
    }
}
