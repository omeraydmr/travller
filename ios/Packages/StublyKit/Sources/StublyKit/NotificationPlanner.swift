import Foundation

/// Seyahat için yerel bildirim planı (saf mantık; zamanlama uygulamada yapılır).
public struct PlannedNotification: Hashable, Sendable {
    /// "trip-<id>-<tür>" ya da belge hatırlatmaları için "doc-<tür>"; değişince aynı kimlikle yeniden kurulur.
    public var id: String
    public var date: Date
    public var title: String
    public var body: String
    /// Dokununca açılacak seyahat ve sekme (`TripLink`); yoksa uygulama açılır.
    public var link: TripLink?
}

public enum NotificationPlanner {
    /// iOS en fazla 64 bekleyen bildirime izin verir; seyahat başına bundan azını kullan.
    public static let perTripLimit = 20

    public static func plan(for trip: Trip, now: Date = Date(), calendar: Calendar = .current) -> [PlannedNotification] {
        guard trip.status == .planned else { return [] }
        var result: [PlannedNotification] = []
        let prefix = "trip-\(trip.id.uuidString)"
        let days = trip.days(calendar: calendar)
        guard let firstDay = days.first else { return [] }

        // Gitmeden önceki akşam: valiz durumu.
        if let eve = at(hour: 20, minute: 0, on: calendar.date(byAdding: .day, value: -1, to: firstDay), calendar) {
            let missing = trip.packing.filter { !$0.isPacked }.count
            let body = missing == 0
                ? String(localized: "Valiz hazır görünüyor. İyi yolculuklar!")
                : String(localized: "Valizde \(missing) madde eksik. Son kontrol için iyi bir zaman.")
            result.append(PlannedNotification(id: "\(prefix)-eve", date: eve, title: String(localized: "Yarın \(trip.destination.city)!"), body: body,
                                              link: TripLink(tripID: trip.id, section: "packing")))
        }

        // Uçuştan 3 saat önce.
        if let flight = trip.primaryFlight,
           let reminder = calendar.date(byAdding: .hour, value: -3, to: flight.departure) {
            var details = ["\(flight.fromCode) → \(flight.toCode)"]
            if let gate = flight.gate { details.append(String(localized: "kapı \(gate)")) }
            if let seat = flight.seat { details.append(String(localized: "koltuk \(seat)")) }
            result.append(PlannedNotification(id: "\(prefix)-flight", date: reminder,
                                              title: String(localized: "Uçuş \(flight.flightNumber) · 3 saat kaldı"),
                                              body: details.joined(separator: " · "),
                                              link: TripLink(tripID: trip.id, section: "plan")))
        }

        // Konaklama: giriş günü sabahı ve çıkış günü sabahı.
        for lodging in trip.lodgingList {
            let checkInClock = String(format: "%02d:%02d", calendar.component(.hour, from: lodging.checkIn),
                                      calendar.component(.minute, from: lodging.checkIn))
            let checkOutClock = String(format: "%02d:%02d", calendar.component(.hour, from: lodging.checkOut),
                                       calendar.component(.minute, from: lodging.checkOut))
            if let morning = at(hour: 9, minute: 0, on: calendar.startOfDay(for: lodging.checkIn), calendar) {
                var body = String(localized: "Giriş saati \(checkInClock)")
                if !lodging.confirmation.isEmpty { body += " · rezervasyon \(lodging.confirmation)" }
                result.append(PlannedNotification(id: "\(prefix)-checkin-\(lodging.id.uuidString)", date: morning,
                                                  title: String(localized: "Bugün otel girişi: \(lodging.name)"), body: body,
                                                  link: TripLink(tripID: trip.id, section: "plan")))
            }
            if let morning = at(hour: 8, minute: 0, on: calendar.startOfDay(for: lodging.checkOut), calendar) {
                result.append(PlannedNotification(id: "\(prefix)-checkout-\(lodging.id.uuidString)", date: morning,
                                                  title: String(localized: "Bugün çıkış: \(lodging.name)"),
                                                  body: String(localized: "Çıkış saati en geç \(checkOutClock)."),
                                                  link: TripLink(tripID: trip.id, section: "plan")))
            }
        }

        // Vize randevusu: önceki akşam ve randevudan 2 saat önce.
        for application in trip.visaApplications ?? [] {
            guard let appointment = application.appointment,
                  application.status == .preparing || application.status == .appointmentBooked else { continue }
            let name = trip.member(application.memberID)?.name ?? String(localized: "Vize")
            let place = application.center.isEmpty ? "" : " · \(application.center)"
            let clock = String(format: "%02d:%02d", calendar.component(.hour, from: appointment),
                               calendar.component(.minute, from: appointment))
            if let eve = at(hour: 20, minute: 0, on: calendar.date(byAdding: .day, value: -1, to: appointment), calendar) {
                result.append(PlannedNotification(id: "\(prefix)-visa-eve-\(application.id.uuidString)", date: eve,
                                                  title: String(localized: "Yarın vize randevusu: \(name)"),
                                                  body: String(localized: "Saat \(clock)\(place). Belge listesini kontrol et."),
                                                  link: TripLink(tripID: trip.id, section: "visa")))
            }
            if let before = calendar.date(byAdding: .hour, value: -2, to: appointment) {
                result.append(PlannedNotification(id: "\(prefix)-visa-\(application.id.uuidString)", date: before,
                                                  title: String(localized: "Vize randevusu 2 saat sonra"), body: "\(name) · \(clock)\(place)",
                                                  link: TripLink(tripID: trip.id, section: "visa")))
            }
        }

        // Gidiş öncesi listesi: son günü gelen, yapılmamış maddeler (aynı gün olanlar tek bildirimde).
        var dueGroups: [Date: [ChecklistItem]] = [:]
        for item in trip.checklistItems where !item.isDone {
            if let due = DepartureChecklist.dueDate(of: item, in: trip, calendar: calendar) { dueGroups[due, default: []].append(item) }
        }
        for (due, items) in dueGroups {
            guard let morning = at(hour: 9, minute: 0, on: due, calendar) else { continue }
            let key = Int(due.timeIntervalSince1970)
            let title = items.count == 1 ? String(localized: "Bugün: \(DepartureChecklist.displayText(of: items[0], in: trip).title)") : String(localized: "Gidiş öncesi \(items.count) iş bugün")
            let body = items.count == 1 ? (items[0].note.isEmpty ? trip.name : items[0].note)
                                        : items.map { DepartureChecklist.displayText(of: $0, in: trip).title }.joined(separator: " · ")
            result.append(PlannedNotification(id: "\(prefix)-todo-\(key)", date: morning, title: title, body: body,
                                              link: TripLink(tripID: trip.id, section: "packing")))
        }

        // Tax-free: dönüş günü sabahı, gümrükte onaylatılmamış form varsa.
        let pendingForms = trip.taxRefundList.filter { $0.status == .formReceived }.count
        if pendingForms > 0, let lastDay = days.last, let morning = at(hour: 8, minute: 0, on: lastDay, calendar) {
            result.append(PlannedNotification(id: "\(prefix)-taxfree", date: morning,
                                              title: String(localized: "Tax-free formlarını onaylat"),
                                              body: String(localized: "\(pendingForms) form bekliyor; havalimanında check-in'den önce gümrüğe/kiosk'a uğra."),
                                              link: TripLink(tripID: trip.id, section: "money")))
        }

        // Her sabah günün planı.
        for (index, day) in days.enumerated() {
            let stops = trip.stops(on: day, calendar: calendar)
            guard !stops.isEmpty, let morning = at(hour: 8, minute: 30, on: day, calendar) else { continue }
            let first = stops[0]
            var body = "\(stops.count) durak"
            if let start = first.startMinutes {
                body += " · ilk durak \(first.name), \(String(format: "%02d:%02d", start / 60, start % 60))"
            } else {
                body += " · ilk durak \(first.name)"
            }
            result.append(PlannedNotification(id: "\(prefix)-day\(index)", date: morning,
                                              title: String(localized: "\(index + 1). gün · \(trip.destination(on: day, calendar: calendar).city)"), body: body,
                                              link: TripLink(tripID: trip.id, section: "plan")))
        }

        // Rezervasyonlu ya da saatli duraklardan 45 dk önce (yalnızca notu olanlar: "bilet", "rezervasyon" vb.).
        for stop in trip.stops where stop.startMinutes != nil && !stop.note.isEmpty {
            guard let start = stop.startMinutes,
                  let time = calendar.date(byAdding: .minute, value: start - 45, to: calendar.startOfDay(for: stop.day)) else { continue }
            result.append(PlannedNotification(id: "\(prefix)-stop-\(stop.id.uuidString)", date: time,
                                              title: "45 dk sonra: \(stop.name)", body: stop.note,
                                              link: TripLink(tripID: trip.id, section: "plan")))
        }

        return Array(result.filter { $0.date > now }.sorted { $0.date < $1.date }.prefix(perTripLimit))
    }

    static func at(hour: Int, minute: Int, on day: Date?, _ calendar: Calendar) -> Date? {
        guard let day else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
