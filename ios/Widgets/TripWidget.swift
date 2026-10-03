import SwiftUI
import StublyKit
import WidgetKit

// Ana ekran widget'ı: sıradaki seyahate kalan gün; seyahat sırasında günün sıradaki durağı.

struct TripEntry: TimelineEntry {
    let date: Date
    let state: WidgetSnapshot.State
}

struct TripTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TripEntry {
        TripEntry(date: .now, state: Self.sample.state(at: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (TripEntry) -> Void) {
        let snapshot = context.isPreview ? (Self.load() ?? Self.sample) : (Self.load() ?? WidgetSnapshot(items: []))
        completion(TripEntry(date: .now, state: snapshot.state(at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TripEntry>) -> Void) {
        let snapshot = Self.load() ?? WidgetSnapshot(items: [])
        let now = Date.now
        let dates = [now] + snapshot.refreshDates(after: now)
        let entries = dates.map { TripEntry(date: $0, state: snapshot.state(at: $0)) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static func load() -> WidgetSnapshot? {
        guard let url = SharedContainer.snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Galeride ve yer tutucuda gösterilen örnek.
    static var sample: WidgetSnapshot {
        let start = Calendar.current.date(byAdding: .day, value: 12, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let end = Calendar.current.date(byAdding: .day, value: 4, to: start) ?? start
        return WidgetSnapshot(items: [
            .init(id: UUID(), name: String(localized: "Lizbon Haftası"), city: String(localized: "Lizbon"), flag: "🇵🇹", tint: 0x2F7D5B, start: start, end: end,
                  flightLabel: "IST → LIS · 09:45",
                  stops: [.init(name: "Belém Kulesi", day: start, startMinutes: 10 * 60, durationMinutes: 90,
                                symbol: "building.columns.fill")]),
        ])
    }
}

struct TripCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedContainer.widgetKind, provider: TripTimelineProvider()) { entry in
            TripWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Sıradaki seyahat"))
        .description(String(localized: "Seyahate kalan gün; yoldayken günün sıradaki durağı."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TripWidgetView: View {
    let entry: TripEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
            .widgetURL(url)
    }

    private var item: WidgetSnapshot.Item? {
        switch entry.state {
        case .none: nil
        case let .upcoming(item, _): item
        case let .ongoing(item, _, _, _, _, _): item
        }
    }

    private var tint: Color { item.map { Color(hex: $0.tint) } ?? .secondary }

    private var url: URL? {
        guard let item else { return nil }
        var section = "packing"
        if case .ongoing = entry.state { section = "plan" }
        return URL(string: "stubly://trip/\(item.id.uuidString)?section=\(section)")
    }

    private var background: some View {
        ZStack {
            Color(.systemBackground)
            LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.state {
        case .none:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "suitcase.fill").font(.title2).foregroundStyle(.secondary)
                Spacer()
                Text("Planlanmış seyahat yok").font(.headline)
                Text("Yeni bir rota çiz.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case let .upcoming(item, days):
            if family == .systemMedium {
                HStack(spacing: 16) {
                    countdown(item, days: days)
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        if let flight = item.flightLabel {
                            Label(flight, systemImage: "airplane").font(.caption.weight(.semibold)).lineLimit(1)
                        }
                        Label(dateRange(item), systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
                        if let first = item.stops.first {
                            Label("İlk durak: \(first.name)", systemImage: first.symbol)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .labelStyle(TintLabelStyle(tint: tint))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                countdown(item, days: days)
            }
        case let .ongoing(item, day, total, stop, isFirst, remaining):
            VStack(alignment: .leading, spacing: 4) {
                header(item)
                Text("\(day). gün").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(tint)
                    + Text(" / \(total)").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(.secondary)
                Spacer(minLength: 2)
                if let stop {
                    Text(isFirst ? String(localized: "Günün ilk durağı") : String(localized: "Sıradaki durak"))
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: stop.symbol).font(.caption.weight(.bold)).foregroundStyle(tint)
                        Text(stop.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    }
                    if let start = stop.startMinutes {
                        Text(String(format: "%02d:%02d", start / 60, start % 60) + (remaining > 1 ? String(localized: " · +\(remaining - 1) durak") : ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Bugün için plan yok").font(.subheadline.weight(.semibold))
                    Text("Keyfini çıkar.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func header(_ item: WidgetSnapshot.Item) -> some View {
        HStack(spacing: 4) {
            Text(item.flag)
            Text(item.city).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
        }
        .font(.caption)
    }

    private func countdown(_ item: WidgetSnapshot.Item, days: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            header(item)
            Spacer(minLength: 4)
            switch days {
            case 0:
                Text("Bugün").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(tint)
            case 1:
                Text("Yarın").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(tint)
            default:
                Text("\(days)").font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(tint)
                    .contentTransition(.numericText())
                Text("gün kaldı").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: family == .systemMedium ? nil : .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func dateRange(_ item: WidgetSnapshot.Item) -> String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(Locale(identifier: "tr_TR"))
        return "\(item.start.formatted(style)) – \(item.end.formatted(style))"
    }
}

private struct TintLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(tint).frame(width: 14)
            configuration.title
        }
    }
}
