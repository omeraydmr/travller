import QuartzCore
import SwiftUI
import StublyKit

// Seyahat onayı: ahşap saplı lastik mühür ve bilete bastığı "İYİ YOLCULUKLAR" izi.

private enum Wood {
    static let light = Color(hex: 0xD49A5C)
    static let mid = Color(hex: 0xAD6E36)
    static let dark = Color(hex: 0x7A4A22)
    static let ink = Color(hex: 0xC2343F)
}

/// Mührün 3 boyutlu gövdesi: üstte ahşap kapak (basılacak yazıyı gösterir), altında ahşap yan yüz ve kırmızı lastik.
/// Kapak, biletle aynı açıyla yatırılır; yan yüz dik kalır, böylece blok kâğıdın üstünde duruyormuş gibi görünür.
struct StampBlock: View {
    let subtitle: String
    /// Kâğıdın yatma açısı (derece).
    var angle: Double

    static let face = CGSize(width: 188, height: 88)
    static let depth: CGFloat = 40
    static let corner: CGFloat = 20

    /// Kapağın alt kenarının yansıtılmış konumu: sol/sağ x ve y.
    struct Metrics {
        var bottomLeft: CGPoint
        var bottomRight: CGPoint
        /// Bloğun yerleşim yüksekliği (kapak + yan yüz); taban ortası bu yüksekliğin altındadır.
        var height: CGFloat { bottomLeft.y + StampBlock.depth }
    }

    static func metrics(angle: Double) -> Metrics {
        Metrics(bottomLeft: PerspectivePlane.project(CGPoint(x: 0, y: face.height), degrees: angle, size: face),
                bottomRight: PerspectivePlane.project(CGPoint(x: face.width, y: face.height), degrees: angle, size: face))
    }

    var body: some View {
        let metrics = Self.metrics(angle: angle)
        let sideWidth = metrics.bottomRight.x - metrics.bottomLeft.x
        ZStack(alignment: .topLeading) {
            // Yan yüz: ortası açık, kenarları koyu ahşap; altta lastik.
            UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Wood.dark, Wood.mid, Wood.light, Wood.mid, Wood.dark],
                                     startPoint: .leading, endPoint: .trailing))
                .overlay(WoodGrain(lines: 3).stroke(Wood.dark.opacity(0.3), lineWidth: 1)
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous)))
                .overlay(alignment: .bottom) {
                    // Lastik: koyu kırmızı, kenarlardan biraz içeride.
                    UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Wood.ink.opacity(0.85), Color(hex: 0x7E1E26)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: 7)
                        .padding(.horizontal, 3)
                }
                .overlay(LinearGradient(colors: [.black.opacity(0.25), .clear], startPoint: .top, endPoint: .center))
                .frame(width: sideWidth, height: Self.depth + Self.corner)
                .offset(x: metrics.bottomLeft.x, y: metrics.bottomLeft.y - Self.corner)

            cover
                .frame(width: Self.face.width, height: Self.face.height)
                .modifier(PerspectivePlane(degrees: angle))
        }
        .frame(width: Self.face.width, height: metrics.height, alignment: .topLeading)
        .compositingGroup()
        .accessibilityHidden(true)
    }

    /// Kapak: açık ahşap, oyulmuş çerçeve ve basılacak yazının kabartması.
    private var cover: some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [Color(hex: 0xE2B27A), Wood.light, Wood.mid],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(WoodGrain(lines: 5).stroke(Wood.dark.opacity(0.18), lineWidth: 1).clipShape(shape))
            .overlay(
                RoundedRectangle(cornerRadius: Self.corner - 7, style: .continuous)
                    .strokeBorder(Wood.dark.opacity(0.35), lineWidth: 1.5)
                    .padding(7)
            )
            .overlay {
                VStack(spacing: 2) {
                    Text(StampImprint.title)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .tracking(2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(-2)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                }
                .foregroundStyle(Wood.dark.opacity(0.6))
                .shadow(color: .white.opacity(0.45), radius: 0, x: 0, y: 1)
            }
            .overlay(shape.strokeBorder(.white.opacity(0.35), lineWidth: 1))
    }
}

/// Görünümü yatay eksende perspektifle yatırır (üst kenar uzaklaşır). Aynı hesapla bir noktanın
/// ekrandaki yeri de bulunur; mühür bu sayede bilet üzerindeki doğru yere iner.
struct PerspectivePlane: GeometryEffect {
    var degrees: Double
    /// Göz uzaklığı: küçüldükçe perspektif güçlenir.
    static let distance: CGFloat = 700

    var animatableData: Double {
        get { degrees }
        set { degrees = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(Self.transform(degrees: degrees, size: size))
    }

    static func transform(degrees: Double, size: CGSize) -> CATransform3D {
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / distance
        let rotation = CATransform3DMakeRotation(CGFloat(degrees) * .pi / 180, 1, 0, 0)
        let toCenter = CATransform3DMakeTranslation(-size.width / 2, -size.height / 2, 0)
        let back = CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0)
        // Nokta önce merkeze taşınır, döndürülür, perspektif uygulanır, sonra yerine konur.
        return CATransform3DConcat(CATransform3DConcat(CATransform3DConcat(toCenter, rotation), perspective), back)
    }

    /// Görünümün yerel koordinatındaki bir noktanın yatırıldıktan sonraki yeri.
    static func project(_ point: CGPoint, degrees: Double, size: CGSize) -> CGPoint {
        let t = transform(degrees: degrees, size: size)
        let x = point.x * t.m11 + point.y * t.m21 + t.m41
        let y = point.x * t.m12 + point.y * t.m22 + t.m42
        let w = point.x * t.m14 + point.y * t.m24 + t.m44
        return CGPoint(x: x / w, y: y / w)
    }
}

/// Ahşap damarları için birkaç yumuşak eğri.
private struct WoodGrain: Shape {
    let lines: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<lines {
            let y = rect.minY + rect.height * (CGFloat(index) + 0.5) / CGFloat(lines)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addCurve(to: CGPoint(x: rect.maxX, y: y + 3),
                          control1: CGPoint(x: rect.width * 0.3, y: y - 5),
                          control2: CGPoint(x: rect.width * 0.7, y: y + 6))
        }
        return path
    }
}

/// Mürekkep izi: çift çerçeve, "İYİ YOLCULUKLAR", tarih ve şehir kodu; lastik baskısı gibi yer yer boş.
struct StampImprint: View {
    static let title = String(localized: "İYİ\nYOLCULUKLAR")
    var title = StampImprint.title
    let subtitle: String
    var color: Color = Wood.ink
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 2 * scale) {
            Text(title)
                .font(.system(size: 20 * scale, weight: .black, design: .rounded))
                .tracking(2 * scale)
                .multilineTextAlignment(.center)
                .lineSpacing(-3 * scale)
            Text(subtitle)
                .font(.system(size: 10 * scale, weight: .bold, design: .monospaced))
                .tracking(1 * scale)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 16 * scale)
        .padding(.vertical, 8 * scale)
        .overlay(RoundedRectangle(cornerRadius: 9 * scale, style: .continuous).strokeBorder(color, lineWidth: 3 * scale))
        .overlay(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous).strokeBorder(color, lineWidth: 1 * scale)
            .padding(4.5 * scale))
        .mask(InkMask())
        .opacity(0.9)
        .rotationEffect(.degrees(-12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title) \(subtitle)"))
    }

    /// Damganın alt yazısı: "01 EKİ 2026 · LIS".
    static func subtitle(for trip: Trip, on date: Date = .now) -> String {
        let day = date.formatted(.dateTime.day(.twoDigits).month(.abbreviated).year().locale(AppFormat.locale))
            .uppercased(with: AppFormat.locale)
        let code = trip.primaryFlight?.toCode
            ?? String(trip.destination.city.prefix(3)).uppercased(with: AppFormat.locale)
        return "\(day) · \(code)"
    }
}

/// Lastik baskısındaki boşlukları taklit eden sabit desenli maske.
private struct InkMask: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            context.blendMode = .clear
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
            }
            for _ in 0..<140 {
                let x = next() * size.width
                let y = next() * size.height
                let r = 0.4 + next() * 1.6
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white))
            }
        }
    }
}

// MARK: - Ceremony

/// Yeni seyahat onayı: bilet masaya yatar, ahşap mühür gölgesiyle süzülerek gelir, bastırır,
/// "İYİ YOLCULUKLAR" izi kalır (çok şehirde de kartın ortasına tek damga); mühür kalkar, bilet doğrulur ve desteye uçar.
struct StampCeremony: View {
    let trip: Trip
    var coverImage: UIImage?
    let onFinished: () -> Void

    private enum Phase: Int, Comparable {
        case appearing, presented, hovering, pressing, inked, lifted, leaving, flying

        static func < (lhs: Phase, rhs: Phase) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    @State private var phase: Phase = .appearing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let side: CGFloat = 280
    /// İzin bilet merkezine göre dikey yeri.
    private let imprintY: CGFloat = 50
    private let tiltAngle: Double = 52

    private var subtitle: String { StampImprint.subtitle(for: trip) }
    private var cardWidth: CGFloat { TripTicketCard.width(for: trip, side: side, maxWidth: 370) }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.18))
                .opacity(phase == .appearing || phase == .flying ? 0 : 1)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    ticket
                    if !reduceMotion {
                        stamp
                    }
                }
                .frame(width: cardWidth, height: side)

                confirmation
            }
            .scaleEffect(phase == .appearing ? 0.85 : (phase == .flying ? 0.45 : 1))
            .rotationEffect(.degrees(phase == .flying ? -8 : 0))
            .offset(y: containerOffset)
            .opacity(phase == .appearing ? 0 : 1)
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: phase == .pressing)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: phase == .lifted)
        .task { await run() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Seyahat oluşturuldu")
    }

    // MARK: Parçalar

    /// Masaya yatan bilet: üstünde mührün gölgesi ve mürekkep izi.
    private var ticket: some View {
        TripTicketCard(trip: trip, side: side, maxWidth: 370)
            .environment(\.coverOverride, coverImage)
            .overlay {
                // Mührün gölgesi: yükseldikçe büyür ve dağılır.
                RoundedRectangle(cornerRadius: StampBlock.corner, style: .continuous)
                    .fill(.black)
                    .frame(width: StampBlock.face.width * shadow.scale, height: StampBlock.face.height * shadow.scale)
                    .blur(radius: shadow.blur)
                    .opacity(shadow.opacity)
                    .offset(y: imprintY + shadow.drop)
                    .allowsHitTesting(false)
            }
            .overlay {
                StampImprint(subtitle: subtitle)
                    .scaleEffect(isInked ? 1 : 1.12)
                    .blur(radius: isInked ? 0 : 3)
                    .opacity(isInked ? 1 : 0)
                    .offset(y: imprintY)
            }
            .scaleEffect(phase == .pressing ? 0.975 : 1)
            .modifier(PerspectivePlane(degrees: planeAngle))
    }

    private var stamp: some View {
        let metrics = StampBlock.metrics(angle: planeAngle)
        // Taban ortası: izin alt kenarının yatırılmış bilet üzerindeki yeri.
        let foot = PerspectivePlane.project(
            CGPoint(x: cardWidth / 2, y: side / 2 + imprintY + StampBlock.face.height / 2),
            degrees: planeAngle, size: CGSize(width: cardWidth, height: side))
        return StampBlock(subtitle: subtitle, angle: planeAngle)
            .scaleEffect(x: phase == .pressing ? 1.03 : 1, y: phase == .pressing ? 0.9 : 1, anchor: .bottom)
            .position(x: foot.x, y: foot.y - lift - metrics.height / 2)
            .opacity(phase >= .hovering && phase <= .lifted ? 1 : 0)
            .allowsHitTesting(false)
    }

    /// Videodaki "Marked as paid" şeridi gibi kısa onay.
    private var confirmation: some View {
        Label("Onaylandı · \(subtitle)", systemImage: "checkmark.seal.fill")
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .opacity(phase >= .lifted && phase < .flying ? 1 : 0)
            .offset(y: phase >= .lifted ? 0 : 12)
    }

    // MARK: Aşamalara göre değerler

    private var planeAngle: Double {
        guard !reduceMotion else { return 0 }
        return phase >= .hovering && phase <= .lifted ? tiltAngle : 0
    }

    private var isInked: Bool { phase >= .inked }

    /// Mührün kâğıttan yüksekliği (ekran noktası).
    private var lift: CGFloat {
        switch phase {
        case .appearing, .presented: 520
        case .hovering: 120
        case .pressing, .inked: 0
        case .lifted: 140
        case .leaving, .flying: 640
        }
    }

    private struct ShadowStyle {
        var opacity: Double
        var blur: CGFloat
        var scale: CGFloat
        var drop: CGFloat
    }

    /// Yükseklikle değişen gölge: yakınken koyu ve keskin, uzakken açık ve dağınık.
    private var shadow: ShadowStyle {
        switch phase {
        case .hovering: ShadowStyle(opacity: 0.16, blur: 16, scale: 1.25, drop: 26)
        case .pressing: ShadowStyle(opacity: 0.38, blur: 3, scale: 0.98, drop: 2)
        case .inked: ShadowStyle(opacity: 0.3, blur: 4, scale: 1, drop: 3)
        case .lifted: ShadowStyle(opacity: 0.14, blur: 18, scale: 1.3, drop: 30)
        default: ShadowStyle(opacity: 0, blur: 22, scale: 1.4, drop: 40)
        }
    }

    private var containerOffset: CGFloat {
        switch phase {
        case .flying: -720
        case .hovering, .pressing, .inked, .lifted: 40
        default: 0
        }
    }

    private func run() async {
        if reduceMotion {
            phase = .inked
            try? await Task.sleep(for: .milliseconds(900))
            onFinished()
            return
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { phase = .presented }
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(.spring(response: 0.62, dampingFraction: 0.8)) { phase = .hovering }
        try? await Task.sleep(for: .milliseconds(650))
        withAnimation(.easeIn(duration: 0.17)) { phase = .pressing }
        try? await Task.sleep(for: .milliseconds(170))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { phase = .inked }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { phase = .lifted }
        try? await Task.sleep(for: .milliseconds(650))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { phase = .leaving }
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(.easeIn(duration: 0.42)) { phase = .flying }
        try? await Task.sleep(for: .milliseconds(360))
        onFinished()
    }
}
