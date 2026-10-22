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
        let cal = Calendar.current
        let now = Date()
        let hourStart = cal.date(bySetting: .minute, value: 0, of: now) ?? now

        // Build one entry per upcoming hour from the stored hourly scores, so the
        // widget ticks through the day on its own — the bite score updates every
        // hour without the app being opened. Falls back to a single entry.
        let upcoming = snap.hourly.filter { $0.date >= hourStart }.prefix(24)
        var entries: [SnapshotEntry] = upcoming.map { h in
            var s = snap
            s.biteScore = h.score
            s.biteVerdict = verdict(for: h.score)
            return SnapshotEntry(date: h.date, snapshot: s)
        }
        if entries.isEmpty { entries = [SnapshotEntry(date: now, snapshot: snap)] }
        // Reload after the last known hour (or in an hour) to pull fresh scores.
        let next = entries.last.map { cal.date(byAdding: .hour, value: 1, to: $0.date) ?? $0.date }
            ?? (cal.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600))
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

private func verdict(for score: Int) -> String {
    switch score {
    case 80...: return "Excellent"
    case 60..<80: return "Good"
    case 40..<60: return "Fair"
    default: return "Slow"
    }
}

// MARK: - Bite score widget

struct BiteScoreWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BiteScoreWidget", provider: SnapshotProvider()) { entry in
            BiteScoreView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    ScoreTintBackground(score: entry.snapshot.biteScore)
                }
        }
        .configurationDisplayName("Bite score")
        .description("The current fishing bite forecast at your location.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// The Luma page tint: the score colour fading into the widget background
/// from the top, as on the Today hero.
private struct ScoreTintBackground: View {
    let score: Int

    var body: some View {
        ZStack {
            WidgetTheme.background
            LinearGradient(colors: [WidgetTheme.scoreColor(score).opacity(0.16), .clear],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

private struct BiteScoreView: View {
    let snapshot: CurrentsSnapshot
    @Environment(\.widgetFamily) private var family

    /// The verdict, hidden when the app has not written one yet.
    private var verdict: String? {
        let v = snapshot.biteVerdict.trimmingCharacters(in: .whitespaces)
        return v.isEmpty || v == "—" ? nil : v
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            // Lock screen circle: a gauge ringed with the bite score.
            Gauge(value: Double(min(100, max(0, snapshot.biteScore))), in: 0...100) {
                Image(systemName: "fish.fill")
            } currentValueLabel: {
                Text("\(snapshot.biteScore)")
                    .font(.system(.body).bold())
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(WidgetTheme.scoreColor(snapshot.biteScore))
            .widgetAccentable()
            .accessibilityLabel("Bite score \(snapshot.biteScore) out of 100")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Bite score", systemImage: "fish.fill")
                    .font(.headline)
                    .widgetAccentable()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(snapshot.biteScore)")
                        .font(.title3.bold())
                        .monospacedDigit()
                    if let verdict {
                        Text(verdict).font(.subheadline)
                    }
                }
                if !snapshot.locationName.isEmpty {
                    Text(snapshot.locationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .accessoryInline:
            Label(inlineText, systemImage: "fish.fill")
        case .systemMedium:
            mediumBody
        default:
            smallBody
        }
    }

    private var inlineText: String {
        if let verdict { return "Bite \(snapshot.biteScore), \(verdict.lowercased())" }
        return "Bite score \(snapshot.biteScore)"
    }

    // Small: the hero ring on top, the verdict and the place below.
    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetScoreRing(score: snapshot.biteScore, size: 64)
            Spacer(minLength: 6)
            Text("Bite score")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verdict ?? "No forecast yet")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if !snapshot.locationName.isEmpty {
                Text(snapshot.locationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // Medium: the Today hero, ring on the left, copy on the right.
    private var mediumBody: some View {
        HStack(spacing: 16) {
            WidgetScoreRing(score: snapshot.biteScore, size: 92, caption: "of 100")
            VStack(alignment: .leading, spacing: 2) {
                Text("Bite score")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(verdict ?? "No forecast yet")
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !snapshot.locationName.isEmpty {
                    Label(snapshot.locationName, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("Updated \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Next session widget

struct NextSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextSessionWidget", provider: SnapshotProvider()) { entry in
            NextSessionView(snapshot: entry.snapshot)
                .containerBackground(WidgetTheme.background, for: .widget)
        }
        .configurationDisplayName("Next session")
        .description("Your next planned fishing session, or the active one.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct NextSessionView: View {
    let snapshot: CurrentsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let start = snapshot.activeSessionStart {
                live(start: start)
            } else if let name = snapshot.nextSessionName, let date = snapshot.nextSessionDate {
                planned(name: name, date: date)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder private func live(start: Date) -> some View {
        HStack(spacing: 6) {
            Circle().fill(WidgetTheme.scoreSlow).frame(width: 8, height: 8)
            Text("Live session")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetTheme.scoreSlow)
        }
        Text(snapshot.activeSessionName ?? "Session")
            .font(.headline)
            .lineLimit(1)
            .padding(.top, 4)
        Spacer(minLength: 4)
        Text(start, style: .timer)
            .font(.title.bold())
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        Label(snapshot.activeSessionCatches == 1 ? "1 catch" : "\(snapshot.activeSessionCatches) catches",
              systemImage: "fish.fill")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private func planned(name: String, date: Date) -> some View {
        Label("Next session", systemImage: "calendar")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        Text(name)
            .font(.headline)
            .lineLimit(2)
            .padding(.top, 4)
        Spacer(minLength: 4)
        Text(date, style: .relative)
            .font(.title3.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        Text(date.formatted(date: .abbreviated, time: .shortened))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    @ViewBuilder private var empty: some View {
        Label("Sessions", systemImage: "figure.fishing")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        Spacer()
        Text("No session planned")
            .font(.headline)
        Text("Plan one in Currents")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}
