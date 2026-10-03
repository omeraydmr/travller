import Foundation

/// Gidiş öncesi yapılacak bir iş (valizden farklı: eşya değil, görev).
public struct ChecklistItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var note: String
    /// Gidişten kaç gün önce yapılmalı; nil ise tarihsiz.
    public var daysBefore: Int?
    public var isDone: Bool
    /// Öneriden eklendiyse önerinin anahtarı (aynı öneri tekrar gösterilmez).
    public var key: String?
    /// Kullanıcı öneriden gelen başlık ya da notu değiştirdi mi; değiştirmediyse metin cihazın dilinde gösterilir.
    public var textEdited: Bool?

    public init(id: UUID = UUID(), title: String, note: String = "", daysBefore: Int? = nil, isDone: Bool = false,
                key: String? = nil) {
        self.id = id
        self.title = title
        self.note = note
        self.daysBefore = daysBefore
        self.isDone = isDone
        self.key = key
    }
}

/// Kural tabanlı gidiş öncesi öneriler (yapay zekâ kullanmaz).
public enum DepartureChecklist {
    public struct Suggestion: Hashable, Sendable {
        public var key: String
        public var title: String
        public var note: String
        public var daysBefore: Int

        public func item() -> ChecklistItem {
            ChecklistItem(title: title, note: note, daysBefore: daysBefore, key: key)
        }
    }

    /// Seyahate göre önerilenler; listede zaten olanlar (anahtara göre) çıkarılır. Yakın tarihliler önce.
    public static func suggestions(for trip: Trip) -> [Suggestion] {
        let existing = Set(trip.checklistItems.compactMap(\.key))
        return all(for: trip).filter { !existing.contains($0.key) }.sorted { $0.daysBefore > $1.daysBefore }
    }

    /// Öneriden gelen ve kullanıcının değiştirmediği madde, cihazın dilinde (kayıtta eklendiği dildeki metin durur).
    public static func displayText(of item: ChecklistItem, in trip: Trip) -> (title: String, note: String) {
        guard let key = item.key, item.textEdited != true,
              let suggestion = all(for: trip).first(where: { $0.key == key }) else { return (item.title, item.note) }
        return (suggestion.title, suggestion.note)
    }

    /// Seyahat için geçerli tüm öneriler (listede olsun olmasın).
    static func all(for trip: Trip) -> [Suggestion] {
        let countries = trip.countryCodes
        var result: [Suggestion] = []

        if countries.contains(where: { $0 != "TR" }) {
            result.append(Suggestion(key: "exit-fee", title: String(localized: "Yurt dışı çıkış harç pulu"),
                                     note: String(localized: "Türkiye'den çıkışta gerekir; e-Devlet, banka ya da vergi dairesinden pasaport numarasıyla alınır."),
                                     daysBefore: 7))
            result.append(Suggestion(key: "roaming", title: String(localized: "Yurt dışı internet paketi ya da eSIM"),
                                     note: String(localized: "Operatörün yurt dışı paketi ya da varış ülkesi için eSIM; hat yurt dışı aramaya açık olsun."),
                                     daysBefore: 3))
            result.append(Suggestion(key: "cards", title: String(localized: "Kartları yurt dışı kullanıma aç"),
                                     note: String(localized: "İnternet ve yurt dışı harcama izni, temassız ödeme ve kart limitleri."),
                                     daysBefore: 3))
        }
        if trip.currency.uppercased() != "TRY" {
            result.append(Suggestion(key: "cash", title: String(localized: "Biraz nakit \(trip.currency.uppercased())"),
                                     note: String(localized: "Ulaşım, bahşiş ve kart geçmeyen yerler için küçük miktar."), daysBefore: 2))
        }
        let isSchengen = countries.contains(where: VisaRules.schengenCountries.contains)
        let needsVisa = countries.contains { VisaRules.requiresVisa(countryCode: $0, members: trip.members) }
        if isSchengen || needsVisa {
            result.append(Suggestion(key: "insurance", title: String(localized: "Seyahat sağlık sigortası"),
                                     note: needsVisa ? String(localized: "Vize başvurusunda da istenir; seyahatin tüm günlerini kapsamalı.")
                                                     : String(localized: "Seyahatin tüm günlerini kapsamalı; poliçeyi Belge kasasına ekle."),
                                     daysBefore: needsVisa ? 30 : 7))
        }
        if needsVisa, (trip.visaApplications ?? []).allSatisfy({ $0.status != .approved }) {
            result.append(Suggestion(key: "visa", title: String(localized: "Vize başvurusu"),
                                     note: String(localized: "Randevular dolabilir; Vize sekmesinden başvuruyu takip et."), daysBefore: 45))
        }
        if !trip.flights.isEmpty {
            result.append(Suggestion(key: "check-in", title: String(localized: "Online check-in"),
                                     note: String(localized: "Çoğu havayolunda kalkıştan 24–48 saat önce açılır; biniş kartını Wallet'a ekle."),
                                     daysBefore: 1))
        }
        if trip.stops.contains(where: { $0.coordinate != nil }) {
            result.append(Suggestion(key: "offline-maps", title: String(localized: "Haritaları çevrimdışı kaydet"),
                                     note: String(localized: "Plan sekmesinde \"Kaydet\"; varışta internet olmasa da rota açılır."), daysBefore: 1))
        }
        result.append(Suggestion(key: "documents", title: String(localized: "Pasaport ve belgelerin kopyası"),
                                 note: String(localized: "Pasaport, bilet ve sigortanın fotoğrafını Belge kasasına ekle."), daysBefore: 7))
        result.append(Suggestion(key: "home", title: String(localized: "Evden çıkmadan son kontrol"),
                                 note: String(localized: "Ocak, su, priz, pencereler, çöp ve anahtar."), daysBefore: 0))

        return result
    }

    /// Maddenin son günü (gidiş gününden `daysBefore` gün önce).
    public static func dueDate(of item: ChecklistItem, in trip: Trip, calendar: Calendar = .current) -> Date? {
        guard let days = item.daysBefore else { return nil }
        return calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: trip.startDate))
    }

    /// Süresi geçmiş ve yapılmamış mı.
    public static func isOverdue(_ item: ChecklistItem, in trip: Trip, now: Date = Date(),
                                 calendar: Calendar = .current) -> Bool {
        guard !item.isDone, let due = dueDate(of: item, in: trip, calendar: calendar) else { return false }
        return calendar.startOfDay(for: now) > due
    }

    /// Yapılmamışlar önce (son günü yakın olan önce), yapılanlar sonda.
    public static func sorted(_ items: [ChecklistItem], in trip: Trip, calendar: Calendar = .current) -> [ChecklistItem] {
        items.sorted { lhs, rhs in
            if lhs.isDone != rhs.isDone { return !lhs.isDone }
            let l = dueDate(of: lhs, in: trip, calendar: calendar) ?? .distantFuture
            let r = dueDate(of: rhs, in: trip, calendar: calendar) ?? .distantFuture
            return l != r ? l < r : lhs.title < rhs.title
        }
    }
}
