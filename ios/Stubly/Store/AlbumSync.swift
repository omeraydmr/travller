import Foundation
import Observation
import StublyKit

/// Ortak albüm: kişi onay verdiyse ve albüm açıksa (en az iki onay) seyahat günlerindeki fotoğraflarını
/// 2048 px JPEG olarak hazırlar ve albüme ekler; dosyalar iCloud eşitlemesiyle ekibe gider.
@MainActor
@Observable
final class AlbumSync {
    static let shared = AlbumSync()

    /// Seyahat → (hazırlanan, toplam) ilerleme; yükleme sürerken dolu.
    private(set) var progress: [UUID: (done: Int, total: Int)] = [:]
    @ObservationIgnored private var running: Set<UUID> = []

    private static let excludedKey = "stubly.album.excluded"

    /// Kişinin albümden çıkardığı fotoğraflar (seyahat → kaynak özetleri); tekrar eklenmez. Yalnızca bu cihazda.
    private var excluded: [String: [String]] {
        get { UserDefaults.standard.dictionary(forKey: Self.excludedKey) as? [String: [String]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.excludedKey) }
    }

    func excludedSources(for tripID: UUID) -> Set<String> {
        Set(excluded[tripID.uuidString] ?? [])
    }

    /// Albüm açıksa ve bu kişi onay verdiyse eksik fotoğrafları ekler.
    func sync(_ tripID: UUID, store: TripStore, library: PhotoLibrary = .shared) async {
        guard let trip = store.trip(tripID), SharedAlbum.canView(store.me.id, in: trip), store.canEdit(trip),
              library.canRead, !running.contains(tripID) else { return }
        running.insert(tripID)
        defer {
            running.remove(tripID)
            progress[tripID] = nil
        }

        let candidates = await library.albumCandidates(for: trip)
        let bySource = Dictionary(candidates.map { (SharedAlbum.sourceKey(for: $0.id), $0) }, uniquingKeysWith: { a, _ in a })
        let pending = SharedAlbum.pendingSources(candidates.map { SharedAlbum.sourceKey(for: $0.id) }, owner: store.me.id,
                                                 in: trip, excluded: excludedSources(for: tripID))
        guard !pending.isEmpty else { return }

        var batch: [AlbumPhoto] = []
        for (index, source) in pending.enumerated() {
            progress[tripID] = (index, pending.count)
            // Kullanıcı bu sırada onayını geri çektiyse dur.
            guard let current = store.trip(tripID), SharedAlbum.canView(store.me.id, in: current),
                  let photo = bySource[source] else { break }
            guard let data = await library.albumJPEG(for: photo.id),
                  let name = try? CoverImageStore.album.saveRaw(data, fileExtension: "jpg") else { continue }
            batch.append(AlbumPhoto(ownerID: store.me.id, fileName: name, takenAt: photo.date, coordinate: photo.coordinate,
                                    sourceKey: source))
            // Az az ekle: ekip ilk fotoğrafları beklemeden görür, eşitleme küçük parçalarla ilerler.
            if batch.count == 12 || index == pending.count - 1 {
                commit(batch, to: tripID, store: store)
                batch.removeAll()
            }
        }
        if !batch.isEmpty { commit(batch, to: tripID, store: store) }
    }

    private func commit(_ photos: [AlbumPhoto], to tripID: UUID, store: TripStore) {
        store.update(tripID) { trip in
            guard SharedAlbum.canView(store.me.id, in: trip) else { return }
            trip.albumPhotos = (trip.albumPhotos ?? []) + photos
        }
    }

    /// Kendi fotoğrafını albümden çıkarır; aynı fotoğraf bir daha eklenmez.
    func remove(_ photo: AlbumPhoto, from tripID: UUID, store: TripStore) {
        guard photo.ownerID == store.me.id else { return }
        var list = excluded
        list[tripID.uuidString, default: []].append(photo.sourceKey)
        excluded = list
        store.update(tripID) { trip in
            trip.albumPhotos?.removeAll { $0.id == photo.id }
            if trip.albumPhotos?.isEmpty == true { trip.albumPhotos = nil }
        }
        CoverImageStore.album.delete(named: photo.fileName)
    }

    /// Hiçbir seyahatin albümünde kalmayan (ör. onayını geri çeken kişinin) dosyaları bu cihazdan siler.
    func pruneOrphans(store: TripStore) {
        let used = Set(store.trips.flatMap { $0.albumPhotos ?? [] }.map(\.fileName))
        for name in CoverImageStore.album.allFileNames() where !used.contains(name) && !name.hasPrefix(".") {
            CoverImageStore.album.delete(named: name)
        }
    }

    /// Onay ver; albüm açıldıysa yüklemeyi başlat.
    func consent(_ tripID: UUID, store: TripStore) {
        store.update(tripID) { SharedAlbum.consent(store.me.id, in: &$0) }
        Task { await sync(tripID, store: store) }
    }

    /// Onayı geri çek: kendi fotoğrafların albümden ve bu cihazdan silinir.
    func withdraw(_ tripID: UUID, store: TripStore) {
        let mine = (store.trip(tripID)?.albumPhotos ?? []).filter { $0.ownerID == store.me.id }
        store.update(tripID) { SharedAlbum.withdraw(store.me.id, in: &$0) }
        mine.forEach { CoverImageStore.album.delete(named: $0.fileName) }
    }
}
