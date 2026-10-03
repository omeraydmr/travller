import CloudKit
import SwiftUI
import StublyKit

/// İlk açılış: uygulamanın tanıtımı, profil ("hesap") oluşturma, kısa anket ve iCloud bağlantısı.
///
/// Ayrı bir kullanıcı adı/şifre yoktur: hesap, bu cihazdaki profil ile cihazın iCloud kimliğidir.
/// Ekip paylaşımı ve eşitleme iCloud üzerinden yürür.
struct OnboardingView: View {
    @Environment(TripStore.self) private var store
    /// Bitince ilk seyahati planlamak istendiyse true.
    let onFinish: (_ planFirstTrip: Bool) -> Void

    enum Step: Int, CaseIterable {
        case welcome, profile, survey, cloud, done
    }

    @State private var step: Step = .welcome
    @State private var profile: Member
    @State private var name: String
    @State private var hasPassport: Bool
    @State private var preferences: TravelPreferences
    @State private var cloudStatus: CloudStatus = .checking
    @State private var cloudUserID: String?
    @FocusState private var isNameFocused: Bool

    enum CloudStatus: Equatable {
        case checking, available, noAccount, restricted, unknown
    }

    init(store: TripStore, onFinish: @escaping (_ planFirstTrip: Bool) -> Void) {
        self.onFinish = onFinish
        let me = store.me
        _profile = State(initialValue: me)
        _name = State(initialValue: ProfileDraft.validName(me.name) ?? "")
        _hasPassport = State(initialValue: me.passport != nil)
        _preferences = State(initialValue: store.preferences)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                Group {
                    switch step {
                    case .welcome: welcome
                    case .profile: profileStep
                    case .survey: survey
                    case .cloud: cloud
                    case .done: done
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .id(step)
            }
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .background(TintGlow(tint: Accent.blue.base, offsetY: -260))
        .task { await checkCloud() }
        .interactiveDismissDisabled()
    }

    // MARK: Çerçeve

    private var header: some View {
        HStack(spacing: 12) {
            if step != .welcome && step != .done {
                Button {
                    go(Step(rawValue: step.rawValue - 1) ?? .welcome)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.circleIcon(size: 40))
                .accessibilityLabel("Geri")
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Color.ink : Color.ink3.opacity(0.4))
                        .frame(width: item == step ? 22 : 7, height: 7)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Adım \(step.rawValue + 1) / \(Step.allCases.count)")
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            switch step {
            case .welcome:
                Button("Başlayalım") { go(.profile) }.buttonStyle(.primary)
            case .profile:
                Button("Devam") { saveProfileDraft(); go(.survey) }
                    .buttonStyle(.primary)
                    .disabled(ProfileDraft.validName(name) == nil)
                    .opacity(ProfileDraft.validName(name) == nil ? 0.5 : 1)
            case .survey:
                Button("Devam") { go(.cloud) }.buttonStyle(.primary)
                Button("Şimdilik geç") {
                    preferences = TravelPreferences()
                    go(.cloud)
                }
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink2)
            case .cloud:
                Button("Devam") { finishSetup(); go(.done) }.buttonStyle(.primary)
            case .done:
                Button("İlk seyahatimi planla") { onFinish(true) }.buttonStyle(.primary)
                Button("Sonra") { onFinish(false) }
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func go(_ next: Step) {
        isNameFocused = false
        withAnimation(.spring(duration: 0.4)) { step = next }
    }

    // MARK: 1 · Tanıtım

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Accent.blue.base)
                .frame(width: 72, height: 72)
                .background(Accent.blue.tint, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text("Stubly'ye hoş geldin").font(.tDisplay).foregroundStyle(Color.ink)
                Text("Seyahatin öncesi, sırası ve sonrası — ekibinle, tek yerde.")
                    .font(.tBody)
                    .foregroundStyle(Color.ink2)
            }
            VStack(spacing: 12) {
                featureRow("map.fill", .green, String(localized: "Plan ve harita"),
                           String(localized: "Günlere durak ekle; rota açılış saatlerine ve en kısa yürüyüşe göre dizilsin, harita internetsiz de açılsın."))
                featureRow("airplane", .blue, String(localized: "Uçuş ve konaklama"),
                           String(localized: "Uçuşu elle yaz ya da e-bilet, ekran görüntüsü veya Wallet kartından içe aktar."))
                featureRow("chart.pie.fill", .orange, String(localized: "Bütçe ve hesaplaşma"),
                           String(localized: "Masrafları böl, makbuzu okut; kimin kime ne borçlu olduğu tek dokunuşta."))
                featureRow("person.text.rectangle.fill", .purple, String(localized: "Vize ve belgeler"),
                           String(localized: "Pasaportuna göre vize durumu, Schengen 90/180 sayacı, belge kasası."))
                featureRow("person.2.fill", .green, String(localized: "Ekip"),
                           String(localized: "Seyahati iCloud ile paylaş; herkes aynı planı anında görsün."))
            }
        }
    }

    private func featureRow(_ symbol: String, _ accent: Accent, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent.base)
                .frame(width: 40, height: 40)
                .background(accent.tint, in: RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.tBodyStrong).foregroundStyle(Color.ink)
                Text(text).font(.tBody).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 2 · Profil

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle(String(localized: "Profilini oluştur"),
                      String(localized: "Ekibin seni bu adla görür. Ayrı bir şifre yok: hesabın bu profil ve cihazının iCloud'u."))

            HStack(spacing: 16) {
                AvatarView(member: previewMember, size: 64)
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Adın", text: $name)
                        .font(.tTitle)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .focused($isNameFocused)
                    Rectangle().fill(Color.ink3.opacity(0.4)).frame(height: 1)
                }
            }
            .tray(padding: 16)

            VStack(alignment: .leading, spacing: 10) {
                Text("Renk").font(.tCaption).foregroundStyle(Color.ink2)
                HStack(spacing: 12) {
                    ForEach(0..<6, id: \.self) { index in
                        Button {
                            profile.colorIndex = index
                        } label: {
                            AvatarView(member: Member(name: name.isEmpty ? "?" : name, colorIndex: index), size: 40)
                                .overlay(Circle().strokeBorder(Color.ink, lineWidth: profile.colorIndex == index ? 3 : 0).padding(-4))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Renk \(index + 1)")
                        .accessibilityAddTraits(profile.colorIndex == index ? .isSelected : [])
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $hasPassport) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("T.C. pasaportum var").font(.tBodyStrong).foregroundStyle(Color.ink)
                        Text("Vize durumunu ve pasaport geçerliliğini senin için kontrol ederiz.")
                            .font(.caption).foregroundStyle(Color.ink2)
                    }
                }
                if hasPassport {
                    Picker("Pasaport türü", selection: Binding(
                        get: { profile.passport?.type ?? .ordinary },
                        set: { type in
                            var passport = profile.passport ?? Passport(expiresOn: Self.defaultExpiry)
                            passport.type = type
                            profile.passport = passport
                        })) {
                        ForEach(PassportType.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    DatePicker("Geçerlilik bitişi", selection: Binding(
                        get: { profile.passport?.expiresOn ?? Self.defaultExpiry },
                        set: { date in
                            var passport = profile.passport ?? Passport(expiresOn: date)
                            passport.expiresOn = date
                            profile.passport = passport
                        }), displayedComponents: .date)
                }
            }
            .tray(padding: 16)

            Text("Pasaport bilgisi ve IBAN yalnızca senin cihazında ve paylaştığın seyahatlerde durur; sonra Profil'den değiştirebilirsin.")
                .font(.caption)
                .foregroundStyle(Color.ink3)
        }
        .onAppear { if name.isEmpty { isNameFocused = true } }
    }

    private static var defaultExpiry: Date { Calendar.current.date(byAdding: .year, value: 5, to: .now) ?? .now }

    private var previewMember: Member {
        var member = profile
        member.name = name.isEmpty ? "?" : name
        return member
    }

    private func saveProfileDraft() {
        profile.name = ProfileDraft.validName(name) ?? profile.name
        if hasPassport {
            if profile.passport == nil { profile.passport = Passport(expiresOn: Self.defaultExpiry) }
        } else {
            profile.passport = nil
        }
    }

    // MARK: 3 · Anket

    private var survey: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepTitle(String(localized: "Nasıl seyahat ediyorsun?"), String(localized: "Üç kısa soru; uygulamayı sana göre açarız. Cevaplar cihazında kalır."))

            question(String(localized: "Genelde kiminle?")) {
                chips(TravelPreferences.Companion.allCases, selected: { preferences.companion == $0 }, title: companionTitle) {
                    preferences.companion = preferences.companion == $0 ? nil : $0
                }
            }
            question(String(localized: "Yılda kaç kez yurt dışına çıkıyorsun?")) {
                chips(TravelPreferences.Frequency.allCases, selected: { preferences.frequency == $0 }, title: frequencyTitle) {
                    preferences.frequency = preferences.frequency == $0 ? nil : $0
                }
            }
            question(String(localized: "En çok neyde yardım istersin?"), note: String(localized: "Birden fazla seçebilirsin; ilk seçtiğin, seyahat açılınca ilk gelir.")) {
                chips(TravelPreferences.Interest.allCases, selected: { preferences.interests.contains($0) }, title: interestTitle) {
                    preferences.toggle($0)
                }
            }
        }
    }

    private func question<Content: View>(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.tBodyStrong).foregroundStyle(Color.ink)
            if let note { Text(note).font(.caption).foregroundStyle(Color.ink3) }
            content()
        }
    }

    private func chips<Item: Hashable>(_ items: [Item], selected: @escaping (Item) -> Bool, title: @escaping (Item) -> String,
                                       action: @escaping (Item) -> Void) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                let isOn = selected(item)
                Button {
                    withAnimation(.spring(duration: 0.25)) { action(item) }
                } label: {
                    Text(title(item))
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(isOn ? Color.onInk : Color.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isOn ? Color.ink : Color.tray, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private func companionTitle(_ value: TravelPreferences.Companion) -> String {
        switch value {
        case .solo: String(localized: "Yalnız")
        case .partner: "Partnerimle"
        case .friends: String(localized: "Arkadaşlarla")
        case .family: "Ailemle"
        }
    }

    private func frequencyTitle(_ value: TravelPreferences.Frequency) -> String {
        switch value {
        case .once: "1 kez ya da daha az"
        case .fewTimes: "2–3 kez"
        case .often: String(localized: "4 ve üzeri")
        }
    }

    private func interestTitle(_ value: TravelPreferences.Interest) -> String {
        switch value {
        case .planning: "Rota ve plan"
        case .money: String(localized: "Bütçe ve masraf")
        case .visa: String(localized: "Vize ve belgeler")
        case .packing: String(localized: "Valiz")
        case .memories: String(localized: "Anılar")
        }
    }

    // MARK: 4 · iCloud

    private var cloud: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle(String(localized: "iCloud ile bağlan"), String(localized: "Seyahatlerin cihazların arasında eşitlenir ve ekibini davet edebilirsin. Veriler Apple'ın iCloud'unda, senin hesabında durur; ayrı bir sunucumuz yok."))

            HStack(spacing: 14) {
                Image(systemName: cloudSymbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(cloudStatus == .available ? Accent.green.base : Color.food)
                    .frame(width: 44, height: 44)
                    .background((cloudStatus == .available ? Accent.green.tint : Accent.orange.tint), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(cloudTitle).font(.tBodyStrong).foregroundStyle(Color.ink)
                    Text(cloudDetail).font(.caption).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if cloudStatus == .checking { ProgressView() }
            }
            .tray(padding: 16)

            if cloudStatus == .noAccount || cloudStatus == .unknown {
                Button {
                    Task { await checkCloud() }
                } label: {
                    Label("Tekrar kontrol et", systemImage: "arrow.clockwise")
                }
                .font(.tBodyStrong)
                .foregroundStyle(Color.ink)
            }

            notificationsRow
        }
    }

    private var notificationsRow: some View {
        let scheduler = NotificationScheduler.shared
        return Toggle(isOn: Binding(get: { scheduler.isEnabled }, set: { value in
            Task { await scheduler.setEnabled(value) }
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hatırlatmalar").font(.tBodyStrong).foregroundStyle(Color.ink)
                Text(scheduler.authorizationDenied
                     ? String(localized: "Bildirim izni kapalı; Ayarlar > Stubly'den açabilirsin.")
                     : String(localized: "Valiz, uçuş, günün planı ve ekipten gelen değişiklikler."))
                    .font(.caption)
                    .foregroundStyle(Color.ink2)
            }
        }
        .tray(padding: 16)
    }

    private var cloudSymbol: String {
        switch cloudStatus {
        case .available: "checkmark.icloud.fill"
        case .checking: "icloud"
        default: "exclamationmark.icloud.fill"
        }
    }

    private var cloudTitle: String {
        switch cloudStatus {
        case .checking: "iCloud kontrol ediliyor…"
        case .available: String(localized: "iCloud bağlı")
        case .noAccount: String(localized: "iCloud'a giriş yapılmamış")
        case .restricted: String(localized: "iCloud bu cihazda kısıtlı")
        case .unknown: String(localized: "iCloud'a ulaşılamadı")
        }
    }

    private var cloudDetail: String {
        switch cloudStatus {
        case .checking: "Bir saniye."
        case .available: String(localized: "Hesabın bu iCloud kimliğine bağlandı; seyahatlerin eşitlenecek ve paylaşabileceksin.")
        case .noAccount: String(localized: "Ayarlar > [adın] > iCloud'dan giriş yap. O zamana kadar uygulama yalnızca bu cihazda çalışır.")
        case .restricted: String(localized: "Ekran Süresi ya da kurum ayarları iCloud'u kısıtlıyor; uygulama yalnızca bu cihazda çalışır.")
        case .unknown: String(localized: "İnternet bağlantını kontrol edip tekrar dene; uygulama bu sırada yerel çalışır.")
        }
    }

    private func checkCloud() async {
        cloudStatus = .checking
        do {
            switch try await CloudConfig.container.accountStatus() {
            case .available:
                cloudStatus = .available
                cloudUserID = try? await CloudConfig.container.userRecordID().recordName
            case .noAccount: cloudStatus = .noAccount
            case .restricted: cloudStatus = .restricted
            default: cloudStatus = .unknown
            }
        } catch {
            cloudStatus = .unknown
        }
    }

    private func finishSetup() {
        store.completeOnboarding(profile: profile, preferences: preferences, cloudUserID: cloudUserID)
        // Açılışta iCloud yoktu ama şimdi bağlandıysa eşitlemeyi başlat.
        if cloudStatus == .available && !CloudSync.shared.isAvailable {
            Task { await CloudSync.shared.start(with: store) }
        }
    }

    // MARK: 5 · Hazır

    private var done: some View {
        VStack(alignment: .leading, spacing: 20) {
            AvatarView(member: store.me, size: 72)
            stepTitle(String(localized: "Hazırsın, \(store.me.name)!"),
                      cloudStatus == .available
                        ? String(localized: "Profilin iCloud hesabına bağlandı. İlk seyahatini planla ya da bir arkadaşının davetini aç.")
                        : String(localized: "Profilin bu cihazda hazır. iCloud'a giriş yapınca seyahatlerin kendiliğinden eşitlenmeye başlar."))
            VStack(alignment: .leading, spacing: 10) {
                tip("hand.tap.fill", String(localized: "Bir seyahat kartına dokun; plan, bütçe, valiz ve vize sekmeleri açılır."))
                tip("person.crop.circle", String(localized: "Sağ üstteki avatarından profiline, pasaportuna ve gezdiğin ülkelere ulaşırsın."))
                tip("square.and.arrow.up", String(localized: "Ekip sekmesinden seyahati iCloud ile paylaşıp arkadaşlarını davet et."))
            }
            .tray(padding: 16)
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Color.ink2).frame(width: 22)
            Text(text).font(.tBody).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.tHeadline).foregroundStyle(Color.ink)
            Text(subtitle).font(.tBody).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }
}
