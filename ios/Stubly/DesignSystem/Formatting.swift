import Foundation
import StublyKit

enum AppFormat {
    /// Arayüz dili Türkçeyse Türkçe biçim; değilse İngilizce (bölge cihazdan).
    static let locale: Locale = {
        if Bundle.main.preferredLocalizations.first == "tr" { return Locale(identifier: "tr_TR") }
        return Locale(identifier: "en_" + (Locale.current.region?.identifier ?? "US"))
    }()

    /// Kuruş/cent → "€2.900" ya da "€12,50".
    static func money(_ minor: Int, _ currency: String) -> String {
        let value = Decimal(minor) / 100
        let isWhole = minor % 100 == 0
        return value.formatted(
            .currency(code: currency)
                .locale(locale)
                .precision(.fractionLength(isWhole ? 0 : 2))
        )
    }

    /// Para birimi sembolü: "EUR" → "€", "TRY" → "₺".
    /// Sembol önbellekte tutulur; para birimi menüsünde her satır için biçimlendirici kurulmaz.
    static func currencySymbol(_ code: String) -> String {
        SymbolCache.shared.symbol(for: code) {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = locale
            formatter.currencyCode = code
            return formatter.currencySymbol ?? code
        }
    }

    private final class SymbolCache: @unchecked Sendable {
        static let shared = SymbolCache()
        private let lock = NSLock()
        private var symbols: [String: String] = [:]

        func symbol(for code: String, make: () -> String) -> String {
            lock.lock()
            defer { lock.unlock() }
            if let cached = symbols[code] { return cached }
            let symbol = make()
            symbols[code] = symbol
            return symbol
        }
    }

    /// Kullanıcının yazdığı tutarı ("1.600", "12,50") kuruşa çevirir.
    static func parseMinor(_ text: String) -> Int? {
        MoneyParser.minorUnits(from: text)
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    /// "1 Haz 2027".
    static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    /// "12 – 17 Eki" veya "28 Eki – 2 Kas".
    static func dateRange(_ start: Date, _ end: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            // Ay adının yeri dile göre değişir: "12 – 17 Eki" / "Oct 12 – 17".
            let interval = start..<max(end, start.addingTimeInterval(1))
            return interval.formatted(.interval.day().month(.abbreviated).locale(locale))
        }
        return "\(shortDate(start)) – \(shortDate(end))"
    }

    /// Gün seçici etiketi: "Sal 14".
    static func dayPill(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().locale(locale))
    }

    static func time(_ date: Date, timeZone identifier: String? = nil) -> String {
        var style = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale)
        if let identifier, let zone = TimeZone(identifier: identifier) {
            style.timeZone = zone
        }
        return date.formatted(style)
    }

    static func time(minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    static func duration(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        switch (h, m) {
        case (0, _): return String(localized: "\(m) dk")
        case (_, 0): return String(localized: "\(h) sa")
        default: return String(localized: "\(h) sa \(m) dk")
        }
    }

    static func distance(meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters.rounded())) m" }
        return (meters / 1000).formatted(.number.precision(.fractionLength(1)).locale(locale)) + " km"
    }

    static func countdown(_ countdown: Countdown) -> String {
        switch countdown {
        case .today: String(localized: "Bugün")
        case let .days(n): n == 1 ? String(localized: "Yarın") : String(localized: "\(n) gün")
        case let .months(n): String(localized: "\(n) ay")
        case let .ongoing(day, total): String(localized: "Gün \(day)/\(total)")
        case .past: String(localized: "Bitti")
        }
    }
}

enum Countries {
    static func flag(_ code: String) -> String {
        let base: UInt32 = 0x1F1E6 - 65
        return code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(base + $0.value) }
            .map(String.init)
            .joined()
    }

    static func name(_ code: String) -> String {
        if code.uppercased() == "XK" { return String(localized: "Kosova") }
        return AppFormat.locale.localizedString(forRegionCode: code) ?? code
    }

    /// Ülke seçici için alfabetik (Türkçe) liste.
    static let all: [String] = {
        var codes = Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
        if !codes.contains("XK") { codes.append("XK") }
        return codes.sorted { name($0).compare(name($1), locale: AppFormat.locale) == .orderedAscending }
    }()
}
