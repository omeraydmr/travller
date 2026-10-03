import ActivityKit
import SwiftUI
import StublyKit

/// Seyahat günü kilit ekranındaki uçuş kartı: planlanmış saatlerle geri sayım, kapı ve koltuk. Tamamen cihazda
/// çalışır (push yok); uygulama öne geldiğinde güncellenir, uçuş inince kapanır.
@MainActor
enum LiveActivityController {
    /// Kalkıştan bu kadar önce otomatik başlatılır (canlı etkinlikler en fazla ~8 saat güncel kalır).
    static let autoStartWindow: TimeInterval = 6 * 3600

    static var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    static func isRunning(for trip: Trip) -> Bool {
        !activities(for: trip).isEmpty
    }

    /// Kalkışa 24 saatten az kaldıysa elle başlatılabilir.
    static func canStart(for trip: Trip, now: Date = .now) -> Bool {
        guard isAvailable, let flight = trip.primaryFlight else { return false }
        return flight.departure > now && flight.departure.timeIntervalSince(now) < 24 * 3600
    }

    static func start(for trip: Trip) {
        guard let flight = trip.primaryFlight, isAvailable, !isRunning(for: trip) else { return }
        let attributes = FlightActivityAttributes(
            tripID: trip.id.uuidString, tripName: trip.name, flightNumber: flight.flightNumber,
            fromCode: flight.fromCode, fromCity: flight.fromCity, toCode: flight.toCode, toCity: flight.toCity,
            tint: trip.tint.rgbHex)
        _ = try? Activity.request(attributes: attributes,
                                  content: ActivityContent(state: state(for: flight), staleDate: flight.arrival))
    }

    static func stop(for trip: Trip) {
        for activity in activities(for: trip) {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Uygulama öne geldiğinde: yaklaşan uçuşları başlat, kartı güncelle, inenleri kapat.
    static func refresh(trips: [Trip], now: Date = .now) {
        guard isAvailable else { return }
        for trip in trips {
            guard let flight = trip.primaryFlight else { continue }
            let running = activities(for: trip)
            if flight.arrival < now {
                running.forEach { activity in Task { await activity.end(nil, dismissalPolicy: .default) } }
                continue
            }
            if running.isEmpty, flight.departure > now, flight.departure.timeIntervalSince(now) < autoStartWindow {
                start(for: trip)
            }
            let latest = state(for: flight, now: now)
            for activity in running where activity.content.state != latest {
                Task { await activity.update(ActivityContent(state: latest, staleDate: flight.arrival)) }
            }
        }
    }

    static func state(for flight: FlightSegment, now: Date = .now) -> FlightActivityAttributes.ContentState {
        FlightActivityAttributes.ContentState(
            gate: flight.gate, seat: flight.seat,
            status: status(for: flight, now: now), departure: flight.departure, arrival: flight.arrival)
    }

    /// Saate göre aşama (canlı durum servisi yok; güncel durum için havayolunun uygulamasına bakılır).
    static func status(for flight: FlightSegment, now: Date = .now) -> String {
        let minutes = flight.departure.timeIntervalSince(now) / 60
        if minutes <= 0 { return String(localized: "Havada") }
        if minutes <= 40 { return String(localized: "Biniş") }
        return String(localized: "Zamanında")
    }

    private static func activities(for trip: Trip) -> [Activity<FlightActivityAttributes>] {
        Activity<FlightActivityAttributes>.activities.filter { $0.attributes.tripID == trip.id.uuidString }
    }
}
