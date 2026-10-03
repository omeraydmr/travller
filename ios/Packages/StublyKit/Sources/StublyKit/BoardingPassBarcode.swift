import Foundation

/// IATA BCBP (Bar Coded Boarding Pass, Resolution 792): biniş kartı barkodundaki standart metin. THY, Pegasus ve
/// diğer IATA havayolları aynı düzeni kullanır; Wallet kartının görünümü havayoluna göre değişse de barkod değişmez.
///
/// İlk bacak: `M` + bacak sayısı (1) + yolcu adı (20) + e-bilet (1) + PNR (7) + kalkış (3) + varış (3) + havayolu (3)
/// + uçuş no (5) + yılın günü (3) + kabin (1) + koltuk (4) + sıra no (5) + durum (1) + koşullu bölüm uzunluğu (2, hex)
/// + koşullu bölüm. Sonraki bacaklar PNR'den başlar.
public enum BoardingPassBarcode {
    public struct Leg: Hashable, Sendable {
        public var pnr: String
        public var fromCode: String
        public var toCode: String
        public var airline: String
        public var flightNumber: String
        /// Yılın günü (1…366); yıl barkodda yoktur.
        public var dayOfYear: Int
        public var seat: String?

        public var flightCode: String { airline + flightNumber }

        /// Gün, `reference` tarihine en yakın yıla yerleştirilir.
        public func date(near reference: Date, calendar: Calendar) -> Date? {
            let year = calendar.component(.year, from: reference)
            return [year - 1, year, year + 1].compactMap { candidate -> Date? in
                guard let start = calendar.date(from: DateComponents(year: candidate, month: 1, day: 1)) else { return nil }
                return calendar.date(byAdding: .day, value: dayOfYear - 1, to: start)
            }.min { abs($0.timeIntervalSince(reference)) < abs($1.timeIntervalSince(reference)) }
        }
    }

    public static func parse(_ message: String) -> [Leg] {
        let chars = Array(message)
        guard chars.count >= 60, chars[0] == "M", let legCount = Int(String(chars[1])), legCount >= 1 else { return [] }
        func text(_ start: Int, _ length: Int) -> String? {
            guard start >= 0, start + length <= chars.count else { return nil }
            return String(chars[start..<start + length]).trimmingCharacters(in: .whitespaces)
        }

        var legs: [Leg] = []
        var offset = 23 // ilk bacağın PNR'si
        for _ in 0..<legCount {
            guard let pnr = text(offset, 7), let from = text(offset + 7, 3), let to = text(offset + 10, 3),
                  let airline = text(offset + 13, 3), let number = text(offset + 16, 5), let day = text(offset + 21, 3),
                  let seat = text(offset + 25, 4), let sizeHex = text(offset + 35, 2),
                  isAirport(from), isAirport(to), airline.count >= 2,
                  let dayOfYear = Int(day), (1...366).contains(dayOfYear),
                  let digits = Int(number.filter(\.isNumber)), digits > 0
            else { break }
            let suffix = number.filter(\.isLetter) // operasyonel ek harf ("1234A")
            let seatText = seat.drop { $0 == "0" }
            legs.append(Leg(pnr: pnr, fromCode: from, toCode: to, airline: airline, flightNumber: "\(digits)\(suffix)",
                            dayOfYear: dayOfYear, seat: seatText.isEmpty || seatText.allSatisfy({ !$0.isNumber }) ? nil : String(seatText)))
            // Sonraki bacak: bu bacağın zorunlu kısmı (37) + koşullu bölümü.
            offset += 37 + (Int(sizeHex, radix: 16) ?? 0)
        }
        return legs
    }

    static func isAirport(_ code: String) -> Bool {
        code.count == 3 && code.allSatisfy { $0.isASCII && $0.isUppercase }
    }
}
