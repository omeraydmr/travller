import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// QR kodu üretir: modüller opak, zemin saydam (şablon olarak renklendirilir). Aynı metin önbellekten gelir.
enum QRCode {
    private static let context = CIContext()
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for text: String) -> UIImage? {
        if let cached = cache.object(forKey: text as NSString) { return cached }
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(text.utf8)
        generator.correctionLevel = "M"
        guard let code = generator.outputImage else { return nil }
        // Siyah modüller → beyaz, sonra parlaklık saydamlığa: modüller opak, zemin saydam.
        let invert = CIFilter.colorInvert()
        invert.inputImage = code
        let mask = CIFilter.maskToAlpha()
        mask.inputImage = invert.outputImage
        guard let output = mask.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: text as NSString)
        return image
    }
}
