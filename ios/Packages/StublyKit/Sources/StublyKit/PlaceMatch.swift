import Foundation

/// Harita aramasının sonuçlarını sorguya benzerlik ve şehir merkezine yakınlıkla sıralar; başka ülkedeki
/// ya da şehirden çok uzaktaki aynı adlı yerler geriye düşer veya elenir.
public enum PlaceMatch {
    public struct Candidate: Hashable, Sendable {
        public var name: String
        public var coordinate: Coordinate
        /// ISO ülke kodu (biliniyorsa).
        public var countryCode: String?

        public init(name: String, coordinate: Coordinate, countryCode: String?) {
            self.name = name
            self.coordinate = coordinate
            self.countryCode = countryCode
        }
    }

    /// Büyük/küçük harf, aksan ve noktalama farkı olmadan karşılaştırma için.
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en"))
            .replacingOccurrences(of: "ı", with: "i")
        return String(folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " })
            .split(separator: " ").joined(separator: " ")
    }

    /// 0…1 arası ad benzerliği: tam eşleşme 1, baştan eşleşme ve içerme yüksek; yoksa kelime örtüşmesi ve
    /// yazım hatasına dayanıklı düzenleme uzaklığı.
    public static func similarity(_ query: String, _ name: String) -> Double {
        let q = normalize(query), n = normalize(name)
        guard !q.isEmpty, !n.isEmpty else { return 0 }
        if q == n { return 1 }
        if n.hasPrefix(q) { return 0.9 }
        if n.contains(q) { return 0.8 }
        let qWords = Set(q.split(separator: " ")), nWords = Set(n.split(separator: " "))
        // Her sorgu kelimesi için adda en çok benzeyen kelime (yazım hatası ya da kısaltma).
        let wordScore = qWords.map { word in
            nWords.map { candidate -> Double in
                if candidate.hasPrefix(word) || word.hasPrefix(candidate) { return 1 }
                return 1 - Double(distance(Array(word), Array(candidate))) / Double(max(word.count, candidate.count))
            }.max() ?? 0
        }.reduce(0, +) / Double(qWords.count)
        let whole = 1 - Double(distance(Array(q), Array(n))) / Double(max(q.count, n.count))
        return max(wordScore * 0.75, whole * 0.7)
    }

    /// Türkçe yer türü kelimelerinin İngilizce karşılıkları (Apple Haritalar yerel ve İngilizce adlarla arar).
    static let turkishTerms: [String: String] = [
        "manastir": "monastery", "manastiri": "monastery", "muze": "museum", "muzesi": "museum",
        "kale": "castle", "kalesi": "castle", "saray": "palace", "sarayi": "palace", "kule": "tower", "kulesi": "tower",
        "kopru": "bridge", "koprusu": "bridge", "meydan": "square", "meydani": "square", "kilise": "church",
        "kilisesi": "church", "katedral": "cathedral", "katedrali": "cathedral", "cami": "mosque", "camii": "mosque",
        "carsi": "market", "carsisi": "market", "pazar": "market", "pazari": "market", "bahce": "garden",
        "bahcesi": "garden", "plaj": "beach", "plaji": "beach", "asansor": "lift", "asansoru": "lift",
        "seyir": "viewpoint", "tepe": "hill", "tepesi": "hill", "liman": "harbour", "limani": "harbour",
        "istasyon": "station", "istasyonu": "station", "havalimani": "airport", "havaalani": "airport",
        "otel": "hotel", "oteli": "hotel", "anit": "monument", "aniti": "monument", "heykel": "statue", "heykeli": "statue",
        "tiyatro": "theatre", "tiyatrosu": "theatre", "akvaryum": "aquarium", "hayvanat": "zoo", "sokak": "street",
        "sokagi": "street", "cadde": "avenue", "caddesi": "avenue",
    ]

    /// Haritada denenecek sorgular: yazılan, aksansız/ı'sız hâli ve Türkçe tür kelimeleri İngilizceye çevrilmiş hâli
    /// ("jeronımo manastır" → "jeronimo manastir", "jeronimo monastery").
    public static func queryVariants(_ query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let folded = normalize(trimmed)
        let words = folded.split(separator: " ").map(String.init)
        let translated = words.map { turkishTerms[$0] ?? $0 }.joined(separator: " ")
        var result = [trimmed]
        for variant in [folded, translated] where !result.contains(variant) { result.append(variant) }
        return result
    }

    /// Levenshtein uzaklığı.
    static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    /// Sıralanmış sonuçlar. `center` verilirse `maxDistance` metreden uzaktakiler ve ülke kodu tutmayanlar elenir;
    /// hepsi elenirse (ör. şehir konumu yanlışsa) ülke filtresiyle yetinilir.
    public static func rank(_ candidates: [Candidate], query: String, center: Coordinate?, countryCode: String?,
                            maxDistance: Double = 60_000, limit: Int = 8) -> [Candidate] {
        let country = countryCode?.uppercased()
        let inCountry = candidates.filter { candidate in
            guard let country, let code = candidate.countryCode else { return true }
            return code.uppercased() == country
        }
        let nearby = center.map { center in inCountry.filter { Geo.distance($0.coordinate, center) <= maxDistance } } ?? inCountry
        let pool = nearby.isEmpty ? inCountry : nearby
        let variants = queryVariants(query)
        func score(_ candidate: Candidate) -> Double {
            let similar = variants.map { similarity($0, candidate.name) }.max() ?? 0
            guard let center else { return similar }
            // Yakınlık eşit benzerlikte öne geçirir: merkezde 0.15, 20 km'de ~0.
            let km = Geo.distance(candidate.coordinate, center) / 1000
            return similar + 0.15 * max(0, 1 - km / 20)
        }
        let scored: [(candidate: Candidate, score: Double)] = pool.map { ($0, score($0)) }
        let sorted = scored.sorted { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.candidate.name < rhs.candidate.name
        }
        var seen: Set<String> = []
        var result: [Candidate] = []
        for (candidate, _) in sorted where result.count < limit {
            // Aynı ad ve ~50 m içindeki tekrarlar tek sonuç.
            let lat = Int(candidate.coordinate.latitude * 2000), lon = Int(candidate.coordinate.longitude * 2000)
            if seen.insert("\(normalize(candidate.name))|\(lat)|\(lon)").inserted { result.append(candidate) }
        }
        return result
    }
}
