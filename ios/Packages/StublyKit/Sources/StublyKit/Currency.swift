import Foundation

/// Kur dönüşümü ve Frankfurter (Avrupa Merkez Bankası referans kurları) yanıtının çözümlenmesi.
public enum CurrencyConverter {
    /// Kuruş cinsinden tutarı verilen kurla çevirir (yarım yukarı yuvarlama).
    public static func convert(minorUnits: Int, rate: Decimal) -> Int {
        var value = Decimal(minorUnits) * rate
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// Avrupa Merkez Bankası'nın kur yayınladığı para birimleri (Frankfurter).
    public static let supported: Set<String> = [
        "AUD", "BGN", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD", "HUF", "IDR", "ILS", "INR", "ISK",
        "JPY", "KRW", "MXN", "MYR", "NOK", "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR",
    ]

    public static func isSupported(_ code: String) -> Bool { supported.contains(code.uppercased()) }

    public static func rateURL(from: String, to: String) -> URL? {
        URL(string: "https://api.frankfurter.app/latest?from=\(from.uppercased())&to=\(to.uppercased())")
    }

    public struct Quote: Hashable, Sendable {
        public var from: String
        public var to: String
        public var rate: Decimal
        /// Kurun yayınlandığı gün, "2026-09-30".
        public var date: String
    }

    private struct Response: Decodable {
        let base: String
        let date: String
        let rates: [String: Decimal]
    }

    public static func decodeQuote(_ data: Data, to: String) throws -> Quote {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let rate = response.rates[to.uppercased()] else { throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "\(to) kuru yanıtta yok")) }
        return Quote(from: response.base, to: to.uppercased(), rate: rate, date: response.date)
    }
}
