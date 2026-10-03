import Foundation

/// Seyahat sonu paylaşılabilir özet kartının rakamları.
public struct TripSummary: Hashable, Sendable {
    public var days: Int
    public var nights: Int
    public var travellers: Int
    public var stops: Int
    /// Günlük rotaların toplam kuş uçuşu uzunluğu (metre).
    public var routeMeters: Double
    public var flights: Int
    /// Hesaplaşma transferleri hariç harcama (seyahat para biriminde, kuruş/cent).
    public var totalSpent: Int
    public var perPerson: Int
    public var topCategory: SpendCategory?
    /// Plandaki ilk birkaç durak (kartta "öne çıkanlar").
    public var highlights: [String]

    public static func make(_ trip: Trip, highlightCount: Int = 3, calendar: Calendar = .current) -> TripSummary {
        let days = trip.days(calendar: calendar)
        let route = days.reduce(0.0) { total, day in
            total + Geo.routeDistance(trip.stops(on: day, calendar: calendar).compactMap(\.coordinate))
        }
        let spending = trip.expenses.filter { !$0.isTransfer }
        let total = spending.reduce(0) { $0 + $1.amount }
        var byCategory: [SpendCategory: Int] = [:]
        for expense in spending { byCategory[expense.category, default: 0] += expense.amount }
        let top = byCategory.max { lhs, rhs in lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key.rawValue > rhs.key.rawValue }
        let travellers = max(1, trip.members.count)
        let highlights = days.flatMap { trip.stops(on: $0, calendar: calendar) }
            .filter { $0.kind != .transport && $0.kind != .stay }
            .prefix(highlightCount)
            .map(\.name)
        return TripSummary(days: days.count, nights: trip.nights(calendar: calendar), travellers: travellers,
                           stops: trip.stops.count, routeMeters: route, flights: trip.flights.count, totalSpent: total,
                           perPerson: total / travellers, topCategory: top?.key, highlights: Array(highlights))
    }
}
