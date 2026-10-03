import Foundation

/// Kullanıcının elle eklediği, uygulamada seyahati olmayan geçmiş Schengen ziyareti.
public struct ManualStay: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var note: String

    public init(id: UUID = UUID(), start: Date, end: Date, note: String = "") {
        self.id = id
        self.start = min(start, end)
        self.end = max(start, end)
        self.note = note
    }
}

/// Schengen kısa süreli kalış kuralı: herhangi bir günden geriye bakan 180 günlük pencerede
/// en fazla 90 gün. Giriş ve çıkış günleri kalış günü sayılır.
public enum Schengen {
    public static let limit = 90
    public static let window = 180

    /// Hesaba katılan bir kalış (seyahat ya da elle eklenen ziyaret).
    public struct Stay: Hashable, Identifiable, Sendable {
        public var id: UUID
        public var start: Date
        public var end: Date
        public var label: String

        public init(id: UUID = UUID(), start: Date, end: Date, label: String) {
            self.id = id
            self.start = min(start, end)
            self.end = max(start, end)
            self.label = label
        }

        public func days(calendar: Calendar = .current) -> Int {
            (calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0) + 1
        }
    }

    public struct Evaluation: Hashable, Sendable {
        /// Seyahatin son günü itibarıyla 180 günde kullanılmış gün (seyahat dahil).
        public var usedOnExit: Int
        /// Seyahat boyunca ulaşılan en yüksek kullanım.
        public var peakUsed: Int
        /// Sınırın ilk aşıldığı gün; aşılmıyorsa nil.
        public var firstOverstayDay: Date?
        /// Sınırı aşan gün sayısı (seyahatin kaç günü kural dışı).
        public var overstayDays: Int
        /// Seyahatin ilk gününden itibaren kesintisiz kalınabilecek son gün; giriş günü bile aşıyorsa nil.
        public var latestExit: Date?

        public var remainingAfterExit: Int { max(0, Schengen.limit - usedOnExit) }
        public var isWithinLimit: Bool { firstOverstayDay == nil }
    }

    /// Kalışların kapsadığı günler (gün başlangıcı); çakışan kalışlar bir kez sayılır.
    public static func days(of stays: [Stay], calendar: Calendar = .current) -> Set<Date> {
        var result: Set<Date> = []
        for stay in stays {
            var day = calendar.startOfDay(for: stay.start)
            let last = calendar.startOfDay(for: stay.end)
            while day <= last {
                result.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return result
    }

    /// `day` dahil geriye 180 gün içinde Schengen'de geçen gün sayısı.
    public static func used(on day: Date, days: Set<Date>, calendar: Calendar = .current) -> Int {
        let end = calendar.startOfDay(for: day)
        guard let start = calendar.date(byAdding: .day, value: -(window - 1), to: end) else { return 0 }
        return days.reduce(0) { $0 + ($1 >= start && $1 <= end ? 1 : 0) }
    }

    /// Planlanan kalışı diğer kalışlarla birlikte değerlendirir.
    public static func evaluate(_ stay: Stay, others: [Stay], calendar: Calendar = .current) -> Evaluation {
        let all = days(of: others + [stay], calendar: calendar)
        let first = calendar.startOfDay(for: stay.start)
        let last = calendar.startOfDay(for: stay.end)

        var peak = 0
        var firstOverstay: Date?
        var overstayDays = 0
        var day = first
        while day <= last {
            let count = used(on: day, days: all, calendar: calendar)
            peak = max(peak, count)
            if count > limit {
                overstayDays += 1
                if firstOverstay == nil { firstOverstay = day }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return Evaluation(usedOnExit: used(on: last, days: all, calendar: calendar), peakUsed: peak,
                          firstOverstayDay: firstOverstay, overstayDays: overstayDays,
                          latestExit: latestExit(entering: first, others: others, calendar: calendar))
    }

    /// `entry` gününde girip kesintisiz kalındığında kuralı bozmadan çıkılabilecek son gün.
    public static func latestExit(entering entry: Date, others: [Stay], calendar: Calendar = .current) -> Date? {
        var all = days(of: others, calendar: calendar)
        var day = calendar.startOfDay(for: entry)
        var lastValid: Date?
        for _ in 0..<limit {
            all.insert(day)
            guard used(on: day, days: all, calendar: calendar) <= limit else { break }
            lastValid = day
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return lastValid
    }

    /// `length` günlük bir kalış için `from` gününden itibaren en erken giriş tarihi.
    public static func earliestEntry(forDays length: Int, from: Date, others: [Stay],
                                     calendar: Calendar = .current, searchDays: Int = 400) -> Date? {
        guard length > 0, length <= limit else { return nil }
        var candidate = calendar.startOfDay(for: from)
        for _ in 0..<searchDays {
            guard let end = calendar.date(byAdding: .day, value: length - 1, to: candidate) else { return nil }
            if evaluate(Stay(start: candidate, end: end, label: ""), others: others, calendar: calendar).isWithinLimit {
                return candidate
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
            candidate = next
        }
        return nil
    }

    /// `end` gününde biten 180 günlük pencereye düşen kalışlar (pencereyle kırpılmış).
    public static func stays(_ stays: [Stay], inWindowEnding end: Date, calendar: Calendar = .current) -> [Stay] {
        let last = calendar.startOfDay(for: end)
        guard let first = calendar.date(byAdding: .day, value: -(window - 1), to: last) else { return [] }
        return stays
            .filter { calendar.startOfDay(for: $0.end) >= first && calendar.startOfDay(for: $0.start) <= last }
            .map { Stay(id: $0.id, start: max(calendar.startOfDay(for: $0.start), first),
                        end: min(calendar.startOfDay(for: $0.end), last), label: $0.label) }
            .sorted { $0.start < $1.start }
    }

    public static func isSchengen(_ countryCode: String) -> Bool {
        VisaRules.schengenCountries.contains(countryCode.uppercased())
    }
}
