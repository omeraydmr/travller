import SwiftUI
import StublyKit

/// Schengen 90/180 hesaplayıcı: dönüş günü itibarıyla son 180 günde kaç gün kullanıldığı,
/// 180 günlük şerit, sayılan ziyaretler ve elle geçmiş ziyaret ekleme.
struct SchengenCard: View {
    let member: Member
    let trip: Trip
    @Environment(TripStore.self) private var store
    @Environment(\.tripTint) private var tint
    @State private var isAdding = false

    /// Çok ülkeli seyahatte yalnızca Schengen'de geçen günler.
    private var range: (start: Date, end: Date) { trip.schengenRange() ?? (trip.startDate, trip.endDate) }

    var body: some View {
        let others = store.schengenStays(for: member.id, excluding: trip.id)
        let current = Schengen.Stay(id: trip.id, start: range.start, end: range.end, label: trip.name)
        let evaluation = Schengen.evaluate(current, others: others)
        let window = Schengen.stays(others, inWindowEnding: range.end)
        let manualIDs = Set((store.manualStays[member.id] ?? []).map(\.id))

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Schengen 90/180", systemImage: "calendar.badge.clock")
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink)
                Spacer()
                if evaluation.isWithinLimit {
                    Tag(text: String(localized: "\(evaluation.remainingAfterExit) gün kalır"), accent: evaluation.remainingAfterExit < 10 ? .orange : .green)
                } else {
                    Tag(text: String(localized: "Sınır aşılıyor"), accent: .orange)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(min(evaluation.usedOnExit, 999))")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(evaluation.isWithinLimit ? Color.ink : Accent.orange.base)
                    .contentTransition(.numericText())
                Text("/ \(Schengen.limit) gün")
                    .font(.system(.title3, weight: .medium))
                    .foregroundStyle(Color.ink3)
            }
            Text("Dönüş günü (\(AppFormat.shortDate(range.end))) itibarıyla son 180 günde Schengen'de geçen gün, bu seyahat dahil.")
                .font(.tBody)
                .foregroundStyle(Color.ink2)

            WindowStrip(current: current, others: others, end: range.end, tint: tint)

            if let first = evaluation.firstOverstayDay {
                overstayBox(first: first, evaluation: evaluation, others: others)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Sayılan ziyaretler").font(.tCaption).foregroundStyle(Color.ink3)
                stayRow(label: String(localized: "Bu seyahat"), stay: current, color: tint, removable: false)
                ForEach(window) { stay in
                    stayRow(label: stay.label, stay: stay, color: Color.ink2, removable: manualIDs.contains(stay.id))
                }
                if window.isEmpty {
                    Text("Son 180 günde başka Schengen ziyareti yok.")
                        .font(.footnote)
                        .foregroundStyle(Color.ink3)
                        .padding(.vertical, 4)
                }
            }

            Button {
                isAdding = true
            } label: {
                Label("Önceki ziyaret ekle", systemImage: "plus")
                    .font(.system(.subheadline, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.transport)

            VStack(alignment: .leading, spacing: 4) {
                Text("Giriş ve çıkış günleri kalış günü sayılır. Bu uygulamadaki seyahatler ve eklediğin ziyaretlerle hesaplanır; sınırda resmî kayıtlar esastır.")
                    .font(.caption)
                    .foregroundStyle(Color.ink3)
                Link("AB kısa süreli kalış hesaplayıcısı", destination: Self.officialCalculator)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Color.transport)
            }
        }
        .tray()
        .sheet(isPresented: $isAdding) {
            ManualStaySheet(memberName: member.name) { stay in
                withAnimation { store.addManualStay(stay, for: member.id) }
            }
            .presentationDetents([.medium])
        }
        .animation(.spring(duration: 0.3), value: evaluation)
    }

    static let officialCalculator = URL(string: "https://home-affairs.ec.europa.eu/policies/schengen-borders-and-visa/border-crossing_en")!

    private func overstayBox(first: Date, evaluation: Schengen.Evaluation, others: [Schengen.Stay]) -> some View {
        let length = Schengen.Stay(start: range.start, end: range.end, label: "").days()
        let suggestion = Schengen.earliestEntry(forDays: length, from: range.start, others: others)
        return VStack(alignment: .leading, spacing: 6) {
            Label("\(AppFormat.shortDate(first)) günü 90 gün dolmuş oluyor; seyahatin \(evaluation.overstayDays) günü kural dışı.",
                  systemImage: "exclamationmark.triangle.fill")
            if let exit = evaluation.latestExit {
                Text("Bu tarihlerle en geç \(AppFormat.shortDate(exit)) günü çıkmalısın.")
            } else {
                Text("Giriş günü bile sınırı aşıyor; önceki ziyaretlerin pencereden çıkmasını beklemelisin.")
            }
            if let suggestion, length <= Schengen.limit {
                Text("\(length) günlük kalış için en erken giriş: \(AppFormat.longDate(suggestion)).")
                    .fontWeight(.semibold)
            }
        }
        .font(.subheadline)
        .foregroundStyle(Color.food)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.foodTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stayRow(label: String, stay: Schengen.Stay, color: Color, removable: Bool) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.subheadline).foregroundStyle(Color.ink).lineLimit(1)
                Text(AppFormat.dateRange(stay.start, stay.end)).font(.caption).foregroundStyle(Color.ink3)
            }
            Spacer(minLength: 8)
            Text("\(stay.days()) gün")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Color.ink2)
                .monospacedDigit()
            if removable {
                Button {
                    withAnimation { store.removeManualStay(stay.id, for: member.id) }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(Color.ink3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ziyareti sil")
            }
        }
        .padding(.vertical, 6)
    }
}

/// 180 günlük pencere: her gün ince bir çubuk. Bu seyahat seyahat renginde, diğer ziyaretler koyu,
/// 90 günü aşan günler turuncu.
private struct WindowStrip: View {
    let current: Schengen.Stay
    let others: [Schengen.Stay]
    let end: Date
    let tint: Color

    var body: some View {
        let calendar = Calendar.current
        let last = calendar.startOfDay(for: end)
        let first = calendar.date(byAdding: .day, value: -(Schengen.window - 1), to: last) ?? last
        let currentDays = Schengen.days(of: [current])
        let otherDays = Schengen.days(of: others)
        let allDays = currentDays.union(otherDays)
        let days = (0..<Schengen.window).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        let overstay = Set(days.filter { currentDays.contains($0) && Schengen.used(on: $0, days: allDays) > Schengen.limit })

        VStack(alignment: .leading, spacing: 6) {
            Canvas { context, size in
                let step = size.width / CGFloat(days.count)
                for (index, day) in days.enumerated() {
                    let color: Color
                    if overstay.contains(day) {
                        color = Accent.orange.base
                    } else if currentDays.contains(day) {
                        color = tint
                    } else if otherDays.contains(day) {
                        color = Color.ink2
                    } else {
                        color = Color.track
                    }
                    let rect = CGRect(x: CGFloat(index) * step, y: 0, width: max(step - 0.6, 0.6), height: size.height)
                    context.fill(Path(roundedRect: rect, cornerRadius: min(step / 2, 1)), with: .color(color))
                }
            }
            .frame(height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            HStack {
                Text(AppFormat.shortDate(first))
                Spacer()
                Text("180 gün")
                Spacer()
                Text(AppFormat.shortDate(last))
            }
            .font(.caption2)
            .foregroundStyle(Color.ink3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(AppFormat.shortDate(first)) ile \(AppFormat.shortDate(last)) arası 180 günlük pencere"))
    }
}

/// Uygulamada seyahati olmayan geçmiş bir Schengen ziyaretini ekler.
private struct ManualStaySheet: View {
    let memberName: String
    let onSave: (ManualStay) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    @State private var end = Calendar.current.date(byAdding: .day, value: -25, to: .now) ?? .now
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Giriş", selection: $start, displayedComponents: .date)
                    DatePicker("Çıkış", selection: $end, in: start..., displayedComponents: .date)
                    TextField("Not (ör. Berlin, iş seyahati)", text: $note)
                } footer: {
                    Text("\(memberName) için yalnızca bu cihazda saklanır. Giriş ve çıkış günleri sayılır.")
                }
            }
            .navigationTitle("Önceki ziyaret")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") {
                        onSave(ManualStay(start: Calendar.current.startOfDay(for: start),
                                          end: Calendar.current.startOfDay(for: end),
                                          note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
                        dismiss()
                    }
                }
            }
            .onChange(of: start) { _, newValue in
                if end < newValue { end = newValue }
            }
        }
    }
}
