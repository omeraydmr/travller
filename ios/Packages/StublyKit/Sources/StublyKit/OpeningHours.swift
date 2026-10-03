import Foundation

/// OpenStreetMap `opening_hours` söz diziminin yaygın alt kümesi:
/// "24/7", "Mo-Fr 09:00-18:00; Sa 10:00-14:00; Su off", "Tu-Su 10:00-13:00,14:00-18:00".
/// Tatil günleri (PH), aylar ve hafta numaraları gibi kurallar yok sayılır.
public struct OpeningHours: Hashable, Sendable {
    /// Dakika aralıkları, gün başından itibaren [başlangıç, bitiş).
    public struct Interval: Hashable, Sendable {
        public var start: Int
        public var end: Int
    }

    /// 0 = Pazartesi … 6 = Pazar.
    public private(set) var days: [[Interval]] = Array(repeating: [], count: 7)

    static let dayCodes = ["mo", "tu", "we", "th", "fr", "sa", "su"]
    public static var turkishDayNames: [String] {
        [String(localized: "Pzt"), String(localized: "Sal"), String(localized: "Çar"), String(localized: "Per"),
         String(localized: "Cum"), String(localized: "Cmt"), String(localized: "Paz")]
    }

    public init?(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text == "24/7" {
            days = Array(repeating: [Interval(start: 0, end: 24 * 60)], count: 7)
            return
        }
        var parsedAny = false
        for rule in text.split(separator: ";") {
            if let parsed = Self.parseRule(String(rule)) {
                for day in parsed.0 { days[day] = parsed.1 }
                parsedAny = true
            }
        }
        guard parsedAny else { return nil }
    }

    /// Önbellekli çözümleme: aynı metin her çizimde yeniden ayrıştırılmaz.
    public static func cached(_ raw: String) -> OpeningHours? {
        ParseCache.shared.value(for: raw)
    }

    private final class ParseCache: @unchecked Sendable {
        static let shared = ParseCache()
        private let lock = NSLock()
        private var storage: [String: OpeningHours?] = [:]

        func value(for raw: String) -> OpeningHours? {
            lock.lock()
            defer { lock.unlock() }
            if let hit = storage[raw] { return hit }
            let parsed = OpeningHours(raw)
            if storage.count > 512 { storage.removeAll() }
            storage[raw] = .some(parsed)
            return parsed
        }
    }

    /// Bir kuralı (günler, aralıklar) olarak çözer; desteklenmeyen kurallar nil döner.
    static func parseRule(_ rule: String) -> ([Int], [Interval])? {
        let parts = rule.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).map(String.init)
        guard let first = parts.first else { return nil }

        var dayPart: String?
        var timePart: String
        if parts.count == 2, first.first?.isLetter == true {
            dayPart = first
            timePart = parts[1]
        } else if first.first?.isLetter == true && parts.count == 1 {
            // "Su off" biçimi tek parça olmaz; "off" tek başına tüm günler kapalı demek.
            if ["off", "closed"].contains(first.lowercased()) { return (Array(0..<7), []) }
            return nil
        } else {
            timePart = rule.trimmingCharacters(in: .whitespaces)
        }

        let ruleDays: [Int]
        if let dayPart {
            guard let parsed = parseDays(dayPart) else { return nil }
            ruleDays = parsed
        } else {
            ruleDays = Array(0..<7)
        }

        timePart = timePart.trimmingCharacters(in: .whitespaces).lowercased()
        if timePart == "off" || timePart == "closed" { return (ruleDays, []) }

        var intervals: [Interval] = []
        for span in timePart.split(separator: ",") {
            let bounds = span.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
            guard bounds.count == 2, let start = minutes(bounds[0]), var end = minutes(bounds[1]) else { return nil }
            if end <= start { end = 24 * 60 } // gece yarısını geçen saatler o gün için 24:00'te kesilir
            intervals.append(Interval(start: start, end: end))
        }
        guard !intervals.isEmpty else { return nil }
        return (ruleDays, intervals.sorted { $0.start < $1.start })
    }

    static func parseDays(_ text: String) -> [Int]? {
        var result: [Int] = []
        for item in text.lowercased().split(separator: ",") {
            let ends = item.split(separator: "-").map(String.init)
            guard let from = dayCodes.firstIndex(of: ends[0]) else { return nil }
            if ends.count == 1 {
                result.append(from)
            } else if ends.count == 2, let to = dayCodes.firstIndex(of: ends[1]) {
                var day = from
                result.append(day)
                while day != to {
                    day = (day + 1) % 7
                    result.append(day)
                }
            } else {
                return nil
            }
        }
        return result.isEmpty ? nil : result
    }

    static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...24).contains(h), (0..<60).contains(m) else {
            return nil
        }
        return h * 60 + m
    }

    /// Takvim haftanın günü (1 = Pazar … 7 = Cumartesi) → 0 = Pazartesi.
    public static func dayIndex(calendarWeekday: Int) -> Int {
        (calendarWeekday + 5) % 7
    }

    public func intervals(onDay day: Int) -> [Interval] { days[day] }

    // MARK: Assessment

    public enum Status: Hashable, Sendable {
        case open(until: Int)
        case closedAllDay
        case opensLater(at: Int)
        case closesDuringVisit(at: Int)
        case alreadyClosed(at: Int)
        /// Saat verilmemiş durak; o günkü açık aralıklar.
        case openToday([Interval])

        public var isWarning: Bool {
            switch self {
            case .open, .openToday: false
            default: true
            }
        }
    }

    /// Ziyaret saati ve süresine göre durum.
    public func status(day: Int, startMinutes: Int?, duration: Int) -> Status {
        let today = days[day]
        guard !today.isEmpty else { return .closedAllDay }
        guard let start = startMinutes else { return .openToday(today) }
        if let current = today.first(where: { $0.start <= start && start < $0.end }) {
            return start + duration > current.end ? .closesDuringVisit(at: current.end) : .open(until: current.end)
        }
        if let next = today.first(where: { $0.start > start }) {
            return .opensLater(at: next.start)
        }
        return .alreadyClosed(at: today.last?.end ?? 0)
    }

    // MARK: Turkish summary

    /// "Pzt–Cum 09:00–18:00 · Cmt 10:00–14:00 · Paz kapalı"
    public var turkishSummary: String {
        if days.allSatisfy({ $0 == [Interval(start: 0, end: 24 * 60)] }) { return String(localized: "Her gün 24 saat") }
        var groups: [(from: Int, to: Int, intervals: [Interval])] = []
        for day in 0..<7 {
            if let last = groups.last, last.intervals == days[day], last.to == day - 1 {
                groups[groups.count - 1].to = day
            } else {
                groups.append((day, day, days[day]))
            }
        }
        return groups.map { group in
            let names = group.from == group.to
                ? Self.turkishDayNames[group.from]
                : "\(Self.turkishDayNames[group.from])–\(Self.turkishDayNames[group.to])"
            let hours = group.intervals.isEmpty
                ? String(localized: "kapalı")
                : group.intervals.map { "\(Self.clock($0.start))–\(Self.clock($0.end))" }.joined(separator: ", ")
            return "\(names) \(hours)"
        }.joined(separator: " · ")
    }

    public static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

/// OpenStreetMap (Overpass) yanıtından doğru yerin açılış saatini seçer.
public enum OpeningHoursLookup {
    public struct Candidate: Hashable, Sendable {
        public var name: String
        public var openingHours: String
    }

    public static func query(latitude: Double, longitude: Double, radius: Int = 80) -> String {
        "[out:json][timeout:10];nwr(around:\(radius),\(latitude),\(longitude))[\"opening_hours\"][\"name\"];out tags 30;"
    }

    private struct Response: Decodable {
        struct Element: Decodable {
            let tags: [String: String]?
        }

        let elements: [Element]
    }

    public static func decodeCandidates(_ data: Data) throws -> [Candidate] {
        try JSONDecoder().decode(Response.self, from: data).elements.compactMap { element in
            guard let tags = element.tags, let hours = tags["opening_hours"] else { return nil }
            let name = tags["name"] ?? tags["name:en"] ?? ""
            return Candidate(name: name, openingHours: hours)
        }
    }

    /// Ada en çok benzeyen aday; benzerlik zayıfsa nil (yanlış saat göstermemek için).
    public static func bestMatch(for name: String, in candidates: [Candidate]) -> Candidate? {
        let target = tokens(name)
        guard !target.isEmpty else { return nil }
        let scored = candidates.map { candidate -> (Candidate, Double) in
            let other = tokens(candidate.name)
            guard !other.isEmpty else { return (candidate, 0) }
            let common = Double(target.intersection(other).count)
            return (candidate, common / Double(min(target.count, other.count)))
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 0.5 else { return nil }
        return best.0
    }

    static func tokens(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let stop: Set<String> = ["de", "da", "do", "the", "of", "la", "le", "el", "and", "e"]
        return Set(words.filter { $0.count > 1 && !stop.contains($0) })
    }
}
