import SwiftUI
import StublyKit

/// Destedeki bilet kartı: üstte kapak (fotoğraf ya da pastel), altta çentikle ayrılmış bilet koçanı. Tek şehirde kare;
/// çok şehirli seyahatte her şehir baştan aşağı ayrı bir bilet, biletler yırtık çizgiyle bitişik (koparılmamış gibi).
/// Şehir eklenince yeni bilet önce ayrı durur, sonra diğerlerine yaslanıp birleşir.
///
/// Performans: kart `Equatable`; deste kaydırılırken yalnızca konumu değişir, içeriği yeniden kurulmaz.
/// İçerik `drawingGroup` ile tek dokuya çizilir, gölge ise yalnızca basit bir şeklin gölgesidir.
struct TripTicketCard: View, Equatable {
    let trip: Trip
    let side: CGFloat
    /// Çok şehirli kartın en fazla genişliği (deste ya da form genişliği).
    var maxWidth: CGFloat?
    /// Çok şehirde biletler bitişik mi (şehir eklenince kısa süre ayrı durur).
    @State private var joined = true

    nonisolated static func == (lhs: TripTicketCard, rhs: TripTicketCard) -> Bool {
        lhs.side == rhs.side && lhs.maxWidth == rhs.maxWidth && lhs.trip == rhs.trip
    }

    /// Çok şehirde her ek bilet için genişler (en fazla `maxWidth`).
    static func width(for trip: Trip, side: CGFloat, maxWidth: CGFloat?) -> CGFloat {
        guard trip.isMultiCity else { return side }
        let wanted = side * (1 + 0.3 * CGFloat(panels(for: trip).count - 1))
        return min(wanted, maxWidth ?? wanted).rounded()
    }

    private var width: CGFloat { Self.width(for: trip, side: side, maxWidth: maxWidth) }
    private var coverHeight: CGFloat { (side * 0.6).rounded() }

    /// Kartta en fazla bu kadar bilet yan yana durur; fazlası son bilette "+N şehir" olarak toplanır.
    static let maxPanels = 3

    /// Çok şehirli kartın biletleri: ilk şehirler tek tek, sığmayanlar sondaki ortak bilette.
    static func panels(for trip: Trip) -> [TicketPanel] {
        let legs = trip.cityLegs
        guard legs.count > maxPanels else { return legs.map { TicketPanel(legs: [$0]) } }
        return legs.prefix(maxPanels - 1).map { TicketPanel(legs: [$0]) } + [TicketPanel(legs: Array(legs.dropFirst(maxPanels - 1)))]
    }

    /// Çok şehirli bilette panellerin aralığı (birleşikken sıfır).
    static func gap(joined: Bool) -> CGFloat { joined ? 0 : 12 }

    var body: some View {
        if trip.isMultiCity {
            multiCity
        } else {
            single
        }
    }

    private var single: some View {
        let tint = trip.tint
        return VStack(spacing: 0) {
            cover(tint: tint)
                .frame(height: coverHeight)
            stub(tint: tint)
                .frame(maxHeight: .infinity)
        }
        .frame(width: width, height: side)
        .background(Color.tray)
        .clipShape(TicketShape(notchY: coverHeight))
        .overlay(
            TicketShape(notchY: coverHeight)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .drawingGroup()
        .background {
            TicketShape(notchY: coverHeight)
                .fill(Color.tray)
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                .shadow(color: tint.opacity(0.28), radius: 18, y: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    // MARK: Cover

    private func cover(tint: Color) -> some View {
        ZStack(alignment: .bottomLeading) {
            TripCover(trip: trip, maxPixelSize: CoverImageStore.cardPixelSize)
            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.name)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(trip.countryCodes.map(Countries.flag).joined()) \(trip.cityTitle) · \(AppFormat.dateRange(trip.startDate, trip.endDate))")
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .overlay(alignment: .topTrailing) {
            let tag = trip.countdownTag
            Text(tag.text)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(tag.accent == .gray ? Color.ink2 : tag.accent.base)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                // Materyal (arka plan bulanıklığı) yerine düz zemin: dokuya çizilebilir ve ucuz.
                .background(Color.tray.opacity(0.92), in: Capsule())
                .padding(12)
        }
    }

    // MARK: Stub

    private func stub(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let flight = trip.primaryFlight {
                HStack(alignment: .center, spacing: 10) {
                    code(flight.fromCode, AppFormat.time(flight.departure, timeZone: flight.departureTimeZone))
                    FlightArc(accent: tint)
                        .frame(height: 24)
                    code(flight.toCode, AppFormat.time(flight.arrival, timeZone: flight.arrivalTimeZone), trailing: true)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trip.destination.city)
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        Text("Uçuş eklenmedi")
                            .font(.caption)
                            .foregroundStyle(Color.ink3)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                AvatarStack(members: trip.members, size: 24, limit: 3)
                Text(summary)
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(Color.ink2)
                    .lineLimit(1)
                Spacer(minLength: 4)
                TicketQR(tripID: trip.id)
                    .frame(width: 30, height: 30)
                    .opacity(0.85)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(colors: [tint.opacity(0.10), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .top) {
            Line()
                .stroke(Color.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(height: 1)
                .padding(.horizontal, 16)
        }
    }

    private func code(_ code: String, _ time: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
            Text(code)
                .font(.system(.title2, weight: .semibold))
                .foregroundStyle(Color.ink)
            Text(time)
                .font(.caption)
                .foregroundStyle(Color.ink2)
        }
        .fixedSize()
    }

    private var summary: String {
        var parts = [String(localized: "\(trip.nights()) gece")]
        if trip.members.count > 1 { parts.append(String(localized: "\(trip.members.count) kişi")) }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        "\(trip.name), \(trip.cityTitle), \(AppFormat.dateRange(trip.startDate, trip.endDate)), \(trip.countdownTag.text)"
    }

    fileprivate struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

// MARK: - Çok şehir

extension TripTicketCard {
    private var multiCity: some View {
        let panels = Self.panels(for: trip)
        let legIDs = trip.cityLegs.map(\.id)
        let tint = trip.tint
        let total = width
        let gap = Self.gap(joined: joined)
        let panel = (total - gap * CGFloat(panels.count - 1)) / CGFloat(panels.count)
        return HStack(spacing: gap) {
            ForEach(Array(panels.enumerated()), id: \.element.id) { index, item in
                let seams = (leading: index > 0, trailing: index < panels.count - 1)
                CityTicket(trip: trip, panel: item, index: index, count: panels.count, coverWidth: total,
                           coverOffset: (panel + gap) * CGFloat(index), coverHeight: coverHeight, tint: tint)
                    .frame(width: panel, height: side)
                    .background(Color.tray)
                    .clipShape(TicketShape(notchY: coverHeight, leadingSeam: seams.leading, trailingSeam: seams.trailing))
                    .overlay(
                        TicketShape(notchY: coverHeight, leadingSeam: seams.leading, trailingSeam: seams.trailing, openSeams: true)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    )
                    .overlay(alignment: .trailing) {
                        if seams.trailing { perforation }
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
        }
        .frame(width: total, height: side)
        .drawingGroup()
        .background {
            HStack(spacing: gap) {
                ForEach(Array(panels.enumerated()), id: \.element.id) { index, _ in
                    TicketShape(notchY: coverHeight, leadingSeam: index > 0, trailingSeam: index < panels.count - 1)
                        .fill(Color.tray)
                        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                        .shadow(color: tint.opacity(0.28), radius: 18, y: 12)
                }
            }
        }
        .onChange(of: legIDs) { old, new in
            guard new.count > old.count else { return }
            // Yeni bilet önce ayrı durur, sonra diğerlerine yaslanır.
            joined = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(380))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { joined = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    /// Biletler arasındaki yırtık çizgi: kapakta beyaz, koçanda çizgi rengi; uçlarda yarım ay çentikler.
    private var perforation: some View {
        let notch: CGFloat = 11
        return VStack(spacing: 0) {
            SeamLine()
                .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: 1, height: coverHeight - notch)
            SeamLine()
                .stroke(Color.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: 1)
        }
        .padding(.top, notch)
        .padding(.bottom, notch)
        .opacity(joined ? 1 : 0)
        .offset(x: 0.5)
    }

    private struct SeamLine: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            }
        }
    }
}

/// Çok şehirli kartta bir bilet: tek şehir ya da sığmayan şehirlerin toplandığı "+N şehir" bileti.
struct TicketPanel: Identifiable, Hashable {
    let legs: [TripLeg]
    var id: UUID { legs[0].id }
    var isGroup: Bool { legs.count > 1 }
}

/// Çok şehirli kartta bir bilet: kapak (ortak kapağın kendi dilimi), şehir, tarih ve gece.
private struct CityTicket: View {
    let trip: Trip
    let panel: TicketPanel
    let index: Int
    let count: Int
    /// Ortak kapağın tam genişliği ve bu biletin dilime düşen başlangıcı.
    let coverWidth: CGFloat
    let coverOffset: CGFloat
    let coverHeight: CGFloat
    let tint: Color

    private var isFirst: Bool { index == 0 }
    private var isLast: Bool { index == count - 1 }
    private var leg: TripLeg { panel.legs[0] }

    var body: some View {
        VStack(spacing: 0) {
            cover.frame(height: coverHeight)
            stub.frame(maxHeight: .infinity)
        }
    }

    /// Bir şehirde geçen gece; aynı gün başka şehre geçiliyorsa günübirlik.
    private func nightsText(_ leg: TripLeg) -> String {
        let isFinal = leg.id == trip.cityLegs.last?.id
        let nights = max(trip.days(in: leg).count - (isFinal ? 1 : 0), 0)
        return nights == 0 ? String(localized: "Günübirlik") : String(localized: "\(nights) gece")
    }

    private var cover: some View {
        let start = trip.dateRange(of: panel.legs[0]).start
        let end = trip.dateRange(of: panel.legs[panel.legs.count - 1]).end
        return ZStack(alignment: .bottomLeading) {
            // Ortak kapak tam genişlikte çizilir, bu bilet yalnızca kendi dilimini gösterir.
            Color.clear
                .overlay(alignment: .topLeading) {
                    TripCover(trip: trip, maxPixelSize: CoverImageStore.cardPixelSize)
                        .frame(width: coverWidth, height: coverHeight)
                        .offset(x: -coverOffset)
                }
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                if isFirst {
                    Text(trip.name)
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                Group {
                    if panel.isGroup {
                        Text("+\(panel.legs.count) şehir")
                    } else {
                        Text("\(Countries.flag(leg.destination.countryCode)) \(leg.destination.city)")
                    }
                }
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Text(AppFormat.dateRange(start, end))
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.bottom, 14)
        }
        .overlay(alignment: .topTrailing) {
            if isLast {
                let tag = trip.countdownTag
                Text(tag.text)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(tag.accent == .gray ? Color.ink2 : tag.accent.base)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.tray.opacity(0.92), in: Capsule())
                    .padding(12)
            }
        }
    }

    private var stub: some View {
        VStack(alignment: .leading, spacing: 4) {
            if panel.isGroup {
                // Sığmayan şehirler: bayrak ve ad (dar bilette gece sığmaz); çok uzunsa son satır "+N".
                let shown = panel.legs.prefix(3)
                ForEach(Array(shown), id: \.id) { leg in
                    Text("\(Countries.flag(leg.destination.countryCode)) \(leg.destination.city)")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if panel.legs.count > shown.count {
                    Text("+\(panel.legs.count - shown.count)")
                        .font(.caption2)
                        .foregroundStyle(Color.ink3)
                }
            } else {
                Text(nightsText(leg))
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if isFirst, let flight = trip.primaryFlight {
                    Label("\(flight.fromCode) → \(flight.toCode) · \(AppFormat.time(flight.departure, timeZone: flight.departureTimeZone))",
                          systemImage: "airplane")
                        .font(.caption)
                        .foregroundStyle(Color.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text(AppFormat.dayPill(leg.arrival))
                        .font(.caption)
                        .foregroundStyle(Color.ink3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 2)
            HStack(spacing: 8) {
                if isFirst {
                    AvatarStack(members: trip.members, size: 24, limit: 3)
                }
                Spacer(minLength: 4)
                if isLast {
                    TicketQR(tripID: trip.id)
                        .frame(width: 30, height: 30)
                        .opacity(0.85)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(colors: [tint.opacity(0.10), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .top) {
            TripTicketCard.Line()
                .stroke(Color.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(height: 1)
                .padding(.leading, isFirst ? 16 : 0)
                .padding(.trailing, isLast ? 16 : 0)
        }
    }
}
