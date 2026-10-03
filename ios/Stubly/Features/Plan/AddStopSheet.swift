import MapKit
import SwiftUI
import StublyKit

struct AddStopSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let day: Date
    /// true ise durak bir güne değil "Fikirler" havuzuna eklenir.
    @State private var asIdea: Bool

    init(trip: Trip, day: Date, asIdea: Bool = false) {
        self.trip = trip
        self.day = day
        _asIdea = State(initialValue: asIdea)
    }

    @State private var query = ""
    @State private var results: [PlaceSearch.Result] = []
    /// Şehir merkezi: arama bu çevreyle sınırlanır (yoksa şehir adından bulunur).
    @State private var center: Coordinate?
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    @State private var name = ""
    @State private var coordinate: Coordinate?
    @State private var kind: StopKind = .sight
    @State private var hasTime = false
    @State private var time = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now) ?? .now
    @State private var duration = 60
    @State private var note = ""
    @State private var mapPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("\(trip.destination(on: day).city) içinde yer ara", text: $query)
                        .autocorrectionDisabled()
                        .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
                    if isSearching {
                        ProgressView()
                    }
                    if !mapPins.isEmpty {
                        previewMap
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    }
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        Button {
                            select(item)
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.system(.caption, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Accent.cycle(index).base, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name.isEmpty ? String(localized: "Adsız yer") : item.name).foregroundStyle(Color.ink)
                                    if let address = item.address {
                                        Text(address).font(.footnote).foregroundStyle(Color.ink2).lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 4)
                                if let distance = item.distance {
                                    Text(AppFormat.distance(meters: distance))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Color.ink3)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Ara")
                } footer: {
                    if results.count > 1 {
                        Text("En benzer ve şehir merkezine en yakın yerler önce; mesafe şehir merkezine göre.")
                    }
                }

                Section {
                    TextField("Durak adı", text: $name)
                    if coordinate != nil {
                        Label("Konum eklendi", systemImage: "mappin.circle.fill")
                            .foregroundStyle(Color.success)
                    }
                    Picker("Tür", selection: $kind) {
                        ForEach(StopKind.allCases, id: \.self) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    Toggle("Fikirler havuzuna ekle (gün seçmeden)", isOn: $asIdea)
                    if !asIdea {
                        Toggle("Saat belirle", isOn: $hasTime)
                    }
                    if hasTime && !asIdea {
                        DatePicker("Başlangıç", selection: $time, displayedComponents: .hourAndMinute)
                    }
                    Stepper("Süre: \(AppFormat.duration(minutes: duration))", value: $duration, in: 15...600, step: 15)
                    TextField("Not (ör. Rezervasyon gerekli)", text: $note)
                } header: {
                    Text(asIdea ? String(localized: "Fikir") : String(localized: "\(AppFormat.dayPill(day)) için durak"))
                }
            }
            .navigationTitle("Durak ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onDisappear { searchTask?.cancel() }
            .task { center = await store.ensureCoordinate(for: trip.id, on: day) }
        }
    }

    // MARK: Map preview

    private struct MapPin: Identifiable {
        let id: String
        let title: String
        let coordinate: CLLocationCoordinate2D
        let label: String
        let color: Color
    }

    /// Arama sonuçları numaralı, seçilen yer yeşil onay işaretiyle.
    private var mapPins: [MapPin] {
        var pins = results.enumerated().map { index, item in
            MapPin(id: "r\(index)", title: item.name,
                   coordinate: CLLocationCoordinate2D(latitude: item.coordinate.latitude, longitude: item.coordinate.longitude),
                   label: "\(index + 1)", color: Accent.cycle(index).base)
        }
        if let coordinate {
            pins.append(MapPin(id: "selected", title: name,
                               coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                               label: "✓", color: .success))
        }
        return pins
    }

    private var previewMap: some View {
        Map(position: $mapPosition) {
            ForEach(mapPins) { pin in
                Marker(pin.title, monogram: Text(pin.label), coordinate: pin.coordinate)
                    .tint(pin.color)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: mapPins.map(\.id), initial: true) { _, _ in
            withAnimation(.easeInOut(duration: 0.4)) { mapPosition = MapFraming.position(mapPins.map(\.coordinate)) }
        }
    }

    private func select(_ result: PlaceSearch.Result) {
        name = result.name.isEmpty ? name : result.name
        coordinate = result.coordinate
        if let category = result.item.pointOfInterestCategory {
            kind = PlaceSearch.kind(for: category)
        }
        results = []
        query = ""
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }

            let city = trip.destination(on: day)
            let found = await PlaceSearch.places(trimmed, city: city.city, countryCode: city.countryCode, center: center)
            guard !Task.isCancelled else { return }
            results = found
        }
    }

    private func save() {
        let order = (trip.stops(on: day).map(\.order).max() ?? -1) + 1
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let stop = Stop(day: day, order: order, name: name.trimmingCharacters(in: .whitespaces), kind: kind,
                        startMinutes: hasTime ? (components.hour ?? 0) * 60 + (components.minute ?? 0) : nil,
                        durationMinutes: duration, coordinate: coordinate,
                        note: note.trimmingCharacters(in: .whitespaces))
        store.update(trip.id) { trip in
            if asIdea {
                var idea = stop
                idea.startMinutes = nil
                trip.ideas = (trip.ideas ?? []) + [idea]
            } else {
                trip.stops.append(stop)
            }
        }
        dismiss()
    }
}
