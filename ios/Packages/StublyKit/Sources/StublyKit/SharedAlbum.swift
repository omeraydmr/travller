import Foundation

/// Bir kişinin seyahatin ortak albümüne fotoğraflarını açtığı kayıt.
public struct AlbumConsent: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var memberID: UUID
    public var date: Date

    public init(id: UUID = UUID(), memberID: UUID, date: Date = Date()) {
        self.id = id
        self.memberID = memberID
        self.date = date
    }
}

/// Ortak albümdeki bir fotoğraf. Dosya, sahibinin cihazında küçültülüp iCloud'a yüklenir.
public struct AlbumPhoto: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var ownerID: UUID
    /// Uygulama klasöründeki dosya adı (iCloud'daki "Photo" kaydının adı da budur).
    public var fileName: String
    public var takenAt: Date
    public var coordinate: Coordinate?
    /// Sahibinin fotoğraf arşivindeki karşılığının özeti; aynı fotoğraf iki kez eklenmez.
    public var sourceKey: String

    public init(id: UUID = UUID(), ownerID: UUID, fileName: String, takenAt: Date, coordinate: Coordinate? = nil,
                sourceKey: String) {
        self.id = id
        self.ownerID = ownerID
        self.fileName = fileName
        self.takenAt = takenAt
        self.coordinate = coordinate
        self.sourceKey = sourceKey
    }
}

/// Ortak albümün kuralları: karşılıklı onay. Albüm en az iki ekip üyesi onay verince açılır ve yalnızca
/// onay verenler görür; onay geri çekilince kişinin fotoğrafları albümden kalkar.
public enum SharedAlbum {
    /// Onay veren (ve hâlâ ekipte olan) kişiler.
    public static func consentingMembers(of trip: Trip) -> Set<UUID> {
        let members = Set(trip.members.map(\.id))
        return Set((trip.albumConsents ?? []).map(\.memberID)).intersection(members)
    }

    public static func hasConsented(_ memberID: UUID, in trip: Trip) -> Bool {
        consentingMembers(of: trip).contains(memberID)
    }

    /// En az iki kişi onay verdiyse albüm açıktır.
    public static func isActive(_ trip: Trip) -> Bool {
        consentingMembers(of: trip).count >= 2
    }

    /// Kişi albümü görebilir mi: albüm açık ve kendisi de onay vermiş olmalı.
    public static func canView(_ memberID: UUID, in trip: Trip) -> Bool {
        isActive(trip) && hasConsented(memberID, in: trip)
    }

    /// Görünen fotoğraflar: yalnızca hâlâ onaylı kişilerinkiler, çekim zamanına göre.
    public static func visiblePhotos(in trip: Trip) -> [AlbumPhoto] {
        let consenting = consentingMembers(of: trip)
        return (trip.albumPhotos ?? []).filter { consenting.contains($0.ownerID) }.sorted { $0.takenAt < $1.takenAt }
    }

    public static func consent(_ memberID: UUID, in trip: inout Trip, now: Date = Date()) {
        guard !hasConsented(memberID, in: trip) else { return }
        trip.albumConsents = (trip.albumConsents ?? []) + [AlbumConsent(memberID: memberID, date: now)]
    }

    /// Onayı geri çeker ve kişinin fotoğraflarını albümden kaldırır.
    public static func withdraw(_ memberID: UUID, in trip: inout Trip) {
        trip.albumConsents?.removeAll { $0.memberID == memberID }
        trip.albumPhotos?.removeAll { $0.ownerID == memberID }
        if trip.albumConsents?.isEmpty == true { trip.albumConsents = nil }
        if trip.albumPhotos?.isEmpty == true { trip.albumPhotos = nil }
    }

    /// Sahibinin arşivindeki adaylardan albümde olmayan ve çıkarılmamış olanlar.
    public static func pendingSources(_ candidates: [String], owner: UUID, in trip: Trip, excluded: Set<String>) -> [String] {
        let present = Set((trip.albumPhotos ?? []).filter { $0.ownerID == owner }.map(\.sourceKey))
        return candidates.filter { !present.contains($0) && !excluded.contains($0) }
    }

    /// Fotoğraf arşivi kimliğinden kısa ve kararlı bir özet (FNV-1a); kimliğin kendisi paylaşılmaz.
    public static func sourceKey(for localIdentifier: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in localIdentifier.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
