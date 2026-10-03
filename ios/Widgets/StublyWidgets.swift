import ActivityKit
import SwiftUI
import WidgetKit

@main
struct StublyWidgets: WidgetBundle {
    var body: some Widget {
        TripCountdownWidget()
        FlightLiveActivity()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Seyahat günü kilit ekranında ve Dynamic Island'da biniş kartı.
struct FlightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { context in
            LockScreenTicket(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.92))
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(tripURL(context.attributes))
        } dynamicIsland: { context in
            let tint = Color(hex: context.attributes.tint)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.fromCode).font(.title2.weight(.semibold))
                        Text(context.state.departure, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.attributes.toCode).font(.title2.weight(.semibold))
                        Text(context.state.arrival, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Image(systemName: "airplane").foregroundStyle(tint)
                        Text(context.attributes.flightNumber).font(.caption.weight(.semibold))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(context.state.gate.map { String(localized: "Kapı \($0)") } ?? String(localized: "Kapı —"), systemImage: "door.left.hand.open")
                        Spacer()
                        Text(timerInterval: Date.now...max(Date.now, context.state.departure), countsDown: true)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90, alignment: .trailing)
                    }
                    .font(.subheadline.weight(.medium))
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: "airplane").foregroundStyle(tint)
                    Text(context.attributes.toCode).font(.caption.weight(.semibold))
                }
            } compactTrailing: {
                Text(timerInterval: Date.now...max(Date.now, context.state.departure), countsDown: true)
                    .monospacedDigit()
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "airplane").foregroundStyle(tint)
            }
            .widgetURL(tripURL(context.attributes))
        }
    }

    private func tripURL(_ attributes: FlightActivityAttributes) -> URL? {
        URL(string: "stubly://trip/\(attributes.tripID)?section=plan")
    }
}

/// Kilit ekranındaki kompakt bilet: rota, saatler, kalkışa geri sayım, kapı ve koltuk.
struct LockScreenTicket: View {
    let attributes: FlightActivityAttributes
    let state: FlightActivityAttributes.ContentState

    var body: some View {
        let tint = Color(hex: attributes.tint)
        VStack(spacing: 10) {
            HStack {
                Text(attributes.tripName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(state.status)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.15), in: Capsule())
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(attributes.fromCode).font(.system(size: 30, weight: .semibold))
                    Text(state.departure, style: .time).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Image(systemName: "airplane").font(.headline).foregroundStyle(tint)
                    Text(attributes.flightNumber).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(attributes.toCode).font(.system(size: 30, weight: .semibold))
                    Text(state.arrival, style: .time).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                chip(String(localized: "Kapı"), state.gate ?? "—")
                chip(String(localized: "Koltuk"), state.seat ?? "—")
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Kalkışa").font(.caption2).foregroundStyle(.secondary)
                    Text(timerInterval: Date.now...max(Date.now, state.departure), countsDown: true)
                        .font(.headline.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(16)
        .overlay(alignment: .leading) {
            Rectangle().fill(tint).frame(width: 4)
        }
    }

    private func chip(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
