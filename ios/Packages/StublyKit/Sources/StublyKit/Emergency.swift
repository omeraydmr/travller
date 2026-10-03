import Foundation

/// Kişinin acil durum bilgileri. Yalnızca bu cihazda saklanır, seyahat ekibiyle paylaşılmaz.
public struct EmergencyInfo: Codable, Hashable, Sendable {
    public var bloodType: String
    public var allergens: [Allergen]
    /// Listede olmayan alerjiler (Türkçe, serbest metin).
    public var otherAllergies: String
    public var medications: String
    public var contactName: String
    public var contactPhone: String
    /// Sigortanın 7/24 yardım hattı.
    public var insurancePhone: String

    public init(bloodType: String = "", allergens: [Allergen] = [], otherAllergies: String = "", medications: String = "",
                contactName: String = "", contactPhone: String = "", insurancePhone: String = "") {
        self.bloodType = bloodType
        self.allergens = allergens
        self.otherAllergies = otherAllergies
        self.medications = medications
        self.contactName = contactName
        self.contactPhone = contactPhone
        self.insurancePhone = insurancePhone
    }

    public var isEmpty: Bool {
        bloodType.isEmpty && allergens.isEmpty && otherAllergies.isEmpty && medications.isEmpty
            && contactName.isEmpty && contactPhone.isEmpty && insurancePhone.isEmpty
    }
}

/// Alerji kartında yerel dile çevrilebilen yaygın alerjenler.
public enum Allergen: String, Codable, CaseIterable, Hashable, Sendable {
    case peanut, treeNuts, gluten, milk, egg, shellfish, fish, soy, sesame, penicillin
}

/// Alerji kartı metinleri: "Alerjim var:" ve alerjen adları. Desteklenmeyen dilde İngilizce kullanılır.
public enum AllergyCard {
    public struct Phrase: Hashable, Sendable {
        /// ISO 639-1 dil kodu.
        public var language: String
        public var heading: String
        public var items: [String]
    }

    public static let supportedLanguages = ["en", "de", "fr", "es", "it", "pt", "ja"]

    /// Ülkede konuşulan (desteklenen) dil; yoksa nil.
    public static func language(forCountry countryCode: String) -> String? {
        switch countryCode.uppercased() {
        case "DE", "AT", "CH", "LI": "de"
        case "FR", "BE", "LU", "MC": "fr"
        case "ES", "MX", "AR", "CL", "CO", "PE", "UY": "es"
        case "IT", "SM", "VA": "it"
        case "PT", "BR": "pt"
        case "JP": "ja"
        case "GB", "IE", "US", "CA", "AU", "NZ", "MT", "SG": "en"
        default: nil
        }
    }

    /// Kartta gösterilecek diller: varış ülkesinin dili ve İngilizce (aynıysa bir kez).
    public static func languages(forCountry countryCode: String) -> [String] {
        let local = language(forCountry: countryCode)
        return local == nil || local == "en" ? ["en"] : [local!, "en"]
    }

    public static func phrase(_ allergens: [Allergen], language: String) -> Phrase? {
        guard let heading = headings[language] else { return nil }
        return Phrase(language: language, heading: heading, items: allergens.compactMap { names[$0]?[language] })
    }

    public static func turkishName(_ allergen: Allergen) -> String {
        names[allergen]?["tr"] ?? allergen.rawValue
    }

    static let headings: [String: String] = [
        "en": "I am allergic to:",
        "de": "Ich bin allergisch gegen:",
        "fr": "Je suis allergique à :",
        "es": "Soy alérgico/a a:",
        "it": "Sono allergico/a a:",
        "pt": "Sou alérgico/a a:",
        "ja": "私は次のものにアレルギーがあります：",
    ]

    static let names: [Allergen: [String: String]] = [
        .peanut: ["tr": "Yer fıstığı", "en": "peanuts", "de": "Erdnüsse", "fr": "arachides", "es": "cacahuetes",
                  "it": "arachidi", "pt": "amendoim", "ja": "ピーナッツ"],
        .treeNuts: ["tr": "Kuruyemiş (fındık, ceviz, badem…)", "en": "tree nuts", "de": "Schalenfrüchte (Nüsse)",
                    "fr": "fruits à coque", "es": "frutos secos", "it": "frutta a guscio", "pt": "frutos de casca rija",
                    "ja": "ナッツ類"],
        .gluten: ["tr": "Gluten", "en": "gluten", "de": "Gluten", "fr": "gluten", "es": "gluten", "it": "glutine",
                  "pt": "glúten", "ja": "小麦（グルテン）"],
        .milk: ["tr": "Süt", "en": "milk", "de": "Milch", "fr": "lait", "es": "leche", "it": "latte", "pt": "leite",
                "ja": "乳製品"],
        .egg: ["tr": "Yumurta", "en": "eggs", "de": "Eier", "fr": "œufs", "es": "huevos", "it": "uova", "pt": "ovos",
               "ja": "卵"],
        .shellfish: ["tr": "Kabuklu deniz ürünleri", "en": "shellfish", "de": "Meeresfrüchte", "fr": "fruits de mer",
                     "es": "mariscos", "it": "frutti di mare", "pt": "marisco", "ja": "甲殻類・貝類"],
        .fish: ["tr": "Balık", "en": "fish", "de": "Fisch", "fr": "poisson", "es": "pescado", "it": "pesce",
                "pt": "peixe", "ja": "魚"],
        .soy: ["tr": "Soya", "en": "soy", "de": "Soja", "fr": "soja", "es": "soja", "it": "soia", "pt": "soja",
               "ja": "大豆"],
        .sesame: ["tr": "Susam", "en": "sesame", "de": "Sesam", "fr": "sésame", "es": "sésamo", "it": "sesamo",
                  "pt": "sésamo", "ja": "ごま"],
        .penicillin: ["tr": "Penisilin", "en": "penicillin", "de": "Penicillin", "fr": "pénicilline",
                      "es": "penicilina", "it": "penicillina", "pt": "penicilina", "ja": "ペニシリン"],
    ]
}

/// Ülkelere göre acil numaralar. Elle derlenmiştir; seyahatten önce doğrulanmalı.
public enum EmergencyNumbers {
    public struct Numbers: Hashable, Sendable {
        /// Tek genel acil numara (varsa).
        public var general: String?
        public var police: String?
        public var ambulance: String?
        public var fire: String?
    }

    /// T.C. Dışişleri Bakanlığı Konsolosluk Çağrı Merkezi (7/24).
    public static let consularCallCenter = "+90 312 292 29 29"
    /// Büyükelçilik ve konsolosluk adresleri için Dışişleri Bakanlığı sitesi.
    public static let representationsURL = URL(string: "https://www.mfa.gov.tr")!

    public static func numbers(for countryCode: String) -> Numbers? {
        let code = countryCode.uppercased()
        if let specific = table[code] { return specific }
        if europe112.contains(code) { return Numbers(general: "112") }
        return nil
    }

    /// Genel acil numarası 112 olan Avrupa ülkeleri (AB, AEA, İsviçre ve komşuları).
    static let europe112: Set<String> = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU",
        "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "IS", "LI", "NO", "CH", "MC", "SM", "AL", "BA", "ME",
        "MK", "RS", "MD", "UA", "GE", "AM",
    ]

    static let table: [String: Numbers] = [
        "GB": Numbers(general: "999 / 112"),
        "US": Numbers(general: "911"), "CA": Numbers(general: "911"), "MX": Numbers(general: "911"),
        "AR": Numbers(general: "911"),
        "JP": Numbers(police: "110", ambulance: "119", fire: "119"),
        "KR": Numbers(police: "112", ambulance: "119", fire: "119"),
        "CN": Numbers(police: "110", ambulance: "120", fire: "119"),
        "AU": Numbers(general: "000"), "NZ": Numbers(general: "111"),
        "TH": Numbers(police: "191", ambulance: "1669", fire: "199"),
        "AE": Numbers(police: "999", ambulance: "998", fire: "997"),
        "SG": Numbers(police: "999", ambulance: "995", fire: "995"),
        "MY": Numbers(general: "999"), "IN": Numbers(general: "112"), "RU": Numbers(general: "112"),
        "BR": Numbers(police: "190", ambulance: "192", fire: "193"),
    ]
}
