import WidgetKit
import SwiftUI

// MARK: - Timeline

private struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: CurrentsSnapshot
}

private struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: CurrentsSnapshot(biteScore: 72, biteVerdict: "Good", locationName: "Your spot"))
    }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: SharedStore.load() ?? placeholder(in: context).snapshot))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snap = SharedStore.load() ?? placeholder(in: context).snapshot
        // Refresh roughly every 30 min; the app also refreshes on foreground.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [SnapshotEntry(date: .now, snapshot: snap)], policy: .after(next)))
    }
}

private func scoreColor(_ s: Int) -> Color {
    switch s {
    case 80...: return .green
    case 60..<80: return .teal
    case 40..<60: return .orange
    default: return .gray
    }
}

// MARK: - Bite Score widget

struct BiteScoreWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BiteScoreWidget", provider: SnapshotProvider()) { entry in
            BiteScoreView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Bite Score")
        .description("The current fishing bite forecast at your location.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct BiteScoreView: View {
    let snapshot: CurrentsSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            // Lock-screen 1-tile: a gauge ringed with the bite score.
            Gauge(value: Double(snapshot.biteScore), in: 0...100) {
                Image(systemName: "fish.fill")
            } currentValueLabel: {
                Text("\(snapshot.biteScore)")
                    .font(.system(.body, design: .rounded).bold())
            }
            .gaugeStyle(.accessoryCircular)
            .tint(scoreColor(snapshot.biteScore))
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Bite \(snapshot.biteScore)/100", systemImage: "fish.fill")
                    .font(.headline).widgetAccentable()
                Text(snapshot.biteVerdict).font(.subheadline)
                if !snapshot.locationName.isEmpty {
                    Text(snapshot.locationName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .accessoryInline:
            Label("Bite \(snapshot.biteScore) · \(snapshot.biteVerdict)", systemImage: "fish.fill")
        default:
            standardBody
        }
    }

    @ViewBuilder private var standardBody: some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 6) {
                Label("Bite", systemImage: "cloud.sun.fill").font(.caption2.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("\(snapshot.biteScore)").font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(snapshot.biteScore))
                Text(snapshot.biteVerdict).font(.caption.bold())
                if !snapshot.locationName.isEmpty {
                    Text(snapshot.locationName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("\(snapshot.biteScore)").font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor(snapshot.biteScore))
                    Text("/ 100").font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Label("Bite Forecast", systemImage: "cloud.sun.fill").font(.subheadline.bold())
                    Text(snapshot.biteVerdict).font(.headline).foregroundStyle(scoreColor(snapshot.biteScore))
                    if !snapshot.locationName.isEmpty {
                        Text(snapshot.locationName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text("Updated \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Next Session widget

struct NextSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextSessionWidget", provider: SnapshotProvider()) { entry in
            NextSessionView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Session")
        .description("Your next planned fishing session, or the active one.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct NextSessionView: View {
    let snapshot: CurrentsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let start = snapshot.activeSessionStart {
                Label("Live Session", systemImage: "record.circle").font(.caption2.bold()).foregroundStyle(.red)
                Text(snapshot.activeSessionName ?? "Session").font(.headline).lineLimit(1)
                Text(start, style: .timer).font(.system(.title2, design: .rounded).bold()).monospacedDigit()
                Label("\(snapshot.activeSessionCatches) caught", systemImage: "fish.fill")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let name = snapshot.nextSessionName, let date = snapshot.nextSessionDate {
                Label("Next Session", systemImage: "calendar").font(.caption2.bold()).foregroundStyle(.secondary)
                Text(name).font(.headline).lineLimit(1)
                Text(date, style: .relative).font(.subheadline.bold())
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Label("Sessions", systemImage: "figure.fishing").font(.caption2.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("No planned session").font(.subheadline).foregroundStyle(.secondary)
                Text("Plan one in Currents").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
