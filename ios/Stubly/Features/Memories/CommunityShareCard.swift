import SwiftUI
import StublyKit

/// Seyahat bitince: gidilen yerleri beğeni/beğenmeme ile topluluk öneri havuzuna paylaşma onayı.
/// Yalnızca yer adı, konumu, türü, oy ve aynı gün art arda gidilen yer çiftleri gider.
struct CommunityShareCard: View {
    let trip: Trip
    /// Fotoğraflarla doğrulanan duraklar.
    let verified: Set<UUID>

    @State private var choice: CommunityService.Choice?
    @State private var ratings: [UUID: Int] = [:]
    @State private var excluded: Set<UUID> = []
    @State private var isExpanded = false
    @State private var isSending = false
    @State private var errorText: String?
    private var service: CommunityService { .shared }

    var body: some View {
        Group {
            if choice == .shared {
                Label("Yerlerin topluluk önerilerine eklendi. Teşekkürler!", systemImage: "heart.fill")
                    .font(.tBody)
                    .foregroundStyle(Color.ink2)
                    .tray(padding: 14)
            } else if choice == nil {
                prompt.tray()
            }
        }
        .onAppear { choice = service.choice(for: trip) }
    }

    private var prompt: some View {
        let stops = CommunityPlaces.eligibleStops(in: trip)
        return VStack(alignment: .leading, spacing: 12) {
            Label("Gittiğin yerleri diğer gezginlere öner", systemImage: "person.3.sequence.fill")
                .font(.tBodyStrong)
                .foregroundStyle(Color.ink)
            Text("Beğendiklerini işaretle; en az üç gezginin gittiği yerler Önerilen yerler'de çıkar. Yalnızca yer adı, konumu, oyun ve aynı gün hangi yerden sonra nereye gittiğin paylaşılır — adın, tarihlerin, notların ve ekibin paylaşılmaz.")
                .font(.footnote)
                .foregroundStyle(Color.ink2)

            Button {
                withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("\(stops.count - excluded.count) yer · oyla")
                        .font(.system(.subheadline, weight: .semibold))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.ink)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(stops) { stop in
                    row(stop)
                }
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Color.food)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await share() }
                } label: {
                    if isSending { ProgressView().tint(Color.onInk) } else { Text("Paylaş") }
                }
                .buttonStyle(PillButtonStyle(isProminent: true))
                .disabled(isSending || stops.count == excluded.count)
                Button("Paylaşma") {
                    service.setChoice(.declined, for: trip)
                    withAnimation { choice = .declined }
                }
                .buttonStyle(PillButtonStyle())
            }
        }
    }

    private func row(_ stop: Stop) -> some View {
        let isExcluded = excluded.contains(stop.id)
        let rating = ratings[stop.id] ?? 0
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(stop.name).font(.subheadline).foregroundStyle(isExcluded ? Color.ink3 : Color.ink).strikethrough(isExcluded)
                if verified.contains(stop.id) {
                    Label("Fotoğraflarla doğrulandı", systemImage: "checkmark.seal").font(.caption2).foregroundStyle(Color.success)
                }
            }
            Spacer(minLength: 4)
            vote(stop, value: 1, symbol: "hand.thumbsup", isOn: rating == 1, label: String(localized: "Beğendim"))
            vote(stop, value: -1, symbol: "hand.thumbsdown", isOn: rating == -1, label: String(localized: "Beğenmedim"))
            Button {
                if isExcluded { excluded.remove(stop.id) } else { excluded.insert(stop.id) }
            } label: {
                Image(systemName: isExcluded ? "eye.slash.fill" : "eye").frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isExcluded ? Color.food : Color.ink3)
            .accessibilityLabel(isExcluded ? String(localized: "Paylaşıma ekle") : String(localized: "Paylaşma"))
        }
        .opacity(isExcluded ? 0.6 : 1)
    }

    private func vote(_ stop: Stop, value: Int, symbol: String, isOn: Bool, label: String) -> some View {
        Button {
            ratings[stop.id] = isOn ? 0 : value
        } label: {
            Image(systemName: isOn ? symbol + ".fill" : symbol).frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? (value > 0 ? Color.success : Color.food) : Color.ink3)
        .disabled(excluded.contains(stop.id))
        .accessibilityLabel(label)
    }

    private func share() async {
        guard let contribution = CommunityPlaces.contribution(for: trip, ratings: ratings, verified: verified,
                                                              excluded: excluded) else { return }
        isSending = true
        defer { isSending = false }
        errorText = nil
        do {
            try await service.contribute(contribution)
            service.setChoice(.shared, for: trip)
            withAnimation { choice = .shared }
        } catch CommunityService.Failure.rejected(429) {
            errorText = String(localized: "Bugün için paylaşım sınırına ulaştın; yarın tekrar dene.")
        } catch {
            errorText = String(localized: "Paylaşılamadı; internet bağlantını kontrol et.")
        }
    }
}
