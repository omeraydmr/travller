import Foundation

/// Gidilen şehirde görülecek yer önerileri: Wikipedia'nın konuma göre aramasından (GeoSearch) gelen sayfalar,
/// son 30 günün okunma sayısına göre sıralanır. Yer olmayan sayfalar (şehrin kendisi, kurumlar, olaylar,
/// istasyonlar…) kısa açıklamalarına bakılarak elenir.
public enum PlaceSuggestions {
    public struct Suggestion: Hashable, Identifiable, Sendable {
        /// Kaynak kimliği ("wiki/123").
        public var id: String
        public var name: String
        public var kind: StopKind
        /// Kısa tür etiketi ("Müze", "Kale / saray"…).
        public var category: String
        public var coordinate: Coordinate
        public var openingHours: String?
        /// Önerilen ziyaret süresi (dakika).
        public var duration: Int
        /// Sıralama puanı (Wikipedia'da son 30 günün okunma sayısı ya da topluluk puanı).
        public var score: Int
        /// Topluluk önerisiyse katkı veren kişi sayısı; Wikipedia'dan gelenlerde nil.
        public var contributors: Int?

        public init(id: String, name: String, kind: StopKind, category: String, coordinate: Coordinate,
                    openingHours: String?, duration: Int, score: Int) {
            self.id = id
            self.name = name
            self.kind = kind
            self.category = category
            self.coordinate = coordinate
            self.openingHours = openingHours
            self.duration = duration
            self.score = score
        }

        /// Plandaki ya da fikirlerdeki bir yerle aynı mı: adı benziyor ya da 80 m yakınında.
        public func matches(_ stop: Stop) -> Bool {
            OpeningHoursLookup.bestMatch(for: stop.name, in: [.init(name: name, openingHours: "")]) != nil
                || stop.coordinate.map { Geo.distance($0, coordinate) < 80 } == true
        }

        /// Fikirler havuzuna eklenecek durak (gün bilgisi anlamsız).
        public func stop(day: Date) -> Stop {
            Stop(day: day, order: 0, name: name, kind: kind, durationMinutes: duration, coordinate: coordinate,
                 note: category, openingHours: openingHours)
        }
    }

    /// Şehrin merkezinde ve çevresinde (yaklaşık `spread` metre uzakta) dört noktadan arama adresleri;
    /// tek arama yalnızca en yakın 100 sayfayı verdiği için merkezdeki sık sayfalar çevreyi gizlemesin.
    public static func searchURLs(center: Coordinate, spread: Double = 3500) -> [URL] {
        let dLat = spread / 111_000
        let dLon = spread / (111_000 * max(0.2, cos(center.latitude * .pi / 180)))
        let points = [(0.0, 0.0), (dLat, dLon), (dLat, -dLon), (-dLat, dLon), (-dLat, -dLon)]
        return points.map { offset in
            var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
            components.queryItems = [
                .init(name: "action", value: "query"),
                .init(name: "generator", value: "geosearch"),
                .init(name: "ggscoord", value: String(format: "%.5f|%.5f", center.latitude + offset.0, center.longitude + offset.1)),
                .init(name: "ggsradius", value: "\(Int(spread))"),
                .init(name: "ggslimit", value: "100"),
                .init(name: "prop", value: "pageviews|coordinates|description|langlinks"),
                .init(name: "lllang", value: "tr"),
                .init(name: "lllimit", value: "max"),
                // Koordinat varsayılan olarak yalnızca ilk 10 sayfa için döner.
                .init(name: "colimit", value: "max"),
                .init(name: "pvipdays", value: "30"),
                .init(name: "format", value: "json"),
                .init(name: "formatversion", value: "2"),
            ]
            return components.url!
        }
    }

    private struct Response: Decodable {
        struct Query: Decodable { let pages: [Page]? }
        struct Page: Decodable {
            let pageid: Int
            let title: String
            let description: String?
            let coordinates: [Point]?
            let pageviews: [String: Int?]?
            let langlinks: [LangLink]?
        }
        struct Point: Decodable {
            let lat: Double
            let lon: Double
        }
        struct LangLink: Decodable {
            let lang: String
            let title: String
        }
        let query: Query?
    }

    /// Wikipedia yanıtlarını birleştirip önerilere çevirir.
    /// - Parameters:
    ///   - excluding: planda ya da fikirlerde zaten olan yerler.
    ///   - language: "tr" ise Türkçe sayfa başlığı varsa o kullanılır.
    public static func decode(_ responses: [Data], excluding existing: [Stop] = [], language: String = "tr",
                              limit: Int = 40) -> [Suggestion] {
        var byID: [Int: Suggestion] = [:]
        for data in responses {
            guard let pages = (try? JSONDecoder().decode(Response.self, from: data))?.query?.pages else { continue }
            for page in pages where byID[page.pageid] == nil {
                guard let point = page.coordinates?.first, let classified = classify(page.description ?? "") else { continue }
                let turkish = page.langlinks?.first { $0.lang == "tr" }?.title
                let views = (page.pageviews ?? [:]).values.reduce(0) { $0 + ($1 ?? 0) }
                byID[page.pageid] = Suggestion(id: "wiki/\(page.pageid)",
                                               name: language == "tr" ? turkish ?? page.title : page.title,
                                               kind: classified.kind, category: classified.category,
                                               coordinate: Coordinate(latitude: point.lat, longitude: point.lon),
                                               openingHours: nil, duration: classified.duration, score: views)
            }
        }
        var kept: [Suggestion] = []
        for suggestion in byID.values.sorted(by: { $0.score != $1.score ? $0.score > $1.score : $0.name < $1.name }) {
            let duplicate = kept.contains { Geo.distance($0.coordinate, suggestion.coordinate) < 30 }
            if !duplicate && !existing.contains(where: suggestion.matches) { kept.append(suggestion) }
            if kept.count == limit { break }
        }
        return kept
    }

    struct Classification: Equatable {
        var kind: StopKind
        var category: String
        var duration: Int
    }

    /// Sayfanın kısa açıklamasından tür. Yer olmayan ya da gezilecek olmayan sayfalar nil.
    static func classify(_ description: String) -> Classification? {
        let text = description.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        // Önce eleme: kurumlar, olaylar, ulaşım istasyonları, idari bölgeler, kişiler.
        if has(["railway station", "metro station", "bus station", "train station", "civil parish", "municipality",
                "capital", "largest city", "federation", "company", "retailer", "bank", "police", "institut",
                "agency", "ministry", "university", "school", "hospital", "hotel", "accident", "derailment", "battle",
                "siege", "earthquake", "emirate", "kingdom", "dynasty", "roman times", "exchange", "club", "football",
                "newspaper", "brand", "festival", "district of", "electoral", "embassy", "consulate", "airport",
                "politician", "footballer", "singer", "writer", "painter", "actor", "born ", "(born"]) {
            return nil
        }
        // Açıklamanın başındaki tür belirleyicidir ("Café in … old quarter"): yeme-içme önce.
        if has(["café", "cafe", "restaurant", "bakery", "pastry"]) {
            return .init(kind: .food, category: String(localized: "Kafe / restoran"), duration: 45)
        }
        if has(["museum"]) { return .init(kind: .sight, category: String(localized: "Müze"), duration: 120) }
        if has(["gallery", "art centre", "art center"]) { return .init(kind: .sight, category: String(localized: "Galeri"), duration: 60) }
        if has(["castle", "palace", "fortress", "fort ", "citadel"]) {
            return .init(kind: .sight, category: String(localized: "Kale / saray"), duration: 90)
        }
        if has(["cathedral", "basilica", "church", "monastery", "convent", "chapel", "mosque", "synagogue", "temple", "abbey"]) {
            return .init(kind: .sight, category: String(localized: "İbadethane"), duration: 40)
        }
        if has(["viewpoint", "miradouro", "lookout", "observation"]) {
            return .init(kind: .sight, category: String(localized: "Seyir noktası"), duration: 30)
        }
        if has(["zoo", "aquarium", "oceanarium"]) {
            return .init(kind: .activity, category: String(localized: "Hayvanat bahçesi / akvaryum"), duration: 180)
        }
        if has(["theme park", "amusement park"]) {
            return .init(kind: .activity, category: String(localized: "Tema parkı"), duration: 240)
        }
        if has(["park", "garden", "botanical"]) { return .init(kind: .activity, category: String(localized: "Park / bahçe"), duration: 60) }
        if has(["square", "plaza", "piazza", "praça"]) { return .init(kind: .sight, category: String(localized: "Meydan"), duration: 30) }
        if has(["neighbourhood", "neighborhood", "quarter", "old town", "historic centre", "historic center"]) {
            return .init(kind: .sight, category: String(localized: "Semt"), duration: 90)
        }
        if has(["monument", "memorial", "statue", "column", "obelisk", "fountain", "triumphal arch"]) {
            return .init(kind: .sight, category: String(localized: "Anıt"), duration: 20)
        }
        if has(["tower", "lighthouse", "bridge", "aqueduct", "elevator", "lift", "funicular", "tram line"]) {
            return .init(kind: .sight, category: String(localized: "Simge yapı"), duration: 30)
        }
        if has(["ruins", "archaeological", "historic site", "historical site", "landmark", "heritage"]) {
            return .init(kind: .sight, category: String(localized: "Tarihî alan"), duration: 60)
        }
        if has(["market", "bazaar"]) { return .init(kind: .food, category: String(localized: "Pazar"), duration: 60) }
        if has(["theatre", "theater", "opera", "concert hall"]) {
            return .init(kind: .activity, category: String(localized: "Tiyatro / opera"), duration: 120)
        }
        if has(["beach"]) { return .init(kind: .activity, category: String(localized: "Plaj"), duration: 120) }
        if has(["library", "bookshop", "bookstore"]) {
            return .init(kind: .sight, category: String(localized: "Kütüphane / kitapçı"), duration: 30)
        }
        return nil
    }
}
