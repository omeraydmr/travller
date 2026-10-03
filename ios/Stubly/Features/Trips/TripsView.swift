import SwiftUI
import StublyKit

/// Seyahat detayına giden rota; isteğe bağlı olarak belirli bir sekmeyle açılır.
struct TripRoute: Hashable {
    let id: Trip.ID
    var section: TripDetailView.TripSection = .plan
}

struct TripsView: View {
    @Environment(TripStore.self) private var store
    @State private var scope: Scope = .upcoming
    @State private var isOnboarding = false
    @State private var index = 0
    @State private var isCreating = false
    @State private var path: [TripRoute] = []
    @State private var coverTarget: Trip.ID?
    @State private var editing: Trip?
    @State private var inviting: Trip?
    @State private var pendingDelete: Trip?
    @State private var isShowingProfile = false
    @State private var arrivingID: Trip.ID?

    enum Scope: Hashable { case upcoming, past }

    private var trips: [Trip] { scope == .upcoming ? store.upcoming : store.past }
    private var focusedIndex: Int { min(max(index, 0), max(trips.count - 1, 0)) }
    private var focused: Trip? { trips.isEmpty ? nil : trips[focusedIndex] }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if trips.isEmpty {
                    emptyState
                } else {
                    TripDeck(
                        trips: trips,
                        index: Binding(get: { focusedIndex }, set: { index = $0 }),
                        onOpen: { path.append(TripRoute(id: $0.id, section: preferredSection)) },
                        onEdit: { editing = $0 },
                        onChangeCover: { coverTarget = $0.id },
                        onRemoveCover: { trip in withAnimation { store.removeCoverPhoto(for: trip.id) } },
                        onDelete: { pendingDelete = $0 },
                        onInvite: { inviting = $0 },
                        arrivingID: arrivingID
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)

                    DeckIndicator(trips: trips, index: focusedIndex)
                        .padding(.top, 4)

                    if let focused {
                        TripGlance(trip: focused) { section in
                            path.append(TripRoute(id: focused.id, section: section))
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .id(focused.id)
                        .transition(.opacity)
                    }
                }

                Spacer(minLength: 12)

                Button {
                    isCreating = true
                } label: {
                    Label("Seyahat planla", systemImage: "plus")
                }
                .buttonStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .background { background }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TripRoute.self) { route in
                TripDetailView(tripID: route.id, initialSection: route.section)
            }
            .sheet(isPresented: $isCreating) {
                NewTripSheet { trip in
                    // Damgalanan bilet desteye uçarak girer ve öne gelir.
                    arrivingID = trip.id
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) {
                        scope = .upcoming
                        store.add(trip)
                        index = store.upcoming.firstIndex { $0.id == trip.id } ?? 0
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(2.2))
                        withAnimation(.easeOut(duration: 0.5)) { arrivingID = nil }
                    }
                }
            }
            .coverPhotoPicker(for: $coverTarget)
            .sheet(isPresented: $isShowingProfile) { ProfileView() }
            .sheet(item: $editing) { trip in TripEditSheet(trip: trip) }
            .sheet(item: $inviting) { trip in InviteQRSheet(trip: trip) }
            .sheet(item: Binding(get: { AppRouter.shared.pendingImport }, set: { AppRouter.shared.pendingImport = $0 })) { file in
                IncomingBookingSheet(url: file.url)
            }
            .fullScreenCover(isPresented: $isOnboarding) {
                OnboardingView(store: store) { planFirstTrip in
                    isOnboarding = false
                    if planFirstTrip {
                        Task {
                            try? await Task.sleep(for: .milliseconds(450))
                            isCreating = true
                        }
                    }
                }
            }
            .onAppear {
                if !store.hasCompletedOnboarding { isOnboarding = true }
            }
            .onChange(of: store.hasCompletedOnboarding) { _, completed in
                // Profilden "tanıtımı yeniden göster": önce profil sayfası kapansın.
                guard !completed, !isOnboarding else { return }
                isShowingProfile = false
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    isOnboarding = true
                }
            }
            .confirmationDialog("Seyahat silinsin mi?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible, presenting: pendingDelete) { trip in
                Button("\(trip.name) seyahatini sil", role: .destructive) {
                    withAnimation(TripDeck.settleAnimation) { store.delete(trip.id) }
                }
            } message: { _ in
                Text("Plan, harcamalar ve valiz listesi de silinir.")
            }
            .onChange(of: scope) { _, _ in index = 0 }
            // Kapak küçük görsellerini ve renklerini arka planda hazırla: ilk kaydırma takılmasın.
            .task(id: store.trips.compactMap(\.coverPhoto)) {
                await CoverImageStore.shared.prewarm(store.trips.compactMap(\.coverPhoto))
            }
            .onChange(of: AppRouter.shared.pending) { _, _ in openPendingLink() }
            .onAppear { openPendingLink() }
            .animation(.easeInOut(duration: 0.25), value: focused?.id)
        }
    }

    /// Bildirim ya da widget'tan gelen bağlantı: seyahati destede öne al ve sekmesini aç.
    private func openPendingLink() {
        guard let link = AppRouter.shared.pending else { return }
        AppRouter.shared.pending = nil
        guard let trip = store.trip(link.tripID) else { return }
        isCreating = false
        isShowingProfile = false
        let target: Scope = trip.isPast() ? .past : .upcoming
        let list = target == .past ? store.past : store.upcoming
        scope = target
        // Kapsam değişince index sıfırlanır; konumu ondan sonra ver.
        if let position = list.firstIndex(where: { $0.id == trip.id }) {
            Task { @MainActor in index = position }
        }
        path = [TripRoute(id: trip.id, section: TripDetailView.TripSection(link: link))]
    }

    private var header: some View {
        HStack {
            // Dar ekranda seçici yazıları kesilmesin; gerekirse başlık küçülür.
            Label("Seyahatler", systemImage: "suitcase.fill")
                .font(.tTitle)
                .foregroundStyle(Color.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(-1)
            Spacer(minLength: 8)
            PillPicker(selection: $scope, options: [.upcoming, .past]) { $0 == .upcoming ? String(localized: "Yaklaşan") : String(localized: "Geçmiş") }
                .fixedSize()
            Button {
                isShowingProfile = true
            } label: {
                AvatarView(member: store.me, size: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profil ve ayarlar")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "map")
                .font(.system(size: 40))
                .foregroundStyle(Color.ink3)
            Text(scope == .upcoming ? String(localized: "Henüz planlanmış bir seyahat yok.") : String(localized: "Geçmiş seyahat yok."))
                .font(.tBodyStrong)
                .foregroundStyle(Color.ink2)
            if scope == .upcoming {
                Text("Aşağıdan ilk seyahatini planla ya da bir arkadaşının iCloud davetini aç.")
                    .font(.tBody)
                    .foregroundStyle(Color.ink3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Anketteki ilgiye göre seyahat açılınca ilk gelen sekme.
    private var preferredSection: TripDetailView.TripSection {
        TripDetailView.TripSection(rawValue: store.preferences.preferredSection) ?? .plan
    }

    /// Odaktaki seyahatin renginden gelen yumuşak ışık.
    private var background: some View {
        TintGlow(tint: focused?.tint ?? Color.ink3)
            .animation(.easeInOut(duration: 0.6), value: focusedIndex)
    }
}

/// Odaktaki seyahatin üç kısa göstergesi: vize, bütçe, valiz. Dokununca ilgili sekme açılır.
struct TripGlance: View {
    let trip: Trip
    let open: (TripDetailView.TripSection) -> Void
    @Environment(TripStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            tile(.visa, symbol: "person.text.rectangle.fill", accent: visa.accent, value: visa.value, caption: String(localized: "Vize"))
            tile(.money, symbol: "chart.pie.fill", accent: .blue, value: budgetValue, caption: String(localized: "Bütçe"))
            tile(.packing, symbol: "bag.fill", accent: .purple, value: packingValue, caption: String(localized: "Valiz"))
        }
    }

    private func tile(_ section: TripDetailView.TripSection, symbol: String, accent: Accent, value: String,
                      caption: String) -> some View {
        Button {
            open(section)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent.base)
                    .frame(width: 28, height: 28)
                    .background(accent.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(value)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Color.ink3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(caption): \(value)"))
    }

    private var visa: (value: String, accent: Accent) {
        let pending = trip.members.filter { store.visaAssessment(for: $0, in: trip).needsAction }.count
        return pending == 0 ? (String(localized: "Hazır ✓"), .green) : (String(localized: "\(pending) kişi bekliyor"), .orange)
    }

    private var budgetValue: String {
        let summary = Budget.summary(for: trip)
        guard summary.limit > 0 else { return AppFormat.money(summary.spent, trip.currency) }
        return "%\(Int((Double(summary.spent) / Double(summary.limit) * 100).rounded()))"
    }

    private var packingValue: String {
        guard !trip.packing.isEmpty else { return String(localized: "Boş") }
        return "\(trip.packing.filter(\.isPacked).count)/\(trip.packing.count)"
    }
}
