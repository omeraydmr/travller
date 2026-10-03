import Foundation

/// Makbuzdan okunan metin satırlarından toplam tutarı ve para birimini çıkarır (cihaz üzerinde, kural tabanlı).
public enum ReceiptParser {
    public struct Result: Hashable, Sendable {
        /// Kuruş/cent cinsinden.
        public var amount: Int
        public var currency: String?
        /// "TOPLAM" gibi bir anahtar kelimenin yanında bulunduysa true; yalnızca en büyük tutar tahminiyse false.
        public var isConfident: Bool
    }

    static let totalKeywords = ["genel toplam", "toplam", "total", "tutar", "odenecek", "amount due", "totale",
                                "summe", "gesamt", "totaal", "a pagar", "betrag"]
    static let excludedKeywords = ["ara toplam", "subtotal", "sub total", "kdv", "vat", "tax", "iva", "mwst", "tva",
                                   "para ustu", "change", "nakit", "cash", "kredi", "card", "kart", "indirim", "discount",
                                   "tip", "bahsis"]

    public static func parse(lines: [String]) -> Result? {
        let folded = lines.map(fold)
        var keywordAmounts: [Int] = []
        for (index, line) in folded.enumerated() {
            guard totalKeywords.contains(where: { line.contains($0) }),
                  !excludedKeywords.contains(where: { line.contains($0) }) else { continue }
            var found = Self.amounts(in: lines[index], requireDecimals: false)
            if found.isEmpty, index + 1 < lines.count {
                found = Self.amounts(in: lines[index + 1], requireDecimals: false)
            }
            keywordAmounts += found
        }
        let currency = detectCurrency(lines.joined(separator: " "))
        if let best = keywordAmounts.max(), best > 0 {
            return Result(amount: best, currency: currency, isConfident: true)
        }
        let fallback = zip(lines, folded)
            .filter { _, line in !excludedKeywords.contains(where: { line.contains($0) }) }
            .flatMap { original, _ in Self.amounts(in: original, requireDecimals: true) }
        guard let largest = fallback.max(), largest > 0 else { return nil }
        return Result(amount: largest, currency: currency, isConfident: false)
    }

    /// Toplam ve vergi satırları dışındaki "ad ... tutar" satırları. Adet önekleri ("2x", "2 x") korunur.
    public static func items(lines: [String]) -> [ReceiptItem] {
        var result: [ReceiptItem] = []
        for line in lines {
            let folded = fold(line)
            if totalKeywords.contains(where: { folded.contains($0) }) || excludedKeywords.contains(where: { folded.contains($0) }) {
                continue
            }
            guard let amount = Self.amounts(in: line, requireDecimals: true).last, amount > 0 else { continue }
            let name = itemName(line)
            guard name.count >= 2, name.contains(where: \.isLetter) else { continue }
            result.append(ReceiptItem(id: result.count, name: name, amount: amount))
        }
        return result
    }

    /// Satırdan tutarı, para birimi işaretlerini ve dolgu karakterlerini atıp adı bırakır.
    static func itemName(_ line: String) -> String {
        var text = line
        text = text.replacingOccurrences(of: #"\d{1,3}(?:[.,]\d{3})*[.,]\d{2}\s*$"#, with: "", options: .regularExpression)
        for sign in ["€", "£", "$", "₺", "TL", "EUR", "*", "#"] {
            text = text.replacingOccurrences(of: sign, with: " ")
        }
        text = text.replacingOccurrences(of: #"[.\-_]{2,}"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    /// Satırdaki tutarlar (kuruş). Tarih ve saatler önce ayıklanır.
    static func amounts(in line: String, requireDecimals: Bool) -> [Int] {
        var text = line
        for pattern in [#"\d{1,2}[./-]\d{1,2}[./-]\d{2,4}"#, #"\d{1,2}:\d{2}(:\d{2})?"#] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        guard let regex = try? NSRegularExpression(pattern: #"\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?"#) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return amount(from: String(text[r]), requireDecimals: requireDecimals)
        }
    }

    /// "1.250,50", "1,250.50", "12,5", "1250" → kuruş.
    static func amount(from token: String, requireDecimals: Bool) -> Int? {
        let cleaned = token.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard let separator = cleaned.lastIndex(where: { $0 == "." || $0 == "," }) else {
            return requireDecimals ? nil : Int(cleaned).map { $0 * 100 }
        }
        let integer = cleaned[..<separator].filter(\.isNumber)
        let fraction = String(cleaned[cleaned.index(after: separator)...])
        switch fraction.count {
        case 2:
            guard let whole = Int(integer.isEmpty ? "0" : integer), let cents = Int(fraction) else { return nil }
            return whole * 100 + cents
        case 1 where !requireDecimals:
            guard let whole = Int(integer.isEmpty ? "0" : integer), let tenth = Int(fraction) else { return nil }
            return whole * 100 + tenth * 10
        case 3 where !requireDecimals:
            return Int(integer + fraction).map { $0 * 100 }
        default:
            return nil
        }
    }

    static func detectCurrency(_ text: String) -> String? {
        let upper = text.uppercased()
        let markers: [(String, [String])] = [
            ("EUR", ["€", "EUR"]), ("GBP", ["£", "GBP"]), ("TRY", ["₺", " TL", "TRY"]), ("USD", ["$", "USD"]),
            ("CHF", ["CHF"]), ("JPY", ["¥", "JPY", "円"]),
        ]
        return markers.first { _, signs in signs.contains(where: { upper.contains($0) }) }?.0
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
    }
}
