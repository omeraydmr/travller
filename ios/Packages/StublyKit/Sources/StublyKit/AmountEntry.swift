import Foundation

/// Tuş takımıyla girilen tutarın durumu. Türkçe yazımı kullanır: binlik ayırıcı nokta, ondalık virgül.
public struct AmountEntry: Hashable, Sendable {
    public private(set) var integerDigits: String = ""
    public private(set) var fractionDigits: String = ""
    public private(set) var hasDecimal = false

    public static let maxIntegerDigits = 9
    public static let maxFractionDigits = 2

    public init() {}

    /// Var olan bir tutardan (kuruş) başlatır.
    public init(minorUnits: Int) {
        guard minorUnits > 0 else { return }
        integerDigits = String(minorUnits / 100)
        let fraction = minorUnits % 100
        if fraction > 0 {
            hasDecimal = true
            fractionDigits = fraction % 10 == 0 ? String(fraction / 10) : String(format: "%02d", fraction)
        }
    }

    public var isEmpty: Bool { integerDigits.isEmpty && !hasDecimal }

    public mutating func append(digit: Int) {
        guard (0...9).contains(digit) else { return }
        if hasDecimal {
            guard fractionDigits.count < Self.maxFractionDigits else { return }
            fractionDigits.append(String(digit))
        } else {
            guard integerDigits.count < Self.maxIntegerDigits else { return }
            if integerDigits == "0" { integerDigits = "" }
            if digit == 0 && integerDigits.isEmpty {
                integerDigits = "0"
                return
            }
            integerDigits.append(String(digit))
        }
    }

    public mutating func appendDecimalSeparator() {
        guard !hasDecimal else { return }
        hasDecimal = true
        if integerDigits.isEmpty { integerDigits = "0" }
    }

    public mutating func backspace() {
        if !fractionDigits.isEmpty {
            fractionDigits.removeLast()
        } else if hasDecimal {
            hasDecimal = false
            if integerDigits == "0" { integerDigits = "" }
        } else if !integerDigits.isEmpty {
            integerDigits.removeLast()
        }
    }

    public mutating func clear() {
        self = AmountEntry()
    }

    /// Kuruş/cent cinsinden değer.
    public var minorUnits: Int {
        let whole = Int(integerDigits) ?? 0
        let paddedFraction = (fractionDigits + "00").prefix(2)
        return whole * 100 + (Int(paddedFraction) ?? 0)
    }

    /// Ekranda gösterilen metin: "1.250", "1.250,", "1.250,5", boşsa "0".
    public var display: String {
        let digits = integerDigits.isEmpty ? "0" : integerDigits
        var grouped = ""
        for (index, character) in digits.reversed().enumerated() {
            if index > 0 && index % 3 == 0 { grouped.append(".") }
            grouped.append(character)
        }
        var text = String(grouped.reversed())
        if hasDecimal { text += "," + fractionDigits }
        return text
    }
}
