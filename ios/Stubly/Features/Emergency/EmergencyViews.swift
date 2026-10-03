import SwiftUI
import StublyKit

/// Vize sekmesinde acil durum kartı: ülkenin acil numaraları, konsolosluk çağrı merkezi, kişisel sağlık bilgileri.
/// Hepsi cihazda; internet olmadan da açılır.
struct EmergencyCard: View {
    @Environment(TripStore.self) private var store
    let trip: Trip
    @State private var isEditing = false
    @State private var isShowingAllergyCard = false

    var body: some View {
        // Çok şehirde bugün bulunulan (seyahatten önce ilk, sonra son) şehir.
        let here = trip.destination(on: .now)
        let country = here.countryCode
        let numbers = EmergencyNumbers.numbers(for: country)
        let info = store.emergency
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Acil durum", systemImage: "cross.case.fill")
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink)
                Spacer()
                Button(info.isEmpty ? String(localized: "Bilgilerimi ekle") : String(localized: "Düzenle")) { isEditing = true }
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Color.ink)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("\(here.city) · acil numaralar").font(.tCaption).foregroundStyle(Color.ink2)
                if let numbers {
                    FlowLayout(spacing: 8) {
                        if let general = numbers.general { callChip(String(localized: "Acil"), general, symbol: "sos") }
                        if let police = numbers.police { callChip(String(localized: "Polis"), police, symbol: "shield.fill") }
                        if let ambulance = numbers.ambulance { callChip(String(localized: "Ambulans"), ambulance, symbol: "cross.fill") }
                        if let fire = numbers.fire, fire != numbers.ambulance { callChip(String(localized: "İtfaiye"), fire, symbol: "flame.fill") }
                    }
                } else {
                    Text("Bu ülkenin numarası listemizde yok. Birçok ülkede cep telefonundan 112 çalışır; varışta doğrula.")
                        .font(.caption).foregroundStyle(Color.ink2)
                }
                callChip(String(localized: "Konsolosluk çağrı merkezi (7/24)"), EmergencyNumbers.consularCallCenter, symbol: "phone.fill")
                Link(destination: EmergencyNumbers.representationsURL) {
                    Label("Büyükelçilik ve konsolosluk adresleri", systemImage: "building.columns")
                        .font(.system(.footnote, weight: .medium))
                }
                .foregroundStyle(Color.ink2)
            }

            if !info.isEmpty {
                Divider().overlay(Color.line)
                personal(info)
            }

            Text("Numaralar elle derlenmiştir; seyahatten önce resmî kaynaktan doğrula.")
                .font(.caption2)
                .foregroundStyle(Color.ink3)
        }
        .tray()
        .sheet(isPresented: $isEditing) {
            EmergencyEditor(info: store.emergency) { store.saveEmergency($0) }
        }
        .fullScreenCover(isPresented: $isShowingAllergyCard) {
            AllergyCardView(info: info, countryCode: country)
        }
    }

    @ViewBuilder
    private func personal(_ info: EmergencyInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !info.bloodType.isEmpty { line("drop.fill", String(localized: "Kan grubu"), info.bloodType) }
            let allergies = info.allergens.map(AllergyCard.turkishName) + (info.otherAllergies.isEmpty ? [] : [info.otherAllergies])
            if !allergies.isEmpty { line("allergens", String(localized: "Alerji"), allergies.joined(separator: ", ")) }
            if !info.medications.isEmpty { line("pills.fill", String(localized: "İlaçlar"), info.medications) }
            if !info.contactName.isEmpty || !info.contactPhone.isEmpty {
                line("person.fill", String(localized: "Acil kişi"), [info.contactName, info.contactPhone].filter { !$0.isEmpty }.joined(separator: " · "))
            }
        }
        HStack(spacing: 8) {
            if !info.contactPhone.isEmpty { callChip(String(localized: "Acil kişiyi ara"), info.contactPhone, symbol: "phone.fill") }
            if !info.insurancePhone.isEmpty { callChip(String(localized: "Sigorta yardım"), info.insurancePhone, symbol: "cross.case") }
        }
        if !info.allergens.isEmpty {
            Button {
                isShowingAllergyCard = true
            } label: {
                Label("Alerji kartını göster", systemImage: "rectangle.portrait.on.rectangle.portrait")
            }
            .buttonStyle(.primary)
        }
    }

    private func line(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Color.food).frame(width: 20)
            Text(title).font(.tBody).foregroundStyle(Color.ink2)
            Spacer(minLength: 8)
            Text(value).font(.tBodyStrong).foregroundStyle(Color.ink).multilineTextAlignment(.trailing)
        }
    }

    private func callChip(_ title: String, _ number: String, symbol: String) -> some View {
        let digits = number.split(separator: "/").first.map { String($0) }?.filter { $0.isNumber || $0 == "+" } ?? ""
        return Link(destination: URL(string: "tel:\(digits)") ?? EmergencyNumbers.representationsURL) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text("\(title) · \(number)")
            }
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.track, in: Capsule())
        }
        .accessibilityLabel("\(title), \(number) ara")
    }
}

/// Kişisel acil durum bilgileri; yalnızca bu cihazda saklanır.
struct EmergencyEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var info: EmergencyInfo
    let onSave: (EmergencyInfo) -> Void

    static let bloodTypes = ["", "0 Rh+", "0 Rh−", "A Rh+", "A Rh−", "B Rh+", "B Rh−", "AB Rh+", "AB Rh−"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kan grubu", selection: $info.bloodType) {
                        ForEach(Self.bloodTypes, id: \.self) { Text($0.isEmpty ? String(localized: "Belirtilmedi") : $0).tag($0) }
                    }
                }
                Section {
                    ForEach(Allergen.allCases, id: \.self) { allergen in
                        Toggle(AllergyCard.turkishName(allergen), isOn: Binding(
                            get: { info.allergens.contains(allergen) },
                            set: { isOn in
                                if isOn { info.allergens.append(allergen) } else { info.allergens.removeAll { $0 == allergen } }
                            }))
                    }
                    TextField("Diğer alerjiler", text: $info.otherAllergies)
                } header: {
                    Text("Alerjiler")
                } footer: {
                    Text("Listedekiler, alerji kartında gidilen ülkenin diline ve İngilizceye çevrilir.")
                }
                Section("İlaçlar") {
                    TextField("Düzenli kullandığın ilaçlar", text: $info.medications, axis: .vertical)
                }
                Section("Acil durumda aranacak kişi") {
                    TextField("Ad", text: $info.contactName).textContentType(.name)
                    TextField("Telefon", text: $info.contactPhone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                }
                Section {
                    TextField("Sigorta yardım hattı", text: $info.insurancePhone).keyboardType(.phonePad)
                } footer: {
                    Text("Bu bilgiler yalnızca bu cihazda saklanır; seyahat ekibiyle ve iCloud'la paylaşılmaz.")
                }
            }
            .navigationTitle("Acil durum bilgilerim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        onSave(info)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Restoranda ya da eczanede gösterilecek büyük yazılı alerji kartı.
struct AllergyCardView: View {
    @Environment(\.dismiss) private var dismiss
    let info: EmergencyInfo
    let countryCode: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(AllergyCard.languages(forCountry: countryCode), id: \.self) { language in
                    if let phrase = AllergyCard.phrase(info.allergens, language: language) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(phrase.heading).font(.system(size: 26, weight: .bold))
                            ForEach(phrase.items, id: \.self) { item in
                                Text("• \(item)").font(.system(size: 30, weight: .semibold))
                            }
                        }
                        .environment(\.locale, Locale(identifier: language))
                    }
                }
                Text(String(localized: "Türkçe: ") + info.allergens.map(AllergyCard.turkishName).joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.black)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 40, height: 40).background(Color.black.opacity(0.08), in: Circle())
            }
            .padding(16)
            .accessibilityLabel("Kapat")
        }
    }
}
