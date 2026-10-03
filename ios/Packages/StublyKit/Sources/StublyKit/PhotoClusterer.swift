import Foundation

/// Seyahat fotoğraflarını "anlara" ayırır: zamanca ve konumca yakın fotoğraflar aynı öbekte toplanır,
/// öbek gün planındaki en yakın durakla eşleştirilir. Tamamen cihazda çalışır.
public enum PhotoClusterer {
    public struct Photo: Hashable, Sendable {
        public var id: String
        public var date: Date
        public var coordinate: Coordinate?

        public init(id: String, date: Date, coordinate: Coordinate?) {
            self.id = id
            self.date = date
            self.coordinate = coordinate
        }
    }

    public struct Moment: Hashable, Identifiable, Sendable {
        public var photoIDs: [String]
        public var start: Date
        public var end: Date
        /// Konumlu fotoğrafların ortalaması.
        public var center: Coordinate?
        /// Eşleşen durağın adı (yakınında durak yoksa nil).
        public var stopName: String?
        public var id: String { photoIDs.first ?? "\(start.timeIntervalSince1970)" }
        public var count: Int { photoIDs.count }
    }

    /// - Parameters:
    ///   - maxGap: aynı andaki ardışık iki fotoğraf arasındaki en uzun süre.
    ///   - maxDistance: fotoğrafın anın merkezinden en fazla uzaklığı (metre).
    public static func moments(_ photos: [Photo], maxGap: TimeInterval = 2 * 3600, maxDistance: Double = 300) -> [Moment] {
        let sorted = photos.sorted { $0.date < $1.date }
        var moments: [Moment] = []
        var current: [Photo] = []

        func centroid(_ items: [Photo]) -> Coordinate? {
            let located = items.compactMap(\.coordinate)
            guard !located.isEmpty else { return nil }
            return Coordinate(latitude: located.map(\.latitude).reduce(0, +) / Double(located.count),
                              longitude: located.map(\.longitude).reduce(0, +) / Double(located.count))
        }
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            moments.append(Moment(photoIDs: current.map(\.id), start: first.date, end: last.date,
                                  center: centroid(current), stopName: nil))
            current = []
        }

        for photo in sorted {
            if let last = current.last {
                let tooLate = photo.date.timeIntervalSince(last.date) > maxGap
                var tooFar = false
                if let coordinate = photo.coordinate, let center = centroid(current) {
                    tooFar = Geo.distance(coordinate, center) > maxDistance
                }
                if tooLate || tooFar { flush() }
            }
            current.append(photo)
        }
        flush()
        return moments
    }

    /// Her anı aynı gündeki en yakın durakla (en fazla `radius` metre) eşleştirir.
    public static func label(_ moments: [Moment], stops: [Stop], radius: Double = 400,
                             calendar: Calendar = .current) -> [Moment] {
        moments.map { moment in
            var labeled = moment
            guard let center = moment.center else { return labeled }
            let candidates = stops.filter { stop in
                stop.coordinate != nil && calendar.isDate(stop.day, inSameDayAs: moment.start)
            }
            let nearest = candidates.min { lhs, rhs in
                Geo.distance(lhs.coordinate!, center) < Geo.distance(rhs.coordinate!, center)
            }
            if let nearest, let coordinate = nearest.coordinate, Geo.distance(coordinate, center) <= radius {
                labeled.stopName = nearest.name
            }
            return labeled
        }
    }
}
