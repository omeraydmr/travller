import Foundation
import StublyKit

/// Topluluk öneri havuzu (Stubly sunucusu, bkz. `server/src/community.ts`): biten seyahatlerden onayla
/// paylaşılan yerler ve aynı gün art arda gidilen yer çiftleri. Sunucu, en az üç farklı kişinin gittiği
/// yerleri ve geçişleri döndürür; kişi, tarih ya da tam rota saklanmaz.
@MainActor
final class CommunityService {
    static let shared = CommunityService()

    enum Choice: String { case shared, declined }

    var isConfigured: Bool { StublyServer.isConfigured }

    private static let contributorKey = "stubly.community.contributor"
    private static let choicesKey = "stubly.community.choices"

    /// Cihaza özel rastgele kimlik; sunucu bunu tuzlayıp özetler, yalnızca kota ve "aynı kişi" sayımı için.
    private var contributorID: String {
        if let id = UserDefaults.standard.string(forKey: Self.contributorKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: Self.contributorKey)
        return id
    }

    /// Seyahat için verilen karar (cihaza özel; ekibin diğer üyeleri kendileri karar verir).
    func choice(for trip: Trip) -> Choice? {
        let choices = UserDefaults.standard.dictionary(forKey: Self.choicesKey) as? [String: String]
        return choices?[trip.id.uuidString].flatMap(Choice.init)
    }

    func setChoice(_ choice: Choice, for trip: Trip) {
        var choices = UserDefaults.standard.dictionary(forKey: Self.choicesKey) as? [String: String] ?? [:]
        choices[trip.id.uuidString] = choice.rawValue
        UserDefaults.standard.set(choices, forKey: Self.choicesKey)
    }

    enum Failure: Error { case notConfigured, rejected(Int) }

    func contribute(_ contribution: CommunityPlaces.Contribution) async throws {
        try await send("places/contribute", body: JSONEncoder().encode(contribution))
    }

    enum ReportReason: String, CaseIterable, Identifiable {
        case wrong, closed, spam, offensive
        var id: String { rawValue }
        var title: String {
            switch self {
            case .wrong: String(localized: "Yanlış bilgi ya da konum")
            case .closed: String(localized: "Kapanmış")
            case .spam: String(localized: "Reklam ya da spam")
            case .offensive: String(localized: "Uygunsuz")
            }
        }
    }

    /// Topluluk yerini bildirir; yeterince bildirilen yer önerilerden düşer.
    func report(_ suggestion: PlaceSuggestions.Suggestion, reason: ReportReason) async throws {
        guard let id = Int(suggestion.id.replacingOccurrences(of: "community/", with: "")) else { return }
        struct Report: Encodable { let placeId: Int; let reason: String }
        try await send("places/report", body: JSONEncoder().encode(Report(placeId: id, reason: reason.rawValue)))
    }

    /// İmzalı gönderim: App Attest varsa gövde cihaz anahtarıyla imzalanır, yoksa cihaz kimliği gider.
    private func send(_ path: String, body: Data) async throws {
        guard var post = request(path), let base = StublyServer.baseURL else { throw Failure.notConfigured }
        post.httpMethod = "POST"
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        post.httpBody = body
        if let headers = await AppAttestClient.shared.headers(for: body, base: base, apiKey: StublyServer.apiKey) {
            for (field, value) in headers { post.setValue(value, forHTTPHeaderField: field) }
        } else {
            post.setValue(contributorID, forHTTPHeaderField: "X-Stubly-Contributor")
        }
        let (_, response) = try await URLSession.shared.data(for: post)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.rejected(status) }
    }

    /// Yakındaki topluluk yerleri; sunucu yoksa ya da ulaşılamazsa boş.
    func nearby(_ center: Coordinate) async -> [PlaceSuggestions.Suggestion] {
        await places("places/nearby", center)
    }

    /// Bu yerden sonra gezginlerin aynı gün genelde gittiği yerler.
    func next(after point: Coordinate) async -> [PlaceSuggestions.Suggestion] {
        await places("places/next", point)
    }

    private func places(_ path: String, _ point: Coordinate) async -> [PlaceSuggestions.Suggestion] {
        guard var request = request(path), var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        else { return [] }
        components.queryItems = [.init(name: "lat", value: String(format: "%.4f", point.latitude)),
                                 .init(name: "lon", value: String(format: "%.4f", point.longitude))]
        request.url = components.url
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return CommunityPlaces.decode(data)
    }

    private func request(_ path: String) -> URLRequest? {
        guard let baseURL = StublyServer.baseURL else { return nil }
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 10)
        if let key = StublyServer.apiKey { request.setValue(key, forHTTPHeaderField: "X-Stubly-Key") }
        return request
    }
}
