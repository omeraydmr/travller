import Foundation

/// Makbuzdaki bir kalem.
public struct ReceiptItem: Hashable, Identifiable, Sendable {
    public var id: Int
    public var name: String
    /// Kuruş, makbuzun para biriminde.
    public var amount: Int

    public init(id: Int, name: String, amount: Int) {
        self.id = id
        self.name = name
        self.amount = amount
    }
}

/// Kalemleri kişilere atayıp kişi başı payları hesaplar.
public enum ItemSplit {
    /// Her kalem, atandığı kişiler arasında eşit bölünür; sonra paylar `total`'a orantılı ölçeklenir
    /// (makbuz para birimi → seyahat para birimi çevrimi, servis/vergi farkı). Kuruşlar kaybolmaz.
    /// - Parameters:
    ///   - assignments: kalem → o kalemi paylaşan kişiler (sıra artan kuruşların dağıtımını belirler).
    ///   - total: payların toplamı olacak tutar.
    public static func shares(items: [ReceiptItem], assignments: [Int: [UUID]], total: Int) -> [UUID: Int] {
        var raw: [UUID: Int] = [:]
        var order: [UUID] = []
        for item in items {
            guard let people = assignments[item.id], !people.isEmpty else { continue }
            for (person, part) in zip(people, Settlement.split(item.amount, into: people.count)) {
                if raw[person] == nil { order.append(person) }
                raw[person, default: 0] += part
            }
        }
        return scale(raw, order: order, to: total)
    }

    /// Payları toplamları `total` olacak şekilde orantılı ölçekler (en büyük kalan yöntemi).
    public static func scale(_ parts: [UUID: Int], order: [UUID], to total: Int) -> [UUID: Int] {
        let sum = parts.values.reduce(0, +)
        guard sum > 0, total >= 0 else { return [:] }
        var result: [UUID: Int] = [:]
        var remainders: [(UUID, Int)] = []
        var assigned = 0
        for person in order {
            let exact = parts[person, default: 0] * total
            result[person] = exact / sum
            assigned += exact / sum
            remainders.append((person, exact % sum))
        }
        var left = total - assigned
        for (person, _) in remainders.sorted(by: { $0.1 > $1.1 }) where left > 0 {
            result[person, default: 0] += 1
            left -= 1
        }
        return result
    }
}
