import Foundation

extension Trip {
    /// Seyahatin tarihlerini değiştirir. `shiftPlan` ise duraklar gidiş tarihindeki kayma kadar kaydırılır.
    /// Yeni tarih aralığının dışında kalan duraklar silinmez, saatleri temizlenip Fikirler'e taşınır.
    /// - Returns: Fikirler'e taşınan durak sayısı.
    @discardableResult
    public mutating func reschedule(start: Date, end: Date, shiftPlan: Bool, calendar: Calendar = .current) -> Int {
        let newStart = calendar.startOfDay(for: start)
        let newEnd = max(newStart, calendar.startOfDay(for: end))
        let delta = calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: newStart).day ?? 0
        startDate = newStart
        endDate = newEnd

        if shiftPlan && delta != 0 {
            for index in stops.indices {
                stops[index].day = calendar.date(byAdding: .day, value: delta, to: stops[index].day) ?? stops[index].day
            }
        }
        let outside = stops.filter { stop in
            let day = calendar.startOfDay(for: stop.day)
            return day < newStart || day > newEnd
        }
        guard !outside.isEmpty else { return 0 }
        let moved = Set(outside.map(\.id))
        stops.removeAll { moved.contains($0.id) }
        // Silinen durağın kimliği mezar taşına düşer; fikir yeni kimlikle eklenir (eşitlemede geri gelmesin).
        ideas = (ideas ?? []) + outside.map { stop in
            var idea = stop
            idea.id = UUID()
            idea.startMinutes = nil
            return idea
        }
        return outside.count
    }
}
