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
                .activityBackgroundTint(WidgetTheme.activityBackground)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "currents://tournament"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(context.state.myTeamName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("\(context.state.myPoints)")
                            .font(.title3.bold())
                            .monospacedDigit()
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let rival = context.state.rivalName, let pts = context.state.rivalPoints {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(rival)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("\(pts)")
                                .font(.title3.bold())
                                .monospacedDigit()
                        }
                        .padding(.trailing, 4)
                    } else {
                        Text(TournamentCopy.rank(context.state))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WidgetTheme.scoreFair)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Text(TournamentCopy.rank(context.state))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WidgetTheme.scoreFair)
                        if let bite = context.state.biteScore {
                            Text("Bite \(bite)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        TournamentClock(state: context.state)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(WidgetTheme.scoreFair)
                    Text(WidgetTheme.ordinal(context.state.myRank))
                        .font(.caption2.weight(.semibold))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TournamentCopy.rank(context.state))
            } compactTrailing: {
                Text("\(context.state.myPoints)")
                    .font(.caption2.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(maxWidth: 64)
                    .accessibilityLabel("\(context.state.myPoints) points")
            } minimal: {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(WidgetTheme.scoreFair)
                    .accessibilityLabel(TournamentCopy.rank(context.state))
            }
        }
    }
}

private enum TournamentCopy {
    /// "Leading", or "2nd of 5".
    static func rank(_ s: TournamentActivityAttributes.ContentState) -> String {
        s.myRank == 1 ? "Leading" : "\(WidgetTheme.ordinal(s.myRank)) of \(s.teamsCount)"
    }
}

/// "Ends in 2:14:05" while counting down to the admin's end time, or the time
/// since the start when the tournament is open-ended.
private struct TournamentClock: View {
    let state: TournamentActivityAttributes.ContentState

    var body: some View {
        if let ends = state.endsAt, ends > .now {
            HStack(spacing: 4) {
                Text("Ends in")
                Text(ends, style: .timer)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        } else {
            HStack(spacing: 4) {
                Text("Running")
                Text(state.startedAt, style: .timer)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
    }
}

/// The lock screen card from the mockup (Crew > tournament > On your lock
/// screen): name and clock on top, the two scores either side of "vs", then
/// your rank and the bite score.
private struct TournamentLockScreenView: View {
    let context: ActivityViewContext<TournamentActivityAttributes>

    private var state: TournamentActivityAttributes.ContentState { context.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label {
                    Text(context.attributes.tournamentName).lineLimit(1)
                } icon: {
                    Image(systemName: "trophy.fill").foregroundStyle(WidgetTheme.scoreFair)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .layoutPriority(1)
                Spacer(minLength: 0)
                TournamentClock(state: state)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize()
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.myTeamName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    Text("\(state.myPoints)")
                        .font(.system(size: 30, weight: .bold))
                        .monospacedDigit()
                }
                Spacer()
                if let rival = state.rivalName, let pts = state.rivalPoints {
                    Text("vs")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(rival)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                        Text("\(pts)")
                            .font(.system(size: 30, weight: .bold))
                            .monospacedDigit()
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Fish")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                        Text("\(state.myFish)")
                            .font(.system(size: 30, weight: .bold))
                            .monospacedDigit()
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.top, 10)
            .padding(.bottom, 8)

            HStack {
                Text(TournamentCopy.rank(state))
                    .foregroundStyle(WidgetTheme.scoreFair)
                if state.rivalName != nil {
                    Text(state.myFish == 1 ? "1 fish" : "\(state.myFish) fish")
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                if let bite = state.biteScore {
                    Text("Bite \(bite)")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
