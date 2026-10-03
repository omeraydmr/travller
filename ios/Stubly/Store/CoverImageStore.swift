import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import SwiftUI
import UIKit

/// Seyahat kapak fotoğraflarını uygulama klasöründe saklar; küçültülmüş görüntüyü ve
/// kartları renklendirmek için baskın rengini önbellekte tutar.
@MainActor
final class CoverImageStore {
    static let shared = CoverImageStore()
    /// Harcama makbuzları için ayrı klasör.
    static let receipts = CoverImageStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Receipts", isDirectory: true))

    /// Belge kasası dosyaları (PDF, fotoğraf) için ayrı klasör; olduğu gibi saklanır.
    static let documents = CoverImageStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TripDocuments", isDirectory: true))

    /// Ortak albüm fotoğrafları (2048 px JPEG); kendi yüklediklerin ve ekipten gelenler.
    static let album = CoverImageStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SharedAlbum", isDirectory: true))

    private let directory: URL
    private let images = NSCache<NSString, UIImage>()
    /// Kartlar için küçültülmüş ve önceden çözülmüş görüntüler ("ad@piksel").
    private let thumbnails = NSCache<NSString, UIImage>()
    private var colors: [String: Color] = [:]
    private let context = CIContext(options: [.workingColorSpace: NSNull()])

    init(directory: URL = CoverImageStore.defaultDirectory) {
        self.directory = directory
        images.countLimit = 8
        thumbnails.countLimit = 48
    }

    /// Destedeki kartlar için yeterli çözünürlük (piksel, uzun kenar).
    static let cardPixelSize: CGFloat = 900

    /// Küçültülmüş, çözülmüş görüntü. Tam boy JPEG'i her karede ölçeklemek yerine bunu çizer.
    func thumbnail(named name: String, maxPixelSize: CGFloat = CoverImageStore.cardPixelSize) -> UIImage? {
        let key = "\(name)@\(Int(maxPixelSize))" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let image = Self.downsample(at: directory.appendingPathComponent(name), maxPixelSize: maxPixelSize) else {
            return nil
        }
        thumbnails.setObject(image, forKey: key)
        return image
    }

    /// Kart küçük görsellerini ve renkleri arka planda hazırlar; ilk kaydırmada takılma olmasın.
    func prewarm(_ names: [String]) async {
        let missing = names.filter { thumbnails.object(forKey: "\($0)@\(Int(Self.cardPixelSize))" as NSString) == nil }
        guard !missing.isEmpty else { return }
        let directory = directory
        let size = Self.cardPixelSize
        let decoded = await Task.detached(priority: .utility) {
            missing.compactMap { name -> (String, UIImage)? in
                Self.downsample(at: directory.appendingPathComponent(name), maxPixelSize: size).map { (name, $0) }
            }
        }.value
        for (name, image) in decoded {
            thumbnails.setObject(image, forKey: "\(name)@\(Int(size))" as NSString)
            _ = dominantColor(named: name)
        }
    }

    /// ImageIO ile doğrudan küçük boyutta çözer (tam görüntüyü belleğe açmaz).
    nonisolated static func downsample(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return downsample(source, maxPixelSize: maxPixelSize)
    }

    nonisolated static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return downsample(source, maxPixelSize: maxPixelSize)
    }

    private nonisolated static func downsample(_ source: CGImageSource, maxPixelSize: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Covers", isDirectory: true)
    }

    /// Ham görüntü verisini en fazla 1400 pt kenarlı JPEG olarak kaydeder ve dosya adını döndürür.
    func save(_ data: Data) throws -> String {
        guard let image = UIImage(data: data) else { throw CoverError.unreadableImage }
        let resized = Self.resized(image, maxDimension: 1400)
        guard let jpeg = resized.jpegData(compressionQuality: 0.82) else { throw CoverError.unreadableImage }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".jpg"
        try jpeg.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        images.setObject(resized, forKey: name as NSString)
        return name
    }

    /// Veriyi değiştirmeden kaydeder (PDF gibi); dosya adını döndürür.
    func saveRaw(_ data: Data, fileExtension: String) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString + "." + fileExtension.lowercased()
        try data.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        return name
    }

    func image(named name: String) -> UIImage? {
        if let cached = images.object(forKey: name as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: directory.appendingPathComponent(name).path) else { return nil }
        images.setObject(image, forKey: name as NSString)
        return image
    }

    /// Diskteki dosya (iCloud'a yüklemek için); yoksa nil.
    func fileURL(named name: String) -> URL? {
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// iCloud'dan gelen dosyayı aynı adla kopyalar (zaten varsa dokunmaz).
    func importFile(at source: URL, named name: String) {
        let target = directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: target.path) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: source, to: target)
        images.removeObject(forKey: name as NSString)
        removeThumbnails(named: name)
        colors[name] = nil
    }

    private func removeThumbnails(named name: String) {
        for size in [Self.cardPixelSize, 64] {
            thumbnails.removeObject(forKey: "\(name)@\(Int(size))" as NSString)
        }
    }

    /// Klasördeki dosya adları (artık kullanılmayanları temizlemek için).
    func allFileNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    func delete(named name: String) {
        images.removeObject(forKey: name as NSString)
        removeThumbnails(named: name)
        colors[name] = nil
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    /// Fotoğrafın ortalama renginden, kart üzerinde okunabilir kalacak şekilde doygunlaştırılmış bir ton.
    func dominantColor(named name: String) -> Color? {
        if let cached = colors[name] { return cached }
        // Ortalama renk için 64 piksellik görüntü yeter; tam boy açmaya gerek yok.
        guard let image = thumbnail(named: name, maxPixelSize: 64), let input = CIImage(image: image) else { return nil }

        let filter = CIFilter.areaAverage()
        filter.inputImage = input
        filter.extent = input.extent
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        let average = UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                              blue: CGFloat(pixel[2]) / 255, alpha: 1)

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let vivid = UIColor(hue: hue, saturation: min(1, max(0.45, saturation * 1.6)),
                            brightness: min(0.85, max(0.55, brightness)), alpha: 1)
        let color = Color(uiColor: vivid)
        colors[name] = color
        return color
    }

    private static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        guard scale < 1 else { return image }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    enum CoverError: LocalizedError {
        case unreadableImage

        var errorDescription: String? { String(localized: "Fotoğraf okunamadı.") }
    }
}
