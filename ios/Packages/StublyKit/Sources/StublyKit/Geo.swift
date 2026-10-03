import Foundation

public enum Geo {
    /// Ortalama yürüme hızı: 4,8 km/s = 80 m/dk.
    public static let walkingMetersPerMinute = 80.0

    /// İki nokta arasındaki büyük daire mesafesi (metre).
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * atan2(sqrt(h), sqrt(1 - h))
    }

    /// Ardışık noktalar arasındaki toplam mesafe (metre).
    public static func routeDistance(_ points: [Coordinate]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    /// Noktaları kenarlarda pay bırakarak kapsayan bölge (harita görüntüsü için).
    public struct Bounds: Hashable, Sendable {
        public var center: Coordinate
        public var latitudeSpan: Double
        public var longitudeSpan: Double
    }

    public static func bounds(_ points: [Coordinate], padding: Double = 0.3, minimumSpan: Double = 0.01) -> Bounds {
        guard let first = points.first else {
            return Bounds(center: Coordinate(latitude: 0, longitude: 0), latitudeSpan: 180, longitudeSpan: 360)
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for point in points {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }
        return Bounds(center: Coordinate(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                      latitudeSpan: max(minimumSpan, (maxLat - minLat) * (1 + padding * 2)),
                      longitudeSpan: max(minimumSpan, (maxLon - minLon) * (1 + padding * 2)))
    }

    /// Kuş uçuşu mesafeden tahmini yürüme süresi; sokak dolambacı için 1,25 çarpanı.
    public static func walkingMinutes(meters: Double) -> Int {
        Int((meters * 1.25 / walkingMetersPerMinute).rounded(.up))
    }
}

/// Yapay zekâ kullanmayan basit rota sıralayıcı.
public enum RouteOptimizer {
    /// Başlangıç noktası (ör. otel) sabitken noktaları sıralar; dönen dizi `points` indeksleridir.
    public static func order(_ points: [Coordinate], from start: Coordinate) -> [Int] {
        guard !points.isEmpty else { return [] }
        return order([start] + points).dropFirst().map { $0 - 1 }
    }

    /// İlk noktayı sabit tutarak en yakın komşu sezgiseli + 2-opt iyileştirmesiyle ziyaret sırası döndürür.
    /// Dönen dizi, giriş dizisinin indekslerinden oluşur.
    public static func order(_ points: [Coordinate]) -> [Int] {
        guard points.count > 2 else { return Array(points.indices) }

        var route = [0]
        var remaining = Set(points.indices.dropFirst())
        while let last = route.last, !remaining.isEmpty {
            let next = remaining.min { lhs, rhs in
                let l = Geo.distance(points[last], points[lhs])
                let r = Geo.distance(points[last], points[rhs])
                return l != r ? l < r : lhs < rhs
            }!
            route.append(next)
            remaining.remove(next)
        }

        // 2-opt: kesişen kenarları açarak açık rotayı kısalt.
        var improved = true
        while improved {
            improved = false
            for i in 1..<(route.count - 1) {
                for j in (i + 1)..<route.count {
                    let before = length(route, points)
                    var candidate = route
                    candidate[i...j].reverse()
                    if length(candidate, points) + 0.5 < before {
                        route = candidate
                        improved = true
                    }
                }
            }
        }
        return route
    }

    static func length(_ route: [Int], _ points: [Coordinate]) -> Double {
        Geo.routeDistance(route.map { points[$0] })
    }
}

// MARK: - Açılış saatine duyarlı sıralama

extension RouteOptimizer {
    /// Sıralanacak bir durak.
    public struct Visit: Hashable, Sendable {
        public var coordinate: Coordinate
        /// Ziyaret süresi (dakika).
        public var duration: Int
        /// O günkü açık aralıklar; nil ise saat bilinmiyor ve her zaman açık sayılır.
        public var open: [OpeningHours.Interval]?
        /// Kullanıcının verdiği başlangıç saati (dakika). Saatli duraklar bu saatte başlar; geç varılırsa çakışmadır.
        public var fixedStart: Int?

        public init(coordinate: Coordinate, duration: Int, open: [OpeningHours.Interval]? = nil, fixedStart: Int? = nil) {
            self.coordinate = coordinate
            self.duration = duration
            self.open = open
            self.fixedStart = fixedStart
        }
    }

    /// Bir sıranın yürüyerek gezilmesinin benzetimi.
    public struct Schedule: Hashable, Sendable {
        /// `visits` indeksi → varış (gerekirse açılışı bekleyerek) başlangıç dakikası.
        public var starts: [Int: Int]
        /// Kapalıyken, kapanışa yetişemeden ya da verilen saatinden geç varılan durak sayısı.
        public var conflicts: Int
    }

    /// Önce açılış saatlerine uyan (çakışması en az), sonra en kısa yürüyüş sırasını döndürür.
    /// - Parameters:
    ///   - start: sabah çıkılan yer (ör. otel); nil ise ilk durak sabit kalmaz, rota ilk duraktan başlar.
    ///   - dayStart: günün başladığı dakika (ör. 09:00 = 540).
    public static func order(_ visits: [Visit], from start: Coordinate?, dayStart: Int) -> [Int] {
        guard !visits.isEmpty else { return [] }
        let points = visits.map(\.coordinate)
        var best = start.map { order(points, from: $0) } ?? order(points)
        guard visits.contains(where: { $0.open != nil || $0.fixedStart != nil }), visits.count > 1 else { return best }

        func cost(_ route: [Int]) -> (Int, Double) {
            let conflicts = schedule(route, visits: visits, from: start, dayStart: dayStart).conflicts
            let path = (start.map { [$0] } ?? []) + route.map { points[$0] }
            return (conflicts, Geo.routeDistance(path))
        }
        func better(_ a: (Int, Double), than b: (Int, Double)) -> Bool {
            a.0 != b.0 ? a.0 < b.0 : a.1 + 0.5 < b.1
        }

        var bestCost = cost(best)
        // Yerel arama: bir durağı başka konuma taşı ya da bir parçayı ters çevir; iyileşme kalmayınca dur.
        var rounds = 0
        var improved = true
        while improved, bestCost.0 > 0 || rounds == 0, rounds < 50 {
            improved = false
            rounds += 1
            for i in best.indices {
                for j in best.indices where i != j {
                    var moved = best
                    let item = moved.remove(at: i)
                    moved.insert(item, at: j)
                    let movedCost = cost(moved)
                    if better(movedCost, than: bestCost) {
                        best = moved
                        bestCost = movedCost
                        improved = true
                    }
                    if i < j {
                        var reversed = best
                        reversed[i...j].reverse()
                        let reversedCost = cost(reversed)
                        if better(reversedCost, than: bestCost) {
                            best = reversed
                            bestCost = reversedCost
                            improved = true
                        }
                    }
                }
            }
        }
        return best
    }

    /// Saatli bir durağa verilen saatinden bu kadar geç varmak çakışma sayılmaz (dakika).
    static let fixedStartSlack = 15

    /// Verilen sırayla gezilince her durağa ne zaman başlanacağı ve kaç çakışma olacağı.
    public static func schedule(_ route: [Int], visits: [Visit], from start: Coordinate?, dayStart: Int) -> Schedule {
        var clock = dayStart
        var previous = start
        var starts: [Int: Int] = [:]
        var conflicts = 0
        for index in route {
            let visit = visits[index]
            if let previous { clock += Geo.walkingMinutes(meters: Geo.distance(previous, visit.coordinate)) }
            var begin = clock
            if let fixed = visit.fixedStart {
                // Saatli durak: kendi saatinde başlar; erken varılırsa beklenir.
                begin = fixed
                let late = clock > fixed + fixedStartSlack
                let closed = visit.open.map { open in
                    !open.contains { $0.start <= fixed && fixed + visit.duration <= $0.end }
                } ?? false
                if late || closed { conflicts += 1 }
            } else if let open = visit.open {
                if open.contains(where: { $0.start <= clock && clock + visit.duration <= $0.end }) {
                    begin = clock
                } else if let later = open.first(where: { $0.start > clock && $0.start + visit.duration <= $0.end }) {
                    begin = later.start
                } else {
                    conflicts += 1
                }
            }
            starts[index] = begin
            clock = begin + visit.duration
            previous = visit.coordinate
        }
        return Schedule(starts: starts, conflicts: conflicts)
    }
}
