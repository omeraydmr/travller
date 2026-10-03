import Foundation

/// Uygulama ile widget eklentisinin ortak klasörü (App Group).
enum SharedContainer {
    static let groupID = "group.com.omeraydemir.stubly"
    static let widgetKind = "TripCountdownWidget"

    /// Widget özetinin JSON dosyası; App Group yetkisi yoksa nil.
    static var snapshotURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("widget-snapshot.json")
    }
}
