import MapKit
import SwiftUI
import StublyKit

struct PlanSection: View {
    @Environment(TripStore.self) private var store
    let trip: Trip

    @State private var selectedDay: Date?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isAddingStop = false
    @State private var lastOrderBeforeOptimize: [Stop.ID: Int]?
    @State private var dropTarget: Stop.ID?
    @State private var editingHours: Stop?
    private var network: NetworkMonitor { .shared }
    private var offlineMaps: OfflineMapStore { .shared }
    @Environment(\.tripTint) private var tint

    private var days: [Date] { trip.days() }
    private var day: Date { Self.day(selected: selectedDay, in: days) }
    private var stops: [Stop] { trip.stops(on: day) }

    private static func day(selected: Date?, in days: [Date]) -> Date {
        if let selected { return selected }
        let today = Calendar.current.startOfDay(for: .now)
        return days.contains(today) ? today : (days.first ?? today)
    }

    /// Seçili günün çizim için gereken her şeyi; gövde başına bir kez hesaplanır
    /// (durak süzme/sıralama, mesafe, açılış saati durumları ve önerileri tekrar tekrar yapılmaz).
    private struct DayPlan {
        let days: [Date]
        let day: Date
        let stops: [Stop]
        let coordinates: [Coordinate]
        let totalMeters: Double
        let hours: [Stop.ID: OpeningHours.Status]
        let fixes: [Stop.ID: Trip.HoursFix]
        let stopCounts: [Date: Int]

        var warningCount: Int { hours.values.filter(\.isWarning).count }
    }

    private func makePlan() -> DayPlan {
        let days = trip.days()
        let day = Self.day(selected: selectedDay, in: days)
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]
        for stop in trip.stops { counts[calendar.startOfDay(for: stop.day), default: 0] += 1 }
        let stops = trip.stops(on: day)
        let coordinates = stops.compactMap(\.coordinate)
        var hours: [Stop.ID: OpeningHours.Status] = [:]
        var fixes: [Stop.ID: Trip.HoursFix] = [:]
        for stop in stops {
            hours[stop.id] = trip.hoursStatus(of: stop)
            fixes[stop.id] = trip.hoursFix(for: stop)
        }
        return DayPlan(days: days, day: day, stops: stops, coordinates: coordinates,
                       totalMeters: Geo.routeDistance(coordinates), hours: hours, fixes: fixes, stopCounts: counts)
    }

    var body: some View {
        let plan = makePlan()
        VStack(alignment: .leading, spacing: 16) {
            DayChips(days: plan.days, selection: Binding(get: { plan.day }, set: { selectedDay = $0 }),
                     stopCount: { plan.stopCounts[Calendar.current.startOfDay(for: $0)] ?? 0 },
                     onDropStop: { id, target in moveStop(id, before: nil, on: target) },
                     city: trip.isMultiCity ? { day in
                         let legs = trip.cityLegs
                         let leg = trip.leg(on: day)
                         let index = legs.firstIndex { $0.id == leg.id } ?? 0
                         return (leg.destination.city, Accent.cycle(index + 1).base,
                                 Calendar.current.isDate(trip.dateRange(of: leg).start, inSameDayAs: day), trip.isTransition(day))
                     } : nil)

            if !plan.coordinates.isEmpty {
                if !network.isOnline, let offline = offlineMaps.image(tripID: trip.id, day: plan.day) {
                    OfflineMapImage(image: offline)
                } else {
                    map(plan)
                }
                OfflineMapRow(trip: trip, day: plan.day)
            }

            stopList(plan)

            HStack(spacing: 12) {
                Button {
                    isAddingStop = true
                } label: {
                    Label("Durak ekle", systemImage: "plus")
                }
                .buttonStyle(.primary)

                if let lastOrderBeforeOptimize {
                    Button {
                        restore(lastOrderBeforeOptimize)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.circleIcon)
                    .accessibilityLabel("Sıralamayı geri al")
                } else {
                    Button(action: optimize) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    }
                    .buttonStyle(.circleIcon)
                    .disabled(plan.coordinates.count < 2)
                    .accessibilityLabel("Rotayı açılış saatlerine ve en kısa yürüyüşe göre diz")
                }
            }

            FlightsCard(trip: trip)
            IdeasCard(trip: trip, day: plan.day)
            LodgingCard(trip: trip)
        }
        .sheet(isPresented: $isAddingStop) {
            AddStopSheet(trip: trip, day: plan.day)
        }
        .sheet(item: $editingHours) { stop in
            OpeningHoursEditor(stop: stop) { hours in
                store.update(trip.id) { trip in
                    if let index = trip.stops.firstIndex(where: { $0.id == stop.id }) {
                        trip.stops[index].openingHours = hours
                        trip.stops[index].openingHoursLookedUp = true
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .task(id: trip.stops.filter { $0.coordinate != nil }.count) { await lookUpOpeningHours() }
        .onChange(of: plan.day) { _, _ in
            lastOrderBeforeOptimize = nil
        }
    }

    // MARK: List

    private func stopList(_ plan: DayPlan) -> some View {
        let stops = plan.stops
        let totalMeters = plan.totalMeters
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(dayTitle(plan))
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink)
                HStack(spacing: 6) {
                    StatChip(symbol: "mappin", text: String(localized: "\(stops.count) durak"))
                    if totalMeters > 0 {
                        StatChip(symbol: "point.topleft.down.to.point.bottomright.curvepath",
                                 text: AppFormat.distance(meters: totalMeters))
                        StatChip(symbol: "figure.walk", text: String(localized: "\(Geo.walkingMinutes(meters: totalMeters)) dk"))
                    }
                    let warnings = plan.warningCount
                    if warnings > 0 {
                        StatChip(symbol: "clock.badge.exclamationmark", text: String(localized: "\(warnings) saat uyarısı"), accent: .orange)
                    }
                }
            }
            .padding(.bottom, 14)

            if stops.isEmpty {
                EmptyHint(symbol: "mappin.and.ellipse", text: String(localized: "Bu gün için henüz durak yok."))
            }

            if let lodging = trip.lodging(forMorningOf: plan.day), let first = stops.first {
                LodgingStartRow(lodging: lodging)
                HopRow(from: lodging.coordinate, to: first.coordinate)
            }

            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                if index > 0 {
                    HopRow(from: stops[index - 1].coordinate, to: stop.coordinate)
                }
                StopRow(stop: stop, number: index + 1, hours: plan.hours[stop.id],
                        fix: plan.fixes[stop.id]) { fix in apply(fix, to: stop) }
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(tint)
                            .frame(height: 3)
                            .offset(y: -4)
                            .opacity(dropTarget == stop.id ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                    .draggable(stop.id.uuidString) {
                        Label(stop.name, systemImage: stop.kind.symbol)
                            .font(.system(.subheadline, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.tray, in: Capsule())
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let first = items.first, let id = UUID(uuidString: first) else { return false }
                        moveStop(id, before: stop.id, on: plan.day)
                        return true
                    } isTargeted: { targeted in
                        if targeted { dropTarget = stop.id } else if dropTarget == stop.id { dropTarget = nil }
                    }
                    .contextMenu { menu(for: stop, index: index, in: plan) }
            }

            if stops.contains(where: { $0.openingHours != nil }) {
                Link(destination: Attribution.openStreetMap.url) {
                    Text("Açılış saatleri: \(Attribution.openStreetMap.notice)")
                        .font(.caption2)
                        .foregroundStyle(Color.ink3)
                        .underline()
                }
                .padding(.top, 10)
            }

            if stops.count > 1 {
                Text("Sıralamak için durağı basılı tutup sürükle; başka güne taşımak için üstteki güne bırak.")
                    .font(.caption)
                    .foregroundStyle(Color.ink3)
                    .padding(.top, 10)
            }
        }
        .tray()
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first, let id = UUID(uuidString: first) else { return false }
            moveStop(id, before: nil, on: plan.day)
            return true
        }
        .animation(.spring(duration: 0.3), value: stops.map(\.id))
    }

    private func dayTitle(_ plan: DayPlan) -> String {
        let number = (plan.days.firstIndex(of: plan.day) ?? 0) + 1
        let city = trip.destination(on: plan.day).city
        return trip.isTransition(plan.day)
            ? String(localized: "\(number). gün · \(AppFormat.dayPill(plan.day)) · \(city) · geçiş günü")
            : String(localized: "\(number). gün · \(AppFormat.dayPill(plan.day)) · \(city)")
    }

    @ViewBuilder
    private func menu(for stop: Stop, index: Int, in plan: DayPlan) -> some View {
        if index > 0 {
            Button("Yukarı taşı", systemImage: "arrow.up") { move(stop, by: -1) }
        }
        if index < plan.stops.count - 1 {
            Button("Aşağı taşı", systemImage: "arrow.down") { move(stop, by: 1) }
        }
        Button("Açılış saatleri", systemImage: "clock") { editingHours = stop }
        Menu("Başka güne taşı", systemImage: "calendar") {
            ForEach(plan.days.filter { $0 != plan.day }, id: \.self) { target in
                Button(AppFormat.dayPill(target)) { moveToDay(stop, target) }
            }
        }
        Button("Fikirlere taşı", systemImage: "lightbulb") {
            withAnimation(.spring(duration: 0.3)) {
                store.update(trip.id) { trip in
                    trip.stops.removeAll { $0.id == stop.id }
                    var idea = stop
                    idea.id = UUID()
                    idea.startMinutes = nil
                    trip.ideas = (trip.ideas ?? []) + [idea]
                }
            }
        }
        Button("Sil", systemImage: "trash", role: .destructive) {
            store.update(trip.id) { $0.stops.removeAll { $0.id == stop.id } }
        }
    }

    // MARK: Map

    private func map(_ plan: DayPlan) -> some View {
        let pinned = plan.stops.enumerated().compactMap { (index, stop) -> PinnedStop? in
            guard let coordinate = stop.coordinate else { return nil }
            return PinnedStop(stop: stop, number: index + 1,
                              coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        let hotel = trip.lodging(forMorningOf: plan.day)
        let hotelCoordinate: CLLocationCoordinate2D? = hotel?.coordinate.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        var route: [CLLocationCoordinate2D] = []
        if let hotelCoordinate { route.append(hotelCoordinate) }
        route += pinned.map(\.coordinate)
        return Map(position: $cameraPosition) {
            MapPolyline(coordinates: route)
                .stroke(Color.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.5, 8]))
            if let hotel, let hotelCoordinate {
                Annotation(hotel.name, coordinate: hotelCoordinate, anchor: .center) {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Accent.green.base, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                }
            }
            ForEach(pinned) { item in
                Annotation(item.stop.name, coordinate: item.coordinate, anchor: .bottom) {
                    NumberedPin(number: item.number, accent: Accent.cycle(item.number - 1), size: 28)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        // Gün ya da duraklar değişince yeniden çerçevelenir; tek durakta da semt görünür.
        .task(id: route.map { "\($0.latitude),\($0.longitude)" }) {
            cameraPosition = MapFraming.position(route)
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
        // Gölge haritanın kendisinden değil zemin şeklinden: canlı harita katmana birleştirilmez.
        .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
    }

    private struct PinnedStop: Identifiable {
        let stop: Stop
        let number: Int
        let coordinate: CLLocationCoordinate2D
        var id: Stop.ID { stop.id }
    }

    // MARK: Actions

    private func move(_ stop: Stop, by offset: Int) {
        var ordered = stops
        guard let index = ordered.firstIndex(where: { $0.id == stop.id }) else { return }
        let target = index + offset
        guard ordered.indices.contains(target) else { return }
        ordered.swapAt(index, target)
        applyOrder(ordered.map(\.id))
    }

    // MARK: Opening hours

    /// Açılış saati henüz aranmamış, konumu olan duraklar (tüm günler).
    private var pendingHoursLookup: [Stop.ID] {
        trip.stops.filter { $0.coordinate != nil && $0.openingHoursLookedUp != true }.map(\.id)
    }

    /// OpenStreetMap'ten açılış saatlerini sırayla sorgular; Overpass'ı yormamak için aralarında kısa bekleme var.
    private func lookUpOpeningHours() async {
        for id in pendingHoursLookup {
            guard !Task.isCancelled,
                  let stop = trip.stops.first(where: { $0.id == id }), let coordinate = stop.coordinate else { continue }
            do {
                let hours = try await OpeningHoursService.shared.lookup(name: stop.name, coordinate: coordinate)
                store.update(trip.id) { trip in
                    if let index = trip.stops.firstIndex(where: { $0.id == id }) {
                        if trip.stops[index].openingHours == nil { trip.stops[index].openingHours = hours }
                        trip.stops[index].openingHoursLookedUp = true
                    }
                }
            } catch {
                return // Ağ hatası: işaretlemeden çık, bir sonraki açılışta yeniden denenir.
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func apply(_ fix: Trip.HoursFix, to stop: Stop) {
        switch fix {
        case let .setStart(minutes):
            withAnimation(.spring(duration: 0.3)) {
                store.update(trip.id) { trip in
                    if let index = trip.stops.firstIndex(where: { $0.id == stop.id }) {
                        trip.stops[index].startMinutes = minutes
                    }
                }
            }
        case let .moveTo(day):
            moveStop(stop.id, before: nil, on: day)
        }
    }

    private func moveStop(_ id: Stop.ID, before target: Stop.ID?, on targetDay: Date) {
        dropTarget = nil
        lastOrderBeforeOptimize = nil
        withAnimation(.spring(duration: 0.3)) {
            store.update(trip.id) { $0.moveStop(id, before: target, on: targetDay) }
        }
    }

    private func moveToDay(_ stop: Stop, _ target: Date) {
        let nextOrder = (trip.stops(on: target).map(\.order).max() ?? -1) + 1
        store.update(trip.id) { trip in
            guard let index = trip.stops.firstIndex(where: { $0.id == stop.id }) else { return }
            trip.stops[index].day = target
            trip.stops[index].order = nextOrder
        }
    }

    /// Koordinatı olan durakları açılış saatlerine ve verilmiş saatlere uyan, sonra en kısa yürüyüş sırasına dizer;
    /// koordinatsızlar sona kalır. Durakların saatleri değiştirilmez.
    private func optimize() {
        let located = stops.filter { $0.coordinate != nil }
        let others = stops.filter { $0.coordinate == nil }
        let weekday = OpeningHours.dayIndex(calendarWeekday: Calendar.current.component(.weekday, from: day))
        let visits = located.map { stop in
            RouteOptimizer.Visit(coordinate: stop.coordinate!, duration: stop.durationMinutes,
                                 open: stop.openingHours.flatMap(OpeningHours.cached)?.intervals(onDay: weekday),
                                 fixedStart: stop.startMinutes)
        }
        let dayStart = min(9 * 60, located.compactMap(\.startMinutes).min() ?? 9 * 60)
        // Sabah otelden çıkılıyorsa rota otelden başlar.
        let order = RouteOptimizer.order(visits, from: trip.lodging(forMorningOf: day)?.coordinate, dayStart: dayStart)
        lastOrderBeforeOptimize = Dictionary(uniqueKeysWithValues: stops.map { ($0.id, $0.order) })
        withAnimation(.spring(duration: 0.35)) {
            applyOrder(order.map { located[$0].id } + others.map(\.id))
        }
    }

    private func restore(_ orders: [Stop.ID: Int]) {
        withAnimation(.spring(duration: 0.35)) {
            store.update(trip.id) { trip in
                for index in trip.stops.indices {
                    if let order = orders[trip.stops[index].id] { trip.stops[index].order = order }
                }
            }
        }
        lastOrderBeforeOptimize = nil
    }

    private func applyOrder(_ ids: [Stop.ID]) {
        store.update(trip.id) { trip in
            for (order, id) in ids.enumerated() {
                if let index = trip.stops.firstIndex(where: { $0.id == id }) {
                    trip.stops[index].order = order
                }
            }
        }
    }
}

// MARK: - Rows

struct StopRow: View {
    let stop: Stop
    let number: Int
    var hours: OpeningHours.Status?
    var fix: Trip.HoursFix?
    var onFix: (Trip.HoursFix) -> Void = { _ in }

    var body: some View {
        let accent = Accent.cycle(number - 1)
        HStack(spacing: 12) {
            NumberedPin(number: number, accent: accent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.name).font(.tBodyStrong).foregroundStyle(Color.ink)
                Text(detail).font(.tBody).foregroundStyle(Color.ink2)
                if let hours {
                    HoursLabel(status: hours)
                }
                if let fix {
                    Button {
                        onFix(fix)
                    } label: {
                        Label(fixTitle(fix), systemImage: fixSymbol(fix))
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(Color.onInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            if let start = stop.startMinutes {
                Tag(text: AppFormat.time(minutes: start), accent: accent)
            }
            Image(systemName: stop.kind.symbol)
                .font(.system(size: 18))
                .foregroundStyle(accent.base)
                .frame(width: 48, height: 48)
                .background(accent.tint, in: RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func fixTitle(_ fix: Trip.HoursFix) -> String {
        switch fix {
        case let .setStart(minutes): String(localized: "Saati \(AppFormat.time(minutes: minutes)) yap")
        case let .moveTo(day): String(localized: "Taşı: \(AppFormat.dayPill(day))")
        }
    }

    private func fixSymbol(_ fix: Trip.HoursFix) -> String {
        switch fix {
        case .setStart: "clock.arrow.circlepath"
        case .moveTo: "calendar.badge.plus"
        }
    }

    private var detail: String {
        var parts = [stop.kind.title, AppFormat.duration(minutes: stop.durationMinutes)]
        if !stop.note.isEmpty { parts = [stop.kind.title, stop.note] }
        return parts.joined(separator: " · ")
    }
}

/// İki nokta arasındaki geçiş satırı: Apple Haritalar'dan yürüme ve toplu taşıma süresi;
/// gelene kadar (ya da ağ yoksa) kuş uçuşu mesafeden yürüme tahmini.
struct HopRow: View {
    let from: Coordinate?
    let to: Coordinate?
    @State private var times: TravelTimeService.Times?

    var body: some View {
        HStack(spacing: 8) {
            VerticalLine()
                .stroke(Color.line, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                .frame(width: 36)
            content
        }
        .font(.tBody)
        .foregroundStyle(Color.ink3)
        .frame(height: 34)
        .accessibilityElement(children: .combine)
        .task(id: key) {
            guard let from, let to else { return }
            times = await TravelTimeService.shared.times(from: from, to: to)
        }
    }

    private var key: String {
        guard let from, let to else { return "" }
        return "\(from.latitude),\(from.longitude)>\(to.latitude),\(to.longitude)"
    }

    @ViewBuilder
    private var content: some View {
        if let walking = times?.walkingMinutes {
            HStack(spacing: 10) {
                Label("\(walking) dk", systemImage: "figure.walk")
                if let transit = times?.transitMinutes, walking > 15, transit < walking {
                    Label("\(transit) dk", systemImage: "tram.fill")
                }
            }
        } else if let estimate {
            Label(estimate > 30 ? String(localized: "Toplu taşıma önerilir · \(estimate) dk yürüyüş") : String(localized: "\(estimate) dk"),
                  systemImage: estimate > 30 ? "tram.fill" : "figure.walk")
        } else {
            Label("Geçiş", systemImage: "arrow.down")
        }
    }

    private var estimate: Int? {
        guard let from, let to else { return nil }
        return Geo.walkingMinutes(meters: Geo.distance(from, to))
    }
}

/// Günün başladığı konaklama satırı.
struct LodgingStartRow: View {
    let lodging: Lodging

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Accent.green.base)
                .frame(width: 36, height: 36)
                .background(Accent.green.tint, in: Circle())
            Text(lodging.name)
                .font(.tBody)
                .foregroundStyle(Color.ink2)
                .lineLimit(1)
            Spacer()
        }
        .accessibilityLabel(Text("Gün \(lodging.name) konaklamasından başlıyor"))
    }
}

struct VerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
    }
}

/// Durağın açılış saatine göre kısa durum etiketi.
struct HoursLabel: View {
    let status: OpeningHours.Status

    var body: some View {
        Label(text, systemImage: status.isWarning ? "exclamationmark.circle.fill" : "clock")
            .font(.system(.caption, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var color: Color {
        switch status {
        case .closedAllDay, .alreadyClosed: Color(hex: 0xD64545)
        case .opensLater, .closesDuringVisit: .food
        case .open, .openToday: .ink3
        }
    }

    private var text: String {
        let clock = OpeningHours.clock
        switch status {
        case .closedAllDay: return String(localized: "O gün kapalı")
        case let .alreadyClosed(at): return String(localized: "Bu saatte kapalı · kapanış \(clock(at))")
        case let .opensLater(at): return String(localized: "Henüz kapalı · açılış \(clock(at))")
        case let .closesDuringVisit(at): return String(localized: "Kapanış \(clock(at)) · süre yetmeyebilir")
        case let .open(until): return String(localized: "Açık · kapanış \(clock(until))")
        case let .openToday(intervals):
            return intervals.map { "\(clock($0.start))–\(clock($0.end))" }.joined(separator: ", ")
        }
    }
}

/// Açılış saatlerini gösterir ve düzenletir (OpenStreetMap biçimi).
struct OpeningHoursEditor: View {
    @Environment(\.dismiss) private var dismiss
    let stop: Stop
    let onSave: (String?) -> Void
    @State private var text: String

    init(stop: Stop, onSave: @escaping (String?) -> Void) {
        self.stop = stop
        self.onSave = onSave
        _text = State(initialValue: stop.openingHours ?? "")
    }

    private var parsed: OpeningHours? { OpeningHours(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Mo-Fr 09:00-18:00; Sa 10:00-14:00; Su off", text: $text, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text(stop.name)
                } footer: {
                    Text("Günler: Mo Tu We Th Fr Sa Su. Kapalı günler için \"off\". Saatler OpenStreetMap'ten otomatik gelir; yanlışsa buradan düzeltebilirsin. \(Attribution.openStreetMap.notice)")
                }

                Section("Önizleme") {
                    if text.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Açılış saati yok").foregroundStyle(Color.ink3)
                    } else if let parsed {
                        Text(parsed.turkishSummary).foregroundStyle(Color.ink)
                    } else {
                        Label("Bu biçim anlaşılamadı", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.food)
                    }
                }
            }
            .navigationTitle("Açılış saatleri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                    .disabled(!text.trimmingCharacters(in: .whitespaces).isEmpty && parsed == nil)
                }
            }
        }
    }
}

/// İnternet yokken gösterilen kayıtlı harita görüntüsü; dokununca tam ekran yakınlaştırılabilir açılır.
struct OfflineMapImage: View {
    let image: UIImage
    @State private var isExpanded = false

    var body: some View {
        Button {
            isExpanded = true
        } label: {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Label("Çevrimdışı harita", systemImage: "wifi.slash")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(10)
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 32, height: 32)
                        .background(.regularMaterial, in: Circle())
                        .padding(10)
                }
        }
        .buttonStyle(.plain)
        .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
        .accessibilityLabel("Kayıtlı çevrimdışı harita")
        .accessibilityHint("Büyütmek için dokun")
        .fullScreenCover(isPresented: $isExpanded) {
            OfflineMapViewer(image: image)
        }
    }
}

/// Kayıtlı harita görüntüsünü iki parmakla yakınlaştırma, kaydırma ve çift dokunuşla büyütme.
struct OfflineMapViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZoomableImage(image: image)
            .ignoresSafeArea()
            .background(Color.black)
            .overlay(alignment: .topTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 40, height: 40)
                        .background(.regularMaterial, in: Circle())
                }
                .padding(16)
                .accessibilityLabel("Kapat")
            }
            .overlay(alignment: .bottom) {
                Label("Çevrimdışı harita · iki parmakla yakınlaştır", systemImage: "wifi.slash")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
            .statusBarHidden()
    }
}

/// UIScrollView tabanlı yakınlaştırma (SwiftUI'da iOS 17 için yerleşik karşılığı yok).
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    var maximumZoom: CGFloat = 4

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = CenteringScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
        scrollView.imageView = imageView
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        scrollView.maximumZoom = maximumZoom
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? CenteringScrollView)?.centerContent()
        }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView, let imageView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale * 1.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let scale = min(scrollView.maximumZoomScale, scrollView.minimumZoomScale * 2.5)
                let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
                scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                           width: size.width, height: size.height), animated: true)
            }
        }
    }

    /// Görüntüyü ekrana sığdıran en küçük yakınlığı boyut değiştikçe yeniden hesaplar ve ortalar.
    final class CenteringScrollView: UIScrollView {
        weak var imageView: UIImageView?
        var maximumZoom: CGFloat = 4
        private var lastBounds: CGSize = .zero

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let imageView, let image = imageView.image, bounds.size != lastBounds, bounds.width > 0 else { return }
            lastBounds = bounds.size
            imageView.frame = CGRect(origin: .zero, size: image.size)
            contentSize = image.size
            let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
            minimumZoomScale = fit
            maximumZoomScale = fit * maximumZoom
            zoomScale = fit
            centerContent()
        }

        func centerContent() {
            guard let imageView else { return }
            let horizontal = max(0, (bounds.width - imageView.frame.width) / 2)
            let vertical = max(0, (bounds.height - imageView.frame.height) / 2)
            contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        }
    }
}

/// Haritaları çevrimdışı kullanım için kaydetme satırı.
struct OfflineMapRow: View {
    let trip: Trip
    let day: Date
    private var store: OfflineMapStore { .shared }
    @State private var isPreviewing = false

    var body: some View {
        let state = store.state(for: trip.id)
        HStack(spacing: 10) {
            Image(systemName: icon(state))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color(state))
            Text(text(state))
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(Color.ink2)
                .lineLimit(1)
            Spacer()
            if case .saving = state {
                ProgressView().controlSize(.small)
            } else {
                if isSaved(state), store.image(tripID: trip.id, day: day) != nil {
                    Button {
                        isPreviewing = true
                    } label: {
                        Image(systemName: "eye")
                    }
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .accessibilityLabel("Kayıtlı haritayı göster")
                }
                Button(isSaved(state) ? String(localized: "Güncelle") : String(localized: "Kaydet")) {
                    Task { await store.save(trip) }
                }
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Color.ink)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .cardBackground(Color.tray, in: Capsule())
        .fullScreenCover(isPresented: $isPreviewing) {
            if let image = store.image(tripID: trip.id, day: day) {
                OfflineMapViewer(image: image)
            }
        }
    }

    private func isSaved(_ state: OfflineMapStore.State) -> Bool {
        if case .saved = state { return true }
        return false
    }

    private func icon(_ state: OfflineMapStore.State) -> String {
        switch state {
        case .idle: "arrow.down.circle"
        case .saving: "arrow.down.circle.dotted"
        case .saved: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func color(_ state: OfflineMapStore.State) -> Color {
        switch state {
        case .saved: .success
        case .failed: .food
        default: .ink2
        }
    }

    private func text(_ state: OfflineMapStore.State) -> String {
        switch state {
        case .idle: String(localized: "Haritaları internetsiz kullanım için kaydet")
        case let .saving(done, total): String(localized: "Kaydediliyor · \(done + 1)/\(total) gün")
        case let .saved(date): String(localized: "Çevrimdışı kayıtlı · \(AppFormat.shortDate(date)) \(AppFormat.time(date))")
        case let .failed(message): message
        }
    }
}
