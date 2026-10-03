import Foundation

/// Tax-free (KDV iadesi) alışverişi: mağazadan form alınır, çıkışta gümrükte onaylatılır, iade gelir.
public struct TaxRefund: Codable, Hashable, Identifiable, Sendable {
    public enum Status: String, Codable, CaseIterable, Hashable, Sendable {
        /// Form mağazadan alındı, henüz onaylatılmadı.
        case formReceived
        /// Gümrükte/kiosk'ta onaylatıldı, iade bekleniyor.
        case validated
        case refunded
    }

    public var id: UUID
    public var shop: String
    public var purchaseDate: Date
    /// KDV dahil tutar; seyahat para biriminde, kuruş/cent.
    public var amount: Int
    /// Beklenen iade (aynı birimde).
    public var expectedRefund: Int
    public var status: Status
    public var note: String

    public init(id: UUID = UUID(), shop: String, purchaseDate: Date, amount: Int, expectedRefund: Int,
                status: Status = .formReceived, note: String = "") {
        self.id = id
        self.shop = shop
        self.purchaseDate = purchaseDate
        self.amount = amount
        self.expectedRefund = expectedRefund
        self.status = status
        self.note = note
    }
}

public enum TaxRefunds {
    /// Standart KDV oranları (%). Elle derlenmiştir; indirimli oranlı ürünlerde iade daha düşüktür.
    public static let vatRates: [String: Double] = [
        "AT": 20, "BE": 21, "BG": 20, "HR": 25, "CY": 19, "CZ": 21, "DK": 25, "EE": 22, "FI": 25.5, "FR": 20,
        "DE": 19, "GR": 24, "HU": 27, "IE": 23, "IT": 22, "LV": 21, "LT": 21, "LU": 17, "MT": 18, "NL": 21,
        "PL": 23, "PT": 23, "RO": 19, "SK": 23, "SI": 22, "ES": 21, "SE": 25, "NO": 25, "IS": 24, "CH": 8.1,
        "JP": 10, "KR": 10, "SG": 9, "TH": 7, "AE": 5,
    ]

    /// Turistlere KDV iadesi yapılmayan ya da tax-free'nin kaldırıldığı yerler.
    public static let unavailable: Set<String> = ["GB", "US"]

    public static func isAvailable(in countryCode: String) -> Bool {
        let code = countryCode.uppercased()
        return !unavailable.contains(code) && vatRates[code] != nil
    }

    /// Tutarın içindeki KDV'nin aracı kurum kesintisi düşülmüş tahmini iadesi.
    /// Kesinti şirkete göre değişir; varsayılan olarak KDV'nin %70'i alınır.
    public static func estimatedRefund(amount: Int, countryCode: String, keptShare: Double = 0.7) -> Int? {
        guard isAvailable(in: countryCode), let rate = vatRates[countryCode.uppercased()], amount > 0 else { return nil }
        let vat = Double(amount) * rate / (100 + rate)
        return Int((vat * keptShare).rounded())
    }

    public struct Summary: Hashable, Sendable {
        public var expected: Int
        public var refunded: Int
        /// Gümrükte onaylatılmayı bekleyen form sayısı.
        public var toValidate: Int
        /// Onaylatılmış ama iadesi gelmemiş form sayısı.
        public var awaitingPayment: Int
    }

    public static func summary(_ refunds: [TaxRefund]) -> Summary {
        Summary(expected: refunds.filter { $0.status != .refunded }.reduce(0) { $0 + $1.expectedRefund },
                refunded: refunds.filter { $0.status == .refunded }.reduce(0) { $0 + $1.expectedRefund },
                toValidate: refunds.filter { $0.status == .formReceived }.count,
                awaitingPayment: refunds.filter { $0.status == .validated }.count)
    }
}
