import Foundation

/// Topluluk öneri havuzu: seyahati biten kullanıcı onay verirse gittiği yerler ve aynı gün art arda gidilen
/// yer çiftleri anonim olarak sunucuya gider. Tarih, ekip, notlar ve tam rota gönderilmez.
public enum CommunityPlaces {
    public struct Place: Codable, Hashable, Sendable {
        public var ref: String
        public var name: String
        public var lat: Double
        public var lon: Double
        public var kind: String
        public var category: String
        /// 1 beğendi, -1 beğenmedi, 0 belirtmedi.
        public var liked: Int
        /// Anılar'daki fotoğraflar bu durakla eşleşti mi (gerçekten gidildi).
        public var verified: Bool
    }

    public struct Contribution: Codable, Hashable, Sendable {
        public var country: String
        public var places: [Place]
        public var transitions: [[String]]
    }

    /// Paylaşılabilecek duraklar: konumu olan, ulaşım ve konaklama dışındaki yerler.
    public static func eligibleStops(in trip: Trip) -> [Stop] {
        trip.stops.filter { $0.coordinate != nil && $0.kind != .transport && $0.kind != .stay }
            .sorted { ($0.day, $0.order) < ($1.day, $1.order) }
    }

    /// Seyahat bitti mi ve paylaşılacak en az iki yer var mı.
    public static func canContribute(_ trip: Trip, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        trip.isPast(now: now, calendar: calendar) && eligibleStops(in: trip).count >= 2
    }

    /// Katkı paketi. Durak kimlikleri yerine sıra numaraları gider (`ref`); konum 5 basamağa yuvarlanır.
    /// - Parameters:
    ///   - ratings: durak → 1 / -1 (verilmeyenler 0).
    ///   - verified: fotoğraflarla doğrulanan duraklar.
    ///   - excluded: kullanıcının paylaşmak istemediği duraklar.
    public static func contribution(for trip: Trip, ratings: [UUID: Int], verified: Set<UUID>,
                                    excluded: Set<UUID> = [], calendar: Calendar = .current) -> Contribution? {
        let stops = eligibleStops(in: trip).filter { !excluded.contains($0.id) }
        guard stops.count >= 1 else { return nil }
        var refs: [UUID: String] = [:]
        let places = stops.enumerated().map { index, stop -> Place in
            let ref = "p\(index)"
            refs[stop.id] = ref
            let coordinate = stop.coordinate!
            return Place(ref: ref, name: stop.name, lat: round5(coordinate.latitude), lon: round5(coordinate.longitude),
                         kind: stop.kind.rawValue, category: String(stop.note.prefix(60)).isEmpty ? "" : category(stop),
                         liked: max(-1, min(1, ratings[stop.id] ?? 0)), verified: verified.contains(stop.id))
        }
        // Aynı gün art arda gidilen paylaşılan yerler.
        var transitions: [[String]] = []
        for day in trip.days(calendar: calendar) {
            let ordered = trip.stops(on: day, calendar: calendar).compactMap { refs[$0.id] }
            for (a, b) in zip(ordered, ordered.dropFirst()) where a != b { transitions.append([a, b]) }
        }
        return Contribution(country: trip.destination.countryCode.uppercased(), places: places, transitions: transitions)
    }

    /// Kullanıcı notu kişisel olabilir; yalnızca öneri ekranından gelen bilinen tür etiketleri paylaşılır.
    static func category(_ stop: Stop) -> String {
        knownCategories.contains(stop.note) ? stop.note : ""
    }

    static let knownCategories: Set<String> = [
        "Müze", "Galeri", "Kale / saray", "İbadethane", "Seyir noktası", "Hayvanat bahçesi / akvaryum", "Tema parkı",
        "Park / bahçe", "Meydan", "Semt", "Anıt", "Simge yapı", "Tarihî alan", "Pazar", "Tiyatro / opera",
        "Kafe / restoran", "Plaj", "Kütüphane / kitapçı", "Gezilecek yer",
    ]

    /// Fotoğraf anlarıyla doğrulanan duraklar: aynı gün, merkezi durağa 150 m'den yakın bir an varsa gidilmiştir.
    public static func verifiedStops(in trip: Trip, moments: [PhotoClusterer.Moment], calendar: Calendar = .current) -> Set<UUID> {
        Set(eligibleStops(in: trip).filter { stop in
            moments.contains { moment in
                guard let center = moment.center, let coordinate = stop.coordinate else { return false }
                return calendar.isDate(moment.start, inSameDayAs: stop.day) && Geo.distance(center, coordinate) < 150
            }
        }.map(\.id))
    }

    static func round5(_ value: Double) -> Double { (value * 100_000).rounded() / 100_000 }

    // MARK: Sunucu yanıtları

    private struct Response: Decodable {
        struct Item: Decodable {
            let id: Int
            let name: String
            let lat: Double
            let lon: Double
            let kind: String
            let category: String
            let contributors: Int
            let score: Int
        }
        let places: [Item]
    }

    /// `/places/nearby` ya da `/places/next` yanıtını önerilere çevirir.
    public static func decode(_ data: Data) -> [PlaceSuggestions.Suggestion] {
        guard let items = try? JSONDecoder().decode(Response.self, from: data).places else { return [] }
        return items.map { item in
            let kind = StopKind(rawValue: item.kind) ?? .sight
            var suggestion = PlaceSuggestions.Suggestion(
                id: "community/\(item.id)", name: item.name, kind: kind,
                category: item.category.isEmpty ? String(localized: "Gezilecek yer") : item.category,
                coordinate: Coordinate(latitude: item.lat, longitude: item.lon), openingHours: nil,
                duration: defaultDuration(kind), score: item.score)
            suggestion.contributors = item.contributors
            return suggestion
        }
    }

    static func defaultDuration(_ kind: StopKind) -> Int {
        switch kind {
        case .food: 60
        case .activity: 90
        default: 60
        }
    }

    /// Topluluk önerileri önce; aynı yerin Wikipedia kaydı tekrar gösterilmez.
    public static func merge(community: [PlaceSuggestions.Suggestion], wikipedia: [PlaceSuggestions.Suggestion])
        -> [PlaceSuggestions.Suggestion] {
        let rest = wikipedia.filter { wiki in
            !community.contains { $0.matches(Stop(day: Date(), order: 0, name: wiki.name, kind: wiki.kind, coordinate: wiki.coordinate)) }
        }
        return community + rest
    }
}
