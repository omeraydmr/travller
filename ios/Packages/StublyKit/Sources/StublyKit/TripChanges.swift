import Foundation

/// Buluttan gelen bir seyahat güncellemesinde nelerin değiştiğini kısa Türkçe cümlelerle özetler
/// ("Elif bir harcama ekledi: Akşam yemeği · €86").
public enum TripChanges {
    public struct Summary: Hashable, Sendable {
        public var title: String
        public var lines: [String]
        /// Dokununca açılacak seyahat ve ilk değişikliğin sekmesi.
        public var link: TripLink

        public init(title: String, lines: [String], link: TripLink) {
            self.title = title
            self.lines = lines
            self.link = link
        }

        public var body: String { lines.joined(separator: "\n") }
    }

    /// - Parameters:
    ///   - old: cihazdaki önceki kopya (yoksa yeni paylaşılan seyahat).
    ///   - new: birleşmiş yeni kopya.
    ///   - me: bu cihazın kullanıcısı; kendi yaptığı değişiklikler bildirilmez.
    ///   - money: tutar biçimlendirici (kuruş, para birimi).
    public static func summarize(old: Trip?, new: Trip, me: UUID?, money: (Int, String) -> String) -> Summary? {
        guard let old else {
            return Summary(title: new.name, lines: [String(localized: "Seyahat seninle paylaşıldı.")], link: TripLink(tripID: new.id, section: "plan"))
        }
        var lines: [String] = []
        var sections: [String] = []
        let name = { (id: UUID) in new.member(id)?.name ?? String(localized: "Biri") }

        let oldExpenses = Set(old.expenses.map(\.id))
        for expense in new.expenses where !oldExpenses.contains(expense.id) && !expense.isTransfer && expense.paidBy != me {
            sections.append("money")
            lines.append("\(name(expense.paidBy)) bir harcama ekledi: \(expense.title) · \(money(expense.amount, new.currency))")
        }
        for expense in new.expenses where !oldExpenses.contains(expense.id) && expense.isTransfer && expense.paidBy != me {
            let to = expense.splitAmong.first.map(name) ?? String(localized: "Biri")
            sections.append("money")
            lines.append(String(localized: "\(name(expense.paidBy)) → \(to) ödemesi yapıldı · \(money(expense.amount, new.currency))"))
        }

        let oldStops = Set(old.stops.map(\.id))
        let addedStops = new.stops.filter { !oldStops.contains($0.id) }
        if !addedStops.isEmpty { sections.append("plan") }
        if addedStops.count == 1 {
            lines.append(String(localized: "Plana eklendi: \(addedStops[0].name)"))
        } else if addedStops.count > 1 {
            lines.append(String(localized: "Plana \(addedStops.count) durak eklendi"))
        }

        let oldLodgings = Set(old.lodgingList.map(\.id))
        for lodging in new.lodgingList where !oldLodgings.contains(lodging.id) {
            sections.append("plan")
            lines.append(String(localized: "Konaklama eklendi: \(lodging.name)"))
        }

        let oldMembers = Set(old.members.map(\.id))
        for member in new.members where !oldMembers.contains(member.id) && member.id != me {
            sections.append("crew")
            lines.append(String(localized: "\(member.name) ekibe katıldı"))
        }

        let oldPacked = Set(old.packing.filter(\.isPacked).map(\.id))
        let newlyPacked = new.packing.filter { $0.isPacked && !oldPacked.contains($0.id) && $0.assignee != me }
        if !newlyPacked.isEmpty {
            sections.append("packing")
            let titles = newlyPacked.prefix(2).map(\.title).joined(separator: ", ")
            let more = newlyPacked.count > 2 ? String(localized: " ve \(newlyPacked.count - 2) madde daha") : ""
            lines.append(String(localized: "Valize konuldu: \(titles)\(more)"))
        }

        if old.startDate != new.startDate || old.endDate != new.endDate {
            sections.append("plan")
            lines.append(String(localized: "Seyahat tarihleri değişti"))
        }

        guard !lines.isEmpty else { return nil }
        return Summary(title: new.name, lines: lines, link: TripLink(tripID: new.id, section: sections.first))
    }
}
