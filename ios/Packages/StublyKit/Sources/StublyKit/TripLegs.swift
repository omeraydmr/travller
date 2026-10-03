import Foundation

/// Çok şehirli seyahat yardımcıları. Tek şehirli seyahat, `destination`'dan oluşan tek bacaklı seyahat gibi davranır.
extension Trip {
    public var isMultiCity: Bool { (legs?.count ?? 0) > 1 }

    /// Şehirler varış sırasıyla; tek şehirde `destination`.
    public var cityLegs: [TripLeg] {
        guard let legs, legs.count > 1 else { return [TripLeg(id: id, destination: destination, arrival: startDate)] }
        return legs.sorted { $0.arrival < $1.arrival }
    }

    /// Şehirleri yazar: varışa göre sıralar, ilk şehri seyahat başlangıcına çeker, `destination`'ı ilk şehir yapar.
    public mutating func setLegs(_ newLegs: [TripLeg], calendar: Calendar = .current) {
        var sorted = newLegs.map { leg -> TripLeg in
            var copy = leg
            copy.arrival = calendar.startOfDay(for: leg.arrival)
            return copy
        }.sorted { $0.arrival < $1.arrival }
        guard let first = sorted.first else { return }
        sorted[0].arrival = calendar.startOfDay(for: startDate)
        destination = first.destination
        legs = sorted.count > 1 ? sorted : nil
    }

    /// O günün şehri (geçiş günü varılan şehre aittir).
    public func leg(on day: Date, calendar: Calendar = .current) -> TripLeg {
        let target = calendar.startOfDay(for: day)
        let all = cityLegs
        return all.last { calendar.startOfDay(for: $0.arrival) <= target } ?? all[0]
    }

    public func destination(on day: Date, calendar: Calendar = .current) -> Destination {
        leg(on: day, calendar: calendar).destination
    }

    /// Şehir değiştirilen gün mü (ilk şehir hariç varış günleri).
    public func isTransition(_ day: Date, calendar: Calendar = .current) -> Bool {
        guard isMultiCity else { return false }
        return cityLegs.dropFirst().contains { calendar.isDate($0.arrival, inSameDayAs: day) }
    }

    /// Şehirde geçirilen günler: varıştan bir sonraki varışın bir gün öncesine (son şehirde seyahat sonuna) kadar.
    public func days(in leg: TripLeg, calendar: Calendar = .current) -> [Date] {
        days(calendar: calendar).filter { self.leg(on: $0, calendar: calendar).id == leg.id }
    }

    /// Şehrin tarih aralığı (ilk gün, son gün).
    public func dateRange(of leg: TripLeg, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let days = days(in: leg, calendar: calendar)
        return (days.first ?? leg.arrival, days.last ?? leg.arrival)
    }

    /// Gidilen ülkeler, ilk varış sırasıyla.
    public var countryCodes: [String] {
        var seen: Set<String> = []
        return cityLegs.map { $0.destination.countryCode.uppercased() }.filter { seen.insert($0).inserted }
    }

    /// "Lizbon → Porto"; tek şehirde şehir adı.
    public var cityTitle: String {
        cityLegs.map(\.destination.city).joined(separator: " → ")
    }

    /// Bir ülkede geçirilen ilk ve son gün (çok ülkeli seyahatte vize değerlendirmesi için); ülke yoksa nil.
    public func dateRange(ofCountry code: String, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        let days = days(calendar: calendar).filter {
            destination(on: $0, calendar: calendar).countryCode.uppercased() == code.uppercased()
        }
        guard let first = days.first, let last = days.last else { return nil }
        return (first, last)
    }

    /// Schengen bölgesinde geçirilen ilk ve son gün; Schengen'e girilmiyorsa nil.
    public func schengenRange(calendar: Calendar = .current) -> (start: Date, end: Date)? {
        let days = days(calendar: calendar).filter { Schengen.isSchengen(destination(on: $0, calendar: calendar).countryCode) }
        guard let first = days.first, let last = days.last else { return nil }
        return (first, last)
    }
}
