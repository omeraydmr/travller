import SwiftUI
import StublyKit

/// Kare bilet kartlarından oluşan, sağa sola kaydırılan ve dairesel bir yörüngede
/// birbirinin arkasına dizilen deste. Arkadaki kartlar hafif bulanıklaşır.
struct TripDeck: View {
    let trips: [Trip]
    @Binding var index: Int
    var onOpen: (Trip) -> Void
    var onEdit: (Trip) -> Void
    var onChangeCover: (Trip) -> Void
    var onRemoveCover: (Trip) -> Void
    var onDelete: (Trip) -> Void
    /// Kartın köşesindeki QR'a dokununca davet ekranı.
    var onInvite: (Trip) -> Void
    /// Yeni oluşturulup damgalanan seyahat; yukarıdan uçarak girer ve kısa süre damga izini taşır.
    var arrivingID: Trip.ID?

    @GestureState(resetTransaction: Transaction(animation: TripDeck.settleAnimation))
    private var dragOffset: CGFloat = 0

    static let settleAnimation = Animation.spring(response: 0.45, dampingFraction: 0.82)
    private let geometry = CarouselGeometry()

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width - 88, 320)
            let travel = side * 0.6
            let progress = Double(index) - Double(dragOffset / travel)

            ZStack {
                ForEach(Array(trips.enumerated()), id: \.element.id) { position, trip in
                    let relative = Double(position) - progress
                    if geometry.isVisible(relative) {
                        let t = geometry.transform(relative: relative)
                        TripTicketCard(trip: trip, side: side, maxWidth: proxy.size.width - 24)
                            .equatable()
                            .overlay {
                                if trip.id == arrivingID {
                                    StampImprint(subtitle: StampImprint.subtitle(for: trip), scale: side / 280)
                                        .offset(y: side * 0.18)
                                        .transition(.opacity)
                                }
                            }
                            .overlay(alignment: .bottomTrailing) {
                                // Koçandaki QR'ın üstünde dokunma alanı (yalnızca öndeki kartta).
                                if position == index {
                                    Color.clear
                                        .frame(width: 56, height: 56)
                                        .contentShape(Rectangle())
                                        .onTapGesture { onInvite(trip) }
                                        .accessibilityLabel(Text("QR ile davet et"))
                                        .accessibilityAddTraits(.isButton)
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .offset(y: -side * 1.6).combined(with: .scale(scale: 0.5)).combined(with: .opacity),
                                removal: .opacity.combined(with: .scale(scale: 0.8))))
                            .scaleEffect(t.scale)
                            .rotationEffect(.degrees(t.rotationDegrees), anchor: .bottom)
                            .offset(x: t.x, y: t.y)
                            // Bulanıklık yarım puanlık adımlarla değişir; her karede yeniden süzülmez.
                            .blur(radius: (t.blur * 2).rounded() / 2, opaque: false)
                            .opacity(t.opacity)
                            .zIndex(t.zIndex)
                            .onTapGesture {
                                if position == index {
                                    onOpen(trip)
                                } else {
                                    withAnimation(Self.settleAnimation) { index = position }
                                }
                            }
                            .contextMenu { menu(for: trip) }
                            .accessibilityHidden(position != index)
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10)
                    .updating($dragOffset) { value, state, _ in
                        state = rubberBand(value.translation.width)
                    }
                    .onEnded { value in
                        let predicted = Double(index) - Double(value.predictedEndTranslation.width / travel)
                        withAnimation(Self.settleAnimation) {
                            index = CarouselGeometry.settle(from: index, predictedProgress: predicted, count: trips.count)
                        }
                    }
            )
        }
        .sensoryFeedback(.selection, trigger: index)
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: index = min(index + 1, trips.count - 1)
            case .decrement: index = max(index - 1, 0)
            @unknown default: break
            }
        }
    }

    /// Destenin uçlarında çekişi yumuşatır.
    private func rubberBand(_ translation: CGFloat) -> CGFloat {
        let atStart = index == 0 && translation > 0
        let atEnd = index == trips.count - 1 && translation < 0
        return atStart || atEnd ? translation * 0.3 : translation
    }

    @ViewBuilder
    private func menu(for trip: Trip) -> some View {
        Button("Aç", systemImage: "arrow.up.forward.app") { onOpen(trip) }
        Button("Düzenle", systemImage: "pencil") { onEdit(trip) }
        Button("QR ile davet et", systemImage: "qrcode") { onInvite(trip) }
        Button("Kapak fotoğrafı seç", systemImage: "photo") { onChangeCover(trip) }
        if trip.coverPhoto != nil {
            Button("Fotoğrafı kaldır", systemImage: "photo.badge.minus") { onRemoveCover(trip) }
        }
        Button("Seyahati sil", systemImage: "trash", role: .destructive) { onDelete(trip) }
    }
}

/// Destenin altındaki sayfa göstergesi; etkin nokta seyahatin rengini alır.
struct DeckIndicator: View {
    let trips: [Trip]
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(trips.enumerated()), id: \.element.id) { position, trip in
                Capsule()
                    .fill(position == index ? trip.tint : Color.ink3.opacity(0.4))
                    .frame(width: position == index ? 20 : 6, height: 6)
            }
        }
        .animation(TripDeck.settleAnimation, value: index)
        .accessibilityHidden(true)
    }
}
