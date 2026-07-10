import WidgetKit
import SwiftUI
import ActivityKit

/// Live Activity for an in-progress fishing session: elapsed timer, catch
/// count, live bite score, and an optional catch-limit line. Shown on the Lock
/// Screen and in the Dynamic Island.
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            // Lock Screen / banner
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.5))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.startDate, style: .timer).monospacedDigit()
                    } icon: {
                        Image(systemName: "timer")
                    }
                    .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label("\(context.state.catchCount)", systemImage: "fish.fill").font(.caption)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.sessionName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text("Bite \(context.state.biteScore)").font(.caption2.bold())
                        if let limit = context.state.catchLimitText {
                            Text("· \(limit)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.fishing")
            } compactTrailing: {
                Text(context.state.startDate, style: .timer).monospacedDigit().frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "figure.fishing")
            }
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<SessionActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label(context.attributes.sessionName, systemImage: "figure.fishing")
                    .font(.subheadline.bold()).lineLimit(1)
                Text(context.state.startDate, style: .timer)
                    .font(.system(.title2, design: .rounded).bold()).monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Label("\(context.state.catchCount)", systemImage: "fish.fill").font(.headline)
                Text("Bite \(context.state.biteScore)").font(.caption.bold()).foregroundStyle(.teal)
                if let limit = context.state.catchLimitText {
                    Text(limit).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}
