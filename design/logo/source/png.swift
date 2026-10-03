import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// png alpha <file>            → köşe pikselinin saydamlığı
// png flatten <in> <out>      → alfa kanalı olmayan opak PNG (App Store ikonu)
let args = CommandLine.arguments
func load(_ path: String) -> CGImage {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}
func save(_ image: CGImage, _ path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
let image = load(args[2])
switch args[1] {
case "alpha":
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
    print("size \(image.width)x\(image.height) corner alpha \(p[3]) center alpha \(p[(image.height / 2 * ctx.bytesPerRow) + image.width / 2 * 4 + 3])")
case "matte":
    // Siyah ve beyaz zeminde çizilmiş iki kopyadan saydamlık: a = 1 - (beyaz - siyah), renk = siyah / a.
    let white = load(args[3])
    func pixels(_ img: CGImage) -> [UInt8] {
        let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: img.width * img.height * 4))
    }
    let b = pixels(image), w = pixels(white)
    var out = [UInt8](repeating: 0, count: b.count)
    for i in stride(from: 0, to: b.count, by: 4) {
        let diff = (0..<3).map { Double(w[i + $0]) - Double(b[i + $0]) }.reduce(0, +) / 3
        let a = max(0, min(255, 255 - diff))
        out[i + 3] = UInt8(a.rounded())
        for c in 0..<3 { out[i + c] = a == 0 ? 0 : UInt8(min(255, Double(b[i + c]) * 255 / a).rounded()) }
    }
    let provider = CGDataProvider(data: Data(out) as CFData)!
    let result = CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: image.width * 4,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    save(result, args[4])
default:
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    save(ctx.makeImage()!, args[3])
}
