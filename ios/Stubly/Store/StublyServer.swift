import Foundation

/// Stubly sunucusu (bkz. depodaki `server/`): topluluk öneri havuzu. `STUBLY_SERVER_HOST` boşsa kapalıdır.
enum StublyServer {
    static var baseURL: URL? {
        guard let host = info("StublyServerHost") else { return nil }
        return URL(string: host.hasPrefix("http") ? host : "https://\(host)")
    }

    static var isConfigured: Bool { baseURL != nil }

    static var apiKey: String? { info("StublyServerKey") }

    private static func info(_ key: String) -> String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces)
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}
