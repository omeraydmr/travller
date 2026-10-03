import SwiftUI
import StublyKit

// MARK: - Surfaces

/// Modül kartı: gri yüzey, sol üstte ikon + başlık, isteğe bağlı sağ aksesuar.
struct ModuleCard<Accessory: View, Content: View>: View {
    let title: String
    let symbol: String
    let accessory: Accessory
    let content: Content

    init(_ title: String, symbol: String, @ViewBuilder accessory: () -> Accessory,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: symbol)
                }
                .font(.tTitle)
                .foregroundStyle(Color.ink2)
                Spacer(minLength: 8)
                accessory
            }
            content
        }
        .padding(20)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.module, style: .continuous)
                .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                .blendMode(.overlay)
        )
        .cardBackground(Color.surface, in: RoundedRectangle(cornerRadius: Radius.module, style: .continuous))
    }
}

extension ModuleCard where Accessory == EmptyView {
    init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.init(title, symbol: symbol, accessory: { EmptyView() }, content: content)
    }
}

extension View {
    /// Beyaz iç kart (tepsi).
    func tray(padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
    }

    /// Zemin şekli ve gölgesi. Gölge yalnızca şekilden hesaplanır: içerik gölgelenmez, katmana birleştirilmez,
    /// kaydırma ya da harita gibi canlı içerik gölge yüzünden yeniden çizilmez. Kart zeminleri için bunu kullan.
    func cardBackground<S: Shape, F: ShapeStyle>(_ fill: F, in shape: S) -> some View {
        background { shape.fill(fill).softShadow() }
    }

    /// Önce tek katmana birleştirilir; aksi halde gölge her alt görünüme (her metne) ayrı ayrı uygulanır.
    /// Büyük kartlarda `cardBackground` tercih edilmeli.
    func softShadow() -> some View {
        self
            .compositingGroup()
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.06), radius: 12, y: 8)
    }
}

/// Modülün başındaki hikâye anlatan cümle.
struct StoryHeadline: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.tHeadline)
            .foregroundStyle(Color.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .medium))
            .foregroundStyle(Color.onInk)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 20)
            .cardBackground(Color.ink, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct CircleIconButtonStyle: ButtonStyle {
    var size: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(Color.ink)
            .frame(width: size, height: size)
            .cardBackground(Color.tray, in: Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == CircleIconButtonStyle {
    static var circleIcon: CircleIconButtonStyle { CircleIconButtonStyle() }
    static func circleIcon(size: CGFloat) -> CircleIconButtonStyle { CircleIconButtonStyle(size: size) }
}

// MARK: - Tags & segmented

struct Tag: View {
    let text: String
    var accent: Accent = .gray

    var body: some View {
        Text(text)
            .font(.system(.subheadline, weight: .medium))
            .foregroundStyle(accent.base)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(accent.tint, in: Capsule())
    }
}

/// Gri hap kap içinde beyaz seçili hap.
struct PillPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    var fillsWidth = false

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.spring(duration: 0.25)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(isSelected ? Color.ink : Color.ink2)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: fillsWidth ? .infinity : nil)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.tray)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.track, in: Capsule())
    }
}

// MARK: - Progress

/// Çapraz taralı ilerleme çubuğu; boş iz de taralıdır ("elle doldurulmuş" hissi).
struct HatchedBar: View {
    let progress: Double
    let color: Color
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.line)
                Hatch(spacing: 6).stroke(Color.track, lineWidth: 2.5)
                Capsule()
                    .fill(color)
                    .overlay(Hatch(spacing: 5).stroke(Color.white.opacity(0.2), lineWidth: 1.5))
                    .frame(width: max(progress > 0 ? height : 0, proxy.size.width * min(max(progress, 0), 1)))
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text("%\(Int((min(max(progress, 0), 1) * 100).rounded()))"))
    }
}

struct Hatch: Shape {
    var spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width + rect.height {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

// MARK: - People

struct AvatarView: View {
    let member: Member
    var size: CGFloat = 32

    private static let gradients: [[UInt32]] = [
        [0xF7A88B, 0xE27A5C], [0x8EA2F5, 0x5B78EE], [0x8A6650, 0x4E3426], [0xF2C46B, 0xD9A23F],
        [0x7FD6B0, 0x3EC58F], [0xE79AE9, 0xD158D6],
    ]

    var body: some View {
        let colors = Self.gradients[abs(member.colorIndex) % Self.gradients.count].map { Color(hex: $0) }
        Text(member.initial)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            .overlay(Circle().strokeBorder(Color.tray, lineWidth: size > 30 ? 2 : 1))
            .accessibilityLabel(Text(member.name))
    }
}

struct AvatarStack: View {
    let members: [Member]
    var size: CGFloat = 32
    var limit = 4

    var body: some View {
        HStack(spacing: -size * 0.25) {
            ForEach(members.prefix(limit)) { member in
                AvatarView(member: member, size: size)
            }
            if members.count > limit {
                Text("+\(members.count - limit)")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Color.ink2)
                    .frame(width: size, height: size)
                    .background(Color.track, in: Circle())
                    .overlay(Circle().strokeBorder(Color.tray, lineWidth: 2))
            }
        }
    }
}

// MARK: - Places

/// Kapak illüstrasyonu yer tutucusu: pastel yatay bantlar + vuruş dokusu.
/// Nihai sürümde el çizimi pastel boya görseller bunun yerini alacak.
struct CoverArt: View {
    let seed: Int

    private static let palettes: [[UInt32]] = [
        [0x6FA6E6, 0xE7B48E, 0xE58C6B, 0xF4D7A1, 0x3F6FC4],
        [0xF2B9A6, 0xE58C6B, 0xD9644C, 0xA7B98A, 0x7A9A6B],
        [0x9DB7E8, 0xBFD3EE, 0x6E9F7E, 0xC8B6E8, 0xE9D9F7],
        [0xF5D5B8, 0xE6BE96, 0xC9A27A, 0xB9CFA8, 0x9AB89A],
        [0xF4D04E, 0xF0B54A, 0xE3A23B, 0xB6CDEB, 0x8FB3E8],
    ]

    var body: some View {
        let palette = Self.palettes[abs(seed) % Self.palettes.count]
        let weights: [CGFloat] = [0.34, 0.16, 0.16, 0.1, 0.24]
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ForEach(palette.indices, id: \.self) { index in
                    Color(hex: palette[index]).frame(height: proxy.size.height * weights[index])
                }
            }
            .overlay(Hatch(spacing: 6).stroke(Color.white.opacity(0.3), lineWidth: 1.5))
            .overlay(Hatch(spacing: 9).stroke(Color.black.opacity(0.05), lineWidth: 1).rotationEffect(.degrees(90)))
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// Bayrak emojisi küçük yuvarlatılmış çerçevede.
struct FlagBadge: View {
    let countryCode: String

    var body: some View {
        Text(Countries.flag(countryCode))
            .font(.system(size: 16))
            .frame(width: 30, height: 22)
            .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel(Text(Countries.name(countryCode)))
    }
}

/// Numaralı damla pin.
struct NumberedPin: View {
    let number: Int
    let accent: Accent
    var size: CGFloat = 30

    var body: some View {
        ZStack(alignment: .top) {
            PinShape()
                .fill(accent.base)
                .overlay(PinShape().stroke(Color.white, lineWidth: 2.5))
            Text("\(number)")
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(.white)
                .frame(height: size * 0.9)
        }
        .frame(width: size, height: size * 1.2)
        .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
        .accessibilityLabel(Text("\(number). durak"))
    }
}

struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2
        let center = CGPoint(x: rect.midX, y: r)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: center.y),
                      control1: CGPoint(x: rect.midX - r * 0.35, y: rect.maxY - r * 0.45),
                      control2: CGPoint(x: rect.minX, y: center.y + r * 0.75))
        path.addArc(center: center, radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: center.y + r * 0.75),
                      control2: CGPoint(x: rect.midX + r * 0.35, y: rect.maxY - r * 0.45))
        path.closeSubpath()
        return path
    }
}

// MARK: - Empty state

struct EmptyHint: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.ink3)
            Text(text)
                .font(.tBody)
                .foregroundStyle(Color.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
