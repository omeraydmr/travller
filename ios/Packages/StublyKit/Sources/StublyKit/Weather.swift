import Foundation

/// Seyahat tarihleri için kısa hava özeti (Open-Meteo).
public struct WeatherSummary: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// Seyahate 16 günden az kaldıysa tahmin.
        case forecast
        /// Daha uzaksa geçen yılın aynı tarihleri.
        case lastYear
    }

    public var minTemperature: Double
    public var maxTemperature: Double
    public var rainyDays: Int
    public var dayCount: Int
    public var source: Source

    public init(minTemperature: Double, maxTemperature: Double, rainyDays: Int, dayCount: Int, source: Source) {
        self.minTemperature = minTemperature
        self.maxTemperature = maxTemperature
        self.rainyDays = rainyDays
        self.dayCount = dayCount
        self.source = source
    }
}

public enum WeatherService {
    /// Open-Meteo tahmin ufku.
    public static let forecastHorizonDays = 15

    /// Seyahat tarihine göre tahmin ya da geçen yılın arşiv isteği.
    public static func requestURL(latitude: Double, longitude: Double, start: Date, end: Date, now: Date = Date(),
                                  calendar: Calendar = .current) -> (url: URL, source: WeatherSummary.Source)? {
        let today = calendar.startOfDay(for: now)
        let daysUntilEnd = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: end)).day ?? 0
        let useForecast = daysUntilEnd <= forecastHorizonDays && calendar.startOfDay(for: end) >= today

        var queryStart = calendar.startOfDay(for: start)
        var queryEnd = calendar.startOfDay(for: end)
        if useForecast {
            queryStart = max(queryStart, today)
        } else {
            guard let s = calendar.date(byAdding: .year, value: -1, to: queryStart),
                  let e = calendar.date(byAdding: .year, value: -1, to: queryEnd) else { return nil }
            queryStart = s
            queryEnd = e
            // Arşiv yalnızca geçmiş günleri içerir.
            if queryEnd >= today, let y = calendar.date(byAdding: .day, value: -1, to: today) { queryEnd = y }
            if queryStart > queryEnd { return nil }
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let host = useForecast ? "https://api.open-meteo.com/v1/forecast" : "https://archive-api.open-meteo.com/v1/archive"
        let rain = useForecast ? "precipitation_probability_max" : "precipitation_sum"
        let query = "latitude=\(latitude)&longitude=\(longitude)&daily=temperature_2m_max,temperature_2m_min,\(rain)"
            + "&start_date=\(formatter.string(from: queryStart))&end_date=\(formatter.string(from: queryEnd))&timezone=auto"
        guard let url = URL(string: "\(host)?\(query)") else { return nil }
        return (url, useForecast ? .forecast : .lastYear)
    }

    private struct Response: Decodable {
        struct Daily: Decodable {
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_probability_max: [Double?]?
            let precipitation_sum: [Double?]?
        }

        let daily: Daily
    }

    /// Günlük verileri özetler. Yağmurlu gün: tahminde olasılık ≥ %50, arşivde ≥ 1 mm.
    public static func decodeSummary(_ data: Data, source: WeatherSummary.Source) throws -> WeatherSummary {
        let daily = try JSONDecoder().decode(Response.self, from: data).daily
        let highs = daily.temperature_2m_max.compactMap { $0 }
        let lows = daily.temperature_2m_min.compactMap { $0 }
        guard let highest = highs.max(), let lowest = lows.min() else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Sıcaklık verisi yok"))
        }
        let rainy: Int
        switch source {
        case .forecast: rainy = (daily.precipitation_probability_max ?? []).compactMap { $0 }.filter { $0 >= 50 }.count
        case .lastYear: rainy = (daily.precipitation_sum ?? []).compactMap { $0 }.filter { $0 >= 1 }.count
        }
        return WeatherSummary(minTemperature: lowest, maxTemperature: highest, rainyDays: rainy, dayCount: highs.count, source: source)
    }
}

public extension WeatherSummary {
    /// Çok şehirli seyahatte şehirlerin özetlerini tek özete toplar (en düşük/en yüksek sıcaklık, toplam yağışlı gün).
    static func combined(_ summaries: [WeatherSummary]) -> WeatherSummary? {
        guard let first = summaries.first else { return nil }
        return WeatherSummary(minTemperature: summaries.map(\.minTemperature).min() ?? first.minTemperature,
                              maxTemperature: summaries.map(\.maxTemperature).max() ?? first.maxTemperature,
                              rainyDays: summaries.map(\.rainyDays).reduce(0, +),
                              dayCount: summaries.map(\.dayCount).reduce(0, +),
                              source: summaries.contains { $0.source == .lastYear } ? .lastYear : .forecast)
    }
}
