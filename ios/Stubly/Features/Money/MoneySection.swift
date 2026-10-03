import SwiftUI
import StublyKit

struct MoneySection: View {
    @Environment(TripStore.self) private var store
    let trip: Trip

    @State private var isAddingExpense = false
    @State private var isEditingBudget = false
    @State private var pendingTransfer: Transfer?
    @State private var viewingReceipt: Expense?
    @State private var editingExpense: Expense?

    private var summary: BudgetSummary { Budget.summary(for: trip) }
    private var transfers: [Transfer] { Settlement.transfers(for: trip) }

    var body: some View {
        let breakdown = Budget.currencyBreakdown(for: trip)
        VStack(spacing: 16) {
            budgetCard
            if breakdown.count > 1 {
                CurrencyBreakdownCard(trip: trip, totals: breakdown)
            }
            balancesCard
            expensesCard
            TaxFreeCard(trip: trip)
        }
        .sheet(isPresented: $isAddingExpense) {
            AddExpenseSheet(trip: trip)
        }
        .sheet(isPresented: $isEditingBudget) {
            EditBudgetSheet(trip: trip)
        }
        .sheet(item: $viewingReceipt) { expense in
            ReceiptViewer(trip: trip, expense: expense)
        }
        .sheet(item: $editingExpense) { expense in
            AddExpenseSheet(trip: trip, editing: expense)
        }
        .confirmationDialog("Ödeme yapıldı mı?", isPresented: Binding(
            get: { pendingTransfer != nil }, set: { if !$0 { pendingTransfer = nil } }
        ), presenting: pendingTransfer) { transfer in
            Button("Ödendi olarak işaretle") { settle(transfer) }
            if let recipient = trip.member(transfer.to), let iban = recipient.iban, IBAN.isValid(iban) {
                Button("IBAN'ı kopyala · \(recipient.name)") {
                    UIPasteboard.general.string = IBAN.normalized(iban)
                }
            }
        } message: { transfer in
            Text("\(name(transfer.from)) → \(name(transfer.to)) · \(money(transfer.amount))")
        }
    }

    // MARK: Budget

    private var budgetCard: some View {
        let summary = self.summary
        return ModuleCard(String(localized: "Bütçe"), symbol: "chart.pie.fill", accessory: {
            Button("Düzenle") { isEditingBudget = true }
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(Color.ink2)
        }) {
            HStack(spacing: 18) {
                DonutChart(slices: summary.categories.map {
                    DonutSlice(id: $0.category.rawValue, value: Double($0.spent), color: $0.category.accent.base)
                }, total: Double(summary.limit), lineWidth: 14) {
                    VStack(spacing: 0) {
                        Text(summary.limit > 0 ? "%\(percent(summary))" : "—")
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(Color.ink)
                        Text("harcandı")
                            .font(.caption2)
                            .foregroundStyle(Color.ink3)
                    }
                }
                .frame(width: 112, height: 112)

                VStack(alignment: .leading, spacing: 6) {
                    Text(money(summary.spent))
                        .font(.tAmount)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if summary.limit > 0 {
                        Text("/ \(money(summary.limit)) · kalan \(money(max(0, summary.limit - summary.spent)))")
                            .font(.tBody)
                            .foregroundStyle(Color.ink3)
                    }
                    let pace = paceChip(summary.pace)
                    StatChip(symbol: pace.symbol, text: pace.text, accent: pace.accent)
                }
                Spacer(minLength: 0)
            }

            if summary.categories.isEmpty {
                EmptyHint(symbol: "chart.bar", text: String(localized: "Kategori limitleri belirle, harcamalar burada dolsun."))
                    .tray()
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(summary.categories, id: \.category) { item in
                        CategoryTile(item: item, currency: trip.currency)
                    }
                }
            }
        }
    }

    private func percent(_ summary: BudgetSummary) -> Int {
        guard summary.limit > 0 else { return 0 }
        return Int((Double(summary.spent) / Double(summary.limit) * 100).rounded())
    }

    private func paceChip(_ pace: BudgetPace) -> (text: String, symbol: String, accent: Accent) {
        switch pace {
        case .notStarted: (String(localized: "Ön harcamalar"), "clock", .gray)
        case let .under(day, total): (String(localized: "Gün \(day)/\(total) · tempo gerisinde"), "tortoise.fill", .green)
        case let .onTrack(day, total): (String(localized: "Gün \(day)/\(total) · tam temposunda"), "checkmark", .blue)
        case let .ahead(day, total): (String(localized: "Gün \(day)/\(total) · biraz önde"), "hare.fill", .orange)
        case .finished: (String(localized: "Seyahat tamamlandı"), "flag.checkered", .gray)
        }
    }

    // MARK: Balances

    private var balancesCard: some View {
        // Borç sadeleştirme bir kez hesaplanır; başlık, liste ve "hesabı kapalı" satırı aynı sonucu kullanır.
        let transfers = self.transfers
        let settled = settledMembers(transfers)
        return ModuleCard(String(localized: "Bakiyeler"), symbol: "wallet.pass.fill") {
            StoryHeadline(text: balancesHeadline(transfers))

            if !transfers.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(transfers.enumerated()), id: \.offset) { _, transfer in
                        TransferTicket(trip: trip, transfer: transfer) { pendingTransfer = transfer }
                    }
                }
            }

            if !transfers.isEmpty {
                ShareLink(item: settlementSummary(transfers)) {
                    Label("Özeti paylaş", systemImage: "square.and.arrow.up")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.ink2)
                }
            }

            if !settled.isEmpty {
                HStack(spacing: 10) {
                    AvatarStack(members: settled, size: 28, limit: 5)
                    Text(transfers.isEmpty ? String(localized: "Herkesin hesabı kapalı") : String(localized: "Hesabı kapalı"))
                        .font(.tBody)
                        .foregroundStyle(Color.ink2)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.success)
                }
                .tray(padding: 14)
            }

            Button {
                isAddingExpense = true
            } label: {
                Label("Masraf ekle", systemImage: "plus")
            }
            .buttonStyle(.primary)
        }
    }

    /// Mesajlaşma uygulamalarına gönderilecek düz metin hesaplaşma özeti.
    private func settlementSummary(_ transfers: [Transfer]) -> String {
        var lines = [String(localized: "\(trip.name) · hesaplaşma")]
        for transfer in transfers {
            var line = "• \(name(transfer.from)) → \(name(transfer.to)): \(money(transfer.amount))"
            if let iban = trip.member(transfer.to)?.iban, IBAN.isValid(iban) {
                line += " (IBAN: \(IBAN.formatted(iban)))"
            }
            lines.append(line)
        }
        let total = trip.expenses.filter { !$0.isTransfer }.reduce(0) { $0 + $1.amount }
        lines.append(String(localized: "Toplam harcama: \(money(total))"))
        return lines.joined(separator: "\n")
    }

    private func settledMembers(_ transfers: [Transfer]) -> [Member] {
        let involved = Set(transfers.flatMap { [$0.from, $0.to] })
        return trip.members.filter { !involved.contains($0.id) }
    }

    private func balancesHeadline(_ transfers: [Transfer]) -> String {
        switch transfers.count {
        case 0: String(localized: "Herkes dengede.")
        case 1: String(localized: "Tek transfer tüm seyahati kapatıyor.")
        default: String(localized: "\(Self.numberWord(transfers.count)) transfer tüm seyahati kapatıyor.")
        }
    }

    private static func numberWord(_ n: Int) -> String {
        let words = [String(localized: "Sıfır"), String(localized: "Bir"), String(localized: "İki"), String(localized: "Üç"), String(localized: "Dört"), String(localized: "Beş"), String(localized: "Altı"), String(localized: "Yedi"), String(localized: "Sekiz"), String(localized: "Dokuz"), String(localized: "On")]
        return n < words.count ? words[n] : "\(n)"
    }

    // MARK: Expenses

    private var expensesCard: some View {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: trip.expenses) { calendar.startOfDay(for: $0.date) }
            .map { ExpenseDay(date: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
        return ModuleCard(String(localized: "Harcamalar"), symbol: "list.bullet.rectangle.fill") {
            if groups.isEmpty {
                EmptyHint(symbol: "creditcard", text: String(localized: "Henüz harcama yok.")).tray()
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groups) { group in
                        let items = group.items
                        let dayTotal = items.filter { !$0.isTransfer }.reduce(0) { $0 + $1.amount }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(AppFormat.shortDate(group.date)).font(.tCaption).foregroundStyle(Color.ink3)
                                Spacer()
                                if dayTotal > 0 {
                                    Text(money(dayTotal)).font(.tCaption).foregroundStyle(Color.ink3)
                                }
                            }
                            .padding(.horizontal, 4)
                            VStack(spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, expense in
                                    if index > 0 { Divider().overlay(Color.line) }
                                    ExpenseRow(trip: trip, expense: expense)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if !expense.isTransfer { editingExpense = expense }
                                        }
                                        .contextMenu {
                                            if !expense.isTransfer {
                                                Button("Düzenle", systemImage: "pencil") { editingExpense = expense }
                                            }
                                            if expense.receiptPhoto != nil {
                                                Button("Makbuzu göster", systemImage: "doc.text.image") {
                                                    viewingReceipt = expense
                                                }
                                            }
                                            Button("Sil", systemImage: "trash", role: .destructive) {
                                                if let receipt = expense.receiptPhoto {
                                                    CoverImageStore.receipts.delete(named: receipt)
                                                }
                                                store.update(trip.id) { $0.expenses.removeAll { $0.id == expense.id } }
                                            }
                                        }
                                }
                            }
                            .tray(padding: 14)
                        }
                    }
                }
            }
        }
    }

    private struct ExpenseDay: Identifiable {
        let date: Date
        let items: [Expense]
        var id: Date { date }
    }

    // MARK: Helpers

    private func settle(_ transfer: Transfer) {
        let payment = Expense(title: String(localized: "Hesaplaşma"), amount: transfer.amount, category: .other, paidBy: transfer.from,
                              splitAmong: [transfer.to], date: .now, isTransfer: true)
        store.update(trip.id) { $0.expenses.append(payment) }
    }

    private func money(_ minor: Int) -> String { AppFormat.money(minor, trip.currency) }
    private func name(_ id: UUID) -> String { trip.member(id)?.name ?? "?" }
}

// MARK: - Rows

/// 2x2 ızgaradaki kategori kutucuğu.
struct CategoryTile: View {
    let item: CategorySpend
    let currency: String

    var body: some View {
        let accent = item.category.accent
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: item.category.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent.base)
                    .frame(width: 26, height: 26)
                    .background(accent.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(item.category.title)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(AppFormat.money(item.spent, currency))
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(item.isOver ? Color.food : accent.base)
                Text(item.limit > 0 ? "/ \(AppFormat.money(item.limit, currency))" : String(localized: "limit yok"))
                    .font(.caption)
                    .foregroundStyle(Color.ink3)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            HatchedBar(progress: item.progress, color: accent.base, height: 8)
        }
        .padding(14)
        .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Bir borç transferi, yanlarında çentik olan küçük bir bilet olarak.
struct TransferTicket: View {
    let trip: Trip
    let transfer: Transfer
    let onSettle: () -> Void

    private static let height: CGFloat = 96

    var body: some View {
        Button(action: onSettle) {
            HStack(spacing: 10) {
                person(transfer.from, caption: String(localized: "öder"))
                ZStack {
                    TransferArc()
                        .stroke(Color.ink3, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 4]))
                        .frame(height: 30)
                        .offset(y: -10)
                    Text(AppFormat.money(transfer.amount, trip.currency))
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(Color.food)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.foodTint, in: Capsule())
                        .offset(y: 10)
                }
                .frame(maxWidth: .infinity)
                person(transfer.to, caption: String(localized: "alır"), trailing: true)
            }
            .padding(.horizontal, 22)
            .frame(height: Self.height)
            .background(Color.tray)
            .clipShape(SideNotchedShape())
            .background { SideNotchedShape().fill(Color.tray).softShadow() }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ödendi olarak işaretle")
    }

    private func person(_ id: UUID, caption: String, trailing: Bool = false) -> some View {
        VStack(spacing: 4) {
            if let member = trip.member(id) {
                AvatarView(member: member, size: 38)
                Text(member.name).font(.system(.subheadline, weight: .semibold)).foregroundStyle(Color.ink).lineLimit(1)
            }
            Text(caption).font(.caption2).foregroundStyle(Color.ink3)
        }
        .frame(width: 64)
    }
}

/// Soldan sağa uçan kesikli yay.
struct TransferArc: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.4))
        }
    }
}

/// Yan kenarlarının ortasında çentik olan kart.
struct SideNotchedShape: Shape {
    var notchRadius: CGFloat = 10
    var cornerRadius: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        let body = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        var notches = Path()
        for x in [rect.minX, rect.maxX] {
            notches.addEllipse(in: CGRect(x: x - notchRadius, y: rect.midY - notchRadius,
                                          width: notchRadius * 2, height: notchRadius * 2))
        }
        return body.subtracting(notches)
    }
}

struct ExpenseRow: View {
    let trip: Trip
    let expense: Expense

    var body: some View {
        let accent = expense.isTransfer ? Accent.gray : expense.category.accent
        HStack(spacing: 12) {
            Image(systemName: expense.isTransfer ? "arrow.left.arrow.right" : expense.category.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent.base)
                .frame(width: 36, height: 36)
                .background(accent.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.tBodyStrong).foregroundStyle(Color.ink).lineLimit(1)
                Text(subtitle).font(.tBody).foregroundStyle(Color.ink2).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    if expense.receiptPhoto != nil {
                        Image(systemName: "paperclip")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.ink3)
                    }
                    Text(AppFormat.money(expense.amount, trip.currency))
                        .font(.tBodyStrong)
                        .foregroundStyle(expense.isTransfer ? Color.ink2 : Color.ink)
                }
                if let original = expense.originalAmount, let code = expense.originalCurrency {
                    Text(AppFormat.money(original, code))
                        .font(.caption)
                        .foregroundStyle(Color.ink3)
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        guard expense.isTransfer else { return expense.title }
        let to = expense.splitAmong.first.flatMap { trip.member($0)?.name } ?? "?"
        return "\(trip.member(expense.paidBy)?.name ?? "?") → \(to)"
    }

    private var subtitle: String {
        let payer = trip.member(expense.paidBy)?.name ?? "?"
        if expense.isTransfer { return String(localized: "Hesaplaşma · \(AppFormat.shortDate(expense.date))") }
        let split = expense.shares == nil ? String(localized: "\(expense.splitAmong.count) kişi") : String(localized: "kalem kalem")
        return String(localized: "\(payer) ödedi · \(split) · \(AppFormat.shortDate(expense.date))")
    }
}

/// Makbuz fotoğrafını tam ekran gösterir; iki parmakla yakınlaştırılabilir.
struct ReceiptViewer: View {
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let expense: Expense
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            Group {
                if let name = expense.receiptPhoto, let image = CoverImageStore.receipts.image(named: name) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(MagnifyGesture().onChanged { scale = max(1, min(4, $0.magnification)) }
                            .onEnded { _ in withAnimation(.spring(duration: 0.3)) { scale = 1 } })
                        .padding()
                } else {
                    ContentUnavailableView("Makbuz bulunamadı", systemImage: "doc.text.image")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.canvas)
            .navigationTitle(expense.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(expense.title).font(.headline)
                        Text(AppFormat.money(expense.amount, trip.currency)).font(.caption).foregroundStyle(Color.ink2)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tamam") { dismiss() }
                }
            }
        }
    }
}

/// Harcamaların para birimine göre dağılımı: hangi parayla ne kadar harcandı, seyahat parasında karşılığı.
struct CurrencyBreakdownCard: View {
    let trip: Trip
    /// Üst görünümde zaten hesaplanmış dağılım.
    let totals: [CurrencyTotal]

    var body: some View {
        let sum = max(totals.reduce(0) { $0 + $1.convertedTotal }, 1)
        ModuleCard(String(localized: "Para birimleri"), symbol: "dollarsign.arrow.circlepath") {
            StoryHeadline(text: headline(totals, sum: sum))

            GeometryReader { proxy in
                HStack(spacing: 4) {
                    ForEach(Array(totals.enumerated()), id: \.element.currency) { index, total in
                        Capsule()
                            .fill(Accent.cycle(index).base)
                            .frame(width: max(8, (proxy.size.width - CGFloat(totals.count - 1) * 4)
                                * CGFloat(total.convertedTotal) / CGFloat(sum)))
                    }
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                ForEach(Array(totals.enumerated()), id: \.element.currency) { index, total in
                    if index > 0 { Divider().overlay(Color.line) }
                    HStack(spacing: 12) {
                        Text(AppFormat.currencySymbol(total.currency))
                            .font(.system(.headline, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Accent.cycle(index).base, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppFormat.money(total.originalTotal, total.currency))
                                .font(.tBodyStrong)
                                .foregroundStyle(Color.ink)
                            Text("\(total.currency) · \(total.count) harcama")
                                .font(.caption)
                                .foregroundStyle(Color.ink3)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            if total.currency != trip.currency {
                                Text("≈ \(AppFormat.money(total.convertedTotal, trip.currency))")
                                    .font(.tBodyStrong)
                                    .foregroundStyle(Color.ink)
                            }
                            Text("%\(Int((Double(total.convertedTotal) / Double(sum) * 100).rounded()))")
                                .font(.caption)
                                .foregroundStyle(Color.ink3)
                        }
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
            .tray(padding: 14)
        }
    }

    private func headline(_ totals: [CurrencyTotal], sum: Int) -> String {
        let foreign = totals.filter { $0.currency != trip.currency }
        let share = Int((Double(foreign.reduce(0) { $0 + $1.convertedTotal }) / Double(sum) * 100).rounded())
        let names = foreign.map(\.currency).joined(separator: ", ")
        return String(localized: "Harcamaların %\(share) kadarı \(names) ile yapıldı.")
    }
}
