import CryptoKit
import DeviceCheck
import Foundation

/// Apple App Attest: sunucuya isteklerin gerçek, değiştirilmemiş Stubly uygulamasından geldiğini kanıtlar
/// (bkz. `server/src/appattest.ts`). Cihaz bir kez anahtar üretip Apple'a onaylatır; sonraki her istekte gövde
/// bu anahtarla imzalanır. Simülatörde ve desteklemeyen cihazlarda kapalıdır; o zaman cihaz kimliği kullanılır.
@MainActor
final class AppAttestClient {
    static let shared = AppAttestClient()

    private let service = DCAppAttestService.shared
    private static let keyIDKey = "stubly.attest.keyID"
    private static let registeredKey = "stubly.attest.registered"
    private var registering: Task<Bool, Never>?

    var isSupported: Bool { service.isSupported }

    /// Gövdenin imzası için başlıklar; App Attest yoksa ya da kayıt başarısızsa nil.
    func headers(for body: Data, base: URL, apiKey: String?) async -> [String: String]? {
        guard isSupported, await ensureRegistered(base: base, apiKey: apiKey),
              let keyID = UserDefaults.standard.string(forKey: Self.keyIDKey) else { return nil }
        let hash = Data(SHA256.hash(data: body))
        do {
            let assertion = try await service.generateAssertion(keyID, clientDataHash: hash)
            return ["X-Stubly-Attest-Key": keyID, "X-Stubly-Assertion": assertion.base64EncodedString()]
        } catch {
            // Anahtar geçersizleştiyse (ör. uygulama yeniden kuruldu) yeniden kayıt.
            if (error as? DCError)?.code == .invalidKey { reset() }
            return nil
        }
    }

    private func reset() {
        UserDefaults.standard.removeObject(forKey: Self.keyIDKey)
        UserDefaults.standard.removeObject(forKey: Self.registeredKey)
    }

    /// Anahtar yoksa üretir, Apple'a onaylatıp sunucuya kaydeder (aynı anda tek kayıt).
    private func ensureRegistered(base: URL, apiKey: String?) async -> Bool {
        if UserDefaults.standard.bool(forKey: Self.registeredKey) { return true }
        if let registering { return await registering.value }
        let task = Task { await register(base: base, apiKey: apiKey) }
        registering = task
        defer { registering = nil }
        return await task.value
    }

    private func register(base: URL, apiKey: String?) async -> Bool {
        do {
            let keyID: String
            if let stored = UserDefaults.standard.string(forKey: Self.keyIDKey) {
                keyID = stored
            } else {
                keyID = try await service.generateKey()
                UserDefaults.standard.set(keyID, forKey: Self.keyIDKey)
            }
            struct Challenge: Decodable { let challenge: String }
            let challengeData = try await post(base.appendingPathComponent("attest/challenge"), body: Data("{}".utf8), apiKey: apiKey)
            let challenge = try JSONDecoder().decode(Challenge.self, from: challengeData).challenge
            let attestation = try await service.attestKey(keyID, clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))
            let body = try JSONEncoder().encode(["keyId": keyID, "attestation": attestation.base64EncodedString(), "challenge": challenge])
            _ = try await post(base.appendingPathComponent("attest/register"), body: body, apiKey: apiKey)
            UserDefaults.standard.set(true, forKey: Self.registeredKey)
            return true
        } catch {
            // Apple anahtarı reddettiyse yeni anahtarla tekrar denenebilsin.
            if (error as? DCError)?.code == .invalidKey { reset() }
            return false
        }
    }

    private func post(_ url: URL, body: Data, apiKey: String?) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "X-Stubly-Key") }
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}
