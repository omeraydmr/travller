import MapKit
import Photos
import SwiftUI
import StublyKit

/// Anılar: seyahat tarihlerindeki fotoğraflar zamana ve konuma göre anlara ayrılır, en yakın durakla
/// adlandırılır, haritada gösterilir; seyahatten paylaşılabilir bir kartpostal üretilir.
struct MemoriesSection: View {
    @Environment(TripStore.self) private var store
    @Environment(\.tripTint) private var tint
    let trip: Trip

    @State private var moments: [PhotoClusterer.Moment]?
    @State private var photoCount = 0
    @State private var expanded: String?
    @State private var postcard: UIImage?
    @State private var isRenderingPostcard = false
    @State private var viewer: PhotoViewerContext?
    private var library: PhotoLibrary { .shared }

    var body: some View {
        ModuleCard(String(localized: "Anılar"), symbol: "photo.on.rectangle.angled") {
            TripSummaryCard(trip: trip)
            SharedAlbumCard(trip: trip)
            if CommunityService.shared.isConfigured && CommunityPlaces.canContribute(trip) {
                CommunityShareCard(trip: trip, verified: CommunityPlaces.verifiedStops(in: trip, moments: moments ?? []))
            }
            if !library.canRead {
                permissionPrompt
            } else if let moments {
                if moments.isEmpty {
                    EmptyHint(symbol: "photo", text: String(localized: "Seyahat tarihlerinde çekilmiş fotoğraf bulunamadı.")).tray()
                } else {
                    content(moments)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Fotoğraflar anlara ayrılıyor…").font(.tBody).foregroundStyle(Color.ink2)
                }
                .tray()
            }
        }
        .task(id: "\(trip.id)-\(library.status.rawValue)-\(trip.stops.count)") { await load() }
        // Albüm açıldıysa (ör. ekipten biri onay verdi) eksik fotoğrafları yükle; kullanılmayanları temizle.
        .task(id: "\(trip.id)-\(SharedAlbum.canView(store.me.id, in: trip))-\(library.status.rawValue)") {
            AlbumSync.shared.pruneOrphans(store: store)
            await AlbumSync.shared.sync(trip.id, store: store)
        }
        .fullScreenCover(item: $viewer) { context in
            PhotoViewer(items: context.items, index: context.index)
        }
    }

    // MARK: İzin

    private var permissionPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seyahat tarihlerindeki fotoğraflarını yer ve zamana göre anlara ayırıp durak adlarıyla eşleştirelim. Fotoğraflar cihazdan çıkmaz.")
                .font(.tBody)
                .foregroundStyle(Color.ink2)
            if library.status == .denied || library.status == .restricted {
                Link("Ayarlar'dan fotoğraf erişimini aç", destination: URL(string: UIApplication.openSettingsURLString)!)
                    .font(.system(.subheadline, weight: .semibold))
            } else {
                Button {
                    Task { await library.requestAccess() }
                } label: {
                    Label("Fotoğraflara erişim ver", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.primary)
            }
        }
        .tray()
    }

    // MARK: İçerik

    @ViewBuilder
    private func content(_ moments: [PhotoClusterer.Moment]) -> some View {
        let biggest = moments.max { $0.count < $1.count }
        StoryHeadline(text: headline(moments, biggest: biggest))

        let located = moments.filter { $0.center != nil }
        if !located.isEmpty {
            Map(initialPosition: MapFraming.position(located.compactMap(\.center).map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            })) {
                ForEach(located) { moment in
                    let center = moment.center!
                    Annotation(moment.stopName ?? "", coordinate: CLLocationCoordinate2D(latitude: center.latitude,
                                                                                       longitude: center.longitude)) {
                        Text("\(moment.count)")
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .frame(minWidth: 26, minHeight: 26)
                            .background(tint, in: Capsule())
                            .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
            .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
        }

        let days = Dictionary(grouping: moments) { Calendar.current.startOfDay(for: $0.start) }
        ForEach(days.keys.sorted(), id: \.self) { day in
            VStack(alignment: .leading, spacing: 10) {
                Text(dayTitle(day)).font(.tCaption).foregroundStyle(Color.ink3)
                ForEach(days[day] ?? []) { moment in
                    momentRow(moment)
                }
            }
            .tray(padding: 14)
        }

        postcardButton(cover: biggest)
    }

    private func momentRow(_ moment: PhotoClusterer.Moment) -> some View {
        let isExpanded = expanded == moment.id
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(duration: 0.3)) { expanded = isExpanded ? nil : moment.id }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(moment.stopName ?? timeRange(moment)).font(.tBodyStrong).foregroundStyle(Color.ink)
                        Text(moment.stopName == nil ? String(localized: "\(moment.count) fotoğraf") : String(localized: "\(timeRange(moment)) · \(moment.count) fotoğraf"))
                            .font(.caption)
                            .foregroundStyle(Color.ink3)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.ink3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 4)], spacing: 4) {
                    ForEach(Array(moment.photoIDs.enumerated()), id: \.element) { index, id in
                        openable(moment, index) { PhotoThumb(id: id, side: 76) }
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(moment.photoIDs.prefix(10).enumerated()), id: \.element) { index, id in
                            openable(moment, index) { PhotoThumb(id: id, side: 64) }
                        }
                    }
                }
            }
        }
    }

    /// Dokununca anın fotoğrafları tam ekran açılır.
    private func openable<Thumb: View>(_ moment: PhotoClusterer.Moment, _ index: Int,
                                       @ViewBuilder thumb: () -> Thumb) -> some View {
        Button {
            viewer = PhotoViewerContext(items: moment.photoIDs.map { .library($0) }, index: index)
        } label: {
            thumb()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fotoğrafı aç")
    }

    // MARK: Kartpostal

    @ViewBuilder
    private func postcardButton(cover: PhotoClusterer.Moment?) -> some View {
        if let postcard {
            ShareLink(item: Image(uiImage: postcard),
                      preview: SharePreview("\(trip.name) kartpostalı", image: Image(uiImage: postcard))) {
                Label("Kartpostalı paylaş", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.primary)
        } else {
            Button {
                Task { await renderPostcard(cover: cover) }
            } label: {
                if isRenderingPostcard {
                    ProgressView().tint(Color.onInk)
                } else {
                    Label("Kartpostal oluştur", systemImage: "rectangle.portrait.on.rectangle.portrait.angled")
                }
            }
            .buttonStyle(.primary)
            .disabled(isRenderingPostcard)
        }
    }

    private func renderPostcard(cover: PhotoClusterer.Moment?) async {
        isRenderingPostcard = true
        defer { isRenderingPostcard = false }
        var image: UIImage?
        if let id = cover?.photoIDs[(cover?.photoIDs.count ?? 1) / 2] {
            image = await library.thumbnail(for: id, side: 1200)
        }
        let card = PostcardView(trip: trip, photo: image, photoCount: photoCount, momentCount: moments?.count ?? 0,
                                stamp: StampImprint.subtitle(for: trip, on: trip.endDate))
            .environment(\.locale, AppFormat.locale)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        withAnimation { postcard = renderer.uiImage }
    }

    // MARK: Yükleme

    private func load() async {
        guard library.canRead else { return }
        let photos = await library.photos(for: trip)
        let grouped = PhotoClusterer.label(PhotoClusterer.moments(photos), stops: trip.stops)
        photoCount = photos.count
        withAnimation { moments = grouped }
    }

    // MARK: Metinler

    private func headline(_ moments: [PhotoClusterer.Moment], biggest: PhotoClusterer.Moment?) -> String {
        var text = String(localized: "\(photoCount) fotoğraf, \(moments.count) an.")
        if let name = biggest?.stopName { text += String(localized: " En çok fotoğraf: \(name).") }
        return text
    }

    private func dayTitle(_ day: Date) -> String {
        let number = (trip.days().firstIndex { Calendar.current.isDate($0, inSameDayAs: day) } ?? 0) + 1
        return String(localized: "\(number). gün · \(AppFormat.dayPill(day))")
    }

    private func timeRange(_ moment: PhotoClusterer.Moment) -> String {
        let start = AppFormat.time(moment.start)
        let end = AppFormat.time(moment.end)
        return start == end ? start : "\(start)–\(end)"
    }
}

/// Fotoğraf arşivinden küçük kare görsel.
struct PhotoThumb: View {
    let id: String
    let side: CGFloat
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Color.track
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .task(id: id) {
                image = await PhotoLibrary.shared.thumbnail(for: id, side: side * displayScale)
            }
            .accessibilityHidden(true)
    }
}

/// Paylaşılabilir seyahat kartpostalı (ImageRenderer ile görüntüye çevrilir).
struct PostcardView: View {
    let trip: Trip
    let photo: UIImage?
    let photoCount: Int
    let momentCount: Int
    let stamp: String

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        CoverArt(seed: trip.coverSeed)
                    }
                }
                .frame(width: 360, height: 270)
                .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.name)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(trip.countryCodes.map(Countries.flag).joined()) \(trip.cityTitle) · \(AppFormat.dateRange(trip.startDate, trip.endDate))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(18)
            }
            .frame(width: 360, height: 270)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    stat("\(trip.days().count)", String(localized: "gün"))
                    stat("\(photoCount)", String(localized: "fotoğraf"))
                    stat("\(momentCount)", "an")
                    stat("\(trip.stops.count)", String(localized: "durak"))
                }
                Spacer()
                StampImprint(subtitle: stamp, scale: 0.8)
            }
            .padding(20)
            .frame(width: 360, height: 180)
            .background(Color.tray)
        }
        .frame(width: 360, height: 450)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(12)
        .background(Color.canvas)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(Color.ink)
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink2)
        }
    }
}
