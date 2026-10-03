import PhotosUI
import SwiftUI
import StublyKit

struct AddExpenseSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    /// Doluysa kayıtlı harcama düzenlenir.
    var editing: Expense?

    @State private var entry = AmountEntry()
    @State private var didLoadEditing = false
    /// Düzenlenen harcamanın özel payları (kalem kalem bölünmüşse); kişiler değişirse bırakılır.
    @State private var keptShares: [UUID: Int]?
    @State private var existingReceipt: String?
    @State private var isConfirmingDelete = false
    @State private var title = ""
    @State private var category: SpendCategory = .food
    @State private var paidBy: UUID?
    @State private var splitAmong: Set<UUID> = []
    @State private var date = Date.now
    @FocusState private var isTitleFocused: Bool

    // Döviz
    @State private var inputCurrency: String?
    @State private var quote: CurrencyConverter.Quote?
    @State private var manualRate = ""
    @State private var isFetchingRate = false
    @State private var rateError: String?

    // Makbuz
    @State private var receiptImage: UIImage?
    /// 44 pt düğme için küçük kopya; tuş takımında her basışta tam boy makbuz ölçeklenmesin.
    @State private var receiptThumbnail: UIImage?
    @State private var receiptData: Data?
    @State private var isChoosingReceiptSource = false
    @State private var isShowingCamera = false
    @State private var isShowingLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var scan: ReceiptScan = .idle
    @State private var receiptItems: [ReceiptItem] = []
    @State private var itemAssignments: [Int: [UUID]]?
    @State private var isSplittingItems = false

    enum ReceiptScan: Equatable {
        case idle, reading, notFound
        /// Okunan sonuç ve uygulanmadan önceki tutar (geri almak için); `applied` false ise kullanıcı onayı bekler.
        case found(ReceiptParser.Result, previous: AmountEntry, previousCurrency: String?, applied: Bool)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                amountDisplay
                    .padding(.top, 4)

                HStack(spacing: 10) {
                    TextField("Ne için? (ör. Akşam yemeği)", text: $title)
                        .focused($isTitleFocused)
                        .submitLabel(.done)
                        .multilineTextAlignment(.center)
                        .font(.system(.body, weight: .medium))
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .cardBackground(Color.tray, in: Capsule())
                    receiptButton
                }
                .padding(.horizontal, 16)

                categoryChips

                VStack(spacing: 10) {
                    peopleRow(String(localized: "Ödeyen"), selected: { paidBy == $0 }) { paidBy = $0 }
                    peopleRow(String(localized: "Bölünecek"), selected: { splitAmong.contains($0) }) { id in
                        keptShares = nil
                        if splitAmong.contains(id) {
                            if splitAmong.count > 1 { splitAmong.remove(id) }
                        } else {
                            splitAmong.insert(id)
                        }
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 0)

                if !isTitleFocused {
                    Keypad(entry: $entry)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Button(action: save) {
                    Label("Kaydet", systemImage: "checkmark")
                }
                .buttonStyle(.primary)
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.4)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .animation(.spring(duration: 0.3), value: isTitleFocused)
            .background(TintGlow(tint: category.accent.base, offsetY: -260))
            .navigationTitle(editing == nil ? String(localized: "Masraf ekle") : String(localized: "Masrafı düzenle"))
            .confirmationDialog("Harcama silinsin mi?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Sil", role: .destructive) { deleteEditing() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 8) {
                        DatePicker("Tarih", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                        if editing != nil {
                            Button(role: .destructive) {
                                isConfirmingDelete = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Harcamayı sil")
                        }
                    }
                }
            }
            .sheet(isPresented: $isSplittingItems) {
                ItemSplitSheet(trip: trip, items: receiptItems, currency: currency,
                               initial: itemAssignments ?? Dictionary(uniqueKeysWithValues: receiptItems.map {
                                   ($0.id, trip.members.map(\.id).filter { splitAmong.contains($0) })
                               })) { assignments in
                    itemAssignments = assignments
                }
            }
            .onAppear {
                loadEditingIfNeeded()
                if paidBy == nil { paidBy = trip.members.first?.id }
                if splitAmong.isEmpty { splitAmong = Set(trip.members.map(\.id)) }
            }
        }
    }

    // MARK: Parts

    private var currency: String { inputCurrency ?? trip.currency }
    private var isForeign: Bool { currency != trip.currency }

    /// Girilen tutarın seyahat para birimindeki karşılığı (kur yoksa nil).
    private var tripAmount: Int? {
        // Düzenlemede tutar ve para birimi değişmediyse kayıtlı karşılığı aynen koru (kur yuvarlaması olmasın).
        if let editing, currency == (editing.originalCurrency ?? trip.currency),
           entry.minorUnits == (editing.originalAmount ?? editing.amount) {
            return editing.amount
        }
        guard isForeign else { return entry.minorUnits }
        guard let rate = effectiveRate else { return nil }
        return CurrencyConverter.convert(minorUnits: entry.minorUnits, rate: rate)
    }

    private var effectiveRate: Decimal? {
        let typed = manualRate.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if !typed.isEmpty, let value = Decimal(string: typed, locale: Locale(identifier: "en_US_POSIX")), value > 0 {
            return value
        }
        return quote?.rate
    }

    private var currencyOptions: [String] {
        var options = [trip.currency, "TRY", "EUR", "USD", "GBP"] + (inputCurrency.map { [$0] } ?? [])
        let locals = trip.countryCodes.compactMap { Locale(identifier: "tr_\($0)").currency?.identifier }
        options.insert(contentsOf: locals, at: 1)
        var seen = Set<String>()
        return options.filter { seen.insert($0).inserted }
    }

    private var amountDisplay: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Menu {
                    ForEach(currencyOptions, id: \.self) { code in
                        Button {
                            selectCurrency(code)
                        } label: {
                            if code == currency {
                                Label("\(code) · \(AppFormat.currencySymbol(code))", systemImage: "checkmark")
                            } else {
                                Text("\(code) · \(AppFormat.currencySymbol(code))")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(AppFormat.currencySymbol(currency))
                            .font(.system(size: 30, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(isForeign ? Color.food : Color.ink3)
                }
                .accessibilityLabel(Text("Para birimi \(currency)"))

                Text(entry.display)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(entry.isEmpty ? Color.ink3 : Color.ink)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.2), value: entry.display)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 24)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Tutar \(AppFormat.money(entry.minorUnits, currency))"))

            if isForeign {
                conversionLine
            }

            Text(shareText)
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(Color.ink2)

            scanBanner
                .animation(.spring(duration: 0.3), value: scan)

            if receiptItems.count >= 2 {
                Button {
                    isSplittingItems = true
                } label: {
                    Label(itemAssignments == nil ? String(localized: "Kalem kalem böl · \(receiptItems.count) kalem") : String(localized: "Kalem dağılımını düzenle"),
                          systemImage: "list.bullet.rectangle.portrait")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .cardBackground(Color.tray, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Receipt scan

    @ViewBuilder
    private var scanBanner: some View {
        switch scan {
        case .idle:
            EmptyView()
        case .reading:
            Label("Makbuz okunuyor…", systemImage: "text.viewfinder")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Color.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.track, in: Capsule())
        case .notFound:
            Label("Makbuzda tutar bulunamadı", systemImage: "exclamationmark.magnifyingglass")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Color.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.track, in: Capsule())
        case let .found(result, previous, previousCurrency, applied):
            let text = AppFormat.money(result.amount, result.currency ?? currency)
            HStack(spacing: 8) {
                Image(systemName: "doc.text.viewfinder")
                Text(applied ? String(localized: "Makbuzdan okundu: \(text)") : String(localized: "Makbuzdaki tutar: \(text)"))
                    .lineLimit(1)
                if !result.isConfident {
                    Text("· kontrol et").foregroundStyle(Color.food)
                }
                Button(applied ? String(localized: "Geri al") : String(localized: "Kullan")) {
                    if applied {
                        entry = previous
                        let target = previousCurrency ?? trip.currency
                        if target != currency { selectCurrency(target) }
                        scan = .found(result, previous: previous, previousCurrency: previousCurrency, applied: false)
                    } else {
                        apply(result)
                    }
                }
                .fontWeight(.bold)
            }
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(Color.success)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.staysTint, in: Capsule())
        }
    }

    private func scanReceipt(_ image: UIImage) {
        scan = .reading
        Task {
            let output = await ReceiptReader.read(image)
            receiptItems = output.items
            itemAssignments = nil
            guard let result = output.total else {
                scan = .notFound
                return
            }
            if entry.isEmpty {
                apply(result)
            } else {
                scan = .found(result, previous: entry, previousCurrency: inputCurrency, applied: false)
            }
        }
    }

    private func apply(_ result: ReceiptParser.Result) {
        let previous = entry
        let previousCurrency = inputCurrency
        withAnimation(.spring(duration: 0.3)) {
            entry = AmountEntry(minorUnits: result.amount)
        }
        if let code = result.currency, code != currency {
            selectCurrency(code)
        }
        scan = .found(result, previous: previous, previousCurrency: previousCurrency, applied: true)
    }

    @ViewBuilder
    private var conversionLine: some View {
        if isFetchingRate {
            ProgressView().controlSize(.small)
        } else if let tripAmount {
            VStack(spacing: 2) {
                Text("≈ \(AppFormat.money(tripAmount, trip.currency))")
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(Color.food)
                if let rate = effectiveRate {
                    Text(rateCaption(rate))
                        .font(.caption)
                        .foregroundStyle(Color.ink3)
                }
            }
        } else {
            HStack(spacing: 8) {
                Text("1 \(currency) =")
                TextField("kur", text: $manualRate)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 80, height: 30)
                    .background(Color.tray, in: Capsule())
                Text(trip.currency)
            }
            .font(.system(.subheadline, weight: .medium))
            .foregroundStyle(Color.ink2)
            if let rateError {
                Text(rateError).font(.caption).foregroundStyle(Color.food).multilineTextAlignment(.center)
            }
        }
    }

    private func rateCaption(_ rate: Decimal) -> String {
        let formatted = NSDecimalNumber(decimal: rate).doubleValue
            .formatted(.number.precision(.significantDigits(1...5)).locale(AppFormat.locale))
        if let quote, manualRate.isEmpty {
            return "1 \(currency) = \(formatted) \(trip.currency) · ECB \(quote.date)"
        }
        return String(localized: "1 \(currency) = \(formatted) \(trip.currency) · elle girildi")
    }

    private func selectCurrency(_ code: String) {
        inputCurrency = code
        quote = nil
        manualRate = ""
        rateError = nil
        guard code != trip.currency else { return }
        isFetchingRate = true
        Task {
            defer { isFetchingRate = false }
            do {
                quote = try await RateService.shared.quote(from: code, to: trip.currency)
            } catch {
                rateError = error.localizedDescription
            }
        }
    }

    // MARK: Receipt

    private var receiptButton: some View {
        Button {
            isChoosingReceiptSource = true
        } label: {
            Group {
                if let receiptImage {
                    Image(uiImage: receiptThumbnail ?? receiptImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.ink)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color.tray)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(receiptImage == nil ? String(localized: "Makbuz ekle") : String(localized: "Makbuzu değiştir"))
        .onChange(of: receiptImage, initial: true) { _, image in
            receiptThumbnail = image.flatMap { image in
                let scale = 132 / max(1, min(image.size.width, image.size.height))
                return image.preparingThumbnail(of: CGSize(width: image.size.width * scale, height: image.size.height * scale))
            }
        }
        .confirmationDialog("Makbuz", isPresented: $isChoosingReceiptSource, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Fotoğraf çek") { isShowingCamera = true }
            }
            Button("Galeriden seç") { isShowingLibrary = true }
            if receiptImage != nil {
                Button("Makbuzu kaldır", role: .destructive) {
                    receiptImage = nil
                    receiptData = nil
                    scan = .idle
                    receiptItems = []
                    itemAssignments = nil
                }
            }
        }
        .photosPicker(isPresented: $isShowingLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    receiptData = data
                    receiptImage = image
                    scanReceipt(image)
                }
                libraryItem = nil
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker(onCapture: { image in
                receiptImage = image
                receiptData = image.jpegData(compressionQuality: 0.85)
                scanReceipt(image)
            }, onClose: { isShowingCamera = false })
            .ignoresSafeArea()
        }
    }

    private var shareText: String {
        if itemAssignments == nil, let keptShares {
            return String(localized: "Özel paylar korunuyor · \(keptShares.filter { $0.value > 0 }.count) kişi")
        }
        if let itemAssignments {
            let people = Set(itemAssignments.values.flatMap { $0 }).count
            return String(localized: "Kalem kalem bölündü · \(people) kişi")
        }
        let count = splitAmong.count
        guard let amount = tripAmount, amount > 0, count > 0 else { return String(localized: "\(count) kişi arasında bölünecek") }
        let share = Settlement.split(amount, into: count).first ?? 0
        return count == 1 ? String(localized: "Tek kişiye ait") : String(localized: "Kişi başı \(AppFormat.money(share, trip.currency)) · \(count) kişi")
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SpendCategory.allCases, id: \.self) { item in
                    let isSelected = item == category
                    Button {
                        withAnimation(.spring(duration: 0.25)) { category = item }
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.white : item.accent.base)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(isSelected ? item.accent.base : item.accent.tint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func peopleRow(_ label: String, selected: @escaping (UUID) -> Bool,
                           toggle: @escaping (UUID) -> Void) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.tCaption)
                .foregroundStyle(Color.ink3)
                .frame(width: 72, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(trip.members) { member in
                        let isOn = selected(member.id)
                        Button {
                            withAnimation(.spring(duration: 0.2)) { toggle(member.id) }
                        } label: {
                            AvatarView(member: member, size: 38)
                                .overlay(Circle().strokeBorder(isOn ? Color.ink : .clear, lineWidth: 2.5).padding(-4))
                                .opacity(isOn ? 1 : 0.35)
                                .saturation(isOn ? 1 : 0)
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(member.name))
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var isValid: Bool {
        (tripAmount ?? 0) > 0 && paidBy != nil && !splitAmong.isEmpty
    }

    private func save() {
        guard let paidBy, let amount = tripAmount, isValid else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        // Üye sırasını koru ki artan kuruşların kime düştüğü tutarlı olsun.
        let order = trip.members.map(\.id)
        var split = order.filter { splitAmong.contains($0) }
        var shares: [UUID: Int]?
        if let itemAssignments {
            let computed = ItemSplit.shares(items: receiptItems, assignments: itemAssignments, total: amount)
            if !computed.isEmpty { shares = computed }
        } else if let keptShares {
            let scaled = ItemSplit.scale(keptShares, order: order.filter { keptShares[$0] != nil }, to: amount)
            if !scaled.isEmpty { shares = scaled }
        }
        if let shares {
            split = order.filter { (shares[$0] ?? 0) > 0 }
        }

        var receipt = existingReceipt
        if let receiptData {
            receipt = try? CoverImageStore.receipts.save(receiptData)
            if let existingReceipt { CoverImageStore.receipts.delete(named: existingReceipt) }
        } else if receiptImage == nil, let existingReceipt {
            CoverImageStore.receipts.delete(named: existingReceipt)
            receipt = nil
        }

        let expense = Expense(id: editing?.id ?? UUID(), title: trimmed.isEmpty ? category.title : trimmed, amount: amount,
                              category: category, paidBy: paidBy, splitAmong: split, date: date,
                              originalAmount: isForeign ? entry.minorUnits : nil,
                              originalCurrency: isForeign ? currency : nil,
                              receiptPhoto: receipt, shares: shares)
        store.update(trip.id) { trip in
            if let index = trip.expenses.firstIndex(where: { $0.id == expense.id }) {
                trip.expenses[index] = expense
            } else {
                trip.expenses.append(expense)
            }
        }
        dismiss()
    }

    private func loadEditingIfNeeded() {
        guard let editing, !didLoadEditing else { return }
        didLoadEditing = true
        entry = AmountEntry(minorUnits: editing.originalAmount ?? editing.amount)
        title = editing.title
        category = editing.category
        paidBy = editing.paidBy
        splitAmong = Set(editing.splitAmong)
        date = editing.date
        keptShares = editing.shares
        existingReceipt = editing.receiptPhoto
        receiptImage = editing.receiptPhoto.flatMap { CoverImageStore.receipts.image(named: $0) }
        if let code = editing.originalCurrency, let original = editing.originalAmount, original > 0 {
            inputCurrency = code
            // Kayıttaki kuru göster; kullanıcı tutarı değiştirirse aynı kurla çevrilir.
            let rate = Decimal(editing.amount) / Decimal(original)
            manualRate = NSDecimalNumber(decimal: rate).stringValue
        }
    }

    private func deleteEditing() {
        guard let editing else { return }
        if let receipt = editing.receiptPhoto { CoverImageStore.receipts.delete(named: receipt) }
        store.update(trip.id) { $0.expenses.removeAll { $0.id == editing.id } }
        dismiss()
    }
}

/// Hesap makinesi tarzı rakam tuşları.
struct Keypad: View {
    @Binding var entry: AmountEntry

    private enum Key: Hashable {
        case digit(Int), decimal, backspace
    }

    private let rows: [[Key]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.decimal, .digit(0), .backspace],
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            press(key)
                        } label: {
                            label(for: key)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(KeyPressStyle())
                    }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: entry)
    }

    @ViewBuilder
    private func label(for key: Key) -> some View {
        switch key {
        case let .digit(value):
            Text("\(value)").font(.system(size: 24, weight: .medium)).foregroundStyle(Color.ink)
        case .decimal:
            Text(",").font(.system(size: 26, weight: .semibold)).foregroundStyle(Color.ink)
                .accessibilityLabel("Virgül")
        case .backspace:
            Image(systemName: "delete.left").font(.system(size: 20, weight: .medium)).foregroundStyle(Color.ink)
                .accessibilityLabel("Sil")
        }
    }

    private func press(_ key: Key) {
        switch key {
        case let .digit(value): entry.append(digit: value)
        case .decimal: entry.appendDecimalSeparator()
        case .backspace: entry.backspace()
        }
    }
}

private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}

struct EditBudgetSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var limits: [SpendCategory: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(SpendCategory.allCases, id: \.self) { category in
                        HStack {
                            Label(category.title, systemImage: category.symbol)
                                .foregroundStyle(category.accent.base)
                            Spacer()
                            TextField("0", text: Binding(
                                get: { limits[category] ?? "" },
                                set: { limits[category] = $0 }
                            ))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            Text(trip.currency).foregroundStyle(Color.ink2)
                        }
                    }
                } footer: {
                    Text("Boş bırakılan kategoriler bütçede gösterilmez (harcama olmadıkça).")
                }
            }
            .navigationTitle("Bütçe limitleri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save)
                }
            }
            .onAppear {
                for line in trip.budget {
                    limits[line.category] = String(line.limit / 100)
                }
            }
        }
    }

    private func save() {
        let lines = SpendCategory.allCases.compactMap { category -> BudgetLine? in
            guard let text = limits[category], let minor = AppFormat.parseMinor(text), minor > 0 else { return nil }
            return BudgetLine(category: category, limit: minor)
        }
        store.update(trip.id) { $0.budget = lines }
        dismiss()
    }
}

/// Makbuz kalemlerini kişilere atar; her kalem atandığı kişiler arasında eşit bölünür.
struct ItemSplitSheet: View {
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let items: [ReceiptItem]
    let currency: String
    let onSave: ([Int: [UUID]]) -> Void
    @State private var assignments: [Int: [UUID]]

    init(trip: Trip, items: [ReceiptItem], currency: String, initial: [Int: [UUID]],
         onSave: @escaping ([Int: [UUID]]) -> Void) {
        self.trip = trip
        self.items = items
        self.currency = currency
        self.onSave = onSave
        _assignments = State(initialValue: initial)
    }

    private var totals: [UUID: Int] {
        ItemSplit.shares(items: items, assignments: assignments, total: items.reduce(0) { $0 + $1.amount })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(item.name).font(.tBodyStrong).foregroundStyle(Color.ink).lineLimit(2)
                                Spacer()
                                Text(AppFormat.money(item.amount, currency)).font(.tBodyStrong).foregroundStyle(Color.ink)
                            }
                            HStack(spacing: 8) {
                                ForEach(trip.members) { member in
                                    let isOn = assignments[item.id, default: []].contains(member.id)
                                    Button {
                                        toggle(member.id, item: item.id)
                                    } label: {
                                        AvatarView(member: member, size: 32)
                                            .overlay(Circle().strokeBorder(isOn ? Color.ink : .clear, lineWidth: 2).padding(-3))
                                            .opacity(isOn ? 1 : 0.3)
                                            .saturation(isOn ? 1 : 0)
                                            .padding(3)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text(member.name))
                                    .accessibilityAddTraits(isOn ? .isSelected : [])
                                }
                                Spacer()
                                if assignments[item.id, default: []].isEmpty {
                                    Tag(text: String(localized: "Kimse yok"), accent: .orange)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Kim ne aldı?")
                } footer: {
                    Text("Kimseye atanmayan kalemler hesaba katılmaz. Vergi, servis ve kur farkı kişilere oransal dağıtılır.")
                }

                Section("Kişi başı") {
                    ForEach(trip.members) { member in
                        if let amount = totals[member.id], amount > 0 {
                            HStack {
                                AvatarView(member: member, size: 28)
                                Text(member.name)
                                Spacer()
                                Text(AppFormat.money(amount, currency)).font(.tBodyStrong)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Kalem kalem böl")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uygula") {
                        onSave(assignments)
                        dismiss()
                    }
                    .disabled(totals.isEmpty)
                }
            }
        }
    }

    private func toggle(_ member: UUID, item: Int) {
        var people = assignments[item, default: []]
        if let index = people.firstIndex(of: member) {
            people.remove(at: index)
        } else {
            // Üye sırasını koru ki artan kuruşların dağılımı tutarlı olsun.
            people = trip.members.map(\.id).filter { people.contains($0) || $0 == member }
        }
        assignments[item] = people
    }
}
