import WidgetKit
import SwiftUI
import ActivityKit

/// Live Activity for an in-progress fishing session: elapsed timer, catch
/// count, live bite score, and an optional catch-limit line. Shown on the Lock
/// Screen and in the Dynamic Island.
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            // Lock Screen / banner — tapping opens the live session to log a catch.
            LockScreenView(context: context)
                .activityBackgroundTint(WidgetTheme.activityBackground)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "currents://session"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Fishing for")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.state.startDate, style: .timer)
                            .font(.title3.bold())
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Catches")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(context.state.catchCount)")
                            .font(.title3.bold())
                            .monospacedDigit()
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Label(context.attributes.sessionName, systemImage: "figure.fishing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        if let limit = context.state.catchLimitText {
                            Text(limit)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text("Bite \(context.state.biteScore)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WidgetTheme.scoreColor(context.state.biteScore))
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "figure.fishing")
                    .foregroundStyle(WidgetTheme.scoreColor(context.state.biteScore))
                    .accessibilityLabel("Fishing session")
            } compactTrailing: {
                Text(context.state.startDate, style: .timer)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "figure.fishing")
                    .foregroundStyle(WidgetTheme.scoreColor(context.state.biteScore))
                    .accessibilityLabel("Fishing session")
            }
        }
    }
}

/// Lock screen card, laid out like the tournament card in the mockup: name and
/// bite score on top, the big numbers in the middle, the bag limit below.
private struct LockScreenView: View {
    let context: ActivityViewContext<SessionActivityAttributes>

    private var state: SessionActivityAttributes.ContentState { context.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label {
                    Text(context.attributes.sessionName).lineLimit(1)
                } icon: {
                    Image(systemName: "figure.fishing")
                        .foregroundStyle(WidgetTheme.scoreColor(state.biteScore))
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                Spacer()
                Text("Bite \(state.biteScore)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WidgetTheme.scoreColor(state.biteScore))
            }
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Fishing for")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(state.startDate, style: .timer)
                        .font(.system(size: 30, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                // A timer Text claims the full width, so it takes the free
                // space here instead of a Spacer.
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Catches")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(state.catchCount)")
                        .font(.system(size: 30, weight: .bold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.white)
            .padding(.top, 10)
            if let limit = state.catchLimitText {
                Label(limit, systemImage: "scalemass")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
