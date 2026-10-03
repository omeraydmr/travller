import SwiftUI
import StublyKit

struct CrewSection: View {
    @Environment(TripStore.self) private var store
    let trip: Trip

    @State private var editing: Member?
    @State private var isAdding = false
    @State private var blockedRemoval: Member?

    var body: some View {
        ModuleCard(String(localized: "Ekip"), symbol: "person.2.fill") {
            StoryHeadline(text: String(localized: "\(trip.members.count) kişi \(trip.cityTitle) yolunda."))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(trip.members) { member in
                    Button {
                        editing = member
                    } label: {
                        MemberTile(member: member, trip: trip)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if member.role != .owner {
                            Button("Ekipten çıkar", systemImage: "person.badge.minus", role: .destructive) {
                                remove(member)
                            }
                        }
                    }
                }
                Button {
                    isAdding = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 52, height: 52)
                            .background(Color.track, in: Circle())
                        Text("Kişi ekle").font(.system(.subheadline, weight: .semibold))
                    }
                    .foregroundStyle(Color.ink2)
                    .frame(maxWidth: .infinity, minHeight: 168)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.ink3.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    )
                }
                .buttonStyle(.plain)
            }

            InviteCard(trip: trip)

            ActivityFeed(entries: store.activity[trip.id] ?? [])

            if CloudSync.shared.sharedWithMe.contains(trip.id), !trip.members.contains(where: { $0.id == store.me.id }) {
                let canJoin = store.canEdit(trip)
                HStack(spacing: 12) {
                    AvatarView(member: store.me, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bu seyahate katıldın").font(.tBodyStrong).foregroundStyle(Color.ink)
                        Text(canJoin ? String(localized: "Harcama ve valizde görünmek için kendini ekle.")
                                     : String(localized: "Seyahatin sahibi seni yalnızca görüntüleyici olarak davet etti."))
                            .font(.caption).foregroundStyle(Color.ink2)
                    }
                    Spacer()
                    if canJoin {
                        Button("Ekle") {
                            var me = store.me
                            me.role = .editor
                            me.colorIndex = trip.members.count
                            // Sahip yetkini değiştirdiğinde iCloud izni de seninle eşleşsin.
                            me.cloudUserID = CloudSync.shared.currentUserID
                            store.update(trip.id) { $0.members.append(me) }
                        }
                        .font(.system(.subheadline, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(Color.ink)
                    }
                }
                .tray(padding: 14)
            }
        }
        .sheet(item: $editing) { member in
            MemberEditor(member: member, canChangeRole: store.role(in: trip) == .owner) { updated in
                store.update(trip.id) { trip in
                    if let index = trip.members.firstIndex(where: { $0.id == updated.id }) {
                        trip.members[index] = updated
                    }
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            MemberEditor(member: Member(name: "", role: .editor, colorIndex: trip.members.count,
                                        passport: Passport(expiresOn: Calendar.current.date(byAdding: .year, value: 5, to: .now) ?? .now)),
                         isNew: true) { member in
                store.update(trip.id) { $0.members.append(member) }
            }
        }
        .alert("Kişi çıkarılamıyor", isPresented: Binding(get: { blockedRemoval != nil },
                                                          set: { if !$0 { blockedRemoval = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("\(blockedRemoval?.name ?? "") harcamalarda yer alıyor. Önce ilgili harcamaları sil ya da düzenle.")
        }
    }

    private func remove(_ member: Member) {
        let involved = trip.expenses.contains { $0.paidBy == member.id || $0.splitAmong.contains(member.id) }
        guard !involved else {
            blockedRemoval = member
            return
        }
        store.update(trip.id) { trip in
            trip.members.removeAll { $0.id == member.id }
            for index in trip.packing.indices where trip.packing[index].assignee == member.id {
                trip.packing[index].assignee = nil
            }
        }
    }
}

/// Ekip ızgarasındaki kişi kartı: büyük avatar, rol ve vize durumu.
struct MemberTile: View {
    let member: Member
    let trip: Trip
    @Environment(TripStore.self) private var store

    var body: some View {
        let result = store.visaAssessment(for: member, in: trip)
        let tag = VisaText.tag(result)
        VStack(spacing: 8) {
            AvatarView(member: member, size: 56)
                .overlay(alignment: .bottomTrailing) {
                    if member.role == .owner {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.food, in: Circle())
                            .overlay(Circle().strokeBorder(Color.tray, lineWidth: 2))
                    }
                }
            VStack(spacing: 2) {
                Text(member.name).font(.tBodyStrong).foregroundStyle(Color.ink).lineLimit(1)
                Text(member.role.title).font(.caption).foregroundStyle(Color.ink3)
            }
            HStack(spacing: 4) {
                Image(systemName: "person.text.rectangle")
                Text(tag.text)
            }
            .font(.system(.caption, weight: .semibold))
            .foregroundStyle(tag.accent == .gray ? Color.ink2 : tag.accent.base)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tag.accent.tint, in: Capsule())
        }
        .frame(maxWidth: .infinity, minHeight: 168)
        .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct MemberEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var member: Member
    var isNew = false
    /// Yetkiyi yalnızca seyahatin sahibi değiştirebilir.
    var canChangeRole = true
    let onSave: (Member) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ad", text: $member.name)
                    if member.role != .owner && canChangeRole {
                        Picker("Yetki", selection: $member.role) {
                            Text(MemberRole.editor.title).tag(MemberRole.editor)
                            Text(MemberRole.viewer.title).tag(MemberRole.viewer)
                        }
                    }
                } footer: {
                    if member.role != .owner && canChangeRole && !isNew {
                        Text(member.cloudUserID == nil
                             ? String(localized: "Bu kişi iCloud davetiyle katılıp kendini eklemediği için yetki yalnızca uygulamada uygulanır.")
                             : String(localized: "Yetki iCloud paylaşımına da uygulanır: \"Sadece görür\" kişi seyahati hiçbir cihazdan değiştiremez."))
                    }
                }

                Section {
                    Toggle("Pasaport bilgisi", isOn: Binding(
                        get: { member.passport != nil },
                        set: { member.passport = $0 ? Passport(expiresOn: Calendar.current.date(byAdding: .year, value: 5, to: .now) ?? .now) : nil }
                    ))
                    if member.passport != nil {
                        Picker("Tür", selection: passportBinding(\.type)) {
                            ForEach(PassportType.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        DatePicker("Geçerlilik bitişi", selection: passportBinding(\.expiresOn), displayedComponents: .date)
                    }
                } header: {
                    Text("Pasaport (T.C.)")
                } footer: {
                    if member.passport != nil {
                        Text("Vize kuralları pasaport türüne göre değişir: yeşil, gri ve diplomatik pasaport Schengen'de 180 günde 90 gün vizesizdir.")
                    }
                }

                Section {
                    TextField("TR00 0000 0000 0000 0000 0000 00", text: Binding(
                        get: { member.iban ?? "" },
                        set: { member.iban = $0.isEmpty ? nil : IBAN.formatted($0) }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    if let iban = member.iban, !iban.isEmpty, !IBAN.isValid(iban) {
                        Label("IBAN geçersiz görünüyor", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.food)
                    }
                } header: {
                    Text("IBAN")
                } footer: {
                    Text("Hesaplaşmada bu kişiye borcu olanlar IBAN'ı tek dokunuşla kopyalayabilir.")
                }

                if member.passport != nil {
                    Section {
                        ForEach(VisaZone.allCases, id: \.self) { zone in
                            heldVisaRow(zone)
                        }
                    } header: {
                        Text("Elindeki geçerli vizeler")
                    } footer: {
                        Text("Geçerli bir vize, aynı bölgeye yapılan seyahatlerde otomatik olarak dikkate alınır.")
                    }
                }
            }
            .navigationTitle(isNew ? String(localized: "Kişi ekle") : member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        member.name = member.name.trimmingCharacters(in: .whitespaces)
                        onSave(member)
                        dismiss()
                    }
                    .disabled(member.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func heldVisaRow(_ zone: VisaZone) -> some View {
        let index = member.passport?.heldVisas.firstIndex { $0.zone == zone }
        Toggle(VisaText.zoneName(zone), isOn: Binding(
            get: { index != nil },
            set: { isOn in
                if isOn {
                    let until = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
                    member.passport?.heldVisas.append(HeldVisa(zone: zone, validUntil: until))
                } else {
                    member.passport?.heldVisas.removeAll { $0.zone == zone }
                }
            }
        ))
        if let index {
            DatePicker("Bitiş", selection: Binding(
                get: { member.passport?.heldVisas[index].validUntil ?? .now },
                set: { member.passport?.heldVisas[index].validUntil = $0 }
            ), displayedComponents: .date)
            .padding(.leading, 16)
        }
    }

    private func passportBinding<Value>(_ keyPath: WritableKeyPath<Passport, Value>) -> Binding<Value> {
        Binding(
            get: { member.passport![keyPath: keyPath] },
            set: { member.passport?[keyPath: keyPath] = $0 }
        )
    }
}

/// iCloud paylaşım davetini (Mesajlar, Mail, AirDrop…) gönderen kart.
struct InviteCard: View {
    let trip: Trip
    @Environment(TripStore.self) private var store
    @State private var isShowingQR = false
    private var sync: CloudSync { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.transport)
                    .frame(width: 36, height: 36)
                    .background(Color.transportTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.tBodyStrong).foregroundStyle(Color.ink)
                    Text(subtitle).font(.caption).foregroundStyle(Color.ink2)
                }
            }

            if sync.isAvailable {
                ShareLink(item: TripShareItem(tripID: trip.id, title: trip.name),
                          preview: SharePreview("\(trip.name) · Stubly")) {
                    Label(sync.sharedByMe.contains(trip.id) ? String(localized: "Paylaşımı yönet / yeni kişi davet et") : String(localized: "Davet bağlantısı gönder"),
                          systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.primary)

                if !sync.sharedWithMe.contains(trip.id) {
                    Button {
                        isShowingQR = true
                    } label: {
                        Label(sync.openInviteLinks.contains(trip.id) ? String(localized: "QR davet açık · göster") : String(localized: "QR ile davet et"),
                              systemImage: "qrcode")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.ink)
                }
            }

            // QR bağlantısıyla katılıp ekipte olmayanlar: salt okur; ekibe eklenince düzenleyebilir.
            if let joiners = sync.linkJoiners[trip.id], !joiners.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("QR ile katılanlar · şimdilik sadece görür").font(.caption).foregroundStyle(Color.ink2)
                    ForEach(joiners) { joiner in
                        HStack {
                            Label(joiner.name, systemImage: "person.crop.circle")
                                .font(.subheadline)
                                .foregroundStyle(Color.ink)
                            Spacer()
                            Button("Ekibe ekle") { add(joiner) }
                                .font(.system(.footnote, weight: .semibold))
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .tray()
        .sheet(isPresented: $isShowingQR) { InviteQRSheet(trip: trip) }
    }

    /// Bağlantıyla katılanı düzenleyebilir olarak ekibe ekler; iCloud izni bir sonraki eşitlemede yükseltilir.
    private func add(_ joiner: CloudSync.LinkJoiner) {
        store.update(trip.id) { trip in
            trip.members.append(Member(name: joiner.name, role: .editor, colorIndex: trip.members.count,
                                       cloudUserID: joiner.id))
        }
        sync.forgetJoiner(joiner.id, in: trip.id)
    }

    private var title: String {
        if sync.sharedWithMe.contains(trip.id) { return String(localized: "Bu seyahat seninle paylaşıldı") }
        if sync.sharedByMe.contains(trip.id) { return String(localized: "Ekip iCloud ile bağlı") }
        return String(localized: "Ekibi davet et")
    }

    private var subtitle: String {
        switch sync.status {
        case let .unavailable(reason): return reason
        case .unknown: return String(localized: "iCloud durumu kontrol ediliyor…")
        case .syncing: return String(localized: "Eşitleniyor…")
        case let .synced(date): return String(localized: "Değişiklikler herkesin telefonunda görünür · son eşitleme \(AppFormat.time(date))")
        case let .failed(message): return String(localized: "Eşitleme sorunu: \(message)")
        }
    }
}

/// Ekipten gelen son değişiklikler ("Elif bir harcama ekledi").
struct ActivityFeed: View {
    let entries: [ActivityEntry]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Son hareketler", systemImage: "clock.arrow.circlepath")
                .font(.tBodyStrong)
                .foregroundStyle(Color.ink)
            if entries.isEmpty {
                Text("Ekipten biri bir şey eklediğinde burada görünür.")
                    .font(.footnote)
                    .foregroundStyle(Color.ink3)
            }
            ForEach(entries.prefix(isExpanded ? 50 : 4)) { entry in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Color.ink3).frame(width: 6, height: 6).padding(.top, 7)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(entry.lines, id: \.self) { line in
                            Text(line).font(.subheadline).foregroundStyle(Color.ink)
                        }
                        Text(entry.date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(Color.ink3)
                    }
                }
            }
            if entries.count > 4 {
                Button(isExpanded ? String(localized: "Daha az göster") : String(localized: "Tümünü göster (\(entries.count))")) {
                    withAnimation { isExpanded.toggle() }
                }
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Color.transport)
            }
        }
        .tray()
    }
}
