import SwiftUI
import StublyKit

/// Gitmek istenen ama henüz bir güne konmamış yerler. Elle ya da önerilerden eklenir; "Güne ekle" ile
/// seçili güne taşınır ya da "Otomatik rota" hepsini günlere dağıtır.
struct IdeasCard: View {
    @Environment(TripStore.self) private var store
    let trip: Trip
    let day: Date
    @State private var isAdding = false
    @State private var isSuggesting = false
    @State private var isPlanning = false
    /// Son otomatik rotadan önceki duraklar ve fikirler; "Geri al" bunları geri yükler.
    @State private var undo: (stops: [Stop], ideas: [Stop]?)?

    var body: some View {
        let ideas = trip.ideaList
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Fikirler", systemImage: "lightbulb.fill")
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink)
                if !ideas.isEmpty {
                    Text("\(ideas.count)").font(.tCaption).foregroundStyle(Color.ink3)
                }
                Spacer()
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.circleIcon(size: 32))
                .accessibilityLabel("Fikir ekle")
            }

            if ideas.isEmpty {
                EmptyHint(symbol: "lightbulb", text: String(localized: "Gitmek istediğin yerleri ekle ya da önerilerden seç; sonra otomatik rota günlere dağıtsın."))
            }

            HStack(spacing: 8) {
                Button {
                    isSuggesting = true
                } label: {
                    Label("Yer öner", systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(PillButtonStyle())
                if !ideas.isEmpty {
                    Button {
                        isPlanning = true
                    } label: {
                        Label("Otomatik rota", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(PillButtonStyle(isProminent: true))
                }
                if let undo {
                    Button {
                        withAnimation(.spring(duration: 0.35)) {
                            store.update(trip.id) { trip in
                                trip.stops = undo.stops
                                // Fikirler uygulanınca silindi olarak işaretlendi; eşitlemede kaybolmasınlar
                                // diye geri gelenler yeni kimlik alır.
                                trip.ideas = undo.ideas?.map { idea in
                                    var copy = idea
                                    if trip.tombstones?.contains(idea.id) == true { copy.id = UUID() }
                                    return copy
                                }
                            }
                        }
                        self.undo = nil
                    } label: {
                        Label("Geri al", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }

            ForEach(ideas) { idea in
                HStack(spacing: 12) {
                    Image(systemName: idea.kind.symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ink2)
                        .frame(width: 34, height: 34)
                        .background(Color.track, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(idea.name).font(.subheadline).foregroundStyle(Color.ink).lineLimit(1)
                        if !idea.note.isEmpty {
                            Text(idea.note).font(.caption).foregroundStyle(Color.ink3).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Button {
                        withAnimation(.spring(duration: 0.3)) { schedule(idea) }
                    } label: {
                        Text("\(AppFormat.dayPill(day)) ekle")
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(Color.onInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .contextMenu {
                    Button("Sil", systemImage: "trash", role: .destructive) {
                        withAnimation { store.update(trip.id) { $0.ideas?.removeAll { $0.id == idea.id } } }
                    }
                }
            }
        }
        .tray()
        .sheet(isPresented: $isAdding) {
            AddStopSheet(trip: trip, day: day, asIdea: true)
        }
        .sheet(isPresented: $isSuggesting) {
            PlaceSuggestionsSheet(trip: trip, day: day)
        }
        .sheet(isPresented: $isPlanning) {
            AutoPlanSheet(trip: trip) { before in
                withAnimation { undo = before }
            }
        }
    }

    /// Fikri günün sonuna durak olarak ekler. Durak yeni kimlik alır; böylece fikrin silinmesi
    /// eşitlemede diğer cihazlara da yansır.
    private func schedule(_ idea: Stop) {
        store.update(trip.id) { trip in
            let order = (trip.stops(on: day).map(\.order).max() ?? -1) + 1
            var stop = idea
            stop.id = UUID()
            stop.day = Calendar.current.startOfDay(for: day)
            stop.order = order
            trip.stops.append(stop)
            trip.ideas?.removeAll { $0.id == idea.id }
        }
    }
}

/// Kart içi küçük hap düğme.
struct PillButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(isProminent ? Color.onInk : Color.ink)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(isProminent ? Color.ink : Color.track, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
