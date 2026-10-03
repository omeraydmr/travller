import Foundation

/// E-bilet ve otel onaylarının metninden (PDF metni ya da cihazda okunan ekran görüntüsü) uçuş ve
/// konaklama adayları çıkarır. Sezgiseldir: kullanıcı sonucu eklemeden önce görür ve düzeltir.
public enum BookingParser {
    public struct FlightCandidate: Hashable, Sendable {
        public var flightNumber: String
        public var fromCode: String
        public var toCode: String
        public var departure: Date
        public var arrival: Date
        /// Saat metinde bulunamadıysa false; kullanıcıya "saati kontrol et" denir.
        public var hasTimes: Bool
        public var seat: String?

        public func segment() -> FlightSegment {
            let from = Airports.airport(fromCode)
            let to = Airports.airport(toCode)
            return FlightSegment(flightNumber: flightNumber, fromCode: fromCode, fromCity: from?.city ?? fromCode,
                                 toCode: toCode, toCity: to?.city ?? toCode, departure: departure, arrival: arrival,
                                 departureTimeZone: from?.timeZone, arrivalTimeZone: to?.timeZone, seat: seat)
        }
    }

    public struct LodgingCandidate: Hashable, Sendable {
        public var name: String
        public var address: String
        public var checkIn: Date
        public var checkOut: Date
        public var confirmation: String
        /// Onayda yazan koordinat (Booking.com "GPS koordinatları").
        public var coordinate: Coordinate?
        /// Kapı/PIN kodu gibi ek bilgiler.
        public var note: String = ""

        public func lodging() -> Lodging {
            Lodging(name: name, address: address, coordinate: coordinate, checkIn: checkIn, checkOut: checkOut,
                    confirmation: confirmation, note: note)
        }
    }

    public struct Result: Hashable, Sendable {
        public var flights: [FlightCandidate]
        public var lodgings: [LodgingCandidate]
        public var isEmpty: Bool { flights.isEmpty && lodgings.isEmpty }
    }

    /// - Parameters:
    ///   - now: yılı yazılmamış tarihler için referans (geçmişte kalıyorsa sonraki yıl alınır).
    ///   - calendar: saat dilimi bilinmeyen tarihler için.
    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Result {
        let source = repairGlyphs(text.replacingOccurrences(of: "\r", with: "\n"))
        let dates = findDates(in: source, now: now, calendar: calendar)
        let times = findTimes(in: source, excluding: dates.map(\.range))
        return Result(flights: flights(in: source, dates: dates, times: times, calendar: calendar),
                      lodgings: lodgings(in: source, dates: dates, times: times, calendar: calendar))
    }

    /// Bazı PDF'lerde (ör. Booking.com onayları) yazı tipi "i" harfini "!" olarak verir ("Cab!nn", "!ç!n").
    /// Harfe bitişik "!" çoksa bu bozulma sayılır ve "i"ye çevrilir.
    static func repairGlyphs(_ text: String) -> String {
        guard matches(#"\p{L}!\p{L}"#, in: text).count >= 3,
              let regex = try? NSRegularExpression(pattern: #"(?<=\p{L})!|!(?=\p{L})"#) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "i")
    }

    // MARK: - Tokens

    struct DayToken: Hashable {
        var year: Int
        var month: Int
        var day: Int
        var range: NSRange
    }

    struct TimeToken: Hashable {
        var hour: Int
        var minute: Int
        var range: NSRange
    }

    static let monthNames: [String: Int] = [
        "oca": 1, "ocak": 1, "sub": 2, "subat": 2, "mar": 3, "mart": 3, "nis": 4, "nisan": 4, "may": 5, "mayis": 5,
        "haz": 6, "haziran": 6, "tem": 7, "temmuz": 7, "agu": 8, "agustos": 8, "eyl": 9, "eylul": 9, "eki": 10, "ekim": 10,
        "kas": 11, "kasim": 11, "ara": 12, "aralik": 12,
        "jan": 1, "january": 1, "feb": 2, "february": 2, "march": 3, "apr": 4, "april": 4, "jun": 6, "june": 6,
        "jul": 7, "july": 7, "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10,
        "nov": 11, "november": 11, "dec": 12, "december": 12,
    ]

    static func month(_ word: String) -> Int? {
        let folded = word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "ı", with: "i")
            .lowercased()
        return monthNames[folded]
    }

    static func matches(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// Üst üste binebilen eşleşmeler: her eşleşmeden sonra bir karakter ileriden aranır. Ay adı olmayan bir
    /// kelimeyle ("15:00 Cmt, 14 Kas" içindeki "00 Cmt, 14") gerçek tarihin ("14 Kas") yutulmaması için.
    static func overlappingMatches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let length = (text as NSString).length
        var result: [NSTextCheckingResult] = []
        var location = 0
        while location < length,
              let m = regex.firstMatch(in: text, range: NSRange(location: location, length: length - location)) {
            result.append(m)
            location = m.range.location + 1
        }
        return result
    }

    static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    static func findDates(in text: String, now: Date, calendar: Calendar) -> [DayToken] {
        var tokens: [DayToken] = []
        let currentYear = calendar.component(.year, from: now)

        func add(day: Int, month: Int, year: Int?, range: NSRange, weekday: Int? = nil) {
            guard (1...12).contains(month), (1...31).contains(day) else { return }
            var resolvedYear = year.map { $0 < 100 ? 2000 + $0 : $0 } ?? currentYear
            if year == nil, let candidate = calendar.date(from: DateComponents(year: resolvedYear, month: month, day: day)),
               candidate < calendar.date(byAdding: .day, value: -30, to: now) ?? now {
                resolvedYear += 1
            }
            // Yıl yazılmamış ama gün adı varsa ("17 Haziran Çarşamba"), o güne denk gelen en yakın yıl.
            if year == nil, let wanted = weekday {
                let candidates = [resolvedYear, resolvedYear - 1, resolvedYear + 1, resolvedYear - 2]
                for candidateYear in candidates {
                    guard let date = calendar.date(from: DateComponents(year: candidateYear, month: month, day: day)),
                          calendar.component(.weekday, from: date) == wanted else { continue }
                    resolvedYear = candidateYear
                    break
                }
            }
            guard calendar.date(from: DateComponents(year: resolvedYear, month: month, day: day)) != nil else { return }
            if tokens.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) { return }
            tokens.append(DayToken(year: resolvedYear, month: month, day: day, range: range))
        }

        // 2026-10-12
        for m in matches(#"\b(\d{4})-(\d{2})-(\d{2})\b"#, in: text) {
            add(day: Int(group(m, 3, in: text)!)!, month: Int(group(m, 2, in: text)!)!, year: Int(group(m, 1, in: text)!), range: m.range)
        }
        // 12.10.2026, 12/10/26, 12-10-2026
        for m in matches(#"\b(\d{1,2})[./-](\d{1,2})[./-](\d{4}|\d{2})\b"#, in: text) {
            add(day: Int(group(m, 1, in: text)!)!, month: Int(group(m, 2, in: text)!)!, year: Int(group(m, 3, in: text)!), range: m.range)
        }
        // 12 Eki 2026, 12OCT26, 12 October
        let word = "([A-Za-zÇĞİÖŞÜçğıöşü]{3,9})"
        for m in overlappingMatches(#"\b(\d{1,2})\s?"# + word + #"\.?,?\s?(\d{4}|\d{2}(?![:.\d]))?"#, in: text) {
            guard let monthValue = month(group(m, 2, in: text) ?? "") else { continue }
            add(day: Int(group(m, 1, in: text)!)!, month: monthValue, year: group(m, 3, in: text).flatMap { Int($0) }, range: m.range,
                weekday: weekday(after: m.range, in: text) ?? weekday(before: m.range, in: text))
        }
        // Oct 12, 2026
        for m in matches(word + #"\.?\s(\d{1,2}),?\s(\d{4})\b"#, in: text) {
            guard let monthValue = month(group(m, 1, in: text) ?? "") else { continue }
            add(day: Int(group(m, 2, in: text)!)!, month: monthValue, year: Int(group(m, 3, in: text)!), range: m.range)
        }
        // Nov 14 (yılsız, Airbnb)
        for m in overlappingMatches(word + #"\.?\s(\d{1,2})\b(?![:.]\d)"#, in: text) {
            guard let monthValue = month(group(m, 1, in: text) ?? "") else { continue }
            add(day: Int(group(m, 2, in: text)!)!, month: monthValue, year: nil, range: m.range,
                weekday: weekday(before: m.range, in: text))
        }
        return tokens.sorted { $0.range.location < $1.range.location }
    }

    static let weekdayNames: [String: Int] = [
        "pazar": 1, "pazartesi": 2, "sali": 3, "carsamba": 4, "persembe": 5, "cuma": 6, "cumartesi": 7,
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
        "paz": 1, "pzt": 2, "sal": 3, "car": 4, "per": 5, "cum": 6, "cmt": 7,
        "sun": 1, "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6, "sat": 7,
    ]

    static func weekday(named word: String) -> Int? {
        let folded = word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "ı", with: "i").lowercased()
        return weekdayNames[folded]
    }

    /// Tarihten hemen önce yazan gün adı ("Sat, Nov 14", "Cmt, 14 Kas").
    static func weekday(before range: NSRange, in text: String) -> Int? {
        let start = max(0, range.location - 14)
        let preceding = (text as NSString).substring(with: NSRange(location: start, length: range.location - start))
        guard let m = matches(#"([A-Za-zÇĞİÖŞÜçğıöşü]{3,10})\.?[\s,]*$"#, in: preceding).first,
              let word = group(m, 1, in: preceding) else { return nil }
        return weekday(named: word)
    }

    /// Tarihten hemen sonra (aynı ya da sonraki satırda) yazan gün adı.
    static func weekday(after range: NSRange, in text: String) -> Int? {
        let end = range.location + range.length
        let length = min(24, (text as NSString).length - end)
        guard length > 0 else { return nil }
        let following = (text as NSString).substring(with: NSRange(location: end, length: length))
        guard let m = matches(#"^[\s,(]*([A-Za-zÇĞİÖŞÜçğıöşü]{4,10})"#, in: following).first,
              let word = group(m, 1, in: following) else { return nil }
        return weekday(named: word)
    }

    static func findTimes(in text: String, excluding excluded: [NSRange]) -> [TimeToken] {
        // 24 saat ("15:00") ya da 12 saat ("3:00 PM", Airbnb).
        matches(#"\b([01]?\d|2[0-3]):([0-5]\d)(?:\s?([AaPp])\.?[Mm]\b\.?)?"#, in: text).compactMap { m in
            guard !excluded.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) else { return nil }
            var hour = Int(group(m, 1, in: text)!)!
            switch group(m, 3, in: text)?.lowercased() {
            case "p"? where hour < 12: hour += 12
            case "a"? where hour == 12: hour = 0
            default: break
            }
            return TimeToken(hour: hour, minute: Int(group(m, 2, in: text)!)!, range: m.range)
        }
    }

    static func date(_ day: DayToken, hour: Int, minute: Int, timeZone: String?, calendar: Calendar) -> Date? {
        var cal = calendar
        if let zone = timeZone.flatMap(TimeZone.init(identifier:)) { cal.timeZone = zone }
        return cal.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute))
    }

    // MARK: - Flights

    /// Bilinen havayolu kodları (yanlış eşleşmeleri azaltmak için).
    static let airlines: Set<String> = [
        "TK", "PC", "VF", "XQ", "AJ", "KK", "FR", "U2", "W6", "W4", "LH", "AF", "KL", "BA", "IB", "VY", "TP", "LX", "OS",
        "SN", "AZ", "A3", "LO", "SK", "AY", "EI", "EK", "QR", "EY", "KC", "J2", "PS", "B2", "FZ", "G9", "UA", "DL", "AA",
        "AC", "JL", "NH", "TG", "SQ", "EW", "HV", "DY", "LS", "OU", "JU", "RO", "FB", "4U", "8Q", "ZF", "WK", "BT", "OK",
    ]

    static func flights(in text: String, dates: [DayToken], times: [TimeToken], calendar: Calendar) -> [FlightCandidate] {
        let labelled = labelledFlights(in: text, calendar: calendar)
        if !labelled.isEmpty { return labelled }
        let upper = text.uppercased(with: Locale(identifier: "en_US"))
        let numbers = matches(#"\b([A-Z0-9]{2})\s?(\d{2,4})\b"#, in: upper).compactMap { m -> (code: String, range: NSRange)? in
            guard let airline = group(m, 1, in: upper), airlines.contains(airline),
                  airline.contains(where: \.isLetter), let digits = group(m, 2, in: upper) else { return nil }
            return (airline + digits, m.range)
        }
        let routes = routes(in: upper)
        guard !numbers.isEmpty, !routes.isEmpty else { return [] }

        var result: [FlightCandidate] = []
        for (index, number) in numbers.enumerated() {
            let blockEnd = index + 1 < numbers.count ? numbers[index + 1].range.location : (upper as NSString).length
            let previousEnd = index > 0 ? numbers[index - 1].range.location + numbers[index - 1].range.length : 0
            let blockStart = max(previousEnd, number.range.location - 160)

            // Önce uçuş numarasından sonrasına bakılır (genelde rota/tarih/saat onu izler), yoksa öncesine.
            func pick<T>(_ items: [T], location: (T) -> Int) -> T? {
                items.first { location($0) >= number.range.location && location($0) < blockEnd }
                    ?? items.last { location($0) >= blockStart && location($0) < number.range.location }
            }
            guard let route = pick(routes, location: { $0.range.location }),
                  let day = pick(dates, location: { $0.range.location }) else { continue }

            var blockTimes = times.filter { $0.range.location >= number.range.location && $0.range.location < blockEnd }
            if blockTimes.count < 2 {
                let anchor = min(number.range.location, route.range.location, day.range.location)
                blockTimes = times.filter { $0.range.location >= anchor && $0.range.location < blockEnd }
            }
            let from = Airports.airport(route.from)
            let to = Airports.airport(route.to)
            let hasTimes = blockTimes.count >= 2
            let depTime = blockTimes.first.map { ($0.hour, $0.minute) } ?? (12, 0)
            guard let departure = date(day, hour: depTime.0, minute: depTime.1, timeZone: from?.timeZone, calendar: calendar)
            else { continue }
            let arrival: Date
            if hasTimes, var arr = date(day, hour: blockTimes[1].hour, minute: blockTimes[1].minute,
                                        timeZone: to?.timeZone, calendar: calendar) {
                if arr <= departure { arr = arr.addingTimeInterval(24 * 3600) }
                arrival = arr
            } else {
                arrival = departure.addingTimeInterval(3 * 3600)
            }
            let blockText = (upper as NSString).substring(with: NSRange(location: number.range.location,
                                                                        length: blockEnd - number.range.location))
            let seat = matches(#"(?:SEAT|KOLTUK)\s*(?:NO\.?)?\s*[:#]?\s*(\d{1,2}[A-K])\b"#, in: blockText)
                .first.flatMap { group($0, 1, in: blockText) }

            let candidate = FlightCandidate(flightNumber: number.code, fromCode: route.from, toCode: route.to,
                                            departure: departure, arrival: arrival, hasTimes: hasTimes, seat: seat)
            if !result.contains(where: { $0.flightNumber == candidate.flightNumber
                && calendar.isDate($0.departure, inSameDayAs: candidate.departure) }) {
                result.append(candidate)
            }
        }
        return result
    }

    /// Etiketli e-bilet (Pegasus, THY ve benzeri; Türkçe/İngilizce): her uçuş "Nereden/From … ( SAW )" ile başlar,
    /// içinde "Nereye/To", "Kalkış Zamanı/Departure time", "Varış Zamanı/Arrival time", "Uçuş No/Flight no.",
    /// "Koltuk/Seat" etiketleri vardır. Etiketler yoksa boş döner.
    static func labelledFlights(in text: String, calendar: Calendar) -> [FlightCandidate] {
        let plain = text.replacingOccurrences(of: "İ", with: "I").replacingOccurrences(of: "ı", with: "i")
        let ns = plain as NSString
        let code = #"\(\s*([A-Z]{3})\s*\)"#
        let origins = matches(#"(?:Nereden|\bFrom)\b[^()]{0,90}?"# + code, in: plain, options: .caseInsensitive)
        guard !origins.isEmpty else { return [] }

        var result: [FlightCandidate] = []
        for (index, origin) in origins.enumerated() {
            let start = origin.range.location
            let end = index + 1 < origins.count ? origins[index + 1].range.location : ns.length
            let block = ns.substring(with: NSRange(location: start, length: end - start))
            guard let from = group(origin, 1, in: plain)?.uppercased(),
                  let to = matches(#"(?:Nereye|\bTo)\b[^()]{0,90}?"# + code, in: block, options: .caseInsensitive)
                    .first.flatMap({ group($0, 1, in: block)?.uppercased() }),
                  from != to else { continue }

            // "08/08/2026 - 06:30" ya da "08.08.2026 06:30"
            func moment(after labels: String, airport: String) -> Date? {
                let pattern = labels + #"[^\d]{0,60}?(\d{1,2})[./](\d{1,2})[./](\d{4})\s*[-–,]?\s*(\d{1,2}):(\d{2})"#
                guard let m = matches(pattern, in: block, options: .caseInsensitive).first,
                      let day = group(m, 1, in: block).flatMap(Int.init), let month = group(m, 2, in: block).flatMap(Int.init),
                      let year = group(m, 3, in: block).flatMap(Int.init), let hour = group(m, 4, in: block).flatMap(Int.init),
                      let minute = group(m, 5, in: block).flatMap(Int.init) else { return nil }
                return date(DayToken(year: year, month: month, day: day, range: m.range), hour: hour, minute: minute,
                            timeZone: Airports.airport(airport)?.timeZone, calendar: calendar)
            }
            guard let departure = moment(after: #"(?:Kalkis Zamani|Kalkis Saati|Departure time|Departure)"#, airport: from)
            else { continue }
            let arrival = moment(after: #"(?:Varis Zamani|Varis Saati|Arrival time|Arrival)"#, airport: to)
            let number = matches(#"(?:Ucus No|Uçuş No|Flight no\.?|Flight)\s*[:#]?\s*(?:Flight no\.?\s*)?([A-Z0-9]{2})\s?(\d{1,4})\b"#,
                                 in: block, options: .caseInsensitive)
                .first.flatMap { m in group(m, 1, in: block).flatMap { a in group(m, 2, in: block).map { (a + $0).uppercased() } } }
                ?? PassParser.flightNumber(in: block)
            guard let number else { continue }
            let seat = matches(#"(?:Koltuk|Seat)\s*(?:Seat)?\s*[:#]?\s*(\d{1,2}[A-K])\b"#, in: block, options: .caseInsensitive)
                .first.flatMap { group($0, 1, in: block)?.uppercased() }
            let estimated = Airports.estimatedFlightMinutes(from: from, to: to).map { departure.addingTimeInterval(Double($0) * 60) }
            result.append(FlightCandidate(flightNumber: number, fromCode: from, toCode: to, departure: departure,
                                          arrival: arrival.map { $0 > departure ? $0 : $0.addingTimeInterval(86_400) }
                                            ?? estimated ?? departure.addingTimeInterval(3 * 3600),
                                          hasTimes: arrival != nil, seat: seat))
        }
        return result
    }

    struct Route {
        var from: String
        var to: String
        var range: NSRange
    }

    /// Üç harfli iki kod güzergâh mı: biri sık uçulan havalimanı ya da ikisi de bilinen havalimanı olmalı
    /// (büyük tabloda "PNR", "TKT" gibi kısaltmalar da tek başına havalimanı kodu olabiliyor).
    static func looksLikeRoute(_ a: String, _ b: String) -> Bool {
        Airports.isCommon(a) || Airports.isCommon(b) || (Airports.airport(a) != nil && Airports.airport(b) != nil)
    }

    static func routes(in upper: String) -> [Route] {
        var routes: [Route] = []
        // IST - LIS, SAW→BCN, IST/LIS
        for m in matches(#"\b([A-Z]{3})\s?(?:-|–|—|→|>|/|TO)\s?([A-Z]{3})\b"#, in: upper) {
            guard let a = group(m, 1, in: upper), let b = group(m, 2, in: upper),
                  looksLikeRoute(a, b), a != b else { continue }
            routes.append(Route(from: a, to: b, range: m.range))
        }
        // İstanbul (IST) ... Lizbon (LIS): aynı satırda ya da art arda iki parantezli kod
        let codes = matches(#"\(([A-Z]{3})\)"#, in: upper).compactMap { m -> (String, NSRange)? in
            group(m, 1, in: upper).map { ($0, m.range) }
        }
        for pair in zip(codes, codes.dropFirst()) where pair.0.0 != pair.1.0 {
            let gap = pair.1.1.location - (pair.0.1.location + pair.0.1.length)
            guard gap < 80, looksLikeRoute(pair.0.0, pair.1.0),
                  !routes.contains(where: { NSIntersectionRange($0.range, pair.0.1).length > 0 }) else { continue }
            routes.append(Route(from: pair.0.0, to: pair.1.0, range: pair.0.1))
        }
        return routes.sorted { $0.range.location < $1.range.location }
    }

    // MARK: - Lodging

    static func lodgings(in text: String, dates: [DayToken], times: [TimeToken], calendar: Calendar) -> [LodgingCandidate] {
        let checkInWords = #"(?:check[\s-]?[iİı]n|giriş tarihi|giriş|arrival|varış tarihi)"#
        let checkOutWords = #"(?:check[\s-]?out|çıkış tarihi|çıkış|ayrılış)"#
        // "15:00 - 00:00" gibi aralıklarda girişte başlangıç, çıkışta bitiş saati geçerlidir ("00:00 - 11:00").
        guard let checkInKey = matches(checkInWords, in: text, options: .caseInsensitive).first,
              let checkOutKey = matches(checkOutWords, in: text, options: .caseInsensitive).first else { return [] }

        func dateAfter(_ key: NSTextCheckingResult) -> DayToken? {
            let end = key.range.location + key.range.length
            return dates.first { $0.range.location >= end && $0.range.location - end < 80 }
        }
        func timeAfter(_ day: DayToken) -> TimeToken? {
            let end = day.range.location + day.range.length
            return times.first { $0.range.location >= end && $0.range.location - end < 40 }
        }
        guard let inDay = dateAfter(checkInKey), let outDay = dateAfter(checkOutKey) else { return [] }
        // Airbnb saati tarihten önce yazar ("Check-in / 3:00 PM / Sat, Nov 14").
        func time(for key: NSTextCheckingResult, _ day: DayToken) -> TimeToken? {
            let end = key.range.location + key.range.length
            return times.first { $0.range.location >= end && $0.range.location < day.range.location } ?? timeAfter(day)
        }
        func rangeEnd(_ time: TimeToken) -> TimeToken {
            let end = time.range.location + time.range.length
            guard let next = times.first(where: { $0.range.location > end && $0.range.location - end <= 4 }) else { return time }
            let between = (text as NSString).substring(with: NSRange(location: end, length: next.range.location - end))
            return between.trimmingCharacters(in: .whitespaces).allSatisfy { "-–—".contains($0) } ? next : time
        }
        let inTime = time(for: checkInKey, inDay).map { ($0.hour, $0.minute) } ?? (14, 0)
        let outTime = time(for: checkOutKey, outDay).map(rangeEnd).map { ($0.hour, $0.minute) } ?? (11, 0)
        guard let checkIn = date(inDay, hour: inTime.0, minute: inTime.1, timeZone: nil, calendar: calendar),
              let checkOut = date(outDay, hour: outTime.0, minute: outTime.1, timeZone: nil, calendar: calendar),
              checkOut > checkIn else { return [] }

        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let addressIndex = lines.firstIndex { $0.lowercased().hasPrefix("adres") || $0.lowercased().hasPrefix("address") }
        let lodgingPattern = #"\b(hotel|otel|hostel|apart|apartments?|residence|suites?|inn|resort|pansiyon|guesthouse|lodge|palace|studios?|flat|loft|villa|daire)\b"#
        let skipWords = ["booking.com", "airbnb", "check", "giriş", "çıkış", "confirmation", "rezervasyon", "onay",
                         "call host", "ev sahibi", "hosted by"]
        func plausibleName(_ line: String) -> String? {
            let lower = line.lowercased()
            return line.count <= 60 && !line.contains(":") && !line.hasPrefix("+") && line.contains(where: \.isLetter)
                && !skipWords.contains { lower.contains($0) } ? line : nil
        }
        // Booking.com: tesis adı adres satırının hemen üstünde.
        let aboveAddress = addressIndex.flatMap { $0 > 0 ? lines[$0 - 1] : nil }.flatMap(plausibleName)
        // Airbnb: ilan adı giriş bilgisinin hemen üstünde.
        let aboveCheckIn = (text as NSString).substring(to: checkInKey.range.location)
            .split(separator: "\n").last.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap(plausibleName)
        let name = aboveAddress ?? aboveCheckIn ?? lines.first { line in
            let lower = line.lowercased()
            return line.count <= 60 && !matches(lodgingPattern, in: line, options: .caseInsensitive).isEmpty
                && !skipWords.contains { lower.contains($0) }
        } ?? "Konaklama"

        // Adres birkaç satıra bölünebilir: satır virgülle bitiyorsa devamı sonraki satırdadır.
        var address = ""
        if let addressIndex {
            address = lines[addressIndex].split(separator: ":", maxSplits: 1).dropFirst().first
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            var next = addressIndex + 1
            while address.hasSuffix(","), next < lines.count, !lines[next].contains(":"), lines[next].count <= 60 {
                address += " " + lines[next]
                next += 1
            }
        } else {
            // Etiketsiz adres (Airbnb): en az iki virgül ve bir sayı içeren satır.
            address = lines.first { line in
                line.count <= 120 && line.filter { $0 == "," }.count >= 2 && line.contains(where: \.isNumber)
                    && !line.contains(":") && !line.hasPrefix("+")
            } ?? ""
        }

        // "ONAY NUMARASI", "PİN KODU": büyük Türkçe I/İ küçük harfe eşlenmez; aynı uzunlukta sadeleştirilir.
        let plain = text.replacingOccurrences(of: "İ", with: "I").replacingOccurrences(of: "ı", with: "i")
        let labelled = #"(?:onay numarasi|onay kodu|confirmation number|confirmation code|booking number|reservation number|rezervasyon (?:no|numarasi|kodu))\s*[:#]?\s*([A-Z0-9][A-Z0-9.\- ]{3,20}[A-Z0-9])"#
        let confirmationPattern = #"(?:confirmation|booking|reservation|rezervasyon|onay|pnr)\s*(?:number|no\.?|numarasi|kodu|code|id)?\s*[:#]?\s*([A-Z0-9]{5,14})\b"#
        let confirmation = (matches(labelled, in: plain, options: .caseInsensitive) + matches(confirmationPattern, in: plain, options: .caseInsensitive))
            .compactMap { group($0, 1, in: plain)?.filter { $0.isLetter || $0.isNumber } }
            .first { $0.count >= 5 && $0.contains(where: \.isNumber) } ?? ""

        let pin = matches(#"\b(?:pin(?: kodu| code)?|kapi kodu|door code)\s*[:#]?\s*(\d{4,8})\b"#, in: plain, options: .caseInsensitive)
            .first.flatMap { group($0, 1, in: plain) }

        let total = matches(#"(?:total cost|total|toplam(?: tutar| maliyet| fiyat)?|fiyat|price)\s*:?\s*(?:yaklaşık|approx(?:imately)?\.?)?\s*([€$£₺]\s?[\d.,]*\d|(?:TL|EUR|USD|GBP|DKK|HUF)\s?[\d.,]*\d|\d[\d.,]*\s?(?:TL|EUR|USD|GBP|DKK|HUF|₺|€))"#,
                            in: text, options: .caseInsensitive).first.flatMap { group($0, 1, in: text) }
        let note = [pin.map { "PIN: \($0)" }, total.map { String(localized: "Toplam: \($0)") }].compactMap { $0 }
            .joined(separator: " · ")
        return [LodgingCandidate(name: name, address: address, checkIn: checkIn, checkOut: checkOut, confirmation: confirmation,
                                 coordinate: coordinate(in: text), note: note)]
    }

    /// "N 055° 39.954, E 12° 33.915" (derece + ondalık dakika) ya da "GPS: 55.66590, 12.56525".
    static func coordinate(in text: String) -> Coordinate? {
        let dm = #"([NS])\s*(\d{1,3})°\s*(\d{1,2}(?:[.,]\d+)?)['′]?\s*,?\s*([EWDB])\s*(\d{1,3})°\s*(\d{1,2}(?:[.,]\d+)?)"#
        if let m = matches(dm, in: text).first {
            func value(_ degrees: Int, _ minutes: Int) -> Double? {
                guard let d = group(m, degrees, in: text).flatMap(Double.init),
                      let min = group(m, minutes, in: text).flatMap({ Double($0.replacingOccurrences(of: ",", with: ".")) })
                else { return nil }
                return d + min / 60
            }
            guard var lat = value(2, 3), var lon = value(5, 6) else { return nil }
            if group(m, 1, in: text) == "S" { lat = -lat }
            if ["W", "B"].contains(group(m, 4, in: text)) { lon = -lon }
            return (-90...90).contains(lat) && (-180...180).contains(lon) ? Coordinate(latitude: lat, longitude: lon) : nil
        }
        let decimal = #"(?:gps|koordinat|coordinates?)[^\n\d-]{0,20}(-?\d{1,2}\.\d{3,})\s*,\s*(-?\d{1,3}\.\d{3,})"#
        if let m = matches(decimal, in: text, options: .caseInsensitive).first,
           let lat = group(m, 1, in: text).flatMap(Double.init), let lon = group(m, 2, in: text).flatMap(Double.init),
           (-90...90).contains(lat), (-180...180).contains(lon) {
            return Coordinate(latitude: lat, longitude: lon)
        }
        return nil
    }
}

extension BookingParser.Result {
    /// Belgenin ait olduğu seyahat: ilk uçuşun ya da girişin tarihi seyahat tarihlerine (gidişten 2 gün önce,
    /// dönüşten 1 gün sonraya kadar) düşen seyahat; birden çoksa başlangıcı en yakın olan.
    public func matchingTrip(in trips: [Trip], calendar: Calendar = .current) -> Trip? {
        guard let date = (flights.map(\.departure) + lodgings.map(\.checkIn)).min() else { return nil }
        let day = calendar.startOfDay(for: date)
        return trips.filter { trip in
            guard let from = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: trip.startDate)),
                  let to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: trip.endDate)) else { return false }
            return (from...to).contains(day)
        }.min { abs($0.startDate.timeIntervalSince(day)) < abs($1.startDate.timeIntervalSince(day)) }
    }
}
