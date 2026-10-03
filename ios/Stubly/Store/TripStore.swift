import Foundation
import Observation
import StublyKit

/// Uygulama durumu. Şimdilik cihazda JSON olarak saklanır; ileride senkronize bir backend'e taşınacak.
@MainActor
@Observable
final class TripStore {
    private(set) var trips: [Trip] = []
    /// Cihaz sahibinin profili (pasaport bilgileri yeni seyahatlere kopyalanır).
    private(set) var me: Member

    /// Elle eklenen geçmiş Schengen ziyaretleri (kişi kimliğine göre; yalnızca bu cihazda saklanır).
    private(set) var manualStays: [UUID: [ManualStay]] = [:]

    private let fileURL: URL
    private static let meKey = "stubly.me"
    private static let manualStaysKey = "stubly.schengen.manualStays"
    private static let visitedKey = "stubly.profile.visitedCountries"

    /// Uygulamada seyahati olmayan, elle eklenen gezilmiş ülkeler.
    private(set) var extraVisitedCountries: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: TripStore.visitedKey) ?? [])

    init(fileURL: URL = TripStore.defaultFileURL) {
        self.fileURL = fileURL
        if let data = UserDefaults.standard.data(forKey: Self.meKey),
           let me = try? JSONDecoder().decode(Member.self, from: data) {
            self.me = me
        } else {
            let me = Member(name: "Ben", role: .owner, colorIndex: 3,
                            passport: Passport(expiresOn: Calendar.current.date(byAdding: .year, value: 5, to: .now) ?? .now))
            self.me = me
            // Hemen kaydet: yoksa her açılışta yeni kimlik üretilir ve seyahatlerdeki "ben" eşleşmez.
            if let data = try? JSONEncoder().encode(me) { UserDefaults.standard.set(data, forKey: Self.meKey) }
        }
        if let data = UserDefaults.standard.data(forKey: Self.manualStaysKey),
           let stays = try? JSONDecoder().decode([UUID: [ManualStay]].self, from: data) {
            manualStays = stays
        }
        load()
    }

    nonisolated static var defaultFileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("trips.json")
    }

    // MARK: Queries

    func trip(_ id: Trip.ID) -> Trip? {
        trips.first { $0.id == id }
    }

    var upcoming: [Trip] {
        trips.filter { !$0.isPast() }.sorted { $0.startDate < $1.startDate }
    }

    var past: [Trip] {
        trips.filter { $0.isPast() }.sorted { $0.startDate > $1.startDate }
    }

    // MARK: Mutations

    func add(_ trip: Trip) {
        var trip = trip
        trip.updatedAt = .now
        trips.append(trip)
        save()
        CloudSync.shared.tripChanged(trip.id)
    }

    func delete(_ id: Trip.ID) {
        if let photo = trip(id)?.coverPhoto {
            CoverImageStore.shared.delete(named: photo)
        }
        for receipt in trip(id)?.expenses.compactMap(\.receiptPhoto) ?? [] {
            CoverImageStore.receipts.delete(named: receipt)
        }
        trips.removeAll { $0.id == id }
        save()
        CloudSync.shared.tripDeleted(id)
    }

    /// Kapak fotoğrafını değiştirir; eski dosya silinir.
    func setCoverPhoto(_ data: Data, for id: Trip.ID) throws {
        let name = try CoverImageStore.shared.save(data)
        let old = trip(id)?.coverPhoto
        update(id) { $0.coverPhoto = name }
        if let old { CoverImageStore.shared.delete(named: old) }
    }

    func removeCoverPhoto(for id: Trip.ID) {
        guard let old = trip(id)?.coverPhoto else { return }
        update(id) { $0.coverPhoto = nil }
        CoverImageStore.shared.delete(named: old)
    }

    // MARK: Roles

    /// Bu cihazın kullanıcısının seyahatteki rolü. Ekipte yoksa: paylaşılan seyahatte düzenleyici, kendi seyahatinde sahip.
    /// Sahip iCloud'da salt okunur yaptıysa ekipteki rol ne olursa olsun görüntüleyici.
    func role(in trip: Trip) -> MemberRole {
        let cloud = CloudSync.shared
        return SharePermissions.effectiveRole(memberRole: trip.members.first(where: { $0.id == me.id })?.role,
                                              shareAccess: cloud.myAccess[trip.id],
                                              isSharedWithMe: cloud.sharedWithMe.contains(trip.id))
    }

    /// "Sadece görür" yetkisindeki kişi seyahati değiştiremez.
    func canEdit(_ trip: Trip) -> Bool { role(in: trip) != .viewer }

    // MARK: Activity

    /// Ekipten gelen değişikliklerin kısa geçmişi (seyahat başına en fazla 50; yalnızca bu cihazda).
    private(set) var activity: [UUID: [ActivityEntry]] = TripStore.loadActivity()
    private static let activityKey = "stubly.activity"

    func recordActivity(_ summary: TripChanges.Summary, at date: Date = .now) {
        let entry = ActivityEntry(date: date, title: summary.title, lines: summary.lines, section: summary.link.section)
        var list = activity[summary.link.tripID] ?? []
        list.insert(entry, at: 0)
        activity[summary.link.tripID] = Array(list.prefix(50))
        if let data = try? JSONEncoder().encode(activity) {
            UserDefaults.standard.set(data, forKey: Self.activityKey)
        }
    }

    private static func loadActivity() -> [UUID: [ActivityEntry]] {
        guard let data = UserDefaults.standard.data(forKey: activityKey),
              let decoded = try? JSONDecoder().decode([UUID: [ActivityEntry]].self, from: data) else { return [:] }
        return decoded
    }

    /// Bir seyahati yerinde değiştirir ve kaydeder. Görüntüleyici yetkisindeyse değişiklik yapılmaz.
    func update(_ id: Trip.ID, _ change: (inout Trip) -> Void) {
        guard let index = trips.firstIndex(where: { $0.id == id }), canEdit(trips[index]) else { return }
        let before = trips[index]
        change(&trips[index])
        guard trips[index] != before else { return }
        trips[index].recordDeletions(since: before)
        trips[index].updatedAt = .now
        save()
        CloudSync.shared.tripChanged(id)
    }

    /// iCloud'dan gelen kopyayı yerel kopyayla birleştirir. Yerelde buluttakinden fazlası varsa
    /// birleşmiş hali geri gönderilmek üzere true döner.
    @discardableResult
    func mergeFromCloud(_ remote: Trip) -> Bool {
        guard let index = trips.firstIndex(where: { $0.id == remote.id }) else {
            trips.append(remote)
            save()
            return false
        }
        let merged = trips[index].merged(with: remote)
        guard merged != trips[index] else { return merged != remote }
        trips[index] = merged
        save()
        return merged != remote
    }

    /// Bulutta silinen (ya da paylaşımı kaldırılan) seyahati yerelden kaldırır.
    func removeFromCloud(_ id: Trip.ID) {
        guard trips.contains(where: { $0.id == id }) else { return }
        trips.removeAll { $0.id == id }
        save()
    }

    // MARK: Schengen 90/180

    /// Kişinin bu seyahat dışındaki Schengen kalışları: planlanmış seyahatler ve elle eklenen ziyaretler.
    func schengenStays(for memberID: UUID, excluding tripID: Trip.ID? = nil) -> [Schengen.Stay] {
        // Çok ülkeli seyahatlerde yalnızca Schengen'de geçen günler sayılır.
        let fromTrips = trips
            .filter { trip in trip.id != tripID && trip.status == .planned && trip.members.contains { $0.id == memberID } }
            .compactMap { trip in
                trip.schengenRange().map { Schengen.Stay(id: trip.id, start: $0.start, end: $0.end, label: trip.name) }
            }
        let manual = (manualStays[memberID] ?? []).map {
            Schengen.Stay(id: $0.id, start: $0.start, end: $0.end, label: $0.note.isEmpty ? String(localized: "Önceki ziyaret") : $0.note)
        }
        return fromTrips + manual
    }

    /// Kişinin bu seyahatte bir ülke için vize değerlendirmesi (diğer Schengen kalışları dahil). Ülke verilmezse,
    /// çok ülkeli seyahatte işlem gerektiren ilk ülke (yoksa ilk ülke). Tarihler o ülkede geçen günlerdir; Schengen'de
    /// bölgede geçen tüm günler.
    func visaAssessment(for member: Member, in trip: Trip, country: String? = nil) -> VisaAssessment {
        if country == nil, trip.countryCodes.count > 1 {
            let all = trip.countryCodes.map { visaAssessment(for: member, in: trip, country: $0) }
            return all.first(where: \.needsAction) ?? all[0]
        }
        let code = country ?? trip.destination.countryCode
        let schengen = Schengen.isSchengen(code)
        let range = (schengen ? trip.schengenRange() : nil) ?? trip.dateRange(ofCountry: code) ?? (trip.startDate, trip.endDate)
        return VisaAdvisor.assess(countryCode: code, passport: member.passport, tripStart: range.start, tripEnd: range.end,
                                  otherSchengenStays: schengen ? schengenStays(for: member.id, excluding: trip.id) : [])
    }

    func addManualStay(_ stay: ManualStay, for memberID: UUID) {
        manualStays[memberID, default: []].append(stay)
        saveManualStays()
    }

    func removeManualStay(_ id: ManualStay.ID, for memberID: UUID) {
        manualStays[memberID]?.removeAll { $0.id == id }
        saveManualStays()
    }

    private func saveManualStays() {
        if let data = try? JSONEncoder().encode(manualStays) {
            UserDefaults.standard.set(data, forKey: Self.manualStaysKey)
        }
    }

    /// Profil kaydedilince ad, pasaport ve IBAN, kendi kopyanın bulunduğu tüm seyahatlere de yansır.
    func saveProfile(_ profile: Member) {
        updateMe { me in
            me.name = profile.name
            me.passport = profile.passport
            me.iban = profile.iban
        }
        for trip in trips where trip.members.contains(where: { $0.id == profile.id }) {
            update(trip.id) { trip in
                guard let index = trip.members.firstIndex(where: { $0.id == profile.id }) else { return }
                trip.members[index].name = profile.name
                trip.members[index].passport = profile.passport
                trip.members[index].iban = profile.iban
            }
        }
    }

    // MARK: Emergency

    private static let emergencyKey = "stubly.emergency"

    /// Kan grubu, alerjiler, ilaçlar ve acil kişi. Yalnızca bu cihazda; ekiple paylaşılmaz.
    private(set) var emergency: EmergencyInfo = {
        guard let data = UserDefaults.standard.data(forKey: TripStore.emergencyKey),
              let decoded = try? JSONDecoder().decode(EmergencyInfo.self, from: data) else { return EmergencyInfo() }
        return decoded
    }()

    func saveEmergency(_ info: EmergencyInfo) {
        emergency = info
        if let data = try? JSONEncoder().encode(info) { UserDefaults.standard.set(data, forKey: Self.emergencyKey) }
    }

    // MARK: Onboarding

    private static let preferencesKey = "stubly.preferences"
    private static let onboardingKey = "stubly.onboarding.completed.v1"

    /// İlk açılış anketinin cevapları.
    private(set) var preferences: TravelPreferences = {
        guard let data = UserDefaults.standard.data(forKey: TripStore.preferencesKey),
              let decoded = try? JSONDecoder().decode(TravelPreferences.self, from: data) else { return TravelPreferences() }
        return decoded
    }()

    /// İlk açılış tanıtımı ve profil oluşturma tamamlandı mı.
    private(set) var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: TripStore.onboardingKey)

    /// Tanıtımın sonunda: profil ("hesap") ve anket kaydedilir; iCloud kimliği biliniyorsa profile bağlanır.
    func completeOnboarding(profile: Member, preferences: TravelPreferences, cloudUserID: String?) {
        var profile = profile
        // Eski sürüm profili kaydetmediği için kimlik değişmiş olabilir: seyahatlerde sahibi olan
        // varsayılan "Ben" kaydı varsa onun kimliği benimsenir (harcamalar ve valiz ona bağlı).
        if !trips.contains(where: { $0.members.contains { $0.id == me.id } }),
           let legacy = trips.lazy.flatMap(\.members).first(where: { $0.role == .owner && $0.name == "Ben" }) {
            updateMe { $0.id = legacy.id }
            profile.id = legacy.id
        }
        saveProfile(profile)
        updateMe { me in
            me.colorIndex = profile.colorIndex
            if let cloudUserID { me.cloudUserID = cloudUserID }
        }
        for trip in trips where trip.members.contains(where: { $0.id == profile.id }) {
            update(trip.id) { trip in
                guard let index = trip.members.firstIndex(where: { $0.id == profile.id }) else { return }
                trip.members[index].colorIndex = profile.colorIndex
            }
        }
        self.preferences = preferences
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: Self.preferencesKey)
        }
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
    }

    /// Profilden "tanıtımı yeniden göster".
    func restartOnboarding() {
        hasCompletedOnboarding = false
        UserDefaults.standard.set(false, forKey: Self.onboardingKey)
    }

    func setVisited(_ code: String, _ visited: Bool) {
        if visited { extraVisitedCountries.insert(code.uppercased()) } else { extraVisitedCountries.remove(code.uppercased()) }
        UserDefaults.standard.set(Array(extraVisitedCountries), forKey: Self.visitedKey)
    }

    func updateMe(_ change: (inout Member) -> Void) {
        change(&me)
        if let data = try? JSONEncoder().encode(me) {
            UserDefaults.standard.set(data, forKey: Self.meKey)
        }
        NotificationScheduler.shared.documentsChanged(me.passport)
    }

    /// Hakkında > "Tüm seyahatleri sil": her seyahat tek tek silinir (fotoğraflar ve iCloud kaydı dahil).
    func deleteAllTrips() {
        for id in trips.map(\.id) { delete(id) }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            trips = try Self.decoder.decode([Trip].self, from: data)
        } catch {
            // Bozuk dosyayı silmek yerine kenara al; kullanıcı verisi kaybolmasın.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    private func save() {
        NotificationScheduler.shared.tripsChanged(trips)
        WidgetBridge.shared.tripsChanged(trips)
        scheduleDiskWrite()
    }

    @ObservationIgnored private var writeTask: Task<Void, Never>?
    @ObservationIgnored private var hasPendingWrite = false
    /// Yazmalar sırayla yapılır; eski bir anlık görüntü yenisinin üstüne yazılamaz.
    private static let writeQueue = DispatchQueue(label: "stubly.store.write", qos: .utility)

    /// Arka arkaya gelen değişiklikleri toplar; JSON'u ana iş parçacığı dışında yazar.
    private func scheduleDiskWrite() {
        hasPendingWrite = true
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            let snapshot = trips
            let url = fileURL
            hasPendingWrite = false
            Self.writeQueue.async { Self.write(snapshot, to: url) }
        }
    }

    /// Uygulama arka plana geçerken bekleyen yazmayı hemen bitirir.
    func flush() {
        writeTask?.cancel()
        writeTask = nil
        if hasPendingWrite {
            hasPendingWrite = false
            let snapshot = trips
            let url = fileURL
            Self.writeQueue.async { Self.write(snapshot, to: url) }
        }
        // Kuyruktaki yazmalar bitene kadar bekle (arka plana geçmeden önce).
        Self.writeQueue.sync {}
    }

    private nonisolated static func write(_ trips: [Trip], to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(trips)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            assertionFailure("Seyahatler kaydedilemedi: \(error)")
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Ekip aktivite akışındaki bir satır grubu ("Elif bir harcama ekledi: …").
struct ActivityEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var date: Date
    var title: String
    var lines: [String]
    var section: String?
}
