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

/// A Home-Screen shortcut: one tap opens Currents straight into logging a catch
/// (via the `currents://log` deep link).
struct QuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickLogWidget", provider: QuickLogProvider()) { _ in
            QuickLogView()
        }
        .configurationDisplayName("Log a Catch")
        .description("One tap to log your latest catch.")
        .supportedFamilies([.systemSmall])
    }
}

private struct QuickLogView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "fish.fill")
                .font(.system(size: 34))
            Text("Log a Catch")
                .font(.headline)
                .minimumScaleFactor(0.7)
            Text("Tap to record")
                .font(.caption2)
                .opacity(0.9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(URL(string: "currents://log"))
    }
}
