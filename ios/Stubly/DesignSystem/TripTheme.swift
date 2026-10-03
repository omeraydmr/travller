import SwiftUI
import StublyKit

// Seyahatin dinamik rengi (kapak fotoğrafının tonu ya da palet rengi) alt ekranlara ortam
// değeri olarak iner; vurgu noktaları, halkalar ve arka plan ışığı bu rengi kullanır.

private struct TripTintKey: EnvironmentKey {
    static let defaultValue: Color = .ink
}

extension EnvironmentValues {
    var tripTint: Color {
        get { self[TripTintKey.self] }
        set { self[TripTintKey.self] = newValue }
    }
}

/// Zemin + seyahat renginden yumuşak bir ışık.
/// Büyük yarıçaplı bulanıklık yerine radyal gradyan: aynı görünüm, renk geçişinde her kare ucuz.
struct TintGlow: View {
    let tint: Color
    var offsetY: CGFloat = -140
    var size: CGFloat = 440

    var body: some View {
        ZStack {
            Color.canvas
            RadialGradient(
                stops: [
                    .init(color: tint.opacity(0.3), location: 0),
                    .init(color: tint.opacity(0.18), location: 0.35),
                    .init(color: tint.opacity(0.06), location: 0.7),
                    .init(color: tint.opacity(0), location: 1),
                ],
                center: .center, startRadius: 0, endRadius: size * 0.75)
                .frame(width: size * 1.5, height: size * 1.5)
                .offset(y: offsetY)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Rings & donut

/// İnce, yuvarlak uçlu ilerleme halkası.
struct ProgressRing<Label: View>: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 8
    @ViewBuilder var label: () -> Label

    var body: some View {
        ZStack {
            Circle().stroke(Color.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label()
        }
        .animation(.spring(duration: 0.5), value: progress)
    }
}

/// Kategori dilimlerinden oluşan halka grafik. Dilimler limitin toplamına göre ölçeklenir,
/// limit yoksa harcamaların toplamına göre.
struct DonutSlice: Identifiable {
    let id: String
    let value: Double
    let color: Color
}

struct DonutChart<Center: View>: View {
    let slices: [DonutSlice]
    let total: Double
    var lineWidth: CGFloat = 16
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle().stroke(Color.track, lineWidth: lineWidth)
            ForEach(segments) { segment in
                Circle()
                    .trim(from: segment.start, to: segment.end)
                    .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            center()
        }
        .animation(.spring(duration: 0.6), value: slices.map(\.value))
        .accessibilityElement(children: .combine)
    }

    /// Dilimlerin [0, 1] aralığındaki başlangıç/bitişleri; aralarında küçük boşluk bırakılır.
    private struct Segment: Identifiable {
        let id: String
        let color: Color
        let start: Double
        let end: Double
    }

    private var segments: [Segment] {
        let denominator = max(total, slices.reduce(0) { $0 + $1.value }, 1)
        let gap = slices.count > 1 ? 0.006 : 0
        var cursor = 0.0
        return slices.compactMap { slice -> Segment? in
            let length = slice.value / denominator
            defer { cursor += length }
            guard length > gap * 2 else { return nil }
            return Segment(id: slice.id, color: slice.color, start: cursor + gap, end: cursor + length - gap)
        }
    }
}

// MARK: - Day chips

/// Gün seçici: kısa gün adı, büyük gün numarası ve durak sayısı kadar nokta.
struct DayChips: View {
    let days: [Date]
    @Binding var selection: Date
    let stopCount: (Date) -> Int
    /// Sürüklenen bir durak bu güne bırakıldığında çağrılır.
    var onDropStop: ((UUID, Date) -> Void)?
    /// Çok şehirli seyahatte günün şehri: ad, renk, şehrin ilk günü mü (ad orada yazılır), geçiş günü mü.
    var city: ((Date) -> (name: String, color: Color, isFirstDay: Bool, isTransition: Bool))?
    @Environment(\.tripTint) private var tint
    @State private var dropTarget: Date?

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(days.enumerated()), id: \.element) { index, day in
                        if let city = city?(day) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(city.isFirstDay ? city.name : " ")
                                    .font(.system(.caption2, weight: .semibold))
                                    .foregroundStyle(city.color)
                                    .lineLimit(1)
                                    .fixedSize()
                                    .frame(width: 52, alignment: .leading)
                                chip(day, number: index + 1)
                                    .overlay(alignment: .topTrailing) {
                                        if city.isTransition {
                                            Image(systemName: "arrow.right.circle.fill")
                                                .font(.system(size: 13))
                                                .foregroundStyle(city.color)
                                                .background(Circle().fill(Color.tray))
                                                .offset(x: 4, y: -4)
                                                .accessibilityLabel(String(localized: "Geçiş günü"))
                                        }
                                    }
                                Capsule().fill(city.color).frame(width: 52, height: 3)
                            }
                            .id(day)
                        } else {
                            chip(day, number: index + 1)
                                .id(day)
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            .onAppear { reader.scrollTo(selection, anchor: .center) }
        }
    }

    private func chip(_ day: Date, number: Int) -> some View {
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selection)
        let count = stopCount(day)
        return Button {
            withAnimation(.spring(duration: 0.3)) { selection = day }
        } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.abbreviated).locale(AppFormat.locale)))
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(isSelected ? Color.onInk.opacity(0.7) : Color.ink3)
                Text(day.formatted(.dateTime.day().locale(AppFormat.locale)))
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.onInk : Color.ink)
                HStack(spacing: 3) {
                    ForEach(0..<min(count, 4), id: \.self) { _ in
                        Circle().fill(isSelected ? tint : Color.ink3).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(width: 52, height: 72)
            .background(isSelected ? Color.ink : Color.tray, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tint, lineWidth: dropTarget == day ? 3 : 0)
            )
            .scaleEffect(dropTarget == day ? 1.08 : 1)
            .animation(.spring(duration: 0.2), value: dropTarget)
            .softShadow()
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { items, _ in
            guard let onDropStop, let first = items.first, let id = UUID(uuidString: first) else { return false }
            onDropStop(id, day)
            return true
        } isTargeted: { targeted in
            if targeted { dropTarget = day } else if dropTarget == day { dropTarget = nil }
        }
        .accessibilityLabel(Text("\(number). gün, \(AppFormat.dayPill(day)), \(count) durak"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Stat chip

/// Küçük ikonlu bilgi hapı: "4 durak", "3,1 km", "41 dk".
struct StatChip: View {
    let symbol: String
    let text: String
    var accent: Accent = .gray

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(.footnote, weight: .medium))
            .foregroundStyle(accent == .gray ? Color.ink2 : accent.base)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(accent.tint, in: Capsule())
    }
}
