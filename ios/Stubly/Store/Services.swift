import CoreLocation
import Foundation
import ImageIO
import MapKit
import StublyKit
import UIKit
import Vision

/// Avrupa Merkez Bankası referans kurları (Frankfurter, anahtarsız). Kurlar gün içinde önbellekte tutulur.
@MainActor
final class RateService {
    static let shared = RateService()
    private var cache: [String: (quote: CurrencyConverter.Quote, fetchedAt: Date)] = [:]

    func quote(from: String, to: String) async throws -> CurrencyConverter.Quote {
        let key = "\(from)-\(to)"
        if let cached = cache[key], Date().timeIntervalSince(cached.fetchedAt) < 6 * 3600 {
            return cached.quote
        }
        guard CurrencyConverter.isSupported(from), CurrencyConverter.isSupported(to),
              let url = CurrencyConverter.rateURL(from: from, to: to) else {
            throw ServiceError.unsupportedCurrency
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ServiceError.badResponse }
        let quote = try CurrencyConverter.decodeQuote(data, to: to)
        cache[key] = (quote, Date())
        return quote
    }
}

/// Open-Meteo üzerinden seyahat tarihleri için hava özeti (anahtarsız).
@MainActor
final class WeatherFetcher {
    static let shared = WeatherFetcher()
    private var cache: [String: WeatherSummary] = [:]

    func summary(latitude: Double, longitude: Double, start: Date, end: Date) async throws -> WeatherSummary {
        guard let request = WeatherService.requestURL(latitude: latitude, longitude: longitude, start: start, end: end) else {
            throw ServiceError.badResponse
        }
        let key = request.url.absoluteString
        if let cached = cache[key] { return cached }
        let (data, response) = try await URLSession.shared.data(from: request.url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ServiceError.badResponse }
        let summary = try WeatherService.decodeSummary(data, source: request.source)
        cache[key] = summary
        return summary
    }
}

enum DestinationGeocoder {
    /// Şehir + ülke adından koordinat bulur (Apple).
    static func coordinate(for destination: Destination) async -> Coordinate? {
        let query = "\(destination.city), \(Countries.name(destination.countryCode))"
        guard let placemark = try? await CLGeocoder().geocodeAddressString(query).first,
              let location = placemark.location else { return nil }
        return Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}

enum ServiceError: LocalizedError {
    case unsupportedCurrency, badResponse

    var errorDescription: String? {
        switch self {
        case .unsupportedCurrency: String(localized: "Bu para birimi için güncel kur yok; kuru elle girebilirsin.")
        case .badResponse: String(localized: "Sunucuya ulaşılamadı.")
        }
    }
}

extension TripStore {
    /// Seyahatin (çok şehirlide verilen günün şehrinin) koordinatı; yoksa şehirden bulup kaydeder.
    func ensureCoordinate(for id: Trip.ID, on day: Date? = nil) async -> Coordinate? {
        guard let trip = trip(id) else { return nil }
        let leg = trip.leg(on: day ?? trip.startDate)
        if let coordinate = leg.destination.coordinate { return coordinate }
        guard let found = await DestinationGeocoder.coordinate(for: leg.destination) else { return nil }
        update(id) { trip in
            if trip.isMultiCity, var legs = trip.legs, let index = legs.firstIndex(where: { $0.id == leg.id }) {
                legs[index].destination.coordinate = found
                trip.legs = legs
                if index == 0 || trip.destination == leg.destination { trip.destination.coordinate = found }
            } else {
                trip.destination.coordinate = found
            }
        }
        return found
    }

    /// Çok şehirli seyahatte konumu bilinmeyen tüm şehirleri bulur (otomatik rota şehirleri ayırabilsin).
    func ensureAllCoordinates(for id: Trip.ID) async {
        guard let trip = trip(id) else { return }
        for leg in trip.cityLegs where leg.destination.coordinate == nil {
            _ = await ensureCoordinate(for: id, on: leg.arrival)
        }
    }
}

/// Makbuz fotoğrafındaki metni cihaz üzerinde (Vision) okuyup toplamı çıkarır; görüntü cihazdan çıkmaz.
enum ReceiptReader {
    struct Output {
        var total: ReceiptParser.Result?
        var items: [ReceiptItem]
    }

    static func read(_ image: UIImage) async -> Output {
        guard let cgImage = image.cgImage else { return Output(total: nil, items: []) }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let lines: [String] = await Task.detached(priority: .userInitiated) { () -> [String] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["tr-TR", "en-US", "de-DE", "fr-FR", "it-IT", "es-ES", "pt-PT"]
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            do {
                try handler.perform([request])
            } catch {
                return []
            }
            return rows(from: request.results ?? [])
        }.value
        return Output(total: ReceiptParser.parse(lines: lines), items: ReceiptParser.items(lines: lines))
    }

    /// Aynı yükseklikteki gözlemleri (ör. "Galão" ve "€1.80") tek satırda birleştirir; yukarıdan aşağıya sıralar.
    static func rows(from observations: [VNRecognizedTextObservation]) -> [String] {
        let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        var rows: [[VNRecognizedTextObservation]] = []
        for observation in sorted {
            if let last = rows.last?.first,
               abs(last.boundingBox.midY - observation.boundingBox.midY) < max(last.boundingBox.height, observation.boundingBox.height) * 0.5 {
                rows[rows.count - 1].append(observation)
            } else {
                rows.append([observation])
            }
        }
        return rows.map { row in
            row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "  ")
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Overpass API istemcisi. Sunucular sık meşgul olduğundan sorgu birkaç sunucuya aynı anda gider,
/// ilk geçerli yanıt kullanılır. User-Agent zorunlu: olmadan ana sunucu 406 döndürüyor.
enum OverpassClient {
    static let endpoints = [
        URL(string: "https://overpass-api.de/api/interpreter")!,
        URL(string: "https://maps.mail.ru/osm/tools/overpass/api/interpreter")!,
        URL(string: "https://overpass.private.coffee/api/interpreter")!,
    ]

    static func run(_ query: String, timeout: TimeInterval = 25) async throws -> Data {
        let body = Data("data=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query)".utf8)
        return try await withThrowingTaskGroup(of: Data?.self) { group in
            for endpoint in endpoints {
                group.addTask {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = timeout
                    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    request.setValue("Stubly/\(Bundle.main.shortVersion) (iOS travel planner)", forHTTPHeaderField: "User-Agent")
                    request.httpBody = body
                    guard let (data, response) = try? await URLSession.shared.data(for: request),
                          (response as? HTTPURLResponse)?.statusCode == 200,
                          data.first == UInt8(ascii: "{") else { return nil }
                    return data
                }
            }
            for try await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            throw ServiceError.badResponse
        }
    }
}

private extension Bundle {
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1" }
}

/// OpenStreetMap (Overpass API) üzerinden bir durağın açılış saatlerini bulur.
@MainActor
final class OpeningHoursService {
    static let shared = OpeningHoursService()

    func lookup(name: String, coordinate: Coordinate) async throws -> String? {
        let query = OpeningHoursLookup.query(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let data = try await OverpassClient.run(query, timeout: 15)
        let candidates = try OpeningHoursLookup.decodeCandidates(data)
        return OpeningHoursLookup.bestMatch(for: name, in: candidates)?.openingHours
    }
}

/// Gidilen şehirde görülecek yer önerileri: Wikipedia (konuma göre arama + okunma sayısı); olmazsa Apple Haritalar.
@MainActor
final class PlaceSuggestionService {
    static let shared = PlaceSuggestionService()
    /// Şehir başına son sonuç (filtresiz); sayfa her açıldığında yeniden sorgulanmasın.
    private var cache: [String: [PlaceSuggestions.Suggestion]] = [:]

    func suggestions(around center: Coordinate, excluding existing: [Stop]) async throws -> [PlaceSuggestions.Suggestion] {
        let key = String(format: "%.3f,%.3f", center.latitude, center.longitude)
        let all: [PlaceSuggestions.Suggestion]
        if let cached = cache[key] {
            all = cached
        } else {
            let language = Bundle.main.preferredLocalizations.first == "tr" ? "tr" : "en"
            let responses = await wikipedia(PlaceSuggestions.searchURLs(center: center))
            let decoded = PlaceSuggestions.decode(responses, language: language, limit: 80)
            all = decoded.isEmpty ? try await mapKitSuggestions(around: center) : decoded
            cache[key] = all
        }
        return Array(all.filter { suggestion in !existing.contains(where: suggestion.matches) }.prefix(40))
    }

    /// Aramalar paralel; başarısız olanlar atlanır.
    private func wikipedia(_ urls: [URL]) async -> [Data] {
        await withTaskGroup(of: Data?.self) { group in
            for url in urls {
                group.addTask {
                    var request = URLRequest(url: url, timeoutInterval: 12)
                    // Wikimedia API kuralı: uygulamayı tanıtan bir User-Agent.
                    request.setValue("Stubly/1.0 (iOS travel planner; https://github.com/omeraydmr/travller)",
                                     forHTTPHeaderField: "User-Agent")
                    guard let (data, response) = try? await URLSession.shared.data(for: request),
                          (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                    return data
                }
            }
            var result: [Data] = []
            for await data in group { if let data { result.append(data) } }
            return result
        }
    }

    /// Yedek: Apple Haritalar'ın turistik yer kategorileri (açılış saati ve popülerlik bilgisi yok).
    private func mapKitSuggestions(around center: Coordinate) async throws -> [PlaceSuggestions.Suggestion] {
        var categories: [MKPointOfInterestCategory] = [.museum, .park, .nationalPark, .zoo, .aquarium, .amusementPark, .theater]
        if #available(iOS 18.0, *) {
            categories += [.castle, .fortress, .landmark, .nationalMonument, .planetarium]
        }
        let request = MKLocalPointsOfInterestRequest(center: CLLocationCoordinate2D(latitude: center.latitude,
                                                                                   longitude: center.longitude),
                                                     radius: 5000)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        let items = try await MKLocalSearch(request: request).start().mapItems
        return items.compactMap { item -> PlaceSuggestions.Suggestion? in
            guard let name = item.name else { return nil }
            let coordinate = Coordinate(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
            let (kind, category, duration) = Self.describe(item.pointOfInterestCategory)
            return PlaceSuggestions.Suggestion(id: "apple/\(name)/\(coordinate.latitude)", name: name, kind: kind,
                                               category: category, coordinate: coordinate, openingHours: nil,
                                               duration: duration, score: item.url == nil ? 1 : 2)
        }.sorted { $0.score > $1.score }
    }

    private static func describe(_ category: MKPointOfInterestCategory?) -> (StopKind, String, Int) {
        switch category {
        case .museum?: (.sight, String(localized: "Müze"), 120)
        case .park?, .nationalPark?: (.activity, String(localized: "Park / bahçe"), 60)
        case .zoo?, .aquarium?: (.activity, String(localized: "Hayvanat bahçesi / akvaryum"), 180)
        case .amusementPark?: (.activity, String(localized: "Tema parkı"), 240)
        case .theater?: (.activity, String(localized: "Tiyatro"), 120)
        default: (.sight, String(localized: "Gezilecek yer"), 75)
        }
    }
}

// MARK: - Metin okuma

/// Görüntüdeki metni cihaz üzerinde satır satır okur (rezervasyon ekran görüntüleri, taranmış PDF sayfaları).
enum TextReader {
    static func lines(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) { () -> [String] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["tr-TR", "en-US", "de-DE", "fr-FR", "it-IT", "es-ES", "pt-PT"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            guard (try? handler.perform([request])) != nil else { return [] }
            return ReceiptReader.rows(from: request.results ?? [])
        }.value
    }
}

// MARK: - Yol süreleri

/// İki durak arası yürüme ve toplu taşıma süresi (Apple Haritalar tahmini). Sonuçlar bellekte tutulur.
@MainActor
final class TravelTimeService {
    static let shared = TravelTimeService()

    struct Times: Equatable {
        var walkingMinutes: Int?
        var transitMinutes: Int?
    }

    private var cache: [String: Times] = [:]
    private var inFlight: [String: Task<Times, Never>] = [:]

    func times(from: Coordinate, to: Coordinate) async -> Times {
        let key = String(format: "%.5f,%.5f>%.5f,%.5f", from.latitude, from.longitude, to.latitude, to.longitude)
        if let cached = cache[key] { return cached }
        if let running = inFlight[key] { return await running.value }
        let task = Task { () -> Times in
            async let walking = Self.eta(from: from, to: to, type: .walking)
            async let transit = Self.eta(from: from, to: to, type: .transit)
            return Times(walkingMinutes: await walking, transitMinutes: await transit)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        // Hiçbiri gelmediyse (ağ yok) önbelleğe alma; sonra yeniden denensin.
        if result.walkingMinutes != nil || result.transitMinutes != nil { cache[key] = result }
        return result
    }

    private static func eta(from: Coordinate, to: Coordinate, type: MKDirectionsTransportType) async -> Int? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: from.latitude,
                                                                                            longitude: from.longitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: to.latitude,
                                                                                                 longitude: to.longitude)))
        request.transportType = type
        guard let response = try? await MKDirections(request: request).calculateETA() else { return nil }
        return max(1, Int((response.expectedTravelTime / 60).rounded()))
    }
}
