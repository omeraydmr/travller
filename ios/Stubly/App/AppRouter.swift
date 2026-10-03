import Foundation
import Observation
import StublyKit

/// Bildirimden, widget'tan ya da canlı karttan gelen "şu seyahatin şu sekmesini aç" isteği.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    /// Ana ekran işleyene kadar bekleyen bağlantı.
    var pending: TripLink?

    func open(_ link: TripLink) {
        pending = link
    }

    /// Başka uygulamadan açılan rezervasyon dosyası (Wallet kartı, PDF); geçici kopyası.
    var pendingImport: IncomingFile?

    struct IncomingFile: Identifiable, Equatable {
        let id = UUID()
        let url: URL
    }

    /// Dosyayı geçici klasöre kopyalar (paylaşan uygulamanın erişimi kalkmasın) ve içe aktarmayı başlatır.
    func importFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
        guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else { return }
        pendingImport = IncomingFile(url: copy)
    }
}

extension TripDetailView.TripSection {
    init(link: TripLink) {
        self = link.section.flatMap(Self.init(rawValue:)) ?? .plan
    }
}
