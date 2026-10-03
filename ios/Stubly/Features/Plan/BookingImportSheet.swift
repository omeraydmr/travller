import CoreLocation
import PDFKit
import PhotosUI
import SwiftUI
import StublyKit
import UniformTypeIdentifiers

/// E-bilet (Uçuşlar kartından) ya da konaklama onayını (Konaklama kartından; Booking.com, Airbnb, otel e-postası)
/// PDF, ekran görüntüsü ya da Wallet biniş kartından okur; seçilenler seyahate eklenir. Metin tamamen cihazda okunur.
struct BookingImportSheet: View {
    /// `all`: başka uygulamadan (Wallet, Dosyalar, Mail) paylaşılan belge; ne bulunursa gösterilir.
    enum Kind { case flights, lodgings, all }

    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let kind: Kind
    /// Önceden okunmuş belge (paylaşılan dosya).
    var preloaded: BookingParser.Result?

    @State private var isPickingFile = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var result: BookingParser.Result?
    @State private var selectedFlights: Set<Int> = []
    @State private var selectedLodgings: Set<Int> = []
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        isPickingFile = true
                    } label: {
                        Label(kind == .lodgings ? String(localized: "PDF ya da dosya seç") : String(localized: "PDF, Wallet kartı ya da dosya seç"),
                              systemImage: "doc.fill")
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Ekran görüntüsü seç", systemImage: "photo")
                    }
                    // Havayolunun e-bilet sayfası gibi metinler: sayfada "Tümünü seç → Kopyala", sonra buraya yapıştır.
                    PasteButton(payloadType: String.self) { strings in
                        let text = strings.joined(separator: "\n")
                        Task { @MainActor in apply(BookingParser.parse(text)) }
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                } footer: {
                    Text(kind == .lodgings
                         ? String(localized: "Booking.com, Airbnb ya da otelin onay PDF'i veya ekran görüntüsü. Metin cihazda okunur, hiçbir yere gönderilmez.")
                         : String(localized: "E-bilet, Wallet biniş kartı (.pkpass) ya da havayolu sayfasından kopyalanan metin. Wallet'taki kartı ••• → Paylaş → Stubly ile de gönderebilirsin. Metin cihazda okunur, hiçbir yere gönderilmez."))
                }

                if isReading {
                    Section { HStack { ProgressView(); Text("Okunuyor…").foregroundStyle(Color.ink2) } }
                }
                if let errorText {
                    Section { Label(errorText, systemImage: "exclamationmark.triangle").foregroundStyle(Color.food) }
                }

                if let result {
                    if isEmpty(result) {
                        Section {
                            Text(emptyText(result)).foregroundStyle(Color.ink2)
                        }
                    }
                    if kind != .lodgings && !result.flights.isEmpty {
                        Section("Uçuşlar") {
                            ForEach(Array(result.flights.enumerated()), id: \.offset) { index, flight in
                                toggleRow(isOn: selectedFlights.contains(index)) {
                                    toggle(&selectedFlights, index)
                                } content: {
                                    flightSummary(flight)
                                }
                            }
                        }
                    }
                    if kind != .flights && !result.lodgings.isEmpty {
                        Section("Konaklama") {
                            ForEach(Array(result.lodgings.enumerated()), id: \.offset) { index, lodging in
                                toggleRow(isOn: selectedLodgings.contains(index)) {
                                    toggle(&selectedLodgings, index)
                                } content: {
                                    lodgingSummary(lodging)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .onAppear { if let preloaded, result == nil { apply(preloaded) } }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle", action: add)
                        .disabled(selectedFlights.isEmpty && selectedLodgings.isEmpty)
                }
            }
            .fileImporter(isPresented: $isPickingFile,
                          allowedContentTypes: kind == .lodgings ? [.pdf, .image] : [.pdf, .image, .walletPass]) { outcome in
                if case let .success(url) = outcome {
                    Task { await read(url: url) }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = CoverImageStore.downsample(data: data, maxPixelSize: 2400) else {
                        errorText = String(localized: "Görüntü açılamadı.")
                        return
                    }
                    await read(lines: TextReader.lines(in: image))
                }
            }
        }
    }

    private func lodgingSummary(_ lodging: BookingParser.LodgingCandidate) -> some View {
        var detail = "\(AppFormat.dayPill(lodging.checkIn)) → \(AppFormat.dayPill(lodging.checkOut))"
        if !lodging.confirmation.isEmpty { detail += " · \(lodging.confirmation)" }
        return VStack(alignment: .leading, spacing: 2) {
            Text(lodging.name).foregroundStyle(Color.ink)
            Text(detail).font(.footnote).foregroundStyle(Color.ink2)
            if !lodging.address.isEmpty {
                Text(lodging.address).font(.caption).foregroundStyle(Color.ink3).lineLimit(2)
            }
            if !lodging.note.isEmpty {
                Text(lodging.note).font(.caption).foregroundStyle(Color.ink3)
            }
        }
    }

    private func flightSummary(_ flight: BookingParser.FlightCandidate) -> some View {
        let from = Airports.airport(flight.fromCode)
        let to = Airports.airport(flight.toCode)
        let departure = AppFormat.time(flight.departure, timeZone: from?.timeZone)
        let arrival = AppFormat.time(flight.arrival, timeZone: to?.timeZone)
        var detail = "\(AppFormat.dayPill(flight.departure)) · \(departure) → \(arrival)"
        if let seat = flight.seat { detail += " · koltuk \(seat)" }
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(flight.flightNumber) · \(flight.fromCode) → \(flight.toCode)").foregroundStyle(Color.ink)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(Color.ink2)
            if !flight.hasTimes {
                Text("Varış ya da kalkış saati eksik; ekledikten sonra kontrol et.").font(.caption).foregroundStyle(Color.food)
            }
        }
    }

    private func toggleRow<Content: View>(isOn: Bool, action: @escaping () -> Void,
                                          @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.success : Color.ink3)
                content()
            }
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        switch kind {
        case .flights: String(localized: "Bileti içe aktar")
        case .lodgings: String(localized: "Konaklamayı içe aktar")
        case .all: String(localized: "Rezervasyon içe aktar")
        }
    }

    private func isEmpty(_ result: BookingParser.Result) -> Bool {
        switch kind {
        case .flights: result.flights.isEmpty
        case .lodgings: result.lodgings.isEmpty
        case .all: result.isEmpty
        }
    }

    /// Aranan tür yoksa diğer kartı işaret eder (ör. konaklama onayı uçuş kartından açıldıysa).
    private func emptyText(_ result: BookingParser.Result) -> String {
        switch kind {
        case .flights where !result.lodgings.isEmpty:
            String(localized: "Bu belgede uçuş yok ama konaklama var; Konaklama kartındaki + ile içe aktarabilirsin.")
        case .lodgings where !result.flights.isEmpty:
            String(localized: "Bu belgede konaklama yok ama uçuş var; Uçuşlar kartındaki + ile içe aktarabilirsin.")
        case .flights:
            String(localized: "Uçuş bulunamadı. Başka bir sayfa ya da daha net bir ekran görüntüsü dene.")
        case .lodgings:
            String(localized: "Konaklama bulunamadı. Giriş/çıkış tarihlerinin göründüğü sayfayı ya da ekran görüntüsünü dene.")
        case .all:
            String(localized: "Uçuş ya da konaklama bulunamadı. Başka bir sayfa ya da daha net bir ekran görüntüsü dene.")
        }
    }

    private func toggle(_ set: inout Set<Int>, _ index: Int) {
        if set.contains(index) { set.remove(index) } else { set.insert(index) }
    }

    // MARK: Okuma

    private func read(url: URL) async {
        isReading = true
        defer { isReading = false }
        errorText = nil
        do {
            apply(try await BookingFileReader.read(url))
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func read(lines: [String]) async {
        apply(BookingParser.parse(lines.joined(separator: "\n")))
    }

    private func apply(_ parsed: BookingParser.Result) {
        withAnimation {
            result = parsed
            selectedFlights = kind != .lodgings ? Set(parsed.flights.indices) : []
            selectedLodgings = kind != .flights ? Set(parsed.lodgings.indices) : []
        }
    }

    private func add() {
        guard let result else { return }
        let flights = selectedFlights.sorted().map { result.flights[$0].segment() }
        let lodgings = selectedLodgings.sorted().map { result.lodgings[$0].lodging() }
        store.update(trip.id) { trip in
            for flight in flights where !trip.flights.contains(where: {
                $0.flightNumber == flight.flightNumber && Calendar.current.isDate($0.departure, inSameDayAs: flight.departure)
            }) {
                trip.flights.append(flight)
            }
            if !lodgings.isEmpty { trip.lodgings = (trip.lodgings ?? []) + lodgings }
        }
        // Onayda koordinat yoksa (Airbnb) adresten bulunur; harita ve gün planı otelden başlasın.
        let store = store, tripID = trip.id
        for lodging in lodgings where lodging.coordinate == nil && !lodging.address.isEmpty {
            Task { @MainActor in
                guard let location = try? await CLGeocoder().geocodeAddressString(lodging.address).first?.location else { return }
                store.update(tripID) { trip in
                    guard let index = trip.lodgings?.firstIndex(where: { $0.id == lodging.id }) else { return }
                    trip.lodgings?[index].coordinate = Coordinate(latitude: location.coordinate.latitude,
                                                                  longitude: location.coordinate.longitude)
                }
            }
        }
        dismiss()
    }
}

/// Rezervasyon dosyasını okur: Wallet kartı (.pkpass), PDF (metni yoksa sayfa görüntüsünden) ya da görüntü.
enum BookingFileReader {
    enum Failure: LocalizedError {
        case pass, file

        var errorDescription: String? {
            switch self {
            case .pass: String(localized: "Wallet kartı okunamadı.")
            case .file: String(localized: "Dosya okunamadı.")
            }
        }
    }

    @MainActor
    static func read(_ url: URL) async throws -> BookingParser.Result {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        if url.pathExtension.lowercased() == "pkpass" {
            guard let data = try? Data(contentsOf: url), let parsed = PassParser.parse(pkpass: data) else { throw Failure.pass }
            return parsed
        }
        if url.pathExtension.lowercased() == "pdf", let document = PDFDocument(url: url) {
            let text = document.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 {
                return BookingParser.parse(text)
            }
            // Taranmış PDF: ilk sayfaları görüntüye çevirip oku.
            var lines: [String] = []
            for index in 0..<min(document.pageCount, 3) {
                guard let page = document.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let scale = 2000 / max(bounds.width, bounds.height)
                let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
                lines += await TextReader.lines(in: image)
            }
            return BookingParser.parse(lines.joined(separator: "\n"))
        }
        guard let data = try? Data(contentsOf: url),
              let image = CoverImageStore.downsample(data: data, maxPixelSize: 2400) else { throw Failure.file }
        return BookingParser.parse(await TextReader.lines(in: image).joined(separator: "\n"))
    }
}

extension UTType {
    /// Wallet kartı. Info.plist'te içe aktarılan tür olarak bildirilir (UTImportedTypeDeclarations).
    static let walletPass = UTType(importedAs: "com.apple.pkpass", conformingTo: .data)
}
