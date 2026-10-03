import Foundation

/// Seyahate ne kadar kaldığının göreli ifadesi ("41 gün", "4 ay").
public enum Countdown: Hashable, Sendable {
    case today
    case days(Int)
    case months(Int)
    case ongoing(day: Int, of: Int)
    case past

    public static func make(start: Date, end: Date, now: Date = Date(), calendar: Calendar = .current) -> Countdown {
        let today = calendar.startOfDay(for: now)
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)

        if today > endDay { return .past }
        if today >= startDay {
            let elapsed = calendar.dateComponents([.day], from: startDay, to: today).day ?? 0
            let total = (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
            return elapsed == 0 && total == 1 ? .today : .ongoing(day: elapsed + 1, of: total)
        }
        let days = calendar.dateComponents([.day], from: today, to: startDay).day ?? 0
        if days < 60 { return .days(days) }
        return .months(Int((Double(days) / 30.44).rounded()))
    }
}
