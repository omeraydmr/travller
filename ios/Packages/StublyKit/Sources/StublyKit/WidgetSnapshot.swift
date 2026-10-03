import Foundation

/// Ana ekran widget'ının okuduğu küçük özet. Uygulama seyahatler değişince yazar, widget yalnızca okur.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public struct Item: Codable, Hashable, Identifiable, Sendable {
        public var id: UUID
        public var name: String
        public var city: String
        public var flag: String
        /// Seyahat rengi (0xRRGGBB).
        public var tint: UInt32
        public var start: Date
        public var end: Date
        /// "IST → LIS · 09:45" gibi; uçuş yoksa nil.
        public var flightLabel: String?
        public var stops: [StopItem]

        public init(id: UUID, name: String, city: String, flag: String, tint: UInt32, start: Date, end: Date,
                    flightLabel: String? = nil, stops: [StopItem] = []) {
            self.id = id
            self.name = name
            self.city = city
            self.flag = flag
            self.tint = tint
            self.start = start
            self.end = end
            self.flightLabel = flightLabel
            self.stops = stops
        }
    }

    public struct StopItem: Codable, Hashable, Sendable {
        public var name: String
        public var day: Date
        public var startMinutes: Int?
        public var durationMinutes: Int
        public var symbol: String

        public init(name: String, day: Date, startMinutes: Int?, durationMinutes: Int, symbol: String) {
            self.name = name
            self.day = day
            self.startMinutes = startMinutes
            self.durationMinutes = durationMinutes
            self.symbol = symbol
        }
    }

    public enum State: Hashable, Sendable {
        case none
        /// Seyahate kalan gün (0 bugün, 1 yarın).
        case upcoming(Item, days: Int)
        /// Seyahatin `day`. günü; `stop` bugünün sıradaki durağı, `isFirst` günün ilk durağıysa true.
        case ongoing(Item, day: Int, totalDays: Int, stop: StopItem?, isFirst: Bool, remaining: Int)
    }

    public var items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    /// Seyahatlerden özet: bitmemiş seyahatler, başlangıca göre sıralı; durakları sıralı.
    public init(trips: [Trip], now: Date = Date(), calendar: Calendar = .current, limit: Int = 4,
                flag: (String) -> String, tint: (Trip) -> UInt32, symbol: (StopKind) -> String,
                flightLabel: (FlightSegment) -> String) {
        let today = calendar.startOfDay(for: now)
        let active = trips
            .filter { calendar.startOfDay(for: $0.endDate) >= today }
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)
        items = active.map { trip in
            let stops = trip.days(calendar: calendar).flatMap { trip.stops(on: $0, calendar: calendar) }
            return Item(id: trip.id, name: trip.name, city: trip.cityTitle, flag: flag(trip.destination.countryCode),
                        tint: tint(trip), start: calendar.startOfDay(for: trip.startDate),
                        end: calendar.startOfDay(for: trip.endDate), flightLabel: trip.primaryFlight.map(flightLabel),
                        stops: stops.map {
                            StopItem(name: $0.name, day: calendar.startOfDay(for: $0.day), startMinutes: $0.startMinutes,
                                     durationMinutes: $0.durationMinutes, symbol: symbol($0.kind))
                        })
        }
    }

    public func state(at date: Date, calendar: Calendar = .current) -> State {
        let today = calendar.startOfDay(for: date)
        if let trip = items.first(where: { $0.start <= today && today <= $0.end }) {
            let day = (calendar.dateComponents([.day], from: trip.start, to: today).day ?? 0) + 1
            let total = (calendar.dateComponents([.day], from: trip.start, to: trip.end).day ?? 0) + 1
            let todays = trip.stops.filter { calendar.isDate($0.day, inSameDayAs: today) }
            let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
            // Saatli durak bittiyse geç; saati olmayan durak beklemede sayılır.
            let index = todays.firstIndex { stop in
                guard let start = stop.startMinutes else { return true }
                return start + stop.durationMinutes > minutes
            }
            return .ongoing(trip, day: day, totalDays: total, stop: index.map { todays[$0] }, isFirst: index == 0,
                            remaining: index.map { todays.count - $0 } ?? 0)
        }
        if let trip = items.first(where: { $0.start > today }) {
            let days = calendar.dateComponents([.day], from: today, to: trip.start).day ?? 0
            return .upcoming(trip, days: days)
        }
        return .none
    }

    /// Widget zaman çizelgesi için durumun değişebileceği anlar: gece yarıları ve durak bitişleri.
    public func refreshDates(after date: Date, calendar: Calendar = .current, days: Int = 3) -> [Date] {
        var dates: [Date] = []
        let today = calendar.startOfDay(for: date)
        for offset in 1...max(days, 1) {
            if let midnight = calendar.date(byAdding: .day, value: offset, to: today) { dates.append(midnight) }
        }
        let horizon = calendar.date(byAdding: .day, value: days, to: today) ?? date
        for item in items {
            for stop in item.stops {
                guard let start = stop.startMinutes,
                      let end = calendar.date(byAdding: .minute, value: start + stop.durationMinutes, to: stop.day),
                      end > date, end < horizon else { continue }
                dates.append(end)
            }
        }
        return Array(Set(dates)).sorted()
    }
}

// MARK: - Bağlantılar

/// Bildirim ve widget'tan uygulamada belirli bir seyahat sekmesine gitmek için adres.
/// Biçim: `stubly://trip/<uuid>?section=money`
public struct TripLink: Hashable, Sendable {
    public static let scheme = "stubly"

    public var tripID: UUID
    /// "plan", "money", "packing", "visa", "crew"
    public var section: String?

    public init(tripID: UUID, section: String? = nil) {
        self.tripID = tripID
        self.section = section
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == "trip",
              let id = UUID(uuidString: url.pathComponents.dropFirst().first ?? "") else { return nil }
        tripID = id
        section = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "section" }?.value
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "trip"
        components.path = "/\(tripID.uuidString)"
        if let section { components.queryItems = [URLQueryItem(name: "section", value: section)] }
        return components.url!
    }

    /// Bildirim `userInfo` anahtarları.
    public static let tripKey = "tripID"
    public static let sectionKey = "section"

    public var userInfo: [String: String] {
        var info = [Self.tripKey: tripID.uuidString]
        if let section { info[Self.sectionKey] = section }
        return info
    }

    public init?(userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo[Self.tripKey] as? String, let id = UUID(uuidString: raw) else { return nil }
        tripID = id
        section = userInfo[Self.sectionKey] as? String
    }
}
