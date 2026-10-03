import SwiftUI
import StublyKit

/// Çok şehirli seyahat: ilk şehirden sonraki şehirler ve varış günleri (yeni seyahat ve düzenleme formunda).
struct ExtraCitiesSection: View {
    @Binding var legs: [TripLeg]
    let start: Date
    let end: Date
    let defaultCountry: String

    var body: some View {
        Section {
            ForEach($legs) { $leg in
                NavigationLink {
                    LegEditor(leg: $leg, start: start, end: end)
                } label: {
                    HStack {
                        Text(leg.destination.city.isEmpty ? String(localized: "Şehir seç")
                                                          : "\(Countries.flag(leg.destination.countryCode)) \(leg.destination.city)")
                            .foregroundStyle(leg.destination.city.isEmpty ? Color.ink3 : Color.ink)
                        Spacer()
                        Text(String(localized: "\(AppFormat.dayPill(leg.arrival)) varış")).foregroundStyle(Color.ink2)
                    }
                }
            }
            .onDelete { legs.remove(atOffsets: $0) }
            if legs.count < 4 {
                Button {
                    withAnimation(.spring(duration: 0.35)) { legs.append(newLeg()) }
                } label: {
                    Label("Şehir ekle", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("Diğer şehirler")
        } footer: {
            Text("Birden çok şehre gidiyorsan ekle: öneriler, harita ve hava durumu her gün o günün şehrine göre çalışır. Şehir değiştirdiğin gün varılan şehre sayılır ve planda \"geçiş\" olarak işaretlenir.")
        }
    }

    /// Yeni şehrin varışı: ilk eklemede seyahatin ortası, sonrakilerde son şehirden 2 gün sonra (seyahat içinde).
    private func newLeg() -> TripLeg {
        let calendar = Calendar.current
        let total = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                                   to: calendar.startOfDay(for: end)).day ?? 1)
        let base = legs.last?.arrival ?? start
        let offset = legs.isEmpty ? max(1, total / 2) : 2
        let arrival = min(calendar.date(byAdding: .day, value: offset, to: base) ?? end, calendar.startOfDay(for: end))
        return TripLeg(destination: Destination(countryCode: legs.last?.destination.countryCode ?? defaultCountry, city: ""),
                       arrival: arrival)
    }

    /// Kaydedilecek şehirler: adı olan ve seyahat içinde (ilk günden sonra) varılanlar.
    static func valid(_ legs: [TripLeg], start: Date, end: Date) -> [TripLeg] {
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: start), last = calendar.startOfDay(for: end)
        return legs.filter { leg in
            let day = calendar.startOfDay(for: leg.arrival)
            return !leg.destination.city.trimmingCharacters(in: .whitespaces).isEmpty && day > first && day <= last
        }
    }
}

/// Bir şehrin ülkesi, adı ve varış günü.
struct LegEditor: View {
    @Binding var leg: TripLeg
    let start: Date
    let end: Date

    var body: some View {
        Form {
            NavigationLink {
                CountryPicker(selection: Binding(
                    get: { leg.destination.countryCode },
                    set: { code in
                        guard code != leg.destination.countryCode else { return }
                        leg.destination = Destination(countryCode: code, city: "")
                    }))
            } label: {
                LabeledContent("Ülke", value: "\(Countries.flag(leg.destination.countryCode)) \(Countries.name(leg.destination.countryCode))")
            }
            NavigationLink {
                CityPicker(countryCode: leg.destination.countryCode) { choice in
                    leg.destination = Destination(countryCode: leg.destination.countryCode, city: choice.name, coordinate: choice.coordinate)
                }
            } label: {
                LabeledContent("Şehir", value: leg.destination.city.isEmpty ? String(localized: "Seç") : leg.destination.city)
            }
            DatePicker("Varış", selection: $leg.arrival,
                       in: (Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start)...max(start, end),
                       displayedComponents: .date)
        }
        .navigationTitle(leg.destination.city.isEmpty ? String(localized: "Şehir") : leg.destination.city)
    }
}
