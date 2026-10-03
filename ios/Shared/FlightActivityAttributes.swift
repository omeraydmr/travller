import ActivityKit
import Foundation

/// Kilit ekranı ve Dynamic Island'daki uçuş kartının verisi (uygulama ve widget eklentisi ortak kullanır).
struct FlightActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var gate: String?
        var seat: String?
        /// Saate göre kısa durum: "Zamanında", "Biniş", "Havada".
        var status: String
        /// Kalkış ve varış; geri sayım kalkışa göre.
        var departure: Date
        var arrival: Date
    }

    var tripID: String
    var tripName: String
    var flightNumber: String
    var fromCode: String
    var fromCity: String
    var toCode: String
    var toCity: String
    /// Seyahat renginin onaltılık değeri (0xRRGGBB).
    var tint: UInt32
}
