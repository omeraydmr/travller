import Foundation

/// Pasaport ve eldeki vizelerin süresi dolmadan önceki hatırlatmalar (yerel bildirim planı; seyahatten bağımsız).
public enum DocumentReminders {
    /// Pasaport bitişinden önce: 6 ay (çoğu ülke dönüşten sonra 6 ay geçerlilik ister), 3 ay, 1 ay.
    static let passportLeadMonths = [6, 3, 1]
    /// Vize bitişinden önce: 2 ay, 2 hafta.
    static let visaLeadDays = [60, 14]

    public static func plan(passport: Passport?, trips: [Trip], now: Date = Date(),
                            calendar: Calendar = .current) -> [PlannedNotification] {
        guard let passport else { return [] }
        let upcoming = trips.filter { $0.status == .planned && $0.startDate > now }.sorted { $0.startDate < $1.startDate }
        let link = upcoming.first.map { TripLink(tripID: $0.id, section: "visa") }
        var result: [PlannedNotification] = []

        func morning(_ date: Date) -> Date? {
            calendar.date(bySettingHour: 9, minute: 30, second: 0, of: date)
        }
        func add(_ id: String, _ date: Date?, _ title: String, _ body: String, link: TripLink?) {
            guard let date, let at = morning(date), at > now else { return }
            result.append(PlannedNotification(id: "doc-\(id)", date: at, title: title, body: body, link: link))
        }

        let expiry = format(passport.expiresOn, calendar: calendar)
        for months in passportLeadMonths {
            add("passport-\(months)m", calendar.date(byAdding: .month, value: -months, to: passport.expiresOn),
                months == 1 ? String(localized: "Pasaportunun süresi 1 ay sonra doluyor")
                            : String(localized: "Pasaportunun süresi \(months) ay sonra doluyor"),
                String(localized: "Bitiş: \(expiry). Yenilemek için randevu almayı unutma; birçok ülke dönüşten sonra 6 ay geçerlilik ister."),
                link: link)
        }

        // Yaklaşan seyahatte pasaport yetmiyorsa gidişten 60 gün önce (geçtiyse yarın) uyar.
        for trip in upcoming {
            let abroad = trip.countryCodes.filter { $0 != passport.nationality.uppercased() }
            guard abroad.contains(where: { country in
                !VisaAdvisor.passportWarnings(passport: passport, entry: VisaRules.entry(for: country), tripEnd: trip.endDate,
                                              calendar: calendar).isEmpty
            }) else { continue }
            let lead = calendar.date(byAdding: .day, value: -60, to: trip.startDate) ?? trip.startDate
            let when = lead > now ? lead : calendar.date(byAdding: .day, value: 1, to: now)
            add("passport-trip-\(trip.id.uuidString)", when,
                String(localized: "Pasaportun \(trip.name) için yeterince geçerli değil"),
                String(localized: "Bitiş: \(expiry). Vize sekmesinde gereken geçerlilik süresini gör."),
                link: TripLink(tripID: trip.id, section: "visa"))
        }

        for visa in passport.heldVisas {
            let until = format(visa.validUntil, calendar: calendar)
            for days in visaLeadDays {
                add("visa-\(visa.id.uuidString)-\(days)", calendar.date(byAdding: .day, value: -days, to: visa.validUntil),
                    days >= 30 ? String(localized: "\(zoneName(visa.zone)) vizen 2 ay sonra bitiyor")
                               : String(localized: "\(zoneName(visa.zone)) vizen 2 hafta sonra bitiyor"),
                    String(localized: "Geçerlilik: \(until). Yeni seyahat planlıyorsan başvuruyu erken yap."),
                    link: link)
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    static func zoneName(_ zone: VisaZone) -> String {
        switch zone {
        case .schengen: "Schengen"
        case .uk: String(localized: "Birleşik Krallık")
        case .us: String(localized: "ABD")
        case .canada: String(localized: "Kanada")
        }
    }

    static func format(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
