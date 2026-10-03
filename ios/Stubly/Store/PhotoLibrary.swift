import CoreLocation
import Observation
import Photos
import StublyKit
import UIKit

/// Fotoğraf arşivinden seyahat tarihlerindeki fotoğrafları okur ve küçük görsellerini verir.
/// Fotoğraflar cihazdan çıkmaz; yalnızca yerel kimlikleri ve konum/zaman bilgisi kullanılır.
@MainActor
@Observable
final class PhotoLibrary {
    static let shared = PhotoLibrary()

    private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private let manager = PHCachingImageManager()
    private let thumbnails = NSCache<NSString, UIImage>()

    var canRead: Bool { status == .authorized || status == .limited }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Seyahatin ilk gününün başından son gününün sonuna kadar çekilen fotoğraflar.
    func photos(for trip: Trip, calendar: Calendar = .current) async -> [PhotoClusterer.Photo] {
        guard canRead else { return [] }
        let start = calendar.startOfDay(for: trip.startDate)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: trip.endDate)) ?? trip.endDate
        return await Task.detached(priority: .userInitiated) { () -> [PhotoClusterer.Photo] in
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@ AND mediaType == %d",
                                            start as NSDate, end as NSDate, PHAssetMediaType.image.rawValue)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let assets = PHAsset.fetchAssets(with: options)
            var result: [PhotoClusterer.Photo] = []
            result.reserveCapacity(assets.count)
            assets.enumerateObjects { asset, _, _ in
                guard let date = asset.creationDate else { return }
                let coordinate = asset.location.map {
                    Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                }
                result.append(PhotoClusterer.Photo(id: asset.localIdentifier, date: date, coordinate: coordinate))
            }
            return result
        }.value
    }

    /// Ortak albüm adayları: seyahat günlerinde çekilmiş fotoğraflar, ekran görüntüleri hariç.
    func albumCandidates(for trip: Trip, calendar: Calendar = .current) async -> [PhotoClusterer.Photo] {
        guard canRead else { return [] }
        let start = calendar.startOfDay(for: trip.startDate)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: trip.endDate)) ?? trip.endDate
        return await Task.detached(priority: .utility) { () -> [PhotoClusterer.Photo] in
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@ AND mediaType == %d",
                                            start as NSDate, end as NSDate, PHAssetMediaType.image.rawValue)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            var result: [PhotoClusterer.Photo] = []
            PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
                guard let date = asset.creationDate, !asset.mediaSubtypes.contains(.photoScreenshot) else { return }
                let coordinate = asset.location.map {
                    Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                }
                result.append(PhotoClusterer.Photo(id: asset.localIdentifier, date: date, coordinate: coordinate))
            }
            return result
        }.value
    }

    /// Ortak albüme yüklenecek JPEG: uzun kenarı en fazla `maxPixelSize`, konum ve diğer meta veriler olmadan.
    func albumJPEG(for id: String, maxPixelSize: CGFloat = 2048) async -> Data? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        let scale = min(1, maxPixelSize / CGFloat(max(asset.pixelWidth, asset.pixelHeight, 1)))
        let target = CGSize(width: CGFloat(asset.pixelWidth) * scale, height: CGFloat(asset.pixelHeight) * scale)
        let image: UIImage? = await withCheckedContinuation { continuation in
            var resumed = false
            manager.requestImage(for: asset, targetSize: target, contentMode: .aspectFit, options: options) { image, info in
                // Yüksek kalite istenince tek sonuç gelir; yine de iki kez devam etmeyi engelle.
                guard !resumed, (info?[PHImageResultIsDegradedKey] as? Bool) != true else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
        return image?.jpegData(compressionQuality: 0.8)
    }

    /// Tam ekran görüntüleyici için büyük görsel.
    func fullImage(for id: String, maxPixelSize: CGFloat = 2400) async -> UIImage? {
        await thumbnail(for: id, side: maxPixelSize, contentMode: .aspectFit)
    }

    /// Kare küçük görsel (piksel cinsinden kenar).
    func thumbnail(for id: String, side: CGFloat, contentMode: PHImageContentMode = .aspectFill) async -> UIImage? {
        let key = "\(id)@\(Int(side))@\(contentMode.rawValue)" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let image: UIImage? = await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: CGSize(width: side, height: side), contentMode: contentMode,
                                 options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
        if let image { thumbnails.setObject(image, forKey: key) }
        return image
    }
}
