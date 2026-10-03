import SwiftUI
import StublyKit

/// Seyahatin genel bilgileri: ad, ülke ve şehir, tarihler, para birimi, taslak durumu, kart rengi.
/// Tarih değişince plan istenirse birlikte kaydırılır; yeni aralığın dışında kalan duraklar Fikirler'e taşınır.
struct TripEditSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var name: String
    @State private var countryCode: String
    @State private var city: String
    @State private var cityCoordinate: Coordinate?
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var shiftPlan = true
    @State private var currency: String
    @State private var isDraft: Bool
    @State private var coverSeed: Int
    @State private var extraLegs: [TripLeg]

    init(trip: Trip) {
        self.trip = trip
        _name = State(initialValue: trip.name)
        _countryCode = State(initialValue: trip.destination.countryCode)
        _city = State(initialValue: trip.destination.city)
        _cityCoordinate = State(initialValue: trip.destination.coordinate)
        _startDate = State(initialValue: trip.startDate)
        _endDate = State(initialValue: trip.endDate)
        _currency = State(initialValue: trip.currency)
        _isDraft = State(initialValue: trip.status == .draft)
        _coverSeed = State(initialValue: trip.coverSeed)
        _extraLegs = State(initialValue: Array(trip.cityLegs.dropFirst()))
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var datesChanged: Bool {
        !Calendar.current.isDate(startDate, inSameDayAs: trip.startDate) || !Calendar.current.isDate(endDate, inSameDayAs: trip.endDate)
    }

    /// Kaydedince Fikirler'e taşınacak durak sayısı (önizleme).
    private var overflow: Int {
        var copy = trip
        return copy.reschedule(start: startDate, end: endDate, shiftPlan: shiftPlan)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Seyahat adı", text: $name)
                    NavigationLink {
                        CountryPicker(selection: $countryCode)
                    } label: {
                        LabeledContent("Ülke", value: "\(Countries.flag(countryCode)) \(Countries.name(countryCode))")
                    }
                    NavigationLink {
                        CityPicker(countryCode: countryCode) { choice in
                            city = choice.name
                            cityCoordinate = choice.coordinate
                        }
                    } label: {
                        LabeledContent("Şehir", value: city.isEmpty ? String(localized: "Seç") : city)
                    }
                }

                Section {
                    DatePicker("Gidiş", selection: $startDate, displayedComponents: .date)
                    DatePicker("Dönüş", selection: $endDate, in: startDate..., displayedComponents: .date)
                    if datesChanged && !trip.stops.isEmpty {
                        Toggle("Planı da kaydır", isOn: $shiftPlan)
                    }
                } footer: {
                    if datesChanged && !trip.stops.isEmpty {
                        let moved = overflow
                        Text(moved > 0
                             ? String(localized: "Duraklar gidiş tarihindeki kayma kadar taşınır. Yeni tarihlerin dışında kalan \(moved) durak Fikirler'e taşınır.")
                             : String(localized: "Duraklar gidiş tarihindeki kayma kadar taşınır; uçuş ve konaklamalar değişmez."))
                    }
                }

                ExtraCitiesSection(legs: $extraLegs, start: startDate, end: endDate, defaultCountry: countryCode)

                Section {
                    Picker("Para birimi", selection: $currency) {
                        ForEach(NewTripSheet.currencies, id: \.self) { Text($0) }
                    }
                    Toggle("Taslak", isOn: $isDraft)
                    Button {
                        withAnimation { coverSeed = (coverSeed + 1) % 100 }
                    } label: {
                        HStack {
                            Text("Kart rengini değiştir").foregroundStyle(Color.ink)
                            Spacer()
                            Circle().fill(Accent.cycle(coverSeed).base).frame(width: 22, height: 22)
                        }
                    }
                } footer: {
                    Text("Kapak fotoğrafını kartın menüsünden ya da seyahat ekranındaki ••• menüsünden değiştirebilirsin.")
                }
            }
            .navigationTitle("Seyahati düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save).disabled(trimmedName.isEmpty)
                }
            }
            .onChange(of: countryCode) { old, new in
                // Şehir başka ülkede kalmasın.
                if old != new {
                    city = ""
                    cityCoordinate = nil
                }
            }
            .onChange(of: startDate) { old, new in
                // Gidiş kayınca süre ve diğer şehirlerin varış günleri de aynı kadar kayar.
                let calendar = Calendar.current
                let length = calendar.dateComponents([.day], from: old, to: endDate).day ?? 0
                endDate = calendar.date(byAdding: .day, value: max(0, length), to: new) ?? new
                let delta = calendar.dateComponents([.day], from: calendar.startOfDay(for: old), to: calendar.startOfDay(for: new)).day ?? 0
                for index in extraLegs.indices {
                    extraLegs[index].arrival = calendar.date(byAdding: .day, value: delta, to: extraLegs[index].arrival) ?? extraLegs[index].arrival
                }
            }
        }
    }

    private func save() {
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = Destination(countryCode: countryCode,
                                      city: trimmedCity.isEmpty ? Countries.name(countryCode) : trimmedCity,
                                      coordinate: cityCoordinate)
        store.update(trip.id) { trip in
            trip.name = trimmedName
            if trip.destination != destination { trip.destination = destination }
            // Tarihler değişmediyse plana dokunulmaz (aralık dışında kalmış eski duraklar da yerinde kalır).
            if datesChanged { trip.reschedule(start: startDate, end: endDate, shiftPlan: shiftPlan) }
            trip.currency = currency
            trip.status = isDraft ? .draft : .planned
            trip.coverSeed = coverSeed
            let firstID = trip.cityLegs.first?.id ?? UUID()
            trip.setLegs([TripLeg(id: firstID, destination: trip.destination, arrival: trip.startDate)]
                         + ExtraCitiesSection.valid(extraLegs, start: startDate, end: endDate))
        }
        dismiss()
    }
}
