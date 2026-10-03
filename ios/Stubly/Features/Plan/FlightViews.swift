import SwiftUI
import StublyKit

/// Plan sekmesindeki uçuş kartı: uçuşları listeler; elle ekleme, düzenleme ve rezervasyondan içe aktarma.
struct FlightsCard: View {
    @Environment(TripStore.self) private var store
    let trip: Trip
    @State private var editing: FlightSegment?
    @State private var isAdding = false
    @State private var isImporting = false

    var body: some View {
        let flights = trip.flights.sorted { $0.departure < $1.departure }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Uçuşlar", systemImage: "airplane")
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink)
                Spacer()
                Menu {
                    Button("Elle ekle", systemImage: "square.and.pencil") { isAdding = true }
                    Button("Biletten içe aktar", systemImage: "doc.viewfinder") { isImporting = true }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.circleIcon(size: 32))
                .accessibilityLabel("Uçuş ekle")
            }

            if flights.isEmpty {
                EmptyHint(symbol: "airplane.departure", text: String(localized: "Uçuşunu elle yaz ya da e-bilet, ekran görüntüsü veya Wallet kartından içe aktar."))
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

            ForEach(flights) { flight in
                Button {
                    editing = flight
                } label: {
                    FlightRow(flight: flight)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Düzenle", systemImage: "pencil") { editing = flight }
                    Button("Sil", systemImage: "trash", role: .destructive) {
                        withAnimation { store.update(trip.id) { $0.flights.removeAll { $0.id == flight.id } } }
                    }
                }
            }
        }
        .tray()
        .sheet(isPresented: $isAdding) { FlightSheet(trip: trip, editing: nil) }
        .sheet(item: $editing) { flight in FlightSheet(trip: trip, editing: flight) }
        .sheet(isPresented: $isImporting) { BookingImportSheet(trip: trip, kind: .flights) }
    }
}

struct FlightRow: View {
    let flight: FlightSegment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "airplane")
                .font(.system(size: 16))
                .foregroundStyle(Accent.blue.base)
                .frame(width: 44, height: 44)
                .background(Accent.blue.tint, in: RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(flight.fromCode) → \(flight.toCode)")
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink)
                Text("\(AppFormat.dayPill(flight.departure)) · \(AppFormat.time(flight.departure, timeZone: flight.departureTimeZone)) → \(AppFormat.time(flight.arrival, timeZone: flight.arrivalTimeZone))")
                    .font(.tBody)
                    .foregroundStyle(Color.ink2)
                Text([flight.flightNumber, flight.seat.map { String(localized: "koltuk \($0)") }, flight.gate.map { String(localized: "kapı \($0)") }]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Color.ink3)
            }
            Spacer(minLength: 8)
            Tag(text: AppFormat.duration(minutes: flight.durationMinutes), accent: .blue)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Uçuşu elle ekler ya da düzenler. Saatler havalimanının yerel saatiyle girilir;
/// tanınan havalimanı kodunda şehir ve saat dilimi kendiliğinden dolar.
struct FlightSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let editing: FlightSegment?

    @State private var flightNumber: String
    @State private var fromCode: String
    @State private var fromCity: String
    @State private var toCode: String
    @State private var toCity: String
    /// Seçicilerde görünen saatler: kalkış/varış havalimanının yerel saati.
    @State private var departure: Date
    @State private var arrival: Date
    @State private var seat: String
    @State private var gate: String
    /// Varış saatine elle dokunulduysa havalimanı değişince kaydırılmaz.
    @State private var arrivalTouched: Bool
    @FocusState private var focus: Field?

    private enum Field: Hashable { case number, from, to }

    init(trip: Trip, editing: FlightSegment?) {
        self.trip = trip
        self.editing = editing
        let calendar = Calendar.current
        let defaultDeparture = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: trip.startDate) ?? trip.startDate
        _flightNumber = State(initialValue: editing?.flightNumber ?? "")
        _fromCode = State(initialValue: editing?.fromCode ?? "")
        _fromCity = State(initialValue: editing?.fromCity ?? "")
        _toCode = State(initialValue: editing?.toCode ?? "")
        _toCity = State(initialValue: editing?.toCity ?? "")
        _departure = State(initialValue: editing.map {
            FlightClock.wallClock(for: $0.departure, timeZone: $0.departureTimeZone)
        } ?? defaultDeparture)
        _arrival = State(initialValue: editing.map {
            FlightClock.wallClock(for: $0.arrival, timeZone: $0.arrivalTimeZone)
        } ?? defaultDeparture.addingTimeInterval(3 * 3600))
        _seat = State(initialValue: editing?.seat ?? "")
        _gate = State(initialValue: editing?.gate ?? "")
        _arrivalTouched = State(initialValue: editing != nil)
    }

    /// Alanlar yazıldığı gibi tutulur (canlı düzeltme hızlı yazmayı bozuyor); kullanılırken temizlenir.
    private static func airportCode(_ text: String) -> String {
        String(text.uppercased(with: Locale(identifier: "en_US")).filter { $0.isLetter && $0.isASCII }.prefix(3))
    }
    private var number: String { flightNumber.uppercased(with: Locale(identifier: "en_US")).filter { !$0.isWhitespace } }
    private var from: String { Self.airportCode(fromCode) }
    private var to: String { Self.airportCode(toCode) }
    private var fromAirport: Airports.Airport? { Airports.airport(from) }
    private var toAirport: Airports.Airport? { Airports.airport(to) }
    private var departureZone: String? { fromAirport?.timeZone ?? (from == editing?.fromCode ? editing?.departureTimeZone : nil) }
    private var arrivalZone: String? { toAirport?.timeZone ?? (to == editing?.toCode ? editing?.arrivalTimeZone : nil) }

    private var departureInstant: Date { FlightClock.instant(wallClock: departure, timeZone: departureZone) }
    private var arrivalInstant: Date { FlightClock.instant(wallClock: arrival, timeZone: arrivalZone) }

    private var isValid: Bool {
        !number.isEmpty && from.count == 3 && to.count == 3 && from != to && arrivalInstant > departureInstant
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Uçuş numarası (ör. TK1759)", text: $flightNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .number)
                }

                Section {
                    airportField("Nereden", example: "IST", code: $fromCode, city: $fromCity, airport: fromAirport)
                        .focused($focus, equals: .from)
                    DatePicker("Kalkış", selection: $departure)
                } header: {
                    Text("Kalkış")
                } footer: {
                    Text(zoneNote(departureZone, code: from, city: fromAirport?.city ?? fromCity))
                }

                Section {
                    airportField("Nereye", example: "LIS", code: $toCode, city: $toCity, airport: toAirport)
                        .focused($focus, equals: .to)
                    DatePicker("Varış", selection: Binding(get: { arrival }, set: { arrival = $0; arrivalTouched = true }))
                } header: {
                    Text("Varış")
                } footer: {
                    if arrivalInstant <= departureInstant && from.count == 3 && to.count == 3 {
                        Text("Varış kalkıştan sonra olmalı.").foregroundStyle(Color.food)
                    } else {
                        Text(zoneNote(arrivalZone, code: to, city: toAirport?.city ?? toCity)
                             + (arrivalInstant > departureInstant
                                ? String(localized: " Uçuş süresi \(AppFormat.duration(minutes: Int(arrivalInstant.timeIntervalSince(departureInstant) / 60))).")
                                : ""))
                    }
                }

                Section {
                    TextField("Koltuk (ör. 14C)", text: $seat)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Kapı", text: $gate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                if editing != nil {
                    Section {
                        Button("Uçuşu sil", role: .destructive) {
                            store.update(trip.id) { $0.flights.removeAll { $0.id == editing?.id } }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? String(localized: "Uçuş ekle") : String(localized: "Uçuş"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? String(localized: "Ekle") : String(localized: "Kaydet"), action: save)
                        .disabled(!isValid)
                }
            }
            .onChange(of: departure) { old, new in
                // Kalkış kayınca varış da aynı süre kadar kaysın.
                arrival = arrival.addingTimeInterval(new.timeIntervalSince(old))
            }
            .onChange(of: departureZone) { old, new in
                // Kalkış havalimanı tanındı: girilen saat yeni yerel saat sayılır; varış süreyi korusun.
                guard !arrivalTouched else { return }
                let shift = FlightClock.instant(wallClock: departure, timeZone: new)
                    .timeIntervalSince(FlightClock.instant(wallClock: departure, timeZone: old))
                arrival = FlightClock.wallClock(for: FlightClock.instant(wallClock: arrival, timeZone: arrivalZone)
                    .addingTimeInterval(shift), timeZone: arrivalZone)
            }
            .onChange(of: arrivalZone) { old, new in
                // Varış havalimanı tanındı: aynı anı (aynı uçuş süresini) yeni yerel saatle göster.
                guard !arrivalTouched else { return }
                arrival = FlightClock.wallClock(for: FlightClock.instant(wallClock: arrival, timeZone: old), timeZone: new)
            }
            .onChange(of: focus) { old, _ in
                // Alan bırakılınca yazılanı toparla (yazarken düzeltmek hızlı girişi bozuyor).
                switch old {
                case .number: flightNumber = number
                case .from: fromCode = from
                case .to: toCode = to
                case nil: break
                }
            }
        }
    }

    @ViewBuilder
    private func airportField(_ title: String, example: String, code: Binding<String>, city: Binding<String>,
                              airport: Airports.Airport?) -> some View {
        HStack {
            TextField("\(title) · havalimanı kodu (\(example))", text: code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            if let airport {
                Text(airport.city).foregroundStyle(Color.ink2)
            }
        }
        if airport == nil && Self.airportCode(code.wrappedValue).count == 3 {
            TextField("Şehir", text: city)
        }
    }

    private func zoneNote(_ zone: String?, code: String, city: String) -> String {
        if zone != nil {
            return city.isEmpty ? String(localized: "Havalimanının yerel saatiyle.") : String(localized: "\(city) saatiyle.")
        }
        if code.count < 3 {
            return String(localized: "Saat, havalimanının yerel saatiyle girilir.")
        }
        return String(localized: "\(code) tanınmadı; saat bu cihazın saatiyle kaydedilir.")
    }

    private func save() {
        var flight = editing ?? FlightSegment(flightNumber: "", fromCode: "", fromCity: "", toCode: "", toCity: "",
                                              departure: departureInstant, arrival: arrivalInstant)
        let changedFlight = flight.flightNumber != number || flight.departure != departureInstant
        flight.flightNumber = number
        flight.fromCode = from
        flight.fromCity = fromAirport?.city ?? (fromCity.trimmingCharacters(in: .whitespaces).isEmpty ? from : fromCity)
        flight.toCode = to
        flight.toCity = toAirport?.city ?? (toCity.trimmingCharacters(in: .whitespaces).isEmpty ? to : toCity)
        flight.departure = departureInstant
        flight.arrival = arrivalInstant
        flight.departureTimeZone = departureZone
        flight.arrivalTimeZone = arrivalZone
        let trimmedSeat = seat.trimmingCharacters(in: .whitespaces)
        let trimmedGate = gate.trimmingCharacters(in: .whitespaces)
        flight.seat = trimmedSeat.isEmpty ? nil : trimmedSeat.uppercased(with: Locale(identifier: "en_US"))
        flight.gate = trimmedGate.isEmpty ? nil : trimmedGate.uppercased(with: Locale(identifier: "en_US"))

        store.update(trip.id) { trip in
            if let index = trip.flights.firstIndex(where: { $0.id == flight.id }) {
                trip.flights[index] = flight
            } else {
                trip.flights.append(flight)
            }
            trip.flights.sort { $0.departure < $1.departure }
        }
        dismiss()
    }
}
