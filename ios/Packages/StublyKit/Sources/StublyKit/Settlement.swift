import Foundation

public struct Transfer: Hashable, Sendable {
    public var from: UUID
    public var to: UUID
    /// Kuruş/cent cinsinden.
    public var amount: Int

    public init(from: UUID, to: UUID, amount: Int) {
        self.from = from
        self.to = to
        self.amount = amount
    }
}

/// Masraf paylaşımı: bakiyeler ve borç sadeleştirme.
public enum Settlement {
    /// Tutarı `n` kişiye kuruşu kaybetmeden böler; artan kuruşlar ilk kişilere dağıtılır.
    public static func split(_ amount: Int, into n: Int) -> [Int] {
        guard n > 0 else { return [] }
        let base = amount / n
        let remainder = amount - base * n
        return (0..<n).map { $0 < remainder ? base + 1 : base }
    }

    /// Her üyenin net bakiyesi. Pozitif: alacaklı, negatif: borçlu.
    public static func balances(expenses: [Expense], members: [UUID]) -> [UUID: Int] {
        var balances = Dictionary(uniqueKeysWithValues: members.map { ($0, 0) })
        for expense in expenses {
            if let custom = expense.shares, !custom.isEmpty {
                balances[expense.paidBy, default: 0] += expense.amount
                for (member, share) in custom {
                    balances[member, default: 0] -= share
                }
                continue
            }
            guard !expense.splitAmong.isEmpty else { continue }
            balances[expense.paidBy, default: 0] += expense.amount
            let shares = split(expense.amount, into: expense.splitAmong.count)
            for (member, share) in zip(expense.splitAmong, shares) {
                balances[member, default: 0] -= share
            }
        }
        return balances
    }

    /// Bakiyeleri kapatan transfer listesi. Açgözlü eşleştirme en fazla n-1 transfer üretir
    /// ve pratikte minimuma çok yakındır.
    public static func transfers(balances: [UUID: Int]) -> [Transfer] {
        func ordered(_ items: [(UUID, Int)]) -> [(UUID, Int)] {
            items.sorted { lhs, rhs in
                lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0.uuidString < rhs.0.uuidString
            }
        }
        var creditors = ordered(balances.filter { $0.value > 0 }.map { ($0.key, $0.value) })
        var debtors = ordered(balances.filter { $0.value < 0 }.map { ($0.key, -$0.value) })

        var result: [Transfer] = []
        var c = 0
        var d = 0
        while c < creditors.count && d < debtors.count {
            let amount = min(creditors[c].1, debtors[d].1)
            if amount > 0 {
                result.append(Transfer(from: debtors[d].0, to: creditors[c].0, amount: amount))
            }
            creditors[c].1 -= amount
            debtors[d].1 -= amount
            if creditors[c].1 == 0 { c += 1 }
            if debtors[d].1 == 0 { d += 1 }
        }
        return result
    }

    public static func transfers(for trip: Trip) -> [Transfer] {
        transfers(balances: balances(expenses: trip.expenses, members: trip.members.map(\.id)))
    }
}
