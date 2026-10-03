import SwiftUI
import StublyKit

/// Profil: kendi bilgilerin (ad, pasaport, vizeler, IBAN) ve gezilen ülkeler.
struct ProfileView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var isAddingCountry = false
    @State private var isShowingAbout = false

    var body: some View {
        let visited = TravelStats.visitedCountries(trips: store.trips, extra: store.extraVisitedCountries)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    meCard
                    countriesCard(visited)
                    Button {
                        store.restartOnboarding()
                    } label: {
                        HStack {
                            Label("Tanıtımı ve anketi yeniden göster", systemImage: "sparkles")
                                .font(.tBodyStrong)
                                .foregroundStyle(Color.ink)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.ink3)
                        }
                        .tray()
                    }
                    .buttonStyle(.plain)
                    Button {
                        isShowingAbout = true
                    } label: {
                        HStack {
                            Label("Hakkında, bildirimler ve veri kaynakları", systemImage: "info.circle")
                                .font(.tBodyStrong)
                                .foregroundStyle(Color.ink)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.ink3)
                        }
                        .tray()
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .background(TintGlow(tint: Accent.blue.base, offsetY: -200))
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
            .sheet(isPresented: $isEditing) {
                MemberEditor(member: store.me) { updated in store.saveProfile(updated) }
            }
            .sheet(isPresented: $isShowingAbout) { AboutView() }
            .sheet(isPresented: $isAddingCountry) {
                CountryPickerSheet(selected: Set(visited)) { code, isOn in store.setVisited(code, isOn) }
            }
        }
    }

    private var meCard: some View {
        let me = store.me
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                AvatarView(member: me, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(me.name).font(.tTitle).foregroundStyle(Color.ink)
                    if let passport = me.passport {
                        Text("\(passport.type.shortTitle) pasaport · \(AppFormat.longDate(passport.expiresOn)) tarihine kadar")
                            .font(.tBody)
                            .foregroundStyle(Color.ink2)
                    }
                }
                Spacer()
                Button("Düzenle") { isEditing = true }
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.ink)
            }
            if let visas = me.passport?.heldVisas, !visas.isEmpty {
                HStack(spacing: 6) {
                    ForEach(visas) { visa in
                        Tag(text: "\(VisaText.zoneName(visa.zone)) · \(AppFormat.shortDate(visa.validUntil))",
                            accent: visa.validUntil > .now ? .green : .orange)
                    }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "creditcard")
                if let iban = me.iban, !iban.isEmpty {
                    Text(IBAN.formatted(iban))
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    Text("IBAN eklenmedi; hesaplaşmada ekip sana kolayca ödeme yapabilsin diye ekleyebilirsin.")
                        .font(.footnote)
                }
            }
            .foregroundStyle(Color.ink2)
        }
        .tray()
    }

    private func countriesCard(_ visited: [String]) -> some View {
        let share = Double(visited.count) / Double(TravelStats.worldCountryCount)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(visited.count)")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ink)
                Text("ülke gezildi").font(.tBodyStrong).foregroundStyle(Color.ink2)
                Spacer()
                Tag(text: String(localized: "Dünyanın %\(Int((share * 100).rounded()))"), accent: .blue)
            }
            ProgressView(value: min(share, 1))
                .tint(Accent.blue.base)

            if visited.isEmpty {
                EmptyHint(symbol: "globe.europe.africa", text: String(localized: "Geçmiş seyahatlerin burada birikir; eskileri de ekleyebilirsin."))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    ForEach(visited, id: \.self) { code in
                        HStack(spacing: 6) {
                            Text(Countries.flag(code))
                            Text(Countries.name(code))
                                .font(.caption)
                                .foregroundStyle(Color.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.track, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }

            Button {
                isAddingCountry = true
            } label: {
                Label("Ülke ekle ya da çıkar", systemImage: "plus")
                    .font(.system(.subheadline, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.transport)
            Text("Planlanmış ve başlamış seyahatlerin ülkeleri otomatik sayılır; Türkiye hariç.")
                .font(.caption)
                .foregroundStyle(Color.ink3)
        }
        .tray()
    }
}

/// Aranabilir ülke listesi; işaretlenenler gezilmiş sayılır.
struct CountryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var selected: Set<String>
    let onToggle: (String, Bool) -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered, id: \.self) { code in
                    let isOn = selected.contains(code)
                    Button {
                        if isOn { selected.remove(code) } else { selected.insert(code) }
                        onToggle(code, !isOn)
                    } label: {
                        HStack {
                            Text("\(Countries.flag(code))  \(Countries.name(code))").foregroundStyle(Color.ink)
                            Spacer()
                            if isOn { Image(systemName: "checkmark").foregroundStyle(Color.success) }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: String(localized: "Ülke ara"))
            .navigationTitle("Gezilen ülkeler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
    }

    private var filtered: [String] {
        let all = Countries.all.filter { $0 != "TR" }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter { Countries.name($0).localizedStandardContains(trimmed) }
    }
}
