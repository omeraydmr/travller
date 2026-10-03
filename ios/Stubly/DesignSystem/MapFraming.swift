import MapKit
import SwiftUI

/// Harita kamerası: noktaları kenar payıyla sığdırır ama en az bir semt genişliğinde (varsayılan ~4 km) gösterir;
/// tek nokta seçilince bina ölçeğine yakınlaşıp çevreyi kaybettirmesin.
enum MapFraming {
    static func position(_ coordinates: [CLLocationCoordinate2D], minimumSpan: CLLocationDistance = 4_000,
                         padding: Double = 1.4) -> MapCameraPosition {
        guard let first = coordinates.first else { return .automatic }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let metersPerDegreeLon = 111_320 * max(0.2, cos(center.latitude * .pi / 180))
        let height = max((maxLat - minLat) * 111_320 * padding, minimumSpan)
        let width = max((maxLon - minLon) * metersPerDegreeLon * padding, minimumSpan)
        return .region(MKCoordinateRegion(center: center, latitudinalMeters: height, longitudinalMeters: width))
    }
}
