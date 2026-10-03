import SwiftUI
import StublyKit

struct PackingSection: View {
    @Environment(TripStore.self) private var store
    let trip: Trip

    @State private var newTitle = ""
    @State private var newAssignee: UUID?
    @FocusState private var isAddFieldFocused: Bool
    @State private var suggestions: [String] = []
    @State private var filter: Filter = .everyone
    /// Şehir başına hava özeti (tek şehirde tek kayıt).
    @State private var legWeather: [TripLeg.ID: WeatherSummary] = [:]
    @State private var failedLegs: Set<TripLeg.ID> = []
    @Environment(\.tripTint) private var tint

    enum Filter: Hashable {
        case everyone, unassigned
        case member(UUID)
    }

    private var items: [PackingItem] { trip.packing }
    private var visibleItems: [PackingItem] {
        switch filter {
        case .everyone: items
        case .unassigned: items.filter { trip.member($0.assignee) == nil }
        case let .member(id): items.filter { $0.assignee == id }
        }
    }
    private var packedCount: Int { items.filter(\.isPacked).count }

    var body: some View {
        ModuleCard(String(localized: "Valiz"), symbol: "bag.fill") {
            HStack(spacing: 16) {
                ProgressRing(progress: items.isEmpty ? 0 : Double(packedCount) / Double(items.count), color: tint,
                             lineWidth: 7) {
                    Text(items.isEmpty ? "—" : "%\(Int((Double(packedCount) / Double(items.count) * 100).rounded()))")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.ink)
                }
                .frame(width: 64, height: 64)
                StoryHeadline(text: headline)
            }

            ForEach(trip.cityLegs) { leg in
                WeatherStrip(city: leg.destination.city, weather: legWeather[leg.id], failed: failedLegs.contains(leg.id))
            }

            if !items.isEmpty {
                filterChips
            }

            VStack(alignment: .leading, spacing: 0) {
                if !items.isEmpty {
                    progress
                        .padding(.bottom, 16)
                    Divider().overlay(Color.line)
                }

                if visibleItems.isEmpty && !items.isEmpty {
                    EmptyHint(symbol: "line.3.horizontal.decrease", text: String(localized: "Bu filtrede madde yok."))
                }

                ForEach(visibleItems) { item in
                    PackingRow(trip: trip, item: item) {
                        store.update(trip.id) { trip in
                            if let index = trip.packing.firstIndex(where: { $0.id == item.id }) {
                                trip.packing[index].isPacked.toggle()
                            }
                        }
                    }
                    .contextMenu { menu(for: item) }
                }

                addRow
                    .padding(.top, 8)
            }
            .tray()

            if !suggestions.isEmpty {
                suggestionList
            }

            Button(action: suggest) {
                Label("Madde öner", systemImage: "sparkles")
            }
            .buttonStyle(.primary)

            DepartureChecklistCard(trip: trip)
        }
        .task(id: "\(trip.id)-\(trip.startDate)-\(trip.endDate)-\(trip.cityLegs.map(\.arrival))") { await loadWeather() }
    }

    private var headline: String {
        guard !items.isEmpty else { return String(localized: "Valiz listesi boş. Önerilerle başla.") }
        let remaining = items.count - packedCount
        let countdown = Countdown.make(start: trip.startDate, end: trip.endDate)
        let when: String = switch countdown {
        case let .days(n) where n == 1: String(localized: " Yarın yola çıkıyorsunuz.")
        case let .days(n): String(localized: " \(n) gün kaldı.")
        case .today: String(localized: " Bugün yola çıkıyorsunuz.")
        default: ""
        }
        if remaining == 0 { return String(localized: "Her şey hazır ✓") }
        return String(localized: "\(packedCount)/\(items.count) madde hazır.\(when)")
    }

    // MARK: Filter

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.everyone) { Text("Herkes · \(items.count)") }
                ForEach(trip.members) { member in
                    let count = items.filter { $0.assignee == member.id }.count
                    if count > 0 {
                        chip(.member(member.id)) {
                            HStack(spacing: 6) {
                                AvatarView(member: member, size: 22)
                                Text("\(member.name) · \(count)")
                            }
                        }
                    }
                }
                let unassigned = items.filter { trip.member($0.assignee) == nil }.count
                if unassigned > 0 {
                    chip(.unassigned) { Text("Atanmadı · \(unassigned)") }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip<ChipLabel: View>(_ value: Filter, @ViewBuilder label: () -> ChipLabel) -> some View {
        let isSelected = filter == value
        return Button {
            withAnimation(.spring(duration: 0.25)) { filter = isSelected ? .everyone : value }
        } label: {
            label()
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(isSelected ? Color.onInk : Color.ink2)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .cardBackground(isSelected ? Color.ink : Color.tray, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Progress

    private var progress: some View {
        let groups = packedByMember
        let remaining = items.count - packedCount
        return VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                let spacing: CGFloat = 6
                let segments = groups.count + (remaining > 0 ? 1 : 0)
                let usable = proxy.size.width - spacing * CGFloat(max(segments - 1, 0))
                HStack(spacing: spacing) {
                    ForEach(groups, id: \.member.id) { group in
                        HatchedBar(progress: 1, color: Accent.cycle(group.member.colorIndex).base)
                            .frame(width: usable * CGFloat(group.count) / CGFloat(items.count))
                    }
                    if remaining > 0 {
                        HatchedBar(progress: 0, color: .clear)
                            .frame(width: usable * CGFloat(remaining) / CGFloat(items.count))
                    }
                }
            }
            .frame(height: 14)

            HStack(spacing: 14) {
                ForEach(groups, id: \.member.id) { group in
                    HStack(spacing: 6) {
                        AvatarView(member: group.member, size: 26)
                        Text("\(group.count)")
                            .font(.tBodyStrong)
                            .foregroundStyle(Accent.cycle(group.member.colorIndex).base)
                    }
                }
                Spacer()
                Text("\(remaining) kaldı").font(.tBody).foregroundStyle(Color.ink3)
            }
        }
    }

    private struct MemberCount {
        let member: Member
        let count: Int
    }

    /// Paketlenen maddelerin kişilere dağılımı (atanmamışlar kalanlarla birlikte sayılmaz).
    private var packedByMember: [MemberCount] {
        trip.members.compactMap { member in
            let count = items.filter { $0.isPacked && $0.assignee == member.id }.count
            return count > 0 ? MemberCount(member: member, count: count) : nil
        } + unassignedPacked
    }

    private var unassignedPacked: [MemberCount] {
        let count = items.filter { $0.isPacked && trip.member($0.assignee) == nil }.count
        guard count > 0 else { return [] }
        return [MemberCount(member: Member(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, name: "?",
                                           colorIndex: 4), count: count)]
    }

    // MARK: Add & suggest

    private var addRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ink2)
                .frame(width: 28, height: 28)
                .background(Color.track, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            TextField("Madde ekle", text: $newTitle)
                .focused($isAddFieldFocused)
                .submitLabel(.done)
                .onSubmit(addItem)
            Menu {
                Picker("Kime", selection: $newAssignee) {
                    Text("Atanmadı").tag(UUID?.none)
                    ForEach(trip.members) { member in
                        Text(member.name).tag(Optional(member.id))
                    }
                }
            } label: {
                if let member = trip.member(newAssignee) {
                    AvatarView(member: member, size: 28)
                } else {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title3)
                        .foregroundStyle(Color.ink3)
                }
            }
            .accessibilityLabel("Kişiye ata")
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Öneriler").font(.tCaption).foregroundStyle(Color.ink3)
            FlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { title in
                    Button {
                        store.update(trip.id) { $0.packing.append(PackingItem(title: title)) }
                        suggestions.removeAll { $0 == title }
                    } label: {
                        Label(title, systemImage: "plus")
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .cardBackground(Color.tray, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func suggest() {
        withAnimation(.spring(duration: 0.3)) {
            suggestions = PackingAdvisor.suggestions(for: trip, weather: weather)
        }
    }

    /// Valiz önerileri için tüm şehirlerin toplu özeti.
    private var weather: WeatherSummary? {
        WeatherSummary.combined(trip.cityLegs.compactMap { legWeather[$0.id] })
    }

    private func loadWeather() async {
        failedLegs = []
        guard !trip.isPast() else { return }
        for leg in trip.cityLegs {
            let range = trip.dateRange(of: leg)
            guard let coordinate = await store.ensureCoordinate(for: trip.id, on: leg.arrival) else {
                failedLegs.insert(leg.id)
                continue
            }
            do {
                let summary = try await WeatherFetcher.shared.summary(latitude: coordinate.latitude, longitude: coordinate.longitude,
                                                                      start: range.start, end: range.end)
                withAnimation(.easeInOut(duration: 0.3)) { legWeather[leg.id] = summary }
            } catch {
                failedLegs.insert(leg.id)
            }
        }
    }

    private func addItem() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        store.update(trip.id) { $0.packing.append(PackingItem(title: title, assignee: newAssignee)) }
        newTitle = ""
        isAddFieldFocused = true
    }

    @ViewBuilder
    private func menu(for item: PackingItem) -> some View {
        Menu("Kime", systemImage: "person") {
            Button("Atanmadı") { assign(item, to: nil) }
            ForEach(trip.members) { member in
                Button(member.name) { assign(item, to: member.id) }
            }
        }
        Button("Sil", systemImage: "trash", role: .destructive) {
            store.update(trip.id) { $0.packing.removeAll { $0.id == item.id } }
        }
    }

    private func assign(_ item: PackingItem, to member: UUID?) {
        store.update(trip.id) { trip in
            if let index = trip.packing.firstIndex(where: { $0.id == item.id }) {
                trip.packing[index].assignee = member
            }
        }
    }
}

struct PackingRow: View {
    let trip: Trip
    let item: PackingItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(item.isPacked ? Color.success : Color.line, lineWidth: 2)
                        .background(item.isPacked ? Color.success : .clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    if item.isPacked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 28, height: 28)
                .animation(.spring(duration: 0.25, bounce: 0.4), value: item.isPacked)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isPacked ? String(localized: "Paketlendi") : String(localized: "Paketlenmedi"))

            Text(item.title)
                .font(.body)
                .foregroundStyle(item.isPacked ? Color.ink3 : Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let member = trip.member(item.assignee) {
                AvatarView(member: member, size: 28)
            } else {
                Tag(text: String(localized: "Atanmadı"), accent: .orange)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// Satır sonuna gelince alta kayan basit yerleşim (öneri hapları için).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Seyahat tarihleri için kısa hava özeti; öneriler bu bilgiyi kullanır.
struct WeatherStrip: View {
    let city: String
    let weather: WeatherSummary?
    let failed: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 26))
                .frame(width: 44, height: 44)
                .background(Color.transportTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                if let weather {
                    Text("\(city) · \(Int(weather.minTemperature.rounded()))° – \(Int(weather.maxTemperature.rounded()))°")
                        .font(.tBodyStrong)
                        .foregroundStyle(Color.ink)
                    Text(detail(weather))
                        .font(.caption)
                        .foregroundStyle(Color.ink2)
                } else if failed {
                    Text("Hava durumu alınamadı").font(.tBodyStrong).foregroundStyle(Color.ink)
                    Text("Öneriler mevsime göre yapılacak.").font(.caption).foregroundStyle(Color.ink2)
                } else {
                    Text("\(city) için hava durumu").font(.tBodyStrong).foregroundStyle(Color.ink)
                    ProgressView().controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .tray(padding: 12)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        guard let weather else { return failed ? "cloud.sun" : "cloud.sun.fill" }
        if weather.maxTemperature <= 3 { return "snowflake" }
        if weather.rainyDays * 3 >= max(weather.dayCount, 1) { return "cloud.rain.fill" }
        if weather.rainyDays > 0 { return "cloud.sun.rain.fill" }
        return weather.maxTemperature >= 24 ? "sun.max.fill" : "cloud.sun.fill"
    }

    private func detail(_ weather: WeatherSummary) -> String {
        let rain = weather.rainyDays == 0 ? String(localized: "yağış beklenmiyor") : String(localized: "\(weather.rainyDays) yağışlı gün")
        let source = weather.source == .forecast ? String(localized: "tahmin") : String(localized: "geçen yıl bu tarihlerde")
        return "\(rain) · \(source) · Open-Meteo"
    }
}
