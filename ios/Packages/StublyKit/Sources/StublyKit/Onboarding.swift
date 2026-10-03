import Foundation

/// İlk açılış anketinin cevapları. Cihazda saklanır; uygulamayı kişiselleştirmek için kullanılır
/// (ör. seyahat açılınca ilk hangi sekmenin geleceği).
public struct TravelPreferences: Codable, Hashable, Sendable {
    public enum Companion: String, Codable, CaseIterable, Sendable {
        case solo, partner, friends, family
    }

    public enum Frequency: String, Codable, CaseIterable, Sendable {
        case once, fewTimes, often
    }

    /// Uygulamada en çok yardım beklenen alanlar; sıra seçim sırasıdır.
    public enum Interest: String, Codable, CaseIterable, Sendable {
        case planning, money, visa, packing, memories
    }

    public var companion: Companion?
    public var frequency: Frequency?
    public var interests: [Interest]

    public init(companion: Companion? = nil, frequency: Frequency? = nil, interests: [Interest] = []) {
        self.companion = companion
        self.frequency = frequency
        self.interests = interests
    }

    /// Seçimi aç/kapa; ilk seçilen öne çıkar.
    public mutating func toggle(_ interest: Interest) {
        if let index = interests.firstIndex(of: interest) {
            interests.remove(at: index)
        } else {
            interests.append(interest)
        }
    }

    /// Seyahat açılınca ilk gösterilecek sekme (uygulamadaki `TripSection` ham değeri).
    /// Ekip sekmesi yalnızca kalabalık seyahat edenlerde ve başka ilgi seçilmemişse öne gelir.
    public var preferredSection: String {
        if let first = interests.first {
            switch first {
            case .planning: return "plan"
            case .money: return "money"
            case .visa: return "visa"
            case .packing: return "packing"
            case .memories: return "memories"
            }
        }
        if let companion, companion == .friends || companion == .family { return "crew" }
        return "plan"
    }
}

/// İlk açılıştaki profil ("hesap") adımının doğrulaması.
public enum ProfileDraft {
    /// Boşlukları temizlenmiş ad; geçersizse nil. Varsayılan "Ben" adı kabul edilmez (kullanıcı adını yazmalı).
    public static func validName(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard trimmed.count >= 2, trimmed.count <= 40, trimmed.lowercased(with: Locale(identifier: "tr_TR")) != "ben"
        else { return nil }
        return trimmed
    }
}
