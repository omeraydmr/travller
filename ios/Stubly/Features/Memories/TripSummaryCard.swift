import SwiftUI
import StublyKit

/// Anılar sekmesinde paylaşılabilir seyahat özeti: gün, durak, rota, harcama ve öne çıkanlar.
struct TripSummaryCard: View {
    let trip: Trip
    @Environment(\.displayScale) private var displayScale
    /// Paylaşılacak görsel; her çizimde değil, özet değişince bir kez üretilir.
    @State private var image: UIImage?

    var body: some View {
        let summary = TripSummary.make(trip)
        VStack(alignment: .leading, spacing: 12) {
            TripSummaryPoster(trip: trip, summary: summary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
            if let image {
                ShareLink(item: Image(uiImage: image),
                          preview: SharePreview("\(trip.name) özeti", image: Image(uiImage: image))) {
                    Label("Özeti paylaş", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.primary)
            }
        }
        .task(id: summary) { image = render(summary) }
    }

    @MainActor
    private func render(_ summary: TripSummary) -> UIImage? {
        let renderer = ImageRenderer(content: TripSummaryPoster(trip: trip, summary: summary).frame(width: 360))
        renderer.scale = displayScale
        return renderer.uiImage
    }
}

/// Özet kartının kendisi (ekranda ve paylaşılan görselde aynı).
struct TripSummaryPoster: View {
    let trip: Trip
    let summary: TripSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(trip.countryCodes.map(flag).joined()) \(trip.cityTitle)")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(trip.name).font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                Text("\(AppFormat.dayPill(trip.startDate)) – \(AppFormat.dayPill(trip.endDate))")
                    .font(.footnote).foregroundStyle(.white.opacity(0.8))
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    tile("\(summary.days)", String(localized: "gün"))
                    tile("\(summary.stops)", String(localized: "durak"))
                    tile("\((summary.routeMeters / 1000).formatted(.number.precision(.fractionLength(1)).locale(AppFormat.locale))) km", String(localized: "rota"))
                }
                GridRow {
                    tile("\(summary.travellers)", String(localized: "kişi"))
                    tile(AppFormat.money(summary.totalSpent, trip.currency), String(localized: "harcama"))
                    tile(AppFormat.money(summary.perPerson, trip.currency), String(localized: "kişi başı"))
                }
            }
            if !summary.highlights.isEmpty {
                Text(String(localized: "Öne çıkanlar: ") + summary.highlights.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.white.opacity(0.9))
            }
            Text("Stubly").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [trip.tint, trip.tint.opacity(0.65)], startPoint: .topLeading,
                                   endPoint: .bottomTrailing))
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.headline, weight: .bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }.map(String.init).joined()
    }
}
