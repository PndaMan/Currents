import WidgetKit
import SwiftUI
import ActivityKit

/// Live Activity for a crew tournament you're fishing in: your team's points
/// and rank against the nearest rival, live on the Lock Screen and in the
/// Dynamic Island while both teams trade the lead.
struct TournamentLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TournamentActivityAttributes.self) { context in
            TournamentLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.5))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "currents://tournament"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(context.state.myTeamName)
                            .font(.caption.bold()).lineLimit(1)
                        Text("\(context.state.myPoints) pts")
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(.teal)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let rival = context.state.rivalName, let pts = context.state.rivalPoints {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(rival)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text("\(pts) pts")
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        rankBadge(context.state)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.tournamentName)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        if let bite = context.state.biteScore {
                            Text("Bite \(bite)")
                                .font(.caption2.bold()).foregroundStyle(.teal)
                        }
                        Text(rankLabel(context.state))
                            .font(.caption2.bold())
                            .foregroundStyle(context.state.myRank == 1 ? .yellow : .primary)
                        if let ends = context.state.endsAt, ends > .now {
                            Text("· ends in \(ends, style: .timer)")
                                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        } else {
                            Text("· \(context.state.startedAt, style: .timer)")
                                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(context.state.myRank == 1 ? .yellow : .white)
            } compactTrailing: {
                Text(scoreline(context.state))
                    .font(.caption2.bold().monospacedDigit())
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(context.state.myRank == 1 ? .yellow : .white)
            }
        }
    }

    private func scoreline(_ s: TournamentActivityAttributes.ContentState) -> String {
        if let rival = s.rivalPoints { return "\(s.myPoints)–\(rival)" }
        return "\(s.myPoints)"
    }

    private func rankLabel(_ s: TournamentActivityAttributes.ContentState) -> String {
        s.myRank == 1 ? "Leading 🥇" : "#\(s.myRank) of \(s.teamsCount)"
    }

    private func rankBadge(_ s: TournamentActivityAttributes.ContentState) -> some View {
        Text(rankLabel(s))
            .font(.caption.bold())
            .foregroundStyle(s.myRank == 1 ? .yellow : .secondary)
    }
}

private struct TournamentLockScreenView: View {
    let context: ActivityViewContext<TournamentActivityAttributes>

    private var state: TournamentActivityAttributes.ContentState { context.state }
    private var leading: Bool { state.myRank == 1 }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label(context.attributes.tournamentName, systemImage: "trophy.fill")
                    .font(.caption.bold()).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if let bite = state.biteScore {
                    Text("Bite \(bite)")
                        .font(.caption.bold()).foregroundStyle(.teal)
                }
                // Counting down to the admin's end time — or counting up from
                // the start when the tournament is open-ended.
                if let ends = state.endsAt, ends > .now {
                    Label { Text(ends, style: .timer) } icon: { Image(systemName: "hourglass") }
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Label { Text(state.startedAt, style: .timer) } icon: { Image(systemName: "clock") }
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                // My team
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.myTeamName).font(.subheadline.bold()).lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(state.myPoints)")
                            .font(.system(.title, design: .rounded).bold().monospacedDigit())
                            .foregroundStyle(.teal)
                        Text("pts").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(state.myFish) fish · \(leading ? "Leading 🥇" : "#\(state.myRank) of \(state.teamsCount)")")
                        .font(.caption2).foregroundStyle(leading ? .yellow : .secondary)
                }
                Spacer()
                if let rival = state.rivalName, let pts = state.rivalPoints {
                    Text("vs").font(.caption2.bold()).foregroundStyle(.tertiary)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(rival).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(pts)")
                                .font(.system(.title, design: .rounded).bold().monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text("pts").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(leading ? "chasing you" : "the team to beat")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding()
    }
}
