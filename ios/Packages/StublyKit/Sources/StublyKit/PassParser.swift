import Foundation

/// Wallet biniş kartından (`.pkpass`) uçuş adayı çıkarır. Sırasıyla `pass.json`'daki anlamsal etiketlere
/// (iOS 15+ `semantics`), barkoddaki IATA BCBP metnine (havayolundan bağımsız: THY, Pegasus…) ve kart alanlarına
/// bakar; hiçbiri yetmezse alan metinlerini `BookingParser`'a verir.
public enum PassParser {
    /// `.pkpass` arşivini okur; arşiv ya da `pass.json` açılamazsa nil.
    public static func parse(pkpass data: Data, now: Date = Date(), calendar: Calendar = .current) -> BookingParser.Result? {
        guard let archive = ZipArchive(data: data), let json = archive.contents(of: "pass.json") else { return nil }
        return parse(passJSON: json, now: now, calendar: calendar)
    }

    public static func parse(passJSON data: Data, now: Date = Date(), calendar: Calendar = .current) -> BookingParser.Result? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let style = ["boardingPass", "eventTicket", "generic", "storeCard", "coupon"]
            .lazy.compactMap { root[$0] as? [String: Any] }.first ?? [:]
        let fields = ["headerFields", "primaryFields", "secondaryFields", "auxiliaryFields", "backFields"]
            .flatMap { (style[$0] as? [[String: Any]] ?? []).map(Field.init) }
        let semantics = root["semantics"] as? [String: Any] ?? [:]
        let barcodes = (root["barcodes"] as? [[String: Any]] ?? []) + [root["barcode"] as? [String: Any]].compactMap { $0 }
        let legs = barcodes.lazy.compactMap { $0["message"] as? String }.map(BoardingPassBarcode.parse).first { !$0.isEmpty } ?? []
        let leg = legs.first

        if let flight = flight(semantics: semantics, fields: fields, barcode: leg, relevantDate: date(root["relevantDate"]),
                               now: now, calendar: calendar) {
            // Aktarmalı barkod: sonraki bacaklar saatsiz aday olarak (kullanıcı kontrol eder).
            let connections = legs.dropFirst().compactMap { leg -> BookingParser.FlightCandidate? in
                guard let day = leg.date(near: flight.departure, calendar: utc),
                      let departure = combine(day, (12, 0), airport: leg.fromCode) else { return nil }
                return BookingParser.FlightCandidate(flightNumber: leg.flightCode, fromCode: leg.fromCode, toCode: leg.toCode,
                                                     departure: departure, arrival: departure.addingTimeInterval(3 * 3600),
                                                     hasTimes: false, seat: leg.seat)
            }
            return BookingParser.Result(flights: [flight] + connections, lodgings: [])
        }
        // Yapı tanınmadı: alanları metne çevirip genel ayrıştırıcıya ver.
        var lines = fields.map { [$0.label, $0.value].filter { !$0.isEmpty }.joined(separator: ": ") }
        if let relevant = root["relevantDate"] as? String { lines.append(relevant) }
        if let description = root["description"] as? String { lines.insert(description, at: 0) }
        return BookingParser.parse(lines.joined(separator: "\n"), now: now, calendar: calendar)
    }

    struct Field {
        var key: String
        var label: String
        var value: String
        var rawValue: Any?

        init(_ dictionary: [String: Any]) {
            key = (dictionary["key"] as? String ?? "").lowercased()
            label = dictionary["label"] as? String ?? ""
            rawValue = dictionary["value"]
            switch dictionary["value"] {
            case let text as String: value = text
            case let number as NSNumber: value = number.stringValue
            default: value = ""
            }
        }

        func mentions(_ words: [String]) -> Bool {
            let haystack = (key + " " + label).lowercased(with: Locale(identifier: "tr_TR"))
            return words.contains { haystack.contains($0) }
        }
    }

    static func flight(semantics: [String: Any], fields: [Field], barcode: BoardingPassBarcode.Leg? = nil, relevantDate: Date?,
                       now: Date = Date(), calendar: Calendar = .current) -> BookingParser.FlightCandidate? {
        // Havalimanı kodları
        var from = (semantics["departureAirportCode"] as? String)?.uppercased() ?? barcode?.fromCode
        var to = (semantics["destinationAirportCode"] as? String)?.uppercased() ?? barcode?.toCode
        if from == nil || to == nil {
            let codes = fields.filter { isAirportCode($0.value) }
            let origin = codes.first { $0.mentions(["origin", "depart", "from", "kalkış", "nereden"]) }
            let destination = codes.first { $0.mentions(["dest", "arriv", "to", "varış", "nereye"]) && $0.key != origin?.key }
            if let origin, let destination {
                from = origin.value.uppercased()
                to = destination.value.uppercased()
            } else if codes.count >= 2 {
                from = codes[0].value.uppercased()
                to = codes[1].value.uppercased()
            }
        }
        guard let from, let to, from != to else { return nil }

        // Uçuş numarası
        var number = (semantics["flightCode"] as? String).map(normalizedFlightNumber)
        if number == nil, let airline = semantics["airlineCode"] as? String, let digits = semantics["flightNumber"] {
            number = normalizedFlightNumber("\(airline)\(digits)")
        }
        if number == nil { number = barcode?.flightCode }
        if number == nil {
            let ordered = fields.filter { $0.mentions(["flight", "uçuş", "sefer", "vol"]) } + fields
            number = ordered.lazy.compactMap { flightNumber(in: $0.value) }.first
        }
        guard let number else { return nil }

        // Saatler
        let semanticDeparture = date(semantics["currentDepartureDate"]) ?? date(semantics["originalDepartureDate"])
        let semanticArrival = date(semantics["currentArrivalDate"]) ?? date(semantics["originalArrivalDate"])
        let fieldDeparture = fields.first { $0.mentions(["depart", "kalkış"]) && date($0.rawValue) != nil }.flatMap { date($0.rawValue) }
        let fieldArrival = fields.first { $0.mentions(["arriv", "varış", "iniş"]) && date($0.rawValue) != nil }.flatMap { date($0.rawValue) }
        // Barkoddaki gün + karttaki "KALKIŞ 07:40" gibi yalnızca saat yazan alanlar (havalimanının saatiyle).
        let day = barcode?.date(near: relevantDate ?? now, calendar: utc)
            ?? relevantDate.map { utc.startOfDay(for: localDay($0, in: from)) }
        let clockDeparture = day.flatMap { day in
            clock(in: fields, words: ["depart", "kalkış", "kalkis"], keys: ["std", "etd"]).flatMap { combine(day, $0, airport: from) }
        }
        let clockArrival = day.flatMap { day in
            clock(in: fields, words: ["arriv", "varış", "varis", "iniş"], keys: ["sta", "eta"]).flatMap { combine(day, $0, airport: to) }
        }
        let barcodeDay = barcode == nil ? nil : day.flatMap { combine($0, (12, 0), airport: from) }
        guard let departure = semanticDeparture ?? fieldDeparture ?? clockDeparture ?? relevantDate ?? barcodeDay else { return nil }
        var arrival = semanticArrival ?? fieldArrival ?? clockArrival.map { $0 < departure ? $0.addingTimeInterval(86_400) : $0 }
        if let value = arrival, value <= departure { arrival = nil }

        // Varış yoksa havalimanları arası mesafeden tahmin (kullanıcıya yine "kontrol et" denir).
        let estimate = Airports.estimatedFlightMinutes(from: from, to: to).map { departure.addingTimeInterval(Double($0) * 60) }
        return BookingParser.FlightCandidate(flightNumber: number, fromCode: from, toCode: to, departure: departure,
                                             arrival: arrival ?? estimate ?? departure.addingTimeInterval(3 * 3600),
                                             hasTimes: (semanticDeparture ?? fieldDeparture ?? clockDeparture) != nil && arrival != nil,
                                             seat: seat(semantics: semantics, fields: fields) ?? barcode?.seat)
    }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Anın havalimanındaki yerel günü (UTC gece yarısı olarak).
    static func localDay(_ date: Date, in airport: String) -> Date {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = Airports.airport(airport).flatMap { TimeZone(identifier: $0.timeZone) } ?? .current
        let parts = local.dateComponents([.year, .month, .day], from: date)
        return utc.date(from: parts) ?? date
    }

    /// Yalnızca saat içeren alan ("07:40", "7:40 PM"); biniş/kapı saatleri hariç.
    static func clock(in fields: [Field], words: [String], keys: [String]) -> (Int, Int)? {
        for field in fields where (field.mentions(words) || keys.contains(field.key))
            && !field.mentions(["board", "biniş", "binis", "gate", "kapı", "kapi", "close", "kapan"]) {
            if let time = BookingParser.findTimes(in: field.value, excluding: []).first { return (time.hour, time.minute) }
        }
        return nil
    }

    /// UTC gün + yerel saat → anı, havalimanının saat dilimiyle.
    static func combine(_ day: Date, _ time: (Int, Int), airport: String) -> Date? {
        let parts = utc.dateComponents([.year, .month, .day], from: day)
        var local = Calendar(identifier: .gregorian)
        local.timeZone = Airports.airport(airport).flatMap { TimeZone(identifier: $0.timeZone) } ?? .current
        return local.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: time.0, minute: time.1))
    }

    static func seat(semantics: [String: Any], fields: [Field]) -> String? {
        if let seats = semantics["seats"] as? [[String: Any]], let first = seats.first {
            if let identifier = first["seatIdentifier"] as? String, !identifier.isEmpty { return identifier.uppercased() }
            let row = first["seatRow"].map { "\($0)" } ?? ""
            let number = first["seatNumber"].map { "\($0)" } ?? ""
            if !(row + number).isEmpty { return (row + number).uppercased() }
        }
        let value = fields.first { $0.mentions(["seat", "koltuk"]) }?.value.trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? nil : value.uppercased()
    }

    static func isAirportCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.count == 3 && trimmed.allSatisfy { $0.isASCII && $0.isUppercase }
    }

    static func normalizedFlightNumber(_ text: String) -> String {
        text.uppercased().filter { !$0.isWhitespace }
    }

    static func flightNumber(in text: String) -> String? {
        let upper = text.uppercased()
        for match in BookingParser.matches(#"\b([A-Z0-9]{2})\s?(\d{1,4})\b"#, in: upper) {
            guard let airline = BookingParser.group(match, 1, in: upper), BookingParser.airlines.contains(airline),
                  let digits = BookingParser.group(match, 2, in: upper) else { continue }
            return airline + digits
        }
        return nil
    }

    /// Pass dosyalarındaki W3C tarihleri: saniyeli ya da saniyesiz, saat dilimli.
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String, text.count >= 16, text.contains("T") else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        // 2026-10-12T07:40+03:00 → saniye ekle
        let index = text.index(text.startIndex, offsetBy: 16)
        return ISO8601DateFormatter().date(from: String(text[..<index]) + ":00" + String(text[index...]))
    }
}
