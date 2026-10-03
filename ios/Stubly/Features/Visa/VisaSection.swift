import SwiftUI
import StublyKit

struct VisaSection: View {
    let trip: Trip
    @Environment(TripStore.self) private var store
    @State private var focusedID: Member.ID?
    /// Çok ülkeli seyahatte seçili ülke; boşsa işlem gerektiren ilk ülke.
    @State private var selectedCountry: String?

    private var country: String {
        if let selectedCountry, trip.countryCodes.contains(selectedCountry) { return selectedCountry }
        return trip.countryCodes.first { code in
            trip.members.contains { store.visaAssessment(for: $0, in: trip, country: code).needsAction }
        } ?? trip.destination.countryCode
    }

    private struct Row {
        let member: Member
        let result: VisaAssessment
    }

    private var assessments: [Row] {
        trip.members.map { member in
            Row(member: member, result: store.visaAssessment(for: member, in: trip, country: country))
        }
    }

    var body: some View {
        let country = country
        let rows = assessments
        let readyCount = rows.filter { !$0.result.needsAction }.count
        VStack(spacing: 16) {
            ModuleCard(String(localized: "Vize"), symbol: "person.text.rectangle.fill") {
                if trip.countryCodes.count > 1 {
                    Picker("Ülke", selection: Binding(get: { country }, set: { value in
                        withAnimation(.spring(duration: 0.35)) { selectedCountry = value }
                    })) {
                        ForEach(trip.countryCodes, id: \.self) { code in
                            Text("\(Countries.flag(code)) \(Countries.name(code))").tag(code)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                StoryHeadline(text: headline(ready: readyCount, total: rows.count))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(rows, id: \.member.id) { row in
                            Button {
                                withAnimation(.spring(duration: 0.35)) { focusedID = row.member.id }
                            } label: {
                                PassportCard(member: row.member, result: row.result,
                                             countryCode: country)
                                    .scaleEffect(row.member.id == focusedRow(rows)?.member.id ? 1 : 0.94)
                                    .opacity(row.member.id == focusedRow(rows)?.member.id ? 1 : 0.7)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, 6)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $focusedID)
                .scrollClipDisabled()
                .animation(.spring(duration: 0.35), value: focusedID)

                if rows.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(rows, id: \.member.id) { row in
                            let isFocused = row.member.id == focusedRow(rows)?.member.id
                            Capsule()
                                .fill(isFocused ? Color.ink : Color.ink3.opacity(0.4))
                                .frame(width: isFocused ? 18 : 6, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .animation(.spring(duration: 0.3), value: focusedID)
                    .accessibilityHidden(true)
                }

                if let row = focusedRow(rows) {
                    VisaDetailPanel(member: row.member, result: row.result, trip: trip)
                        .id(row.member.id)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))

                    if Schengen.isSchengen(country) {
                        SchengenCard(member: row.member, trip: trip)
                            .id("schengen-\(row.member.id)")
                            .transition(.opacity)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("\(Countries.flag(country)) \(Countries.name(country))")
                        .font(.tBodyStrong)
                        .foregroundStyle(Color.ink)
                    if let note = visaNote(VisaRules.entry(for: country)) {
                        Text(note).font(.tBody).foregroundStyle(Color.ink2)
                    }
                    SourceFootnote()
                }
                .tray()
            }

            DocumentsCard(trip: trip)
            EmergencyCard(trip: trip)
        }
    }

    /// Elle yazılmış not her dilde; Dışişleri'nin Türkçe resmî metni yalnızca Türkçe arayüzde.
    private func visaNote(_ entry: CountryEntry?) -> String? {
        guard let entry else { return nil }
        if let note = entry.note { return note }
        return Bundle.main.preferredLocalizations.first == "tr" ? entry.officialText : nil
    }

    private func focusedRow(_ rows: [Row]) -> Row? {
        rows.first { $0.member.id == focusedID } ?? rows.first
    }

    private func headline(ready: Int, total: Int) -> String {
        if total == 0 { return String(localized: "Ekipte kimse yok.") }
        if ready == total { return total == 1 ? String(localized: "Girişe hazırsın.") : String(localized: "Herkes girişe hazır.") }
        let waiting = total - ready
        return ready == 0 ? String(localized: "\(waiting) kişinin yapacakları var.") : String(localized: "\(ready) kişi hazır, \(waiting) kişinin yapacakları var.")
    }
}

/// T.C. pasaportu görünümünde kart (türüne göre bordo, yeşil, gri ya da siyah); üzerinde seyahatin vize durumu
/// damga olarak basılı.
struct PassportCard: View {
    let member: Member
    let result: VisaAssessment
    let countryCode: String

    private var cover: [Color] { (member.passport?.type ?? .ordinary).coverColors }
    private static let gold = Color(hex: 0xE2C27A)

    var body: some View {
        let tag = VisaText.tag(result)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TÜRKİYE CUMHURİYETİ")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.2)
                    Text("PASAPORT")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(2.5)
                }
                .foregroundStyle(Self.gold)
                Spacer()
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Self.gold.opacity(0.85))
            }
            Spacer(minLength: 10)
            HStack(spacing: 10) {
                AvatarView(member: member, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(passportLine)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(width: 250, height: 156)
        .background(
            LinearGradient(colors: cover, startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(Hatch(spacing: 7).stroke(Color.white.opacity(0.04), lineWidth: 1))
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .topTrailing) {
            VisaStamp(text: tag.text, countryCode: countryCode, accent: tag.accent)
                .rotationEffect(.degrees(-12))
                .offset(x: -14, y: 46)
        }
        .shadow(color: cover[1].opacity(0.3), radius: 12, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(member.name), \(VisaText.subtitle(result))"))
        .accessibilityAddTraits(.isButton)
    }

    private var passportLine: String {
        guard let passport = member.passport else { return String(localized: "Pasaport bilgisi yok") }
        return passport.type == .ordinary
            ? String(localized: "Geçerlilik \(AppFormat.longDate(passport.expiresOn))")
            : String(localized: "\(passport.type.shortTitle) · geçerlilik \(AppFormat.longDate(passport.expiresOn))")
    }
}

/// Mürekkep damgası görünümünde durum etiketi.
struct VisaStamp: View {
    let text: String
    let countryCode: String
    let accent: Accent

    var body: some View {
        let color = accent == .gray ? Color.white.opacity(0.8) : accent.base
        VStack(spacing: 1) {
            Text(Countries.flag(countryCode)).font(.system(size: 14))
            Text(text.uppercased(with: AppFormat.locale))
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.8)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [5, 2]))
                .padding(2)
        )
    }
}

/// Yeni seyahat formunda gösterilen kısa önizleme.
struct VisaPreview: View {
    let countryCode: String
    let passport: Passport?
    let start: Date
    let end: Date
    var otherSchengenStays: [Schengen.Stay] = []

    var body: some View {
        let result = VisaAdvisor.assess(countryCode: countryCode, passport: passport, tripStart: start, tripEnd: end,
                                        otherSchengenStays: otherSchengenStays)
        let tag = VisaText.tag(result)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(VisaText.subtitle(result)).font(.subheadline)
                Spacer()
                Tag(text: tag.text, accent: tag.accent)
            }
            ForEach(result.warnings, id: \.self) { warning in
                Label(VisaText.warning(warning), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.food)
            }
        }
    }
}

struct SourceFootnote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bilgiler her kişinin pasaport türüne göredir (bordo, yeşil, gri, diplomatik); kaynak Dışişleri Bakanlığı, son gözden geçirme \(VisaRules.lastReviewed). Seyahatten önce resmî kaynaktan doğrula.")
                .font(.footnote)
                .foregroundStyle(Color.ink3)
            Link("konsolosluk.gov.tr", destination: VisaRules.officialSourceURL)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Color.transport)
        }
    }
}

// MARK: - Detail

/// Odaktaki pasaportun detayı: pasaport bitişi, uyarılar ve vize gerekiyorsa başvuru takibi
/// (durum, randevu, belge listesi). Takip seyahatle birlikte saklanır ve ekiple eşitlenir.
struct VisaDetailPanel: View {
    @Environment(TripStore.self) private var store
    let member: Member
    let result: VisaAssessment
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AvatarView(member: member, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name).font(.tBodyStrong).foregroundStyle(Color.ink)
                    Text(VisaText.subtitle(result)).font(.tBody).foregroundStyle(Color.ink2)
                }
                Spacer(minLength: 8)
                let tag = VisaText.tag(result)
                Tag(text: tag.text, accent: tag.accent)
            }

            if !result.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(result.warnings, id: \.self) { warning in
                        Label(VisaText.warning(warning), systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.food)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.foodTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if case let .required(zone) = result.status {
                applicationTracker(zone: zone)
            }
        }
        .tray()
    }

    // MARK: Başvuru takibi

    private var application: VisaApplication {
        trip.visaApplication(for: member.id) ?? VisaApplication(memberID: member.id)
    }

    private func updateApplication(_ change: (inout VisaApplication) -> Void) {
        store.update(trip.id) { trip in
            var list = trip.visaApplications ?? []
            if let index = list.firstIndex(where: { $0.memberID == member.id }) {
                change(&list[index])
            } else {
                var created = VisaApplication(memberID: member.id)
                change(&created)
                list.append(created)
            }
            trip.visaApplications = list
        }
    }

    @ViewBuilder
    private func applicationTracker(zone: VisaZone?) -> some View {
        let application = self.application
        let documents = VisaText.documents(for: zone)
        let checked = Set(application.checkedDocuments)

        VStack(alignment: .leading, spacing: 8) {
            Text("Başvuru durumu").font(.tCaption).foregroundStyle(Color.ink3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(VisaApplication.Status.allCases, id: \.self) { status in
                        let isSelected = application.status == status
                        Button {
                            withAnimation(.spring(duration: 0.25)) { updateApplication { $0.status = status } }
                        } label: {
                            Text(VisaText.statusTitle(status))
                                .font(.system(.footnote, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.onInk : Color.ink2)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(isSelected ? VisaText.statusAccent(status).base : Color.track, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { application.appointment != nil },
                set: { isOn in
                    updateApplication {
                        $0.appointment = isOn
                            ? Calendar.current.date(bySettingHour: 10, minute: 0, second: 0,
                                                    of: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now)
                            : nil
                        if isOn && $0.status == .preparing { $0.status = .appointmentBooked }
                    }
                }
            )) {
                Label("Randevu", systemImage: "calendar.badge.clock").font(.subheadline)
            }
            .tint(Color.ink)
            if let appointment = application.appointment {
                DatePicker("Tarih ve saat", selection: Binding(
                    get: { appointment },
                    set: { value in updateApplication { $0.appointment = value } }
                ), in: Date.now...)
                .font(.subheadline)
                TextField("Yer (ör. VFS Global İstanbul)", text: Binding(
                    get: { application.center },
                    set: { value in updateApplication { $0.center = value } }
                ))
                .font(.subheadline)
                .textFieldStyle(.roundedBorder)
                if let days = Calendar.current.dateComponents([.day], from: .now, to: appointment).day,
                   let latest = Calendar.current.date(byAdding: .day, value: -15, to: trip.startDate), appointment > latest {
                    Label("Randevu seyahate \(max(0, days)) gün kala; onay süresi yetmeyebilir.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.food)
                }
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Belge listesi").font(.tCaption).foregroundStyle(Color.ink3)
                Spacer()
                Text("\(checked.intersection(documents).count)/\(documents.count)")
                    .font(.tCaption)
                    .foregroundStyle(Color.ink3)
            }
            ForEach(documents, id: \.self) { document in
                let isDone = checked.contains(document)
                Button {
                    withAnimation(.spring(duration: 0.2)) {
                        updateApplication { application in
                            if isDone {
                                application.checkedDocuments.removeAll { $0 == document }
                            } else {
                                application.checkedDocuments.append(document)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isDone ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundStyle(isDone ? Color.success : Color.ink3)
                        Text(document)
                            .font(.subheadline)
                            .foregroundStyle(isDone ? Color.ink3 : Color.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("Konsolosluğa ve başvuru amacına göre değişir; randevu ve güncel liste için yetkili aracı kurumu kontrol et.")
                .font(.caption)
                .foregroundStyle(Color.ink3)
                .padding(.top, 4)
        }
    }
}

// MARK: - Texts

enum VisaText {
    static func zoneName(_ zone: VisaZone?) -> String {
        switch zone {
        case .schengen: "Schengen"
        case .uk: String(localized: "Birleşik Krallık")
        case .us: "ABD"
        case .canada: String(localized: "Kanada")
        case nil: ""
        }
    }

    static func subtitle(_ result: VisaAssessment) -> String {
        switch result.status {
        case .domestic: return String(localized: "Yurt içi seyahat")
        case let .notRequired(days): return String(localized: "Vizesiz · \(days) güne kadar")
        case .eVisa: return String(localized: "Önceden e-vize alınmalı")
        case let .onArrival(days): return days.map { String(localized: "Kapıda vize · \($0) gün") } ?? String(localized: "Kapıda vize")
        case let .required(zone): return String(localized: "\(zoneName(zone)) vizesi gerekli").trimmingCharacters(in: .whitespaces)
        case let .coveredByHeldVisa(zone, until):
            return String(localized: "\(zoneName(zone)) vizesi · bitiş \(AppFormat.longDate(until))")
        case .noPassport: return String(localized: "Pasaport bilgisi eklenmedi")
        case .unknown: return String(localized: "Bu ülke için veri yok")
        }
    }

    static func tag(_ result: VisaAssessment) -> (text: String, accent: Accent) {
        if result.warnings.contains(where: {
            if case .passportExpiresDuringTrip = $0 { return true }
            return false
        }) {
            return ("Pasaport", .orange)
        }
        switch result.status {
        case .domestic, .notRequired: return result.needsAction ? (String(localized: "Uyarı"), .orange) : (String(localized: "Gerekmez"), .green)
        case .coveredByHeldVisa: return result.needsAction ? (String(localized: "Uyarı"), .orange) : (String(localized: "Geçerli ✓"), .green)
        case .onArrival: return (String(localized: "Kapıda"), .blue)
        case .eVisa: return (String(localized: "e-Vize"), .blue)
        case .required: return (String(localized: "Başvuru"), .orange)
        case .noPassport: return ("Eksik", .orange)
        case .unknown: return ("Kontrol et", .gray)
        }
    }

    static func warning(_ warning: VisaWarning) -> String {
        switch warning {
        case let .passportExpiresDuringTrip(date):
            return String(localized: "Pasaport seyahat bitmeden sona eriyor (\(AppFormat.shortDate(date))). Yenilemen gerekiyor.")
        case let .passportValidityShort(months, mandatory, _):
            return mandatory
                ? String(localized: "Pasaport dönüşten sonra en az \(months) ay geçerli olmalı.")
                : String(localized: "Pasaportun dönüşten sonra \(months) aydan az geçerli; bazı havayolları ve sınır kapıları sorun çıkarabilir.")
        case let .stayExceedsLimit(maxDays, tripDays):
            return String(localized: "Seyahat \(tripDays) gün; vizesiz kalış sınırı \(maxDays) gün.")
        case let .heldVisaExpiresDuringTrip(zone, until):
            return String(localized: "\(zoneName(zone)) vizen seyahat bitmeden sona eriyor (\(AppFormat.shortDate(until))).")
        case let .schengenOverstay(firstDay, latestExit, days):
            let exit = latestExit.map { String(localized: " En geç \(AppFormat.shortDate($0)) günü çıkmalısın.") } ?? ""
            return String(localized: "Schengen 90/180 sınırı \(AppFormat.shortDate(firstDay)) günü aşılıyor (\(days) gün fazla).\(exit)")
        }
    }

    static func statusTitle(_ status: VisaApplication.Status) -> String {
        switch status {
        case .preparing: String(localized: "Hazırlanıyor")
        case .appointmentBooked: String(localized: "Randevu alındı")
        case .submitted: String(localized: "Başvuruldu")
        case .approved: String(localized: "Onaylandı")
        case .rejected: String(localized: "Reddedildi")
        }
    }

    static func statusAccent(_ status: VisaApplication.Status) -> Accent {
        switch status {
        case .preparing: .gray
        case .appointmentBooked, .submitted: .blue
        case .approved: .green
        case .rejected: .orange
        }
    }

    static func documents(for zone: VisaZone?) -> [String] {
        var list = [
            String(localized: "Başvuru formu"),
            String(localized: "Biyometrik fotoğraf"),
            "Pasaport ve eski vizelerin fotokopisi",
            String(localized: "Uçak rezervasyonu"),
            String(localized: "Konaklama rezervasyonu"),
            String(localized: "Son 3 ayın banka hesap dökümü"),
            String(localized: "İşveren yazısı / SGK dökümü veya öğrenci belgesi"),
        ]
        if zone == .schengen {
            list.insert(String(localized: "En az 30.000 € teminatlı seyahat sağlık sigortası"), at: 4)
        }
        return list
    }
}
