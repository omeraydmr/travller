import SwiftUI
import StublyKit

/// Valiz sekmesinde gidiş öncesi yapılacaklar: harç pulu, eSIM, kartlar, sigorta…
/// Öneriler seyahate göre kural tabanlı gelir; son günü gelen maddeler için sabah bildirim gider.
struct DepartureChecklistCard: View {
    @Environment(TripStore.self) private var store
    let trip: Trip
    @State private var newTitle = ""
    @State private var editing: ChecklistItem?
    @FocusState private var isAdding: Bool

    var body: some View {
        let items = DepartureChecklist.sorted(trip.checklistItems, in: trip)
        let suggestions = DepartureChecklist.suggestions(for: trip)
        let done = items.filter(\.isDone).count
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Gidiş öncesi", systemImage: "checklist")
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink)
                Spacer()
                if !items.isEmpty {
                    Text("\(done)/\(items.count)")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(done == items.count ? Color.success : Color.ink2)
                }
            }

            if items.isEmpty {
                EmptyHint(symbol: "checklist", text: String(localized: "Harç pulu, internet paketi, kartlar… Aşağıdaki önerilerden ekle."))
            }

            ForEach(items) { item in
                row(item)
                    .contextMenu {
                        Button("Düzenle", systemImage: "pencil") { editing = item }
                        Button("Sil", systemImage: "trash", role: .destructive) { remove(item) }
                    }
            }

            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Color.ink3)
                TextField("Yapılacak ekle", text: $newTitle)
                    .focused($isAdding)
                    .submitLabel(.done)
                    .onSubmit(addCustom)
            }
            .font(.tBody)

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Öneriler").font(.tCaption).foregroundStyle(Color.ink2)
                        Spacer()
                        Button("Hepsini ekle") { add(suggestions) }
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(Color.ink)
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(suggestions, id: \.key) { suggestion in
                            Button {
                                add([suggestion])
                            } label: {
                                Label(suggestion.title, systemImage: "plus")
                                    .font(.system(.footnote, weight: .medium))
                                    .foregroundStyle(Color.ink)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.track, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .tray()
        .sheet(item: $editing) { item in
            // Düzenleyici gösterilen (cihaz dilindeki) metinle açılır; metin değişmediyse kayıttaki hali korunur.
            let shown = DepartureChecklist.displayText(of: item, in: trip)
            ChecklistItemEditor(item: { var copy = item; copy.title = shown.title; copy.note = shown.note; return copy }()) { updated in
                var saved = updated
                if saved.title == shown.title && saved.note == shown.note {
                    saved.title = item.title
                    saved.note = item.note
                } else {
                    saved.textEdited = true
                }
                store.update(trip.id) { trip in
                    if let index = trip.checklist?.firstIndex(where: { $0.id == saved.id }) { trip.checklist?[index] = saved }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func row(_ item: ChecklistItem) -> some View {
        let overdue = DepartureChecklist.isOverdue(item, in: trip)
        return Button {
            withAnimation(.spring(duration: 0.25)) {
                store.update(trip.id) { trip in
                    if let index = trip.checklist?.firstIndex(where: { $0.id == item.id }) { trip.checklist?[index].isDone.toggle() }
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isDone ? Color.success : Color.ink3)
                let text = DepartureChecklist.displayText(of: item, in: trip)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.title)
                        .font(.tBodyStrong)
                        .foregroundStyle(item.isDone ? Color.ink3 : Color.ink)
                        .strikethrough(item.isDone)
                    if !text.note.isEmpty && !item.isDone {
                        Text(text.note).font(.caption).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let due = DepartureChecklist.dueDate(of: item, in: trip), !item.isDone {
                    Tag(text: overdue ? String(localized: "Gecikti") : dueText(due), accent: overdue ? .orange : .gray)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(item.isDone ? .isSelected : [])
    }

    private func dueText(_ due: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: due).day ?? 0
        switch days {
        case 0: return String(localized: "Bugün")
        case 1: return String(localized: "Yarın")
        default: return AppFormat.dayPill(due)
        }
    }

    private func add(_ suggestions: [DepartureChecklist.Suggestion]) {
        withAnimation(.spring(duration: 0.3)) {
            store.update(trip.id) { trip in
                trip.checklist = (trip.checklist ?? []) + suggestions.map { $0.item() }
            }
        }
    }

    private func addCustom() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        store.update(trip.id) { trip in
            trip.checklist = (trip.checklist ?? []) + [ChecklistItem(title: title)]
        }
        newTitle = ""
        isAdding = true
    }

    private func remove(_ item: ChecklistItem) {
        withAnimation {
            store.update(trip.id) { trip in
                trip.checklist?.removeAll { $0.id == item.id }
                if trip.checklist?.isEmpty == true { trip.checklist = nil }
            }
        }
    }
}

/// Madde adı, not ve "kaç gün önce" ayarı.
struct ChecklistItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: ChecklistItem
    let onSave: (ChecklistItem) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Yapılacak", text: $item.title)
                TextField("Not", text: $item.note, axis: .vertical)
                Toggle("Son gün", isOn: Binding(get: { item.daysBefore != nil },
                                                set: { item.daysBefore = $0 ? (item.daysBefore ?? 3) : nil }))
                if let days = item.daysBefore {
                    Stepper(days == 0 ? String(localized: "Gidiş günü") : String(localized: "Gidişten \(days) gün önce"),
                            value: Binding(get: { days }, set: { item.daysBefore = $0 }), in: 0...90)
                }
            }
            .navigationTitle("Yapılacak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        item.title = item.title.trimmingCharacters(in: .whitespaces)
                        onSave(item)
                        dismiss()
                    }
                    .disabled(item.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
