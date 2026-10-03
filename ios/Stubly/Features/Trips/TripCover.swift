import SwiftUI
import StublyKit

/// Seyahatin kapağı: kullanıcının fotoğrafı, yoksa pastel yer tutucu.
struct TripCover: View {
    let trip: Trip
    /// Verilirse fotoğraf bu boyuta küçültülmüş haliyle çizilir (destedeki kartlar).
    var maxPixelSize: CGFloat?
    @Environment(\.coverOverride) private var override

    private func photo(named name: String) -> UIImage? {
        if let maxPixelSize { return CoverImageStore.shared.thumbnail(named: name, maxPixelSize: maxPixelSize) }
        return CoverImageStore.shared.image(named: name)
    }

    var body: some View {
        if let override {
            Color.clear
                .overlay(Image(uiImage: override).resizable().scaledToFill())
                .clipped()
                .accessibilityHidden(true)
        } else if let name = trip.coverPhoto, let image = photo(named: name) {
            Color.clear
                .overlay(Image(uiImage: image).resizable().scaledToFill())
                .clipped()
                .accessibilityHidden(true)
        } else {
            CoverArt(seed: trip.coverSeed)
        }
    }
}

/// Henüz kaydedilmemiş bir kapak fotoğrafını önizlemek için (yeni seyahat formu).
private struct CoverOverrideKey: EnvironmentKey {
    static let defaultValue: UIImage? = nil
}

extension EnvironmentValues {
    var coverOverride: UIImage? {
        get { self[CoverOverrideKey.self] }
        set { self[CoverOverrideKey.self] = newValue }
    }
}

extension Trip {
    /// Kartların dinamik vurgu rengi: fotoğrafın baskın tonu, yoksa paletten bir kategori rengi.
    @MainActor
    var tint: Color {
        if let name = coverPhoto, let color = CoverImageStore.shared.dominantColor(named: name) {
            return color
        }
        return Accent.cycle(coverSeed).base
    }

    var countdownTag: (text: String, accent: Accent) {
        if status == .draft { return ("Taslak", .orange) }
        let countdown = Countdown.make(start: startDate, end: endDate)
        let accent: Accent = switch countdown {
        case .days, .today: .blue
        case .months: .purple
        case .ongoing: .green
        case .past: .gray
        }
        return (AppFormat.countdown(countdown), accent)
    }
}
