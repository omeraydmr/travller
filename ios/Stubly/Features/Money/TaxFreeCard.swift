import SwiftUI
import StublyKit

/// Bütçe sekmesinde tax-free (KDV iadesi) takibi: form alındı → gümrükte onaylatıldı → iade geldi.
struct TaxFreeCard: View {
    @Environment(TripStore.self) private var store
    let trip: Trip
    @State private var editing: TaxRefund?
    @State private var isAdding = false

    var body: some View {
        let refunds = trip.taxRefundList
        let summary = TaxRefunds.summary(refunds)
        let available = trip.countryCodes.contains { TaxRefunds.isAvailable(in: $0) }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tax-free", systemImage: "percent")
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink)
                Spacer()
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.circleIcon(size: 32))
                .accessibilityLabel("Tax-free alışverişi ekle")
            }

            if refunds.isEmpty {
                EmptyHint(symbol: "bag", text: available
                          ? String(localized: "Mağazadan tax-free formu aldığın alışverişleri ekle; dönüşte gümrükte onaylatmayı hatırlatalım.")
                          : String(localized: "Bu ülkede turistlere KDV iadesi yapılmıyor ya da oranı listemizde yok; yine de elle ekleyebilirsin."))
            } else {
                HStack(spacing: 10) {
                    stat(String(localized: "Beklenen"), AppFormat.money(summary.expected, trip.currency), .orange)
                    stat(String(localized: "Gelen"), AppFormat.money(summary.refunded, trip.currency), .green)
                }
                if summary.toValidate > 0 {
                    Label("\(summary.toValidate) form gümrükte onaylatılmayı bekliyor. Havalimanında check-in'den önce uğra.",
                          systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Color.food)
                }
                ForEach(refunds) { refund in
                    Button {
                        editing = refund
                    } label: {
                        row(refund)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Sil", systemImage: "trash", role: .destructive) {
                            withAnimation { store.update(trip.id) { $0.taxRefunds?.removeAll { $0.id == refund.id } } }
                        }
                    }
                }
            }
        }
        .tray()
        .sheet(isPresented: $isAdding) { TaxRefundSheet(trip: trip, editing: nil) }
        .sheet(item: $editing) { refund in TaxRefundSheet(trip: trip, editing: refund) }
    }

    private func stat(_ title: String, _ value: String, _ accent: Accent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Color.ink2)
            Text(value).font(.tBodyStrong).foregroundStyle(accent.base)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accent.tint, in: RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
    }

    private func row(_ refund: TaxRefund) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(refund.shop).font(.tBodyStrong).foregroundStyle(Color.ink).lineLimit(1)
                Text("\(AppFormat.dayPill(refund.purchaseDate)) · \(AppFormat.money(refund.amount, trip.currency))")
                    .font(.caption).foregroundStyle(Color.ink2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text("+\(AppFormat.money(refund.expectedRefund, trip.currency))").font(.tBodyStrong).foregroundStyle(Color.ink)
                Tag(text: Self.statusTitle(refund.status), accent: Self.statusAccent(refund.status))
            }
        }
        .contentShape(Rectangle())
    }

    static func statusTitle(_ status: TaxRefund.Status) -> String {
        switch status {
        case .formReceived: String(localized: "Form alındı")
        case .validated: String(localized: "Onaylatıldı")
        case .refunded: String(localized: "İade geldi")
        }
    }

    static func statusAccent(_ status: TaxRefund.Status) -> Accent {
        switch status {
        case .formReceived: .orange
        case .validated: .blue
        case .refunded: .green
        }
    }
}

struct TaxRefundSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let editing: TaxRefund?

    @State private var shop: String
    @State private var date: Date
    @State private var amountText: String
    @State private var refundText: String
    @State private var refundEdited: Bool
    @State private var status: TaxRefund.Status
    @State private var note: String

    init(trip: Trip, editing: TaxRefund?) {
        self.trip = trip
        self.editing = editing
        _shop = State(initialValue: editing?.shop ?? "")
        _date = State(initialValue: editing?.purchaseDate ?? min(max(.now, trip.startDate), trip.endDate))
        _amountText = State(initialValue: editing.map { Self.text($0.amount) } ?? "")
        _refundText = State(initialValue: editing.map { Self.text($0.expectedRefund) } ?? "")
        _refundEdited = State(initialValue: editing != nil)
        _status = State(initialValue: editing?.status ?? .formReceived)
        _note = State(initialValue: editing?.note ?? "")
    }

    private static func text(_ minor: Int) -> String {
        minor % 100 == 0 ? "\(minor / 100)" : String(format: "%d,%02d", minor / 100, minor % 100)
    }

    /// Alışverişin yapıldığı ülke (çok şehirde tarihe göre).
    private var countryCode: String { trip.destination(on: date).countryCode }

    private var amount: Int? { MoneyParser.minorUnits(from: amountText) }
    private var estimate: Int? { amount.flatMap { TaxRefunds.estimatedRefund(amount: $0, countryCode: countryCode) } }
    private var refund: Int? { refundEdited ? MoneyParser.minorUnits(from: refundText) : (estimate ?? MoneyParser.minorUnits(from: refundText)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Mağaza", text: $shop)
                    DatePicker("Tarih", selection: $date, displayedComponents: .date)
                    HStack {
                        TextField("Tutar (KDV dahil)", text: $amountText).keyboardType(.decimalPad)
                        Text(trip.currency).foregroundStyle(Color.ink2)
                    }
                }
                Section {
                    HStack {
                        TextField("Beklenen iade", text: Binding(
                            get: { refundEdited ? refundText : (estimate.map(Self.text) ?? refundText) },
                            set: { refundText = $0; refundEdited = true }))
                            .keyboardType(.decimalPad)
                        Text(trip.currency).foregroundStyle(Color.ink2)
                    }
                    Picker("Durum", selection: $status) {
                        ForEach(TaxRefund.Status.allCases, id: \.self) { Text(TaxFreeCard.statusTitle($0)).tag($0) }
                    }
                    TextField("Not (ör. Global Blue, karta iade)", text: $note)
                } footer: {
                    if let rate = TaxRefunds.vatRates[countryCode.uppercased()],
                       TaxRefunds.isAvailable(in: countryCode), !refundEdited {
                        Text("Tahmin: %\(rate.formatted()) KDV'nin aracı kurum kesintisinden sonra yaklaşık %70'i. Mağazanın asgari tutarı ve kesinti değişebilir.")
                    }
                }
                if editing != nil {
                    Section {
                        Button("Sil", role: .destructive) {
                            store.update(trip.id) { $0.taxRefunds?.removeAll { $0.id == editing?.id } }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? String(localized: "Tax-free ekle") : "Tax-free")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? String(localized: "Ekle") : String(localized: "Kaydet"), action: save)
                        .disabled(shop.trimmingCharacters(in: .whitespaces).isEmpty || amount == nil)
                }
            }
        }
    }

    private func save() {
        guard let amount else { return }
        let item = TaxRefund(id: editing?.id ?? UUID(), shop: shop.trimmingCharacters(in: .whitespaces), purchaseDate: date,
                             amount: amount, expectedRefund: refund ?? 0, status: status,
                             note: note.trimmingCharacters(in: .whitespaces))
        store.update(trip.id) { trip in
            var list = trip.taxRefunds ?? []
            if let index = list.firstIndex(where: { $0.id == item.id }) { list[index] = item } else { list.append(item) }
            trip.taxRefunds = list
        }
        dismiss()
    }
}
