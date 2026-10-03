import MapKit
import StublyKit

/// Apple Haritalar araması: sonuçlar seyahatin ülkesi ve şehriyle sınırlanır, sorguya benzerlik ve merkeze
/// yakınlıkla sıralanır (bkz. `PlaceMatch`).
enum PlaceSearch {
    struct Result: Hashable, Identifiable {
        let item: MKMapItem
        let name: String
        let coordinate: Coordinate
        let address: String?
        /// Şehir merkezine uzaklık (metre).
        let distance: Double?
        var id: String { "\(name)|\(coordinate.latitude)|\(coordinate.longitude)" }
    }

    struct City: Hashable, Identifiable {
        let name: String
        /// Bölge / eyalet ("Lizbon", "Bavyera").
        let region: String?
        let coordinate: Coordinate
        var id: String { "\(name)|\(region ?? "")" }
    }

    /// Şehir içinde yer arama. Merkez yoksa sorguya şehir ve ülke adı eklenir. Sonuçlar sorguya pek benzemiyorsa
    /// en uzun kelimeyle bir kez daha aranır.
    @MainActor
    static func places(_ query: String, city: String, countryCode: String, center: Coordinate?,
                       limit: Int = 6) async -> [Result] {
        // Yazılan, ı'sız/aksansız ve İngilizce tür kelimeli sorgular paralel aranır.
        var items: [MKMapItem] = []
        await withTaskGroup(of: [MKMapItem].self) { group in
            for variant in PlaceMatch.queryVariants(query) {
                group.addTask { await mapItems(variant, city: city, countryCode: countryCode, center: center) }
            }
            for await found in group { items += found }
        }
        let best = items.map { PlaceMatch.similarity(query, $0.name ?? "") }.max() ?? 0
        let words = PlaceMatch.normalize(query).split(separator: " ").map(String.init)
        if best < 0.6, words.count > 1, let longest = words.max(by: { $0.count < $1.count }), longest.count >= 4 {
            items += await mapItems(longest, city: city, countryCode: countryCode, center: center)
        }
        var byCandidate: [PlaceMatch.Candidate: MKMapItem] = [:]
        for item in items {
            let location = item.placemark.coordinate
            let candidate = PlaceMatch.Candidate(name: item.name ?? "", coordinate: Coordinate(latitude: location.latitude,
                                                                                               longitude: location.longitude),
                                                 countryCode: item.placemark.isoCountryCode)
            if byCandidate[candidate] == nil { byCandidate[candidate] = item }
        }
        return PlaceMatch.rank(Array(byCandidate.keys), query: query, center: center, countryCode: countryCode, limit: limit)
            .compactMap { candidate in
                guard let item = byCandidate[candidate] else { return nil }
                return Result(item: item, name: candidate.name, coordinate: candidate.coordinate,
                              address: item.placemark.title, distance: center.map { Geo.distance($0, candidate.coordinate) })
            }
    }

    @MainActor
    private static func mapItems(_ query: String, city: String, countryCode: String, center: Coordinate?) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.resultTypes = [.pointOfInterest, .address]
        if let center {
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                                                latitudinalMeters: 30_000, longitudinalMeters: 30_000)
            // Bölge yalnızca ipucu olursa "belem" Brezilya'daki Belém'i getirir.
            if #available(iOS 18.0, *) { request.regionPriority = .required }
        } else {
            request.naturalLanguageQuery = "\(query), \(city), \(Countries.name(countryCode))"
        }
        return (try? await MKLocalSearch(request: request).start().mapItems) ?? []
    }

    private static var countryRegions: [String: MKCoordinateRegion] = [:]

    /// Ülkenin kabaca kapladığı bölge (bir kez bulunur, bellekte tutulur).
    @MainActor
    static func countryRegion(_ countryCode: String) async -> MKCoordinateRegion? {
        let code = countryCode.uppercased()
        if let cached = countryRegions[code] { return cached }
        let english = Locale(identifier: "en_US").localizedString(forRegionCode: code) ?? Countries.name(code)
        guard let placemark = try? await CLGeocoder().geocodeAddressString(english).first(where: { $0.isoCountryCode == code }),
              let location = placemark.location else { return nil }
        let radius = (placemark.region as? CLCircularRegion)?.radius ?? 300_000
        let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        countryRegions[code] = region
        return region
    }

    /// Ülke içindeki şehirler (yalnızca yerleşim yeri adları).
    @MainActor
    static func cities(_ query: String, countryCode: String) async -> [City] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(query), \(Countries.name(countryCode))"
        request.resultTypes = .address
        if let region = await countryRegion(countryCode) {
            request.region = region
            if #available(iOS 18.0, *) { request.regionPriority = .required }
        }
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return [] }
        var seen: Set<String> = []
        let cities = items.compactMap { item -> City? in
            let placemark = item.placemark
            guard placemark.isoCountryCode?.uppercased() == countryCode.uppercased(),
                  let name = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
            else { return nil }
            let region = placemark.administrativeArea == name ? nil : placemark.administrativeArea
            guard seen.insert("\(name)|\(region ?? "")").inserted else { return nil }
            return City(name: name, region: region,
                        coordinate: Coordinate(latitude: placemark.coordinate.latitude, longitude: placemark.coordinate.longitude))
        }
        return cities.sorted { PlaceMatch.similarity(query, $0.name) > PlaceMatch.similarity(query, $1.name) }
    }

    /// Otomatik tamamlama önerisini konuma çevirir; başka ülkedeyse nil.
    @MainActor
    static func city(from completion: MKLocalSearchCompletion, countryCode: String) async -> City? {
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first,
              item.placemark.isoCountryCode?.uppercased() == countryCode.uppercased() else { return nil }
        let placemark = item.placemark
        let name = placemark.locality ?? completion.title
        return City(name: name, region: placemark.administrativeArea == name ? nil : placemark.administrativeArea,
                    coordinate: Coordinate(latitude: placemark.coordinate.latitude, longitude: placemark.coordinate.longitude))
    }

    static func kind(for category: MKPointOfInterestCategory?) -> StopKind {
        switch category {
        case .restaurant?, .cafe?, .bakery?, .brewery?, .winery?, .foodMarket?, .nightlife?: .food
        case .hotel?, .campground?: .stay
        case .airport?, .publicTransport?, .carRental?, .marina?: .transport
        case .museum?, .theater?, .movieTheater?, .amusementPark?, .aquarium?, .zoo?, .stadium?: .activity
        default: .sight
        }
    }
}

/// Yazarken şehir önerileri (Apple Haritalar otomatik tamamlama), yalnızca seçili ülkedekiler.
@MainActor
@Observable
final class CityCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var completions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()
    private let countryNames: [String]

    init(countryCode: String) {
        // Alt başlık cihaz dilinde gelir; Türkçe ve İngilizce ülke adıyla süzülür.
        countryNames = [Locale(identifier: "tr_TR"), Locale(identifier: "en_US"), Locale.current]
            .compactMap { $0.localizedString(forRegionCode: countryCode) }
        super.init()
        completer.resultTypes = .address
        completer.delegate = self
        // Bölge verilmezse öneriler dünya geneline bakar ("port" → Portland, Port Said…).
        Task {
            guard let region = await PlaceSearch.countryRegion(countryCode) else { return }
            completer.region = region
            if !lastQuery.isEmpty { completer.queryFragment = lastQuery }
        }
    }

    private var lastQuery = ""

    func search(_ text: String) {
        lastQuery = text
        if text.isEmpty { completions = [] } else { completer.queryFragment = text }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        MainActor.assumeIsolated {
            completions = Array(results.filter { completion in
                // Sokak/adres değil yerleşim yeri: başlıkta virgül yok ve alt başlıkta ülke adı var.
                !completion.title.contains(",")
                    && countryNames.contains { completion.subtitle.localizedCaseInsensitiveContains($0) || completion.title == $0 }
                    && !countryNames.contains(completion.title)
            }.prefix(8))
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}
