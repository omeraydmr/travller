import SwiftUI
import StublyKit

struct TripDetailView: View {
    @Environment(TripStore.self) private var store
    let tripID: Trip.ID
    @State private var section: TripSection
    @State private var coverTarget: Trip.ID?
    @State private var isEditingTrip = false
    @State private var calendarMessage: String?
    @State private var isHeroCollapsed = false

    init(tripID: Trip.ID, initialSection: TripSection = .plan) {
        self.tripID = tripID
        _section = State(initialValue: initialSection)
    }

    enum TripSection: String, CaseIterable, Hashable {
        case plan, money, packing, visa, crew, memories

        var title: String {
            switch self {
            case .plan: String(localized: "Plan")
            case .money: String(localized: "Bütçe")
            case .packing: String(localized: "Valiz")
            case .visa: String(localized: "Vize")
            case .crew: String(localized: "Ekip")
            case .memories: String(localized: "Anılar")
            }
        }

        var symbol: String {
            switch self {
            case .plan: "map.fill"
            case .money: "chart.pie.fill"
            case .packing: "bag.fill"
            case .visa: "person.text.rectangle.fill"
            case .crew: "person.2.fill"
            case .memories: "photo.on.rectangle.angled"
            }
        }
    }

    static let heroHeight: CGFloat = 300

    var body: some View {
        if let trip = store.trip(tripID) {
            let tint = trip.tint
            let canEdit = store.canEdit(trip)
            ScrollView {
                VStack(spacing: 0) {
                    TripHero(trip: trip, height: Self.heroHeight, isCollapsed: $isHeroCollapsed)

                    TripStub(trip: trip)
                        .padding(.horizontal, 16)
                        .padding(.top, -44)

                    if !canEdit {
                        Label("Bu seyahati yalnızca görüntüleyebilirsin", systemImage: "eye")
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(Color.ink2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.track, in: Capsule())
                            .padding(.top, 12)
                    }

                    SectionTabs(selection: $section)
                        .padding(.top, 16)

                    Group {
                        switch section {
                        case .plan: PlanSection(trip: trip)
                        case .money: MoneySection(trip: trip)
                        case .packing: PackingSection(trip: trip)
                        case .visa: VisaSection(trip: trip)
                        case .crew: CrewSection(trip: trip)
                        case .memories: MemoriesSection(trip: trip)
                        }
                    }
                    // Görüntüleyici: düğmeler ve alanlar kapalı (anılar yalnızca okuma olduğu için açık kalır).
                    .disabled(!canEdit && section != .memories)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                    .transition(.opacity)
                    .id(section)
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(TintGlow(tint: tint, offsetY: 260))
            .environment(\.tripTint, tint)
            .navigationTitle(isHeroCollapsed ? trip.name : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(isHeroCollapsed ? .visible : .hidden, for: .navigationBar)
            .toolbarColorScheme(isHeroCollapsed ? nil : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    coverMenu(trip)
                }
            }
            .coverPhotoPicker(for: $coverTarget)
            .sheet(isPresented: $isEditingTrip) { TripEditSheet(trip: trip) }
            .alert("Takvim", isPresented: Binding(get: { calendarMessage != nil }, set: { if !$0 { calendarMessage = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(calendarMessage ?? "")
            }
            .animation(.easeInOut(duration: 0.2), value: isHeroCollapsed)
            .animation(.easeInOut(duration: 0.2), value: section)
        } else {
            ContentUnavailableView("Seyahat bulunamadı", systemImage: "suitcase")
        }
    }

    private func coverMenu(_ trip: Trip) -> some View {
        Menu {
            Button("Seyahati düzenle", systemImage: "pencil") { isEditingTrip = true }
            Button("Takvime aktar", systemImage: "calendar.badge.plus") {
                Task {
                    do {
                        let count = try await CalendarExporter.export(trip)
                        calendarMessage = count == 0
                            ? String(localized: "Aktarılacak uçuş, konaklama ya da saatli durak yok.")
                            : String(localized: "\(count) etkinlik Takvim'deki Stubly takvimine eklendi. Planı değiştirince tekrar aktarabilirsin.")
                    } catch {
                        calendarMessage = error.localizedDescription
                    }
                }
            }
            Button("Kapak fotoğrafı seç", systemImage: "photo") { coverTarget = trip.id }
            if trip.coverPhoto != nil {
                Button("Fotoğrafı kaldır", systemImage: "photo.badge.minus", role: .destructive) {
                    withAnimation { store.removeCoverPhoto(for: trip.id) }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
        }
        .accessibilityLabel("Seyahat seçenekleri")
    }
}

// MARK: - Hero

/// Aşağı çekince esneyen, yukarı kayınca gezinme çubuğuna devreden kapak.
struct TripHero: View {
    let trip: Trip
    let height: CGFloat
    @Binding var isCollapsed: Bool

    var body: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .scrollView).minY
            let stretch = max(0, minY)
            ZStack(alignment: .bottomLeading) {
                TripCover(trip: trip)
                    .frame(width: proxy.size.width, height: height + stretch)
                    .clipped()
                LinearGradient(colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.55)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    let tag = trip.countdownTag
                    Text(tag.text)
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(tag.accent == .gray ? Color.ink2 : tag.accent.base)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                    Text(trip.name)
                        .font(.system(.largeTitle, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(trip.isMultiCity
                         ? "\(trip.countryCodes.map(Countries.flag).joined()) \(trip.cityTitle)"
                         : "\(Countries.flag(trip.destination.countryCode)) \(trip.destination.city), \(Countries.name(trip.destination.countryCode))")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 60)
            }
            .frame(width: proxy.size.width, height: height + stretch)
            .offset(y: -stretch)
            .onChange(of: minY < -(height - 140)) { _, collapsed in
                isCollapsed = collapsed
            }
        }
        .frame(height: height)
    }
}

// MARK: - Stub

/// Kapağın altına binen bilet koçanı: rota, tarih, gece, ekip.
struct TripStub: View {
    let trip: Trip
    @Environment(\.tripTint) private var tint
    @State private var isLiveActivityRunning = false

    var body: some View {
        VStack(spacing: 14) {
            if let flight = trip.primaryFlight {
                HStack(spacing: 12) {
                    endpoint(flight.fromCode, "\(flight.fromCity) · \(AppFormat.time(flight.departure, timeZone: flight.departureTimeZone))")
                    VStack(spacing: 2) {
                        FlightArc(accent: tint).frame(height: 26)
                        Text(AppFormat.duration(minutes: flight.durationMinutes))
                            .font(.caption)
                            .foregroundStyle(Color.ink3)
                    }
                    endpoint(flight.toCode, "\(AppFormat.time(flight.arrival, timeZone: flight.arrivalTimeZone)) · \(flight.toCity)",
                             trailing: true)
                }
                Divider().overlay(Color.line)
            }
            HStack(alignment: .top) {
                meta(String(localized: "Tarih"), AppFormat.dateRange(trip.startDate, trip.endDate))
                Spacer()
                meta(String(localized: "Konaklama"), String(localized: "\(trip.nights()) gece"))
                Spacer()
                if let flight = trip.primaryFlight, let seat = flight.seat {
                    meta(String(localized: "Koltuk"), seat)
                    Spacer()
                }
                AvatarStack(members: trip.members, size: 30, limit: 3)
            }
            if LiveActivityController.canStart(for: trip) {
                let running = isLiveActivityRunning
                Button {
                    if running { LiveActivityController.stop(for: trip) } else { LiveActivityController.start(for: trip) }
                    isLiveActivityRunning.toggle()
                } label: {
                    Label(running ? String(localized: "Kilit ekranından kaldır") : String(localized: "Kilit ekranında göster"),
                          systemImage: running ? "lock.slash" : "lock.iphone")
                        .font(.system(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(running ? Color.ink : Color.onInk)
                        .background(running ? Color.track : Color.ink, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { isLiveActivityRunning = LiveActivityController.isRunning(for: trip) }
        .padding(18)
        .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
        .overlay(alignment: .top) {
            Capsule().fill(tint).frame(width: 36, height: 4).offset(y: -2)
        }
    }

    private func endpoint(_ code: String, _ detail: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(code).font(.system(.title, weight: .semibold)).foregroundStyle(Color.ink)
            Text(detail).font(.caption).foregroundStyle(Color.ink2).lineLimit(1)
        }
        .fixedSize()
    }

    private func meta(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.tCaption).foregroundStyle(Color.ink3)
            Text(value).font(.system(.subheadline, weight: .semibold)).foregroundStyle(Color.ink)
        }
    }
}

// MARK: - Tabs

/// İkonlu sekme hapları; seçili sekmenin ikonu seyahat rengini alır.
struct SectionTabs: View {
    @Binding var selection: TripDetailView.TripSection
    @Environment(\.tripTint) private var tint
    @Namespace private var namespace

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(TripDetailView.TripSection.allCases, id: \.self) { section in
                        let isSelected = section == selection
                        Button {
                            withAnimation(.spring(duration: 0.3)) {
                                selection = section
                                reader.scrollTo(section, anchor: .center)
                            }
                        } label: {
                            Label(section.title, systemImage: section.symbol)
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.ink : Color.ink2)
                                .labelStyle(TintedIconLabelStyle(iconColor: isSelected ? tint : Color.ink3))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background {
                                    if isSelected {
                                        Capsule()
                                            .fill(Color.tray)
                                            .softShadow()
                                            .matchedGeometryEffect(id: "tab", in: namespace)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .id(section)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }
}

struct TintedIconLabelStyle: LabelStyle {
    let iconColor: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(iconColor)
            configuration.title
        }
    }
}
