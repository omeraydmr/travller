import MapKit
import PhotosUI
import SwiftUI
import StublyKit

struct NewTripSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onCreate: (Trip) -> Void

    @State private var name = ""
    @State private var countryCode = "PT"
    @State private var city = ""
    /// Seçilen şehrin konumu; haritalar, öneriler ve hava durumu buradan başlar.
    @State private var cityCoordinate: Coordinate?
    /// İlk şehirden sonraki şehirler (çok şehirli seyahat).
    @State private var extraLegs: [TripLeg] = []
    @State private var startDate = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 35, to: .now) ?? .now
    @State private var currency = "EUR"
    @State private var isDraft = false
    @State private var coverSeed = Int.random(in: 0..<100)
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var previewImage: UIImage?
    @State private var ceremonyTrip: Trip?

    static let currencies = ["EUR", "USD", "GBP", "TRY", "JPY", "CHF", "GEL", "AZN", "RSD", "MAD", "AMD", "BRL"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
                Section {
                    TextField("Seyahat adı (ör. Lizbon Kaçamağı)", text: $name)
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
                }
                ExtraCitiesSection(legs: $extraLegs, start: startDate, end: endDate, defaultCountry: countryCode)
                Section {
                    Picker("Para birimi", selection: $currency) {
                        ForEach(Self.currencies, id: \.self) { Text($0) }
                    }
                    Toggle("Taslak olarak kaydet", isOn: $isDraft)
                }
                Section {
                    VisaPreview(countryCode: countryCode, passport: store.me.passport, start: startDate, end: endDate,
                                otherSchengenStays: store.schengenStays(for: store.me.id))
                } header: {
                    Text("Senin için vize durumu")
                }
            }
            .navigationTitle(String(localized: "Yeni seyahat"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Oluştur", action: create)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onChange(of: countryCode) { _, _ in
                // Şehir başka ülkede kalmasın.
                city = ""
                cityCoordinate = nil
            }
            .onChange(of: startDate) { _, newValue in
                if endDate < newValue { endDate = newValue }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    // Önizleme için küçültülmüş görüntü: 12 MP fotoğraf her tuş vuruşunda yeniden çizilmesin.
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = CoverImageStore.downsample(data: data, maxPixelSize: CoverImageStore.cardPixelSize) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            photoData = data
                            previewImage = image
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(TintGlow(tint: Accent.cycle(coverSeed).base, offsetY: -200))
        }
        .overlay {
            if let ceremonyTrip {
                StampCeremony(trip: ceremonyTrip, coverImage: previewImage) {
                    onCreate(ceremonyTrip)
                    dismiss()
                }
            }
        }
        .interactiveDismissDisabled(ceremonyTrip != nil)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Formdaki değerlerle canlı önizleme kartı.
    private var preview: some View {
        TripTicketCard(trip: draftTrip, side: 230, maxWidth: 340)
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: draftTrip.cityLegs.count)
            .environment(\.coverOverride, previewImage)
            .overlay(alignment: .topLeading) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(previewImage == nil ? String(localized: "Fotoğraf ekle") : String(localized: "Değiştir"), systemImage: "camera.fill")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }
                .padding(12)
            }
            .rotationEffect(.degrees(-2))
            .padding(.vertical, 6)
    }

    private var draftTrip: Trip {
        var owner = store.me
        owner.role = .owner
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        var trip = Trip(name: trimmedName.isEmpty ? String(localized: "Yeni seyahat") : trimmedName,
                    destination: Destination(countryCode: countryCode,
                                             city: trimmedCity.isEmpty ? Countries.name(countryCode) : trimmedCity,
                                             coordinate: cityCoordinate),
                    startDate: Calendar.current.startOfDay(for: startDate),
                    endDate: Calendar.current.startOfDay(for: endDate),
                    status: isDraft ? .draft : .planned,
                    currency: currency,
                    coverSeed: coverSeed,
                    members: [owner])
        let extra = ExtraCitiesSection.valid(extraLegs, start: startDate, end: endDate)
        if !extra.isEmpty {
            trip.setLegs([TripLeg(destination: trip.destination, arrival: trip.startDate)] + extra)
        }
        return trip
    }

    private func create() {
        var trip = draftTrip
        trip.name = trimmedName
        if let photoData {
            trip.coverPhoto = try? CoverImageStore.shared.save(photoData)
        }
        ceremonyTrip = trip
    }
}

struct CountryPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List(filtered, id: \.self) { code in
            Button {
                selection = code
                dismiss()
            } label: {
                HStack {
                    Text(Countries.flag(code))
                    Text(Countries.name(code)).foregroundStyle(Color.ink)
                    Spacer()
                    if code == selection {
                        Image(systemName: "checkmark").foregroundStyle(Color.success)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: String(localized: "Ülke ara"))
        .navigationTitle("Ülke")
    }

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Countries.all }
        return Countries.all.filter {
            Countries.name($0).range(of: q, options: [.caseInsensitive, .diacriticInsensitive], locale: AppFormat.locale) != nil
        }
    }
}

/// Seçili ülkenin şehirleri (Apple Haritalar). Bulunamazsa yazılan ad konumsuz kullanılabilir.
struct CityPicker: View {
    let countryCode: String
    let onPick: (CityChoice) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var cities: [PlaceSearch.City] = []
    @State private var isSearching = false
    @State private var completer: CityCompleter

    init(countryCode: String, onPick: @escaping (CityChoice) -> Void) {
        self.countryCode = countryCode
        self.onPick = onPick
        _completer = State(initialValue: CityCompleter(countryCode: countryCode))
    }

    struct CityChoice {
        let name: String
        let coordinate: Coordinate?
    }

    var body: some View {
        List {
            if isSearching {
                ProgressView()
            }
            ForEach(cities) { city in
                Button {
                    pick(CityChoice(name: city.name, coordinate: city.coordinate))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(city.name).foregroundStyle(Color.ink)
                        if let region = city.region {
                            Text(region).font(.footnote).foregroundStyle(Color.ink2)
                        }
                    }
                }
            }
            ForEach(extraCompletions, id: \.self) { completion in
                Button {
                    Task {
                        isSearching = true
                        let city = await PlaceSearch.city(from: completion, countryCode: countryCode)
                        isSearching = false
                        pick(CityChoice(name: city?.name ?? completion.title, coordinate: city?.coordinate))
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(completion.title).foregroundStyle(Color.ink)
                        Text(completion.subtitle).font(.footnote).foregroundStyle(Color.ink2)
                    }
                }
            }
            let typed = query.trimmingCharacters(in: .whitespaces)
            if !typed.isEmpty && !isSearching && !cities.contains(where: { $0.name.localizedCaseInsensitiveCompare(typed) == .orderedSame }) {
                Button {
                    pick(CityChoice(name: typed, coordinate: nil))
                } label: {
                    Label("\"\(typed)\" olarak kullan", systemImage: "character.cursor.ibeam")
                }
            }
        }
        .overlay {
            if query.isEmpty {
                ContentUnavailableView("\(Countries.flag(countryCode)) \(Countries.name(countryCode))",
                                       systemImage: "building.2",
                                       description: Text("Gideceğin şehri ara; konumu haritalar ve öneriler için kaydedilir."))
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: String(localized: "Şehir ara"))
        .onChange(of: query) { _, newValue in completer.search(newValue.trimmingCharacters(in: .whitespaces)) }
        .task(id: query) {
            let typed = query.trimmingCharacters(in: .whitespaces)
            guard typed.count >= 2 else {
                cities = []
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            let found = await PlaceSearch.cities(typed, countryCode: countryCode)
            isSearching = false
            if !Task.isCancelled { cities = found }
        }
        .navigationTitle("Şehir")
    }

    /// Aramada çıkmayan otomatik tamamlama önerileri.
    private var extraCompletions: [MKLocalSearchCompletion] {
        var names = Set(cities.map { PlaceMatch.normalize($0.name) })
        // Aksanlı/aksansız aynı ad ("Portimao", "Portimão") tek satır.
        return completer.completions.filter { names.insert(PlaceMatch.normalize($0.title)).inserted }
    }

    private func pick(_ choice: CityChoice) {
        onPick(choice)
        dismiss()
    }
}
