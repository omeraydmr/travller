import SwiftUI
import StublyKit
import UIKit
import WidgetKit

/// Seyahatler değişince ana ekran widget'ının okuduğu özeti yazar ve widget'ı yeniler.
@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()
    private var task: Task<Void, Never>?
    private var lastWritten: WidgetSnapshot?

    func tripsChanged(_ trips: [Trip]) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            write(trips)
        }
    }

    private func write(_ trips: [Trip]) {
        let snapshot = WidgetSnapshot(
            trips: trips,
            flag: { Countries.flag($0) },
            tint: { $0.tint.rgbHex },
            symbol: { $0.symbol },
            flightLabel: { flight in
                "\(flight.fromCode) → \(flight.toCode) · \(AppFormat.time(flight.departure, timeZone: flight.departureTimeZone))"
            })
        guard snapshot != lastWritten, let url = SharedContainer.snapshotURL,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try data.write(to: url, options: .atomic)
            lastWritten = snapshot
            WidgetCenter.shared.reloadTimelines(ofKind: SharedContainer.widgetKind)
        } catch {
            // App Group yetkisi yoksa widget örnek veriyle kalır.
        }
    }
}

extension Color {
    /// Açık görünümdeki 0xRRGGBB değeri (widget ve canlı kart için).
    var rgbHex: UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> UInt32 { UInt32(max(0, min(255, (value * 255).rounded()))) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }
}
