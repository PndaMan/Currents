import WidgetKit
import SwiftUI

private struct QuickLogEntry: TimelineEntry { let date: Date }

private struct QuickLogProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickLogEntry { QuickLogEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (QuickLogEntry) -> Void) {
        completion(QuickLogEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickLogEntry>) -> Void) {
        completion(Timeline(entries: [QuickLogEntry(date: .now)], policy: .never))
    }
}

/// A Home Screen shortcut: one tap opens Currents straight into logging a catch
/// (via the `currents://log` deep link).
struct QuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickLogWidget", provider: QuickLogProvider()) { _ in
            QuickLogView()
        }
        .configurationDisplayName("Log a catch")
        .description("One tap to log your latest catch.")
        .supportedFamilies([.systemSmall])
    }
}

private struct QuickLogView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // A Luma thumbnail: the symbol on a soft tint of its colour.
            Image(systemName: "fish.fill")
                .font(.title2)
                .foregroundStyle(WidgetTheme.scoreBest)
                .frame(width: 52, height: 52)
                .background(WidgetTheme.scoreBest.opacity(0.22),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .widgetAccentable()
            Spacer(minLength: 6)
            Text("Log a catch")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("Tap to record")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(WidgetTheme.background, for: .widget)
        .widgetURL(URL(string: "currents://log"))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
