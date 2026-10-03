import Foundation

public enum MoneyParser {
    /// Kullanıcının yazdığı tutarı kuruş/cent'e çevirir. Türkçe yazımı esas alır:
    /// "1.600" → 160000, "12,50" → 1250, "1.250,75" → 125075. Ayırıcıdan sonra tam 3 rakam
    /// yoksa nokta ondalık kabul edilir ("12.5" → 1250).
    public static func minorUnits(from text: String) -> Int? {
        var cleaned = text.filter { !$0.isWhitespace && $0 != "\u{00A0}" }
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) else { return nil }

        if cleaned.contains(",") {
            // Virgül ondalık; noktalar binlik ayırıcı.
            cleaned = cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if let lastDot = cleaned.lastIndex(of: ".") {
            let fraction = cleaned[cleaned.index(after: lastDot)...]
            let dotCount = cleaned.filter { $0 == "." }.count
            if fraction.count == 3 || dotCount > 1 {
                cleaned = cleaned.replacingOccurrences(of: ".", with: "")
            }
        }
        guard cleaned.filter({ $0 == "." }).count <= 1,
              let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return nil }

        var minor = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &minor, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
