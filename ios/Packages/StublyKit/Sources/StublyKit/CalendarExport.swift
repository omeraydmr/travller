import Foundation

/// Seyahatin takvime aktarılacak etkinlikleri: uçuşlar, otel giriş/çıkışları ve saati belli duraklar.
/// Her etkinliğin kalıcı anahtarı var; yeniden aktarınca eskisi silinip güncel hali yazılır.
public enum CalendarExport {
    public struct Event: Hashable, Sendable {
        /// "flight-<id>", "checkin-<id>", "checkout-<id>", "stop-<id>"
        public var key: String
        public var title: String
        public var start: Date
        public var end: Date
        /// Saatlerin gösterileceği saat dilimi (uçuşlarda kalkış havalimanı).
        public var timeZone: String?
        public var location: String?
        public var coordinate: Coordinate?
        public var notes: String
    }

    public static func events(for trip: Trip, calendar: Calendar = .current) -> [Event] {
        var result: [Event] = []
        for flight in trip.flights {
            var details = [String]()
            if let seat = flight.seat { details.append(String(localized: "Koltuk \(seat)")) }
            if let gate = flight.gate { details.append(String(localized: "Kapı \(gate)")) }
            result.append(Event(key: "flight-\(flight.id.uuidString)",
                                title: "✈︎ \(flight.flightNumber) \(flight.fromCode) → \(flight.toCode)",
                                start: flight.departure, end: max(flight.arrival, flight.departure.addingTimeInterval(1800)),
                                timeZone: flight.departureTimeZone ?? Airports.airport(flight.fromCode)?.timeZone,
                                location: "\(flight.fromCity) (\(flight.fromCode))", coordinate: Airports.airport(flight.fromCode)?.coordinate,
                                notes: details.joined(separator: " · ")))
        }
        for lodging in trip.lodgingList {
            let place = lodging.address.isEmpty ? lodging.name : "\(lodging.name), \(lodging.address)"
            var notes = [String]()
            if !lodging.confirmation.isEmpty { notes.append(String(localized: "Rezervasyon \(lodging.confirmation)")) }
            if !lodging.note.isEmpty { notes.append(lodging.note) }
            result.append(Event(key: "checkin-\(lodging.id.uuidString)", title: String(localized: "Otel girişi: \(lodging.name)"),
                                start: lodging.checkIn, end: lodging.checkIn.addingTimeInterval(1800), timeZone: nil,
                                location: place, coordinate: lodging.coordinate, notes: notes.joined(separator: "\n")))
            result.append(Event(key: "checkout-\(lodging.id.uuidString)", title: String(localized: "Otel çıkışı: \(lodging.name)"),
                                start: lodging.checkOut, end: lodging.checkOut.addingTimeInterval(1800), timeZone: nil,
                                location: place, coordinate: lodging.coordinate, notes: notes.joined(separator: "\n")))
        }
        for stop in trip.stops where stop.kind != .transport {
            guard let minutes = stop.startMinutes,
                  let start = calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: stop.day)) else { continue }
            result.append(Event(key: "stop-\(stop.id.uuidString)", title: stop.name, start: start,
                                end: start.addingTimeInterval(Double(max(15, stop.durationMinutes)) * 60), timeZone: nil,
                                location: stop.name, coordinate: stop.coordinate, notes: stop.note))
        }
        return result.sorted { $0.start < $1.start }
    }
}
