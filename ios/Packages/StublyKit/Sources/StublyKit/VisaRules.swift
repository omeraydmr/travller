import Foundation

/// Bir ülkeye giriş kuralı.
public enum EntryRule: Hashable, Sendable {
    case visaFree(maxDays: Int)
    case eVisa
    case visaOnArrival(maxDays: Int?)
    case visaRequired(zone: VisaZone?)
}

public struct CountryEntry: Hashable, Sendable {
    public var code: String
    /// Umuma mahsus (bordo) pasaport için kural.
    public var rule: EntryRule
    /// Hususi, hizmet ve diplomatik pasaport için farklı kurallar (yoksa bordo ile aynı).
    public var rulesByType: [PassportType: EntryRule]
    /// Dönüş tarihinden sonra pasaportun geçerli olması gereken/önerilen ay sayısı.
    public var passportValidityMonths: Int
    /// Değer yasal zorunluluk mu, yoksa genel tavsiye mi.
    public var validityIsMandatory: Bool
    /// Pasaport yerine yeni çipli kimlik kartıyla giriş mümkün mü.
    public var idCardAccepted: Bool
    public var note: String?
    /// Dışişleri Bakanlığı listesindeki resmî metin (Türkçe; yalnızca Türkçe arayüzde gösterilir).
    public var officialText: String?

    public init(code: String, rule: EntryRule, rulesByType: [PassportType: EntryRule] = [:], passportValidityMonths: Int = 6,
                validityIsMandatory: Bool = false, idCardAccepted: Bool = false, note: String? = nil, officialText: String? = nil) {
        self.code = code
        self.rule = rule
        self.rulesByType = rulesByType
        self.passportValidityMonths = passportValidityMonths
        self.validityIsMandatory = validityIsMandatory
        self.idCardAccepted = idCardAccepted
        self.note = note
        self.officialText = officialText
    }

    public func rule(for type: PassportType) -> EntryRule {
        type == .ordinary ? rule : rulesByType[type] ?? rule
    }

    /// Hususi, hizmet ve diplomatik pasaport için aynı kural.
    static func official(_ rule: EntryRule) -> [PassportType: EntryRule] {
        [.special: rule, .service: rule, .diplomatic: rule]
    }
}

/// Türk vatandaşları için pasaport türüne göre derlenmiş giriş kuralları. Kaynak: Dışişleri Bakanlığı,
/// "Türk Vatandaşlarının Tabi Olduğu Vize Uygulamaları" (mfa.gov.tr, Ekim 2026).
///
/// ÖNEMLİ: Bu veri seti elle derlenmiştir ve yayından önce ve düzenli aralıklarla
/// https://www.konsolosluk.gov.tr üzerinden doğrulanmalıdır. Uygulama her zaman resmî
/// kaynağa yönlendirir ve son gözden geçirme tarihini gösterir.
public enum VisaRules {
    public static let lastReviewed = "2026-10"
    public static let officialSourceURL = URL(string: "https://www.konsolosluk.gov.tr")!
    public static let mfaRulesURL = URL(string: "https://www.mfa.gov.tr/turk-vatandaslarinin-tabi-oldugu-vize-uygulamalari.tr.mfa")!

    /// Schengen bölgesi (29 ülke; Bulgaristan ve Romanya 2025'ten itibaren tam üye).
    public static let schengenCountries: Set<String> = [
        "AT", "BE", "BG", "HR", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IS", "IT", "LV",
        "LI", "LT", "LU", "MT", "NL", "NO", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "CH",
    ]

    /// Tüm ülkeler: Dışişleri listesinden üretilen `visa_rules.tsv` (~195 ülke), üstüne elle doğrulanmış kayıtlar
    /// (Schengen bölgesi, vize bölgeleri, pasaport geçerlilik süresi, kimlik kartıyla giriş).
    public static let entries: [String: CountryEntry] = {
        var map = loadDataset()
        for (code, entry) in curated {
            var merged = entry
            merged.officialText = map[code]?.officialText
            map[code] = merged
        }
        return map
    }()

    static func loadDataset() -> [String: CountryEntry] {
        guard let url = Bundle.module.url(forResource: "visa_rules", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var map: [String: CountryEntry] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 5, let ordinary = rule(parts[1]) else { continue }
            var byType: [PassportType: EntryRule] = [:]
            for (index, type) in [PassportType.special, .service, .diplomatic].enumerated() {
                if let rule = rule(parts[2 + index]), rule != ordinary { byType[type] = rule }
            }
            map[parts[0]] = CountryEntry(code: parts[0], rule: ordinary, rulesByType: byType,
                                         officialText: parts.count > 5 && !parts[5].isEmpty ? parts[5] : nil)
        }
        return map
    }

    /// "free:90", "evisa", "arrival:30", "arrival:", "required", "required:schengen"
    static func rule(_ text: String) -> EntryRule? {
        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let value = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "free": return .visaFree(maxDays: Int(value) ?? 90)
        case "evisa": return .eVisa
        case "arrival": return .visaOnArrival(maxDays: Int(value))
        case "required": return .visaRequired(zone: VisaZone(rawValue: value))
        default: return nil
        }
    }

    static let curated: [String: CountryEntry] = {
        var map: [String: CountryEntry] = [:]
        // Hususi, hizmet ve diplomatik pasaport Schengen ülkelerinde 180 günde 90 gün vizeden muaf.
        for code in schengenCountries {
            map[code] = CountryEntry(
                code: code, rule: .visaRequired(zone: .schengen), rulesByType: CountryEntry.official(.visaFree(maxDays: 90)),
                passportValidityMonths: 3, validityIsMandatory: true,
                note: String(localized: "Schengen: 180 gün içinde en fazla 90 gün. Pasaport son 10 yıl içinde verilmiş olmalı."))
        }
        // Bulgaristan: hizmet ve diplomatik pasaport 30 güne kadar muaf.
        map["BG"]?.rulesByType = [.special: .visaFree(maxDays: 90), .service: .visaFree(maxDays: 30), .diplomatic: .visaFree(maxDays: 30)]
        let others: [CountryEntry] = [
            CountryEntry(code: "GB", rule: .visaRequired(zone: .uk)),
            CountryEntry(code: "US", rule: .visaRequired(zone: .us)),
            CountryEntry(code: "CA", rule: .visaRequired(zone: .canada)),
            CountryEntry(code: "JP", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "GE", rule: .visaFree(maxDays: 365), idCardAccepted: true),
            CountryEntry(code: "AZ", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "RS", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "BA", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "ME", rule: .visaFree(maxDays: 30), rulesByType: CountryEntry.official(.visaFree(maxDays: 90))),
            CountryEntry(code: "MK", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "AL", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "XK", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "MA", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "TN", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "BR", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "AR", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "MY", rule: .visaOnArrival(maxDays: 90), rulesByType: CountryEntry.official(.visaFree(maxDays: 90)),
                         note: String(localized: "Bordo pasaporta girişte ücretsiz 90 günlük turist vizesi verilir.")),
            CountryEntry(code: "SG", rule: .visaFree(maxDays: 30)),
            CountryEntry(code: "ID", rule: .visaFree(maxDays: 30), note: String(localized: "Girişten önce internet üzerinden varış bildirimi yapılmalı.")),
            CountryEntry(code: "AM", rule: .eVisa, note: String(localized: "Tüm pasaport türleri vizeye tabi; e-vize alınabilir.")),
        ]
        for entry in others { map[entry.code] = entry }
        return map
    }()

    public static func entry(for countryCode: String) -> CountryEntry? {
        entries[countryCode.uppercased()]
    }

    /// Ekipten herhangi birinin pasaport türüne göre vize gerekiyor mu (pasaport bilgisi girilmemiş kişi bordo sayılır).
    public static func requiresVisa(countryCode: String, members: [Member]) -> Bool {
        guard let entry = entry(for: countryCode) else { return false }
        // Pasaport bilgisi girilmemiş kişi bordo sayılır.
        let types = members.map { $0.passport?.type ?? .ordinary }
        return (types.isEmpty ? [.ordinary] : types).contains { type in
            if case .visaRequired = entry.rule(for: type) { return true }
            return false
        }
    }
}

// MARK: - Assessment

public enum VisaStatus: Hashable, Sendable {
    case domestic
    case notRequired(maxDays: Int)
    case eVisa
    case onArrival(maxDays: Int?)
    case required(zone: VisaZone?)
    case coveredByHeldVisa(zone: VisaZone, until: Date)
    case noPassport
    case unknown
}

public enum VisaWarning: Hashable, Sendable {
    /// Pasaport seyahat bitmeden sona eriyor.
    case passportExpiresDuringTrip(expiresOn: Date)
    /// Pasaport, dönüşten sonra gereken/önerilen süre kadar geçerli değil.
    case passportValidityShort(months: Int, mandatory: Bool, expiresOn: Date)
    /// Seyahat süresi vizesiz kalış limitini aşıyor.
    case stayExceedsLimit(maxDays: Int, tripDays: Int)
    /// Eldeki vize seyahat bitmeden sona eriyor.
    case heldVisaExpiresDuringTrip(zone: VisaZone, until: Date)
    /// Schengen 90/180 kuralı aşılıyor: ilk aşım günü, en geç çıkış günü, kural dışı gün sayısı.
    case schengenOverstay(firstDay: Date, latestExit: Date?, days: Int)
}

public struct VisaAssessment: Hashable, Sendable {
    public var status: VisaStatus
    public var warnings: [VisaWarning]
    public var entry: CountryEntry?

    /// Yolcunun harekete geçmesi gerekiyor mu (vize başvurusu, e-vize, pasaport yenileme).
    public var needsAction: Bool {
        switch status {
        case .required, .eVisa, .noPassport: return true
        default: return warnings.contains { warning in
            switch warning {
            case .passportExpiresDuringTrip, .stayExceedsLimit, .heldVisaExpiresDuringTrip, .schengenOverstay: return true
            case let .passportValidityShort(_, mandatory, _): return mandatory
            }
        }
        }
    }
}

public enum VisaAdvisor {
    /// - Parameter otherSchengenStays: aynı kişinin diğer Schengen kalışları (90/180 hesabı için).
    public static func assess(countryCode: String, passport: Passport?, tripStart: Date, tripEnd: Date,
                              otherSchengenStays: [Schengen.Stay] = [],
                              calendar: Calendar = .current) -> VisaAssessment {
        let code = countryCode.uppercased()
        guard let passport else { return VisaAssessment(status: .noPassport, warnings: [], entry: nil) }
        if passport.nationality.uppercased() == code {
            return VisaAssessment(status: .domestic, warnings: [], entry: nil)
        }
        guard passport.nationality.uppercased() == "TR", let entry = VisaRules.entry(for: code)
        else {
            return VisaAssessment(status: .unknown, warnings: passportWarnings(passport: passport, entry: nil,
                                                                               tripEnd: tripEnd, calendar: calendar),
                                  entry: nil)
        }

        var warnings: [VisaWarning] = []
        let status: VisaStatus
        switch entry.rule(for: passport.type) {
        case let .visaFree(maxDays):
            status = .notRequired(maxDays: maxDays)
            let tripDays = (calendar.dateComponents([.day], from: calendar.startOfDay(for: tripStart),
                                                    to: calendar.startOfDay(for: tripEnd)).day ?? 0) + 1
            if tripDays > maxDays {
                warnings.append(.stayExceedsLimit(maxDays: maxDays, tripDays: tripDays))
            }
        case .eVisa:
            status = .eVisa
        case let .visaOnArrival(maxDays):
            status = .onArrival(maxDays: maxDays)
        case let .visaRequired(zone):
            let held = passport.heldVisas
                .filter { $0.zone == zone && $0.validUntil >= tripStart }
                .max { $0.validUntil < $1.validUntil }
            if let zone, let held {
                status = .coveredByHeldVisa(zone: zone, until: held.validUntil)
                if calendar.startOfDay(for: held.validUntil) < calendar.startOfDay(for: tripEnd) {
                    warnings.append(.heldVisaExpiresDuringTrip(zone: zone, until: held.validUntil))
                }
            } else {
                status = .required(zone: zone)
            }
        }

        if Schengen.isSchengen(code) {
            let evaluation = Schengen.evaluate(Schengen.Stay(start: tripStart, end: tripEnd, label: ""),
                                               others: otherSchengenStays, calendar: calendar)
            if let first = evaluation.firstOverstayDay {
                warnings.append(.schengenOverstay(firstDay: first, latestExit: evaluation.latestExit,
                                                  days: evaluation.overstayDays))
            }
        }
        warnings += passportWarnings(passport: passport, entry: entry, tripEnd: tripEnd, calendar: calendar)
        return VisaAssessment(status: status, warnings: warnings, entry: entry)
    }

    static func passportWarnings(passport: Passport, entry: CountryEntry?, tripEnd: Date,
                                 calendar: Calendar) -> [VisaWarning] {
        if calendar.startOfDay(for: passport.expiresOn) < calendar.startOfDay(for: tripEnd) {
            return [.passportExpiresDuringTrip(expiresOn: passport.expiresOn)]
        }
        let months = entry?.passportValidityMonths ?? 6
        let mandatory = entry?.validityIsMandatory ?? false
        if let required = calendar.date(byAdding: .month, value: months, to: tripEnd), passport.expiresOn < required {
            return [.passportValidityShort(months: months, mandatory: mandatory, expiresOn: passport.expiresOn)]
        }
        return []
    }
}
