import SwiftUI
import StublyKit

/// Başka uygulamadan paylaşılan rezervasyon (Wallet'tan biniş kartı, Dosyalar ya da Mail'den PDF): belge okunur,
/// tarihine uyan seyahat seçilir (yoksa kullanıcıya sorulur) ve içe aktarma ekranı açılır.
struct IncomingBookingSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let url: URL

    @State private var result: BookingParser.Result?
    @State private var errorText: String?
    @State private var chosen: Trip.ID?

    var body: some View {
        if let result, let chosen, let trip = store.trip(chosen) {
            BookingImportSheet(trip: trip, kind: .all, preloaded: result)
        } else {
            NavigationStack {
                List {
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle").foregroundStyle(Color.food)
                    } else if result == nil {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Okunuyor…").foregroundStyle(Color.ink2)
                        }
                    } else if store.trips.isEmpty {
                        Text("Önce bir seyahat oluştur; sonra belgeyi tekrar paylaş.").foregroundStyle(Color.ink2)
                    } else {
                        Section {
                            ForEach(store.upcoming + store.past) { trip in
                                Button {
                                    withAnimation { chosen = trip.id }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(trip.countryCodes.map(Countries.flag).joined()) \(trip.name)").foregroundStyle(Color.ink)
                                        Text(AppFormat.dateRange(trip.startDate, trip.endDate)).font(.footnote).foregroundStyle(Color.ink2)
                                    }
                                }
                            }
                        } header: {
                            Text("Hangi seyahate eklensin?")
                        } footer: {
                            Text("Belgenin tarihi hiçbir seyahate denk gelmedi.")
                        }
                    }
                }
                .navigationTitle("Rezervasyon içe aktar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                }
            }
            .task(id: url) { await read() }
        }
    }

    private func read() async {
        do {
            let parsed = try await BookingFileReader.read(url)
            // Tarihi tutan seyahat varsa doğrudan onu aç.
            chosen = parsed.matchingTrip(in: store.trips)?.id
            result = parsed
        } catch {
            errorText = error.localizedDescription
        }
    }
}
