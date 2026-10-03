import EventKit
import Foundation
import StublyKit

/// Seyahati iPhone Takvimi'ne aktarır: ayrı bir "Stubly" takvimine uçuş, otel giriş/çıkışı ve saati belli
/// duraklar yazılır. Etkinlikler seyahat bağlantısını taşır; yeniden aktarınca o seyahatin eski etkinlikleri silinir.
@MainActor
enum CalendarExporter {
    enum Failure: LocalizedError {
        case denied, noSource

        var errorDescription: String? {
            switch self {
            case .denied: String(localized: "Takvim izni verilmedi. Ayarlar > Stubly > Takvimler'den açabilirsin.")
            case .noSource: String(localized: "Takvim oluşturulamadı; iCloud ya da cihaz takvimi bulunamadı.")
            }
        }
    }

    private static let store = EKEventStore()
    private static let calendarIDKey = "stubly.calendar.id"

    /// Aktarılan etkinlik sayısı.
    static func export(_ trip: Trip) async throws -> Int {
        guard try await store.requestFullAccessToEvents() else { throw Failure.denied }
        let calendar = try stublyCalendar()

        // Bu seyahatin önceki aktarımı: bağlantısı aynı seyahati gösteren etkinlikler.
        let prefix = "stubly://trip/\(trip.id.uuidString)"
        let start = Calendar.current.date(byAdding: .day, value: -60, to: trip.startDate) ?? trip.startDate
        let end = Calendar.current.date(byAdding: .day, value: 60, to: trip.endDate) ?? trip.endDate
        let old = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: [calendar]))
            .filter { $0.url?.absoluteString.hasPrefix(prefix) == true }
        for event in old { try store.remove(event, span: .thisEvent, commit: false) }

        let drafts = CalendarExport.events(for: trip)
        for draft in drafts {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = draft.title
            event.startDate = draft.start
            event.endDate = draft.end
            event.timeZone = draft.timeZone.flatMap(TimeZone.init(identifier:))
            event.notes = draft.notes.isEmpty ? nil : draft.notes
            event.url = URL(string: "\(prefix)?section=plan&event=\(draft.key)")
            if let location = draft.location {
                let structured = EKStructuredLocation(title: location)
                if let coordinate = draft.coordinate {
                    structured.geoLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                }
                event.structuredLocation = structured
            }
            try store.save(event, span: .thisEvent, commit: false)
        }
        try store.commit()
        return drafts.count
    }

    /// "Stubly" takvimi; yoksa iCloud'da (yoksa cihazda) oluşturulur.
    private static func stublyCalendar() throws -> EKCalendar {
        if let id = UserDefaults.standard.string(forKey: calendarIDKey), let existing = store.calendar(withIdentifier: id) {
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Stubly"
        calendar.cgColor = CGColor(red: 0.95, green: 0.45, blue: 0.2, alpha: 1)
        let sources = store.sources
        guard let source = sources.first(where: { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") })
                ?? store.defaultCalendarForNewEvents?.source
                ?? sources.first(where: { $0.sourceType == .local }) else { throw Failure.noSource }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        UserDefaults.standard.set(calendar.calendarIdentifier, forKey: calendarIDKey)
        return calendar
    }
}
