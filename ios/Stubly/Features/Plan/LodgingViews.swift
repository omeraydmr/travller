import MapKit
import SwiftUI
import StublyKit

/// Plan sekmesindeki konaklama kartı: oteller, gece sayıları, konaklaması olmayan geceler; elle ekleme ya da
/// Booking.com/Airbnb onayından içe aktarma.
struct LodgingCard: View {
    @Environment(TripStore.self) private var store
    let trip: Trip
    @State private var editing: Lodging?
    @State private var isAdding = false
    @State private var isImporting = false

    var body: some View {
        let lodgings = trip.lodgingList
        let uncovered = trip.nightsWithoutLodging()
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(String(localized: "Konaklama"), systemImage: "bed.double.fill")
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink)
                Spacer()
                Menu {
                    Button("Elle ekle", systemImage: "square.and.pencil") { isAdding = true }
                    Button("Rezervasyondan içe aktar", systemImage: "doc.viewfinder") { isImporting = true }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.circleIcon(size: 32))
                .accessibilityLabel(String(localized: "Konaklama ekle"))
            }

            if lodgings.isEmpty {
                EmptyHint(symbol: "building.2",
                          text: String(localized: "Otel ya da ev ekle ya da Booking.com, Airbnb onayından içe aktar; günlerin planı oradan başlasın."))
                HStack(spacing: 10) {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Elle ekle", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.primary)
                    Button {
                        isImporting = true
                    } label: {
                        Label("İçe aktar", systemImage: "doc.viewfinder")
                    }
                    .buttonStyle(.primary)
                }
            }

            ForEach(lodgings) { lodging in
                Button {
                    editing = lodging
                } label: {
                    LodgingRow(lodging: lodging)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Düzenle", systemImage: "pencil") { editing = lodging }
                    if let coordinate = lodging.coordinate {
                        Button("Haritada aç", systemImage: "map") { openInMaps(lodging, coordinate) }
                    }
                    Button("Sil", systemImage: "trash", role: .destructive) {
                        withAnimation { store.update(trip.id) { $0.lodgings?.removeAll { $0.id == lodging.id } } }
                    }
                }
            }

            if !uncovered.isEmpty && !lodgings.isEmpty {
                Label("\(uncovered.map(AppFormat.dayPill).joined(separator: ", ")) gecesi için konaklama yok",
                      systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.food)
            }
        }
        .tray()
        .sheet(isPresented: $isAdding) { LodgingSheet(trip: trip, editing: nil) }
        .sheet(isPresented: $isImporting) { BookingImportSheet(trip: trip, kind: .lodgings) }
        .sheet(item: $editing) { lodging in LodgingSheet(trip: trip, editing: lodging) }
    }

    private func openInMaps(_ lodging: Lodging, _ coordinate: Coordinate) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude,
                                                                                      longitude: coordinate.longitude)))
        item.name = lodging.name
        item.openInMaps()
    }
}

struct LodgingRow: View {
    let lodging: Lodging

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 16))
                .foregroundStyle(Accent.green.base)
                .frame(width: 44, height: 44)
                .background(Accent.green.tint, in: RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(lodging.name).font(.tBodyStrong).foregroundStyle(Color.ink).lineLimit(1)
                Text("\(AppFormat.dayPill(lodging.checkIn)) \(AppFormat.time(lodging.checkIn)) → \(AppFormat.dayPill(lodging.checkOut)) \(AppFormat.time(lodging.checkOut))")
                    .font(.tBody)
                    .foregroundStyle(Color.ink2)
                if !lodging.confirmation.isEmpty {
                    Text("Rezervasyon \(lodging.confirmation)")
                        .font(.caption)
                        .foregroundStyle(Color.ink3)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            Tag(text: String(localized: "\(lodging.nights()) gece"), accent: .green)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Konaklama ekler ya da düzenler; adı yazarken yer araması yapar.
struct LodgingSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let editing: Lodging?

    @State private var name: String
    @State private var address: String
    @State private var coordinate: Coordinate?
    @State private var checkIn: Date
    @State private var checkOut: Date
    @State private var confirmation: String
    @State private var note: String
    @State private var results: [MKMapItem] = []
    @State private var searchTask: Task<Void, Never>?
    /// Arama sonucundan ad seçilince ad alanındaki değişiklik yeni arama başlatmasın.
    @State private var suppressNextSearch = false

    init(trip: Trip, editing: Lodging?) {
        self.trip = trip
        self.editing = editing
        let calendar = Calendar.current
        let defaultIn = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: trip.startDate) ?? trip.startDate
        let defaultOut = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: trip.endDate) ?? trip.endDate
        _name = State(initialValue: editing?.name ?? "")
        _address = State(initialValue: editing?.address ?? "")
        _coordinate = State(initialValue: editing?.coordinate)
        _checkIn = State(initialValue: editing?.checkIn ?? defaultIn)
        _checkOut = State(initialValue: editing?.checkOut ?? defaultOut)
        _confirmation = State(initialValue: editing?.confirmation ?? "")
        _note = State(initialValue: editing?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Otel ya da ev adı", text: $name)
                        .onChange(of: name) { _, newValue in scheduleSearch(newValue) }
                    ForEach(results, id: \.self) { item in
                        Button {
                            select(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? String(localized: "Adsız yer")).foregroundStyle(Color.ink)
                                if let title = item.placemark.title {
                                    Text(title).font(.footnote).foregroundStyle(Color.ink2).lineLimit(1)
                                }
                            }
                        }
                    }
                    TextField("Adres", text: $address)
                    if coordinate != nil {
                        Label("Konum eklendi", systemImage: "mappin.circle.fill").foregroundStyle(Color.success)
                    }
                }
                Section {
                    DatePicker("Giriş", selection: $checkIn)
                    DatePicker("Çıkış", selection: $checkOut, in: checkIn...)
                } footer: {
                    Text("\(Lodging(name: "", checkIn: checkIn, checkOut: checkOut).nights()) gece")
                }
                Section {
                    TextField("Rezervasyon numarası", text: $confirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Not (ör. kapı kodu, kahvaltı dahil)", text: $note, axis: .vertical)
                }
                if editing != nil {
                    Section {
                        Button("Konaklamayı sil", role: .destructive) {
                            store.update(trip.id) { $0.lodgings?.removeAll { $0.id == editing?.id } }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? String(localized: "Konaklama ekle") : String(localized: "Konaklama"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? String(localized: "Ekle") : String(localized: "Kaydet"), action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: checkIn) { _, newValue in
                if checkOut < newValue { checkOut = newValue }
            }
            .onDisappear { searchTask?.cancel() }
        }
    }

    private func select(_ item: MKMapItem) {
        searchTask?.cancel()
        let location = item.placemark.coordinate
        coordinate = Coordinate(latitude: location.latitude, longitude: location.longitude)
        address = item.placemark.title ?? address
        results = []
        if let itemName = item.name, itemName != name {
            suppressNextSearch = true
            name = itemName
        }
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        if suppressNextSearch {
            suppressNextSearch = false
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.hotel])
            if let center = trip.destination(on: checkIn).coordinate ?? trip.destination.coordinate {
                request.region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                    latitudinalMeters: 60_000, longitudinalMeters: 60_000)
            }
            let response = try? await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            results = Array((response?.mapItems ?? []).prefix(5))
        }
    }

    private func save() {
        let lodging = Lodging(id: editing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespaces),
                              address: address.trimmingCharacters(in: .whitespaces), coordinate: coordinate,
                              checkIn: checkIn, checkOut: checkOut,
                              confirmation: confirmation.trimmingCharacters(in: .whitespaces),
                              note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        store.update(trip.id) { trip in
            var list = trip.lodgings ?? []
            if let index = list.firstIndex(where: { $0.id == lodging.id }) {
                list[index] = lodging
            } else {
                list.append(lodging)
            }
            trip.lodgings = list
        }
        dismiss()
    }
}
