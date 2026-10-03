import Foundation

/// Üst üste dizilmiş, dairesel bir yörüngede kayan kart destesinin geometrisi.
///
/// `relative`, kartın öndeki karta göre konumudur: 0 öndeki kart, 1 sağdaki ilk kart, -1 soldaki ilk kart;
/// sürükleme sırasında ara değerler alır.
public struct CarouselGeometry: Hashable, Sendable {
    /// Yörünge yarıçapı (pt). Kartlar bu çemberin üst yayı boyunca dizilir.
    public var radius: Double
    /// Komşu kartlar arasındaki açı (radyan).
    public var step: Double
    /// Her adımda kartın kendi etrafında dönmesi (derece).
    public var tiltPerStep: Double
    public var scaleFalloff: Double
    public var blurPerStep: Double
    public var maxBlur: Double
    /// Bu uzaklıktan sonraki kartlar çizilmez.
    public var visibleRange: Double

    public init(radius: Double = 560, step: Double = 0.13, tiltPerStep: Double = 5, scaleFalloff: Double = 0.09,
                blurPerStep: Double = 2.5, maxBlur: Double = 5, visibleRange: Double = 2.6) {
        self.radius = radius
        self.step = step
        self.tiltPerStep = tiltPerStep
        self.scaleFalloff = scaleFalloff
        self.blurPerStep = blurPerStep
        self.maxBlur = maxBlur
        self.visibleRange = visibleRange
    }

    public struct Transform: Hashable, Sendable {
        public var x: Double
        public var y: Double
        public var rotationDegrees: Double
        public var scale: Double
        public var blur: Double
        public var opacity: Double
        /// Büyük olan önde çizilir.
        public var zIndex: Double
    }

    public func isVisible(_ relative: Double) -> Bool {
        abs(relative) < visibleRange
    }

    public func transform(relative r: Double) -> Transform {
        let distance = abs(r)
        let angle = r * step
        let fade = max(0, 1 - max(0, distance - 1.6))
        return Transform(
            x: radius * sin(angle),
            y: radius * (1 - cos(angle)),
            rotationDegrees: r * tiltPerStep,
            scale: max(0.5, 1 - scaleFalloff * distance),
            blur: min(maxBlur, blurPerStep * distance),
            opacity: fade,
            zIndex: -distance
        )
    }

    /// Sürükleme sonunda oturulacak kart. Hız yönündeki tahmini konuma gider ama
    /// destenin hissini korumak için başlangıç kartından en fazla bir kart uzaklaşır.
    public static func settle(from current: Int, predictedProgress: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let target = Int(predictedProgress.rounded())
        let limited = min(max(target, current - 1), current + 1)
        return min(max(limited, 0), count - 1)
    }
}
