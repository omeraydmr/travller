import Foundation

public struct CategorySpend: Hashable, Sendable {
    public var category: SpendCategory
    public var spent: Int
    public var limit: Int

    /// 0...1 arası doluluk; limit yoksa harcama varsa 1.
    public var progress: Double {
        guard limit > 0 else { return spent > 0 ? 1 : 0 }
        return min(1, Double(spent) / Double(limit))
    }

    public var isOver: Bool { limit > 0 && spent > limit }
}

public enum BudgetPace: Hashable, Sendable {
    case notStarted
    case under(day: Int, of: Int)
    case onTrack(day: Int, of: Int)
    case ahead(day: Int, of: Int)
    case finished
}

public struct BudgetSummary: Hashable, Sendable {
    public var spent: Int
    public var limit: Int
    public var categories: [CategorySpend]
    public var pace: BudgetPace
}

public enum Budget {
    public static func summary(for trip: Trip, now: Date = Date(), calendar: Calendar = .current) -> BudgetSummary {
        let spending = trip.expenses.filter { !$0.isTransfer }
        var spentBy: [SpendCategory: Int] = [:]
        for expense in spending {
            spentBy[expense.category, default: 0] += expense.amount
        }
        let limitBy = Dictionary(trip.budget.map { ($0.category, $0.limit) }, uniquingKeysWith: +)

        let categories = SpendCategory.allCases.compactMap { category -> CategorySpend? in
            let spent = spentBy[category] ?? 0
            let limit = limitBy[category] ?? 0
            guard spent > 0 || limit > 0 else { return nil }
            return CategorySpend(category: category, spent: spent, limit: limit)
        }
        let spent = categories.reduce(0) { $0 + $1.spent }
        let limit = categories.reduce(0) { $0 + $1.limit }

        return BudgetSummary(spent: spent, limit: limit, categories: categories,
                             pace: pace(spent: spent, limit: limit, trip: trip, now: now, calendar: calendar))
    }

    /// Harcamanın seyahatin geçen gün oranına göre temposu (±%10 tolerans).
    public static func pace(spent: Int, limit: Int, trip: Trip, now: Date, calendar: Calendar) -> BudgetPace {
        let days = trip.days(calendar: calendar)
        let today = calendar.startOfDay(for: now)
        guard let first = days.first, let last = days.last else { return .notStarted }
        if today < first { return .notStarted }
        if today > last { return .finished }

        let dayIndex = (days.firstIndex(of: today) ?? 0) + 1
        let total = days.count
        guard limit > 0 else { return .onTrack(day: dayIndex, of: total) }

        let expected = Double(limit) * Double(dayIndex) / Double(total)
        let ratio = Double(spent) / expected
        if ratio > 1.1 { return .ahead(day: dayIndex, of: total) }
        if ratio < 0.9 { return .under(day: dayIndex, of: total) }
        return .onTrack(day: dayIndex, of: total)
    }
}

/// Harcamaların para birimine göre dağılımı (orijinal tutar ve seyahat para birimindeki karşılığı).
public struct CurrencyTotal: Hashable, Sendable {
    public var currency: String
    public var originalTotal: Int
    public var convertedTotal: Int
    public var count: Int
}

extension Budget {
    public static func currencyBreakdown(for trip: Trip) -> [CurrencyTotal] {
        var totals: [String: CurrencyTotal] = [:]
        for expense in trip.expenses where !expense.isTransfer {
            let currency = expense.originalCurrency ?? trip.currency
            var total = totals[currency] ?? CurrencyTotal(currency: currency, originalTotal: 0, convertedTotal: 0, count: 0)
            total.originalTotal += expense.originalAmount ?? expense.amount
            total.convertedTotal += expense.amount
            total.count += 1
            totals[currency] = total
        }
        return totals.values.sorted {
            $0.convertedTotal != $1.convertedTotal ? $0.convertedTotal > $1.convertedTotal : $0.currency < $1.currency
        }
    }
}
