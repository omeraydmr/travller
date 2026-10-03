import Foundation

// MARK: - Enums

/// Harcama ve bütçe kategorileri. Renkleri tasarım dilinde sabittir.
public enum SpendCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case stays, transport, food, activities, other
}

public enum MemberRole: String, Codable, CaseIterable, Hashable, Sendable {
    case owner, editor, viewer
}

/// Türk pasaport türleri: umuma mahsus (bordo), hususi (yeşil), hizmet (gri), diplomatik (siyah).
/// Vize kuralları türe göre değişir (bkz. `VisaRules`).
public enum PassportType: String, Codable, CaseIterable, Hashable, Sendable {
    case ordinary, special, service, diplomatic
}

/// Kullanıcının elinde olabilecek ve başka ülkelere girişte de işe yarayan vize bölgeleri.
public enum VisaZone: String, Codable, CaseIterable, Hashable, Sendable {
    case schengen, uk, us, canada
}

public enum StopKind: String, Codable, CaseIterable, Hashable, Sendable {
    case sight, food, activity, transport, stay
}

public enum TripStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case draft, planned
}

// MARK: - People

public struct HeldVisa: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var zone: VisaZone
    public var validUntil: Date
    public var multipleEntry: Bool

    public init(id: UUID = UUID(), zone: VisaZone, validUntil: Date, multipleEntry: Bool = true) {
        self.id = id
        self.zone = zone
        self.validUntil = validUntil
        self.multipleEntry = multipleEntry
    }
}

public struct Passport: Codable, Hashable, Sendable {
    /// ISO 3166-1 alpha-2, ör. "TR".
    public var nationality: String
    public var type: PassportType
    public var expiresOn: Date
    public var heldVisas: [HeldVisa]

    public init(nationality: String = "TR", type: PassportType = .ordinary, expiresOn: Date, heldVisas: [HeldVisa] = []) {
        self.nationality = nationality
        self.type = type
        self.expiresOn = expiresOn
        self.heldVisas = heldVisas
    }
}

public struct Member: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var role: MemberRole
    /// Avatar ve kişi bazlı grafiklerde kullanılan palet sırası.
    public var colorIndex: Int
    public var passport: Passport?
    /// Hesaplaşmada para gönderilecek IBAN (isteğe bağlı).
    public var iban: String?
    /// Kişinin iCloud kullanıcı kaydı adı; paylaşımdaki katılımcıyla eşleştirip yetkiyi iCloud'a da uygulamak için.
    /// Paylaşıma katılan kişi kendini ekibe eklerken yazılır; elle eklenen kişilerde nil'dir.
    public var cloudUserID: String?

    public init(id: UUID = UUID(), name: String, role: MemberRole = .editor, colorIndex: Int = 0, passport: Passport? = nil,
                iban: String? = nil, cloudUserID: String? = nil) {
        self.id = id
        self.name = name
        self.role = role
        self.colorIndex = colorIndex
        self.passport = passport
        self.iban = iban
        self.cloudUserID = cloudUserID
    }

    public var initial: String {
        guard let first = name.trimmingCharacters(in: .whitespaces).first else { return "?" }
        return String(first).uppercased(with: Locale(identifier: "tr_TR"))
    }
}

// MARK: - Plan

public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct Destination: Codable, Hashable, Sendable {
    /// ISO 3166-1 alpha-2, ör. "PT".
    public var countryCode: String
    public var city: String
    public var coordinate: Coordinate?

    public init(countryCode: String, city: String, coordinate: Coordinate? = nil) {
        self.countryCode = countryCode
        self.city = city
        self.coordinate = coordinate
    }
}

public struct FlightSegment: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var flightNumber: String
    public var fromCode: String
    public var fromCity: String
    public var toCode: String
    public var toCity: String
    public var departure: Date
    public var arrival: Date
    /// Kalkış ve varış saatleri havalimanının yerel saatinde gösterilir (IANA kimliği, ör. "Europe/Lisbon").
    public var departureTimeZone: String?
    public var arrivalTimeZone: String?
    public var gate: String?
    public var seat: String?

    public init(id: UUID = UUID(), flightNumber: String, fromCode: String, fromCity: String, toCode: String, toCity: String,
                departure: Date, arrival: Date, departureTimeZone: String? = nil, arrivalTimeZone: String? = nil,
                gate: String? = nil, seat: String? = nil) {
        self.id = id
        self.flightNumber = flightNumber
        self.fromCode = fromCode
        self.fromCity = fromCity
        self.toCode = toCode
        self.toCity = toCity
        self.departure = departure
        self.arrival = arrival
        self.departureTimeZone = departureTimeZone
        self.arrivalTimeZone = arrivalTimeZone
        self.gate = gate
        self.seat = seat
    }

    public var durationMinutes: Int {
        max(0, Int(arrival.timeIntervalSince(departure) / 60))
    }
}

/// Uçuş saatleri havalimanının yerel saatiyle girilir ve gösterilir; cihazın saat dilimi farklı olabilir.
public enum FlightClock {
    /// Tarih seçicide görünen "duvar saatini" (cihaz takviminde) havalimanı saat diliminde gerçek ana çevirir.
    /// Örn. cihaz İstanbul'da, seçicide 10:15 → Lizbon'da 10:15 olan an.
    public static func instant(wallClock: Date, timeZone: String?, device: Calendar = .current) -> Date {
        guard let identifier = timeZone, let zone = TimeZone(identifier: identifier) else { return wallClock }
        let parts = device.dateComponents([.year, .month, .day, .hour, .minute], from: wallClock)
        var airport = Calendar(identifier: .gregorian)
        airport.timeZone = zone
        return airport.date(from: parts) ?? wallClock
    }

    /// `instant`'ın tersi: gerçek anı, havalimanı saatini gösteren cihaz-takvimi tarihine çevirir (seçici için).
    public static func wallClock(for instant: Date, timeZone: String?, device: Calendar = .current) -> Date {
        guard let identifier = timeZone, let zone = TimeZone(identifier: identifier) else { return instant }
        var airport = Calendar(identifier: .gregorian)
        airport.timeZone = zone
        let parts = airport.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
        return device.date(from: parts) ?? instant
    }
}

public struct Stop: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Durağın ait olduğu gün (gün başlangıcı).
    public var day: Date
    public var order: Int
    public var name: String
    public var kind: StopKind
    /// Gece yarısından itibaren dakika; nil ise saat belirlenmemiş.
    public var startMinutes: Int?
    public var durationMinutes: Int
    public var coordinate: Coordinate?
    public var note: String
    /// OpenStreetMap `opening_hours` biçiminde açılış saatleri.
    public var openingHours: String?
    /// Açılış saatleri bir kez arandıysa true (bulunamasa bile tekrar aranmaz).
    public var openingHoursLookedUp: Bool?

    public init(id: UUID = UUID(), day: Date, order: Int, name: String, kind: StopKind, startMinutes: Int? = nil,
                durationMinutes: Int = 60, coordinate: Coordinate? = nil, note: String = "", openingHours: String? = nil) {
        self.id = id
        self.day = day
        self.order = order
        self.name = name
        self.kind = kind
        self.startMinutes = startMinutes
        self.durationMinutes = durationMinutes
        self.coordinate = coordinate
        self.note = note
        self.openingHours = openingHours
    }
}

// MARK: - Money

public struct Expense: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    /// Seyahat para biriminde, kuruş/cent cinsinden.
    public var amount: Int
    public var category: SpendCategory
    public var paidBy: UUID
    public var splitAmong: [UUID]
    public var date: Date
    /// Hesaplaşma ödemesi; bütçeye sayılmaz, sadece bakiyeleri etkiler.
    public var isTransfer: Bool
    /// Farklı para birimiyle girildiyse orijinal tutar (kuruş) ve para birimi; `amount` seyahat para birimindedir.
    public var originalAmount: Int?
    public var originalCurrency: String?
    /// Makbuz fotoğrafının dosya adı.
    public var receiptPhoto: String?
    /// Eşit bölünmeyen harcamalarda kişi başı paylar (kuruş, seyahat para birimi); toplamı `amount`'a eşittir.
    public var shares: [UUID: Int]?

    public init(id: UUID = UUID(), title: String, amount: Int, category: SpendCategory, paidBy: UUID, splitAmong: [UUID],
                date: Date, isTransfer: Bool = false, originalAmount: Int? = nil, originalCurrency: String? = nil,
                receiptPhoto: String? = nil, shares: [UUID: Int]? = nil) {
        self.id = id
        self.title = title
        self.amount = amount
        self.category = category
        self.paidBy = paidBy
        self.splitAmong = splitAmong
        self.date = date
        self.isTransfer = isTransfer
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
        self.receiptPhoto = receiptPhoto
        self.shares = shares
    }
}

public struct BudgetLine: Codable, Hashable, Sendable {
    public var category: SpendCategory
    /// Kuruş/cent cinsinden limit.
    public var limit: Int

    public init(category: SpendCategory, limit: Int) {
        self.category = category
        self.limit = limit
    }
}

// MARK: - Packing

public struct PackingItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var assignee: UUID?
    public var isPacked: Bool

    public init(id: UUID = UUID(), title: String, assignee: UUID? = nil, isPacked: Bool = false) {
        self.id = id
        self.title = title
        self.assignee = assignee
        self.isPacked = isPacked
    }
}

// MARK: - Visa application

/// Vize gereken bir yolcu için başvuru takibi.
public struct VisaApplication: Codable, Hashable, Identifiable, Sendable {
    public enum Status: String, Codable, CaseIterable, Hashable, Sendable {
        case preparing, appointmentBooked, submitted, approved, rejected
    }

    public var id: UUID
    public var memberID: UUID
    public var status: Status
    /// Randevu (aracı kurum / konsolosluk) tarihi ve saati.
    public var appointment: Date?
    /// Randevu yeri, ör. "VFS Global İstanbul Gayrettepe".
    public var center: String
    /// Tamamlanan belge listesi maddeleri.
    public var checkedDocuments: [String]
    public var note: String

    public init(id: UUID = UUID(), memberID: UUID, status: Status = .preparing, appointment: Date? = nil,
                center: String = "", checkedDocuments: [String] = [], note: String = "") {
        self.id = id
        self.memberID = memberID
        self.status = status
        self.appointment = appointment
        self.center = center
        self.checkedDocuments = checkedDocuments
        self.note = note
    }
}

// MARK: - Documents

/// Belge kasasındaki bir dosya (pasaport, sigorta, bilet…). Dosya uygulama klasöründe, kayıt seyahatte.
public struct TravelDocument: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case passport, visa, insurance, ticket, reservation, other
    }

    public var id: UUID
    public var title: String
    public var kind: Kind
    /// Uygulama klasöründeki dosya adı (uzantısıyla).
    public var fileName: String
    /// Kime ait (yoksa herkes için).
    public var memberID: UUID?
    /// true ise dosya iCloud'a yüklenmez; yalnızca ekleyen cihazda kalır.
    public var isPrivate: Bool
    public var addedAt: Date

    public init(id: UUID = UUID(), title: String, kind: Kind, fileName: String, memberID: UUID? = nil,
                isPrivate: Bool = false, addedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.kind = kind
        self.fileName = fileName
        self.memberID = memberID
        self.isPrivate = isPrivate
        self.addedAt = addedAt
    }
}

// MARK: - Lodging

/// Otel, ev ya da hostel kaydı.
public struct Lodging: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var address: String
    public var coordinate: Coordinate?
    /// Giriş tarihi ve saati (konaklama yerinin yerel saatiyle girilir).
    public var checkIn: Date
    public var checkOut: Date
    public var confirmation: String
    public var note: String

    public init(id: UUID = UUID(), name: String, address: String = "", coordinate: Coordinate? = nil,
                checkIn: Date, checkOut: Date, confirmation: String = "", note: String = "") {
        self.id = id
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.checkIn = checkIn
        self.checkOut = max(checkIn, checkOut)
        self.confirmation = confirmation
        self.note = note
    }

    public func nights(calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: checkIn),
                                       to: calendar.startOfDay(for: checkOut)).day ?? 0)
    }
}

// MARK: - Trip

/// Çok şehirli seyahatin bir şehri: varış gününden bir sonraki şehre varışa (ya da seyahat sonuna) kadar.
/// Geçiş günü varılan şehre aittir.
public struct TripLeg: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var destination: Destination
    /// Bu şehre varış günü (gün başlangıcı); ilk şehir için seyahatin başlangıcı.
    public var arrival: Date

    public init(id: UUID = UUID(), destination: Destination, arrival: Date) {
        self.id = id
        self.destination = destination
        self.arrival = arrival
    }
}

public struct Trip: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var destination: Destination
    public var startDate: Date
    public var endDate: Date
    public var status: TripStatus
    /// ISO 4217, ör. "EUR".
    public var currency: String
    /// Kapak illüstrasyonu yer tutucusu için tohum.
    public var coverSeed: Int
    /// Kullanıcının seçtiği kapak fotoğrafının dosya adı (uygulama klasöründe). Eski kayıtlarda yoktur.
    public var coverPhoto: String?
    public var members: [Member]
    public var flights: [FlightSegment]
    public var stops: [Stop]
    public var budget: [BudgetLine]
    public var expenses: [Expense]
    public var packing: [PackingItem]
    /// Son değişiklik zamanı (eşitlemede hangi kopyanın daha yeni olduğunu belirler).
    public var updatedAt: Date?
    /// Silinen üye/durak/harcama/valiz kimlikleri; eşitlemede silinenlerin geri gelmesini önler.
    public var tombstones: Set<UUID>?
    /// Konaklamalar (eski kayıtlarda yok).
    public var lodgings: [Lodging]?
    /// Henüz bir güne atanmamış yerler ("Fikirler" havuzu); `day` alanı anlamsızdır.
    public var ideas: [Stop]?
    /// Vize başvuru takipleri (kişi başına).
    public var visaApplications: [VisaApplication]?
    /// Belge kasası.
    public var documents: [TravelDocument]?
    /// Gidiş öncesi yapılacaklar (harç, roaming, sigorta…); eski kayıtlarda yok.
    public var checklist: [ChecklistItem]?
    /// Tax-free (KDV iadesi) kayıtları; eski kayıtlarda yok.
    public var taxRefunds: [TaxRefund]?
    /// Ortak albüme fotoğraflarını açan kişiler (karşılıklı onay); eski kayıtlarda yok.
    public var albumConsents: [AlbumConsent]?
    /// Ortak albümdeki fotoğrafların bilgisi; dosyalar iCloud'da ayrı "Photo" kayıtlarıdır.
    public var albumPhotos: [AlbumPhoto]?
    /// Çok şehirli seyahatte şehirler (varış gününe göre sıralı); tek şehirde nil. `destination` her zaman ilk şehirdir.
    /// Eşitlemede ad ve tarihler gibi daha yeni kopyanınki geçerlidir.
    public var legs: [TripLeg]?

    public init(id: UUID = UUID(), name: String, destination: Destination, startDate: Date, endDate: Date,
                status: TripStatus = .planned, currency: String = "EUR", coverSeed: Int = 0, coverPhoto: String? = nil,
                members: [Member] = [],
                flights: [FlightSegment] = [], stops: [Stop] = [], budget: [BudgetLine] = [], expenses: [Expense] = [],
                packing: [PackingItem] = []) {
        self.id = id
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.currency = currency
        self.coverSeed = coverSeed
        self.coverPhoto = coverPhoto
        self.members = members
        self.flights = flights
        self.stops = stops
        self.budget = budget
        self.expenses = expenses
        self.packing = packing
    }

    /// Seyahatin her günü (gün başlangıçları), başlangıç ve bitiş dahil.
    public func days(calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard start <= end else { return [start] }
        var result: [Date] = []
        var cursor = start
        while cursor <= end {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    public func nights(calendar: Calendar = .current) -> Int {
        max(0, days(calendar: calendar).count - 1)
    }

    public func stops(on day: Date, calendar: Calendar = .current) -> [Stop] {
        stops
            .filter { calendar.isDate($0.day, inSameDayAs: day) }
            .sorted { $0.order < $1.order }
    }

    public func member(_ id: UUID?) -> Member? {
        guard let id else { return nil }
        return members.first { $0.id == id }
    }

    public var lodgingList: [Lodging] { (lodgings ?? []).sorted { $0.checkIn < $1.checkIn } }
    public var ideaList: [Stop] { ideas ?? [] }
    public var documentList: [TravelDocument] { (documents ?? []).sorted { $0.addedAt > $1.addedAt } }
    public var checklistItems: [ChecklistItem] { checklist ?? [] }
    public var taxRefundList: [TaxRefund] { (taxRefunds ?? []).sorted { $0.purchaseDate < $1.purchaseDate } }

    public func visaApplication(for memberID: UUID) -> VisaApplication? {
        visaApplications?.first { $0.memberID == memberID }
    }

    /// Günün başladığı konaklama: önceki gece kalınan yer, yoksa o gün girilen yer.
    public func lodging(forMorningOf day: Date, calendar: Calendar = .current) -> Lodging? {
        let target = calendar.startOfDay(for: day)
        let list = lodgingList
        return list.first { calendar.startOfDay(for: $0.checkIn) < target && target <= calendar.startOfDay(for: $0.checkOut) }
            ?? list.first { calendar.startOfDay(for: $0.checkIn) == target }
    }

    /// Bir günün tarihlerinde gecesi konaklama kaydıyla karşılanmayan geceler (son gün hariç).
    public func nightsWithoutLodging(calendar: Calendar = .current) -> [Date] {
        let nights = days(calendar: calendar).dropLast()
        let list = lodgingList
        return nights.filter { night in
            !list.contains { calendar.startOfDay(for: $0.checkIn) <= night && night < calendar.startOfDay(for: $0.checkOut) }
        }
    }

    /// İlk uçuş; ana ekrandaki biniş kartı için.
    public var primaryFlight: FlightSegment? {
        flights.min { $0.departure < $1.departure }
    }

    public func isPast(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: endDate) < calendar.startOfDay(for: now)
    }

    /// Durağın ziyaret gününe ve saatine göre açılış durumu; saat bilgisi yoksa nil.
    public func hoursStatus(of stop: Stop, calendar: Calendar = .current) -> OpeningHours.Status? {
        guard let raw = stop.openingHours, let hours = OpeningHours.cached(raw) else { return nil }
        let day = OpeningHours.dayIndex(calendarWeekday: calendar.component(.weekday, from: stop.day))
        return hours.status(day: day, startMinutes: stop.startMinutes, duration: stop.durationMinutes)
    }

    /// Açılış saatine takılan bir durak için önerilen düzeltme.
    public enum HoursFix: Hashable, Sendable {
        /// Aynı gün, açık olduğu bir saate al.
        case setStart(minutes: Int)
        /// Durağın aynı saatte açık olduğu en yakın seyahat gününe taşı.
        case moveTo(day: Date)
    }

    /// Önce aynı gün içinde saat kaydırmayı, olmazsa en yakın uygun günü önerir; çözüm yoksa nil.
    public func hoursFix(for stop: Stop, calendar: Calendar = .current) -> HoursFix? {
        guard let raw = stop.openingHours, let hours = OpeningHours.cached(raw),
              let status = hoursStatus(of: stop, calendar: calendar), status.isWarning else { return nil }

        let weekday = OpeningHours.dayIndex(calendarWeekday: calendar.component(.weekday, from: stop.day))
        switch status {
        case let .opensLater(at):
            return .setStart(minutes: at)
        case let .closesDuringVisit(at):
            if let interval = hours.intervals(onDay: weekday).first(where: { $0.end == at }),
               at - stop.durationMinutes >= interval.start {
                return .setStart(minutes: at - stop.durationMinutes)
            }
        default:
            break
        }

        let current = calendar.startOfDay(for: stop.day)
        let candidates = days(calendar: calendar)
            .filter { $0 != current }
            .sorted { lhs, rhs in
                let l = abs(lhs.timeIntervalSince(current))
                let r = abs(rhs.timeIntervalSince(current))
                return l != r ? l < r : lhs > rhs
            }
        for day in candidates {
            let index = OpeningHours.dayIndex(calendarWeekday: calendar.component(.weekday, from: day))
            if !hours.status(day: index, startMinutes: stop.startMinutes, duration: stop.durationMinutes).isWarning {
                return .moveTo(day: day)
            }
        }
        return nil
    }

    // MARK: Stop ordering

    /// Bir durağı aynı ya da başka bir günde `target` durağının önüne taşır; `target` nil ise günün sonuna.
    /// Etkilenen günlerin sıra numaraları 0'dan yeniden yazılır.
    public mutating func moveStop(_ id: UUID, before target: UUID?, on day: Date, calendar: Calendar = .current) {
        guard let moving = stops.first(where: { $0.id == id }), id != target else { return }
        let sourceDay = moving.day
        let destinationDay = calendar.startOfDay(for: day)

        var destination = self.stops(on: destinationDay, calendar: calendar).map(\.id).filter { $0 != id }
        if let target, let index = destination.firstIndex(of: target) {
            destination.insert(id, at: index)
        } else {
            destination.append(id)
        }

        if let index = stops.firstIndex(where: { $0.id == id }) {
            stops[index].day = destinationDay
        }
        renumber(destination)
        if !calendar.isDate(sourceDay, inSameDayAs: destinationDay) {
            renumber(self.stops(on: sourceDay, calendar: calendar).map(\.id))
        }
    }

    private mutating func renumber(_ ids: [UUID]) {
        for (order, id) in ids.enumerated() {
            if let index = stops.firstIndex(where: { $0.id == id }) {
                stops[index].order = order
            }
        }
    }

    // MARK: Sync

    /// Bu seyahatteki tüm alt öğelerin kimlikleri.
    public var itemIDs: Set<UUID> {
        // Tek uzun "+" zinciri derleyicinin tür çıkarımını çok yavaşlatıyor; adım adım toplanır.
        var ids: [UUID] = members.map(\.id)
        ids += stops.map(\.id)
        ids += expenses.map(\.id)
        ids += packing.map(\.id)
        ids += (lodgings ?? []).map(\.id)
        ids += (ideas ?? []).map(\.id)
        ids += (visaApplications ?? []).map(\.id)
        ids += (documents ?? []).map(\.id)
        ids += flights.map(\.id)
        ids += (checklist ?? []).map(\.id)
        ids += (taxRefunds ?? []).map(\.id)
        ids += (albumConsents ?? []).map(\.id)
        ids += (albumPhotos ?? []).map(\.id)
        return Set(ids)
    }

    /// Önceki halde olup bu halde olmayan öğeleri silindi olarak işaretler.
    public mutating func recordDeletions(since previous: Trip) {
        let removed = previous.itemIDs.subtracting(itemIDs)
        guard !removed.isEmpty else { return }
        tombstones = (tombstones ?? []).union(removed)
    }

    /// İki kopyayı birleştirir: alanlarda daha yeni kopya kazanır, listeler kimliğe göre birleşir
    /// (ortak öğede daha yeni kopyanınki), her iki taraftaki silinenler çıkarılır.
    public func merged(with other: Trip) -> Trip {
        let selfIsNewer = (updatedAt ?? .distantPast) >= (other.updatedAt ?? .distantPast)
        var result = selfIsNewer ? self : other
        let older = selfIsNewer ? other : self
        let deleted = (tombstones ?? []).union(other.tombstones ?? [])

        func union<T: Identifiable>(_ newer: [T], _ older: [T]) -> [T] where T.ID == UUID {
            let known = Set(newer.map(\.id))
            return (newer + older.filter { !known.contains($0.id) }).filter { !deleted.contains($0.id) }
        }

        result.members = union(result.members, older.members)
        result.stops = union(result.stops, older.stops)
        result.expenses = union(result.expenses, older.expenses)
        result.packing = union(result.packing, older.packing)
        result.flights = union(result.flights, older.flights).sorted { $0.departure < $1.departure }
        let lodgings = union(result.lodgings ?? [], older.lodgings ?? [])
        result.lodgings = lodgings.isEmpty ? nil : lodgings
        let ideas = union(result.ideas ?? [], older.ideas ?? [])
        result.ideas = ideas.isEmpty ? nil : ideas
        // Aynı kişi için iki cihazda ayrı başvuru açıldıysa yenisi kalır.
        var seenMembers: Set<UUID> = []
        let applications = union(result.visaApplications ?? [], older.visaApplications ?? [])
            .filter { seenMembers.insert($0.memberID).inserted }
        result.visaApplications = applications.isEmpty ? nil : applications
        let documents = union(result.documents ?? [], older.documents ?? [])
        result.documents = documents.isEmpty ? nil : documents
        let checklist = union(result.checklist ?? [], older.checklist ?? [])
        result.checklist = checklist.isEmpty ? nil : checklist
        let refunds = union(result.taxRefunds ?? [], older.taxRefunds ?? [])
        result.taxRefunds = refunds.isEmpty ? nil : refunds
        // Aynı kişi iki cihazdan onay verdiyse tek kayıt kalır.
        var consented: Set<UUID> = []
        let consents = union(result.albumConsents ?? [], older.albumConsents ?? [])
            .filter { consented.insert($0.memberID).inserted }
        result.albumConsents = consents.isEmpty ? nil : consents
        var seenSources: Set<String> = []
        let album = union(result.albumPhotos ?? [], older.albumPhotos ?? [])
            .filter { seenSources.insert("\($0.ownerID)-\($0.sourceKey)").inserted }
        result.albumPhotos = album.isEmpty ? nil : album
        result.tombstones = deleted.isEmpty ? nil : deleted
        return result
    }
}
