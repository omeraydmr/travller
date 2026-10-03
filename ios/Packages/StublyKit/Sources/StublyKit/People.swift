import Foundation

/// IBAN biçimlendirme ve doğrulama (ISO 13616, mod 97).
public enum IBAN {
    /// Boşluksuz, büyük harf.
    public static func normalized(_ text: String) -> String {
        text.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Dörtlü gruplar: "TR33 0006 1005 1978 6457 8413 26".
    public static func formatted(_ text: String) -> String {
        let raw = normalized(text)
        return stride(from: 0, to: raw.count, by: 4).map { start in
            let lower = raw.index(raw.startIndex, offsetBy: start)
            let upper = raw.index(lower, offsetBy: min(4, raw.count - start))
            return String(raw[lower..<upper])
        }.joined(separator: " ")
    }

    public static func isValid(_ text: String) -> Bool {
        let raw = normalized(text)
        guard raw.count >= 15, raw.count <= 34, raw.prefix(2).allSatisfy(\.isLetter),
              raw.dropFirst(2).prefix(2).allSatisfy(\.isNumber) else { return false }
        if raw.hasPrefix("TR") && raw.count != 26 { return false }
        let rearranged = raw.dropFirst(4) + raw.prefix(4)
        var remainder = 0
        for character in rearranged {
            let value: Int
            if let digit = character.wholeNumberValue {
                value = digit
            } else if let ascii = character.asciiValue, (65...90).contains(ascii) {
                value = Int(ascii) - 55
            } else {
                return false
            }
            remainder = value >= 10 ? (remainder * 100 + value) % 97 : (remainder * 10 + value) % 97
        }
        return remainder == 1
    }
}

/// Profil istatistikleri: gezilen ülkeler.
public enum TravelStats {
    /// BM üyesi + 2 gözlemci devlet.
    public static let worldCountryCount = 195

    /// Bitmiş (ya da başlamış) seyahatlerin ülkeleri ve elle eklenenler; ev ülkesi hariç.
    public static func visitedCountries(trips: [Trip], extra: Set<String>, home: String = "TR",
                                        now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let today = calendar.startOfDay(for: now)
        let fromTrips = trips
            .filter { $0.status == .planned && calendar.startOfDay(for: $0.startDate) <= today }
            .flatMap(\.countryCodes)
        return Array(Set(fromTrips).union(extra.map { $0.uppercased() }).subtracting([home.uppercased()])).sorted()
    }
}
