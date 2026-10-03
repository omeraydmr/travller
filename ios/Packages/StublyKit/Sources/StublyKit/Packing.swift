import Foundation

/// Kural tabanlı (yapay zekâ kullanmayan) valiz önerileri.
public enum PackingAdvisor {
    /// Türkiye'de kullanılan priz tipleri.
    public static let homePlugTypes: Set<String> = ["C", "F"]

    /// Ülke → priz tipleri. Listede olmayan ülkeler için adaptör önerilmez.
    public static let plugTypes: [String: Set<String>] = [
        "GB": ["G"], "MT": ["G"], "MY": ["G"], "SG": ["G"], "IE": ["G"], "CY": ["G"],
        "US": ["A", "B"], "CA": ["A", "B"], "JP": ["A", "B"], "MX": ["A", "B"],
        "AR": ["C", "I"], "BR": ["C", "N"], "CH": ["C", "J"], "IT": ["C", "F", "L"],
    ]

    /// Gidilen ülkede Türkiye'deki fişler kullanılamıyorsa gereken adaptör tipleri.
    public static func adapterTypes(for countryCode: String) -> [String]? {
        guard let types = plugTypes[countryCode.uppercased()], types.isDisjoint(with: homePlugTypes) else { return nil }
        return types.sorted()
    }

    /// Seyahat için önerilen maddeler; listede zaten bulunanlar (büyük/küçük harf duyarsız) çıkarılır.
    public static func suggestions(for trip: Trip, weather: WeatherSummary? = nil, now: Date = Date(),
                                   calendar: Calendar = .current) -> [String] {
        // Çok ülkeli seyahatte tüm ülkeler hesaba katılır.
        let countries = trip.countryCodes
        var items = [String(localized: "Pasaport"), String(localized: "Telefon şarj aleti"), String(localized: "Powerbank")]

        if countries.contains(where: { VisaRules.entry(for: $0)?.idCardAccepted == true }) {
            items.append(String(localized: "Kimlik kartı"))
        }
        let adapters = Set(countries.compactMap(adapterTypes(for:)).flatMap { $0 })
        if !adapters.isEmpty {
            items.append(String(localized: "Priz adaptörü · Tip \(adapters.sorted().joined(separator: "/"))"))
        }
        if countries.contains(where: VisaRules.schengenCountries.contains) {
            items.append(String(localized: "Seyahat sağlık sigortası poliçesi"))
        }
        if countries.contains(where: { VisaRules.requiresVisa(countryCode: $0, members: trip.members) }) {
            items.append(String(localized: "Vize ve başvuru belgelerinin kopyası"))
        }
        if trip.flights.isEmpty == false {
            items.append(String(localized: "Biniş kartları"))
        }
        if trip.nights(calendar: calendar) >= 5 {
            items.append(String(localized: "Küçük çamaşır torbası"))
        }
        if let weather {
            items += weatherItems(weather)
        } else {
            let month = calendar.component(.month, from: trip.startDate)
            if (5...9).contains(month) {
                items.append(String(localized: "Güneş kremi"))
            } else if month == 12 || month <= 2 {
                items.append(String(localized: "Bere ve eldiven"))
            }
        }

        let existing = Set(trip.packing.map { normalize($0.title) })
        return items.filter { !existing.contains(normalize($0)) }
    }

    /// Hava özetine göre giyim ve ekipman önerileri.
    public static func weatherItems(_ weather: WeatherSummary) -> [String] {
        var items: [String] = []
        if weather.maxTemperature >= 24 {
            items += [String(localized: "Güneş kremi"), String(localized: "Şapka"), String(localized: "Güneş gözlüğü")]
        }
        if weather.maxTemperature >= 28 {
            items.append(String(localized: "Matara"))
        }
        if weather.minTemperature <= 8 {
            items.append(String(localized: "Mont"))
        }
        if weather.minTemperature <= 3 {
            items.append(String(localized: "Bere ve eldiven"))
        }
        if weather.maxTemperature - weather.minTemperature >= 12 {
            items.append(String(localized: "İnce hırka (katmanlı giyim)"))
        }
        if weather.rainyDays > 0 {
            items.append(weather.rainyDays * 3 >= weather.dayCount ? String(localized: "Yağmurluk") : String(localized: "Katlanır şemsiye"))
            items.append(String(localized: "Su geçirmez ayakkabı"))
        }
        return items
    }

    static func normalize(_ text: String) -> String {
        text.lowercased(with: Locale(identifier: "tr_TR")).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
