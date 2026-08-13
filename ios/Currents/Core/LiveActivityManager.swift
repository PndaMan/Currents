import Foundation
import ActivityKit

/// Starts, updates, and ends the fishing-session Live Activity, and keeps the
/// shared widget snapshot's active-session fields in sync so the home-screen
/// widgets match. No-ops gracefully when Live Activities are disabled.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    private var activity: Activity<SessionActivityAttributes>?
    /// The local trip the current activity belongs to, so the tournament
    /// manager can tell "this session IS the team session" and replace it.
    private(set) var activeTripId: String?

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(sessionName: String, startDate: Date, biteScore: Int, tripId: String? = nil) {
        activeTripId = tripId
        guard isSupported, activity == nil else { return }
        let attributes = SessionActivityAttributes(sessionName: sessionName)
        let state = SessionActivityAttributes.ContentState(
            startDate: startDate, catchCount: 0, biteScore: biteScore, catchLimitText: nil
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            activity = nil
        }
    }

    func update(catchCount: Int, biteScore: Int, catchLimitText: String?) {
        guard let activity else { return }
        let startDate = activity.content.state.startDate
        let state = SessionActivityAttributes.ContentState(
            startDate: startDate, catchCount: catchCount, biteScore: biteScore, catchLimitText: catchLimitText
        )
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func end() {
        activeTripId = nil
        guard let activity else { return }
        let final = activity.content.state
        Task { await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate) }
        self.activity = nil
    }
}

/// Starts, updates, and ends the TOURNAMENT Live Activity — your team vs the
/// nearest rival, live on the Lock Screen. `sync` is idempotent: call it with
/// every standings refresh and it starts/updates/ends as the state demands.
@MainActor
final class TournamentActivityManager {
    static let shared = TournamentActivityManager()
    private init() {}

    private var activity: Activity<TournamentActivityAttributes>?

    /// Reconcile the Live Activity with the latest standings. No-ops unless
    /// you're actually on a team in a live tournament.
    func sync(tournament: CommunityService.Tournament,
              standings: [CommunityService.TeamStanding],
              myCode: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Tournament over (or you're not in it): tear the activity down.
        guard !tournament.isEnded,
              let myIndex = standings.firstIndex(where: { $0.memberCodes.contains(myCode) }) else {
            if activity?.attributes.tournamentCode == tournament.id { end() }
            return
        }
        let me = standings[myIndex]
        // The team session and the tournament are the same event — one Lock
        // Screen card is enough. If the session Live Activity is showing this
        // team's trip, drop it: the tournament card carries the bite score too.
        if let linked = CommunityService.shared.tripId(forGroupCode: me.id),
           LiveActivityManager.shared.activeTripId == linked {
            LiveActivityManager.shared.end()
        }
        // The team to beat: the leader when chasing, second place when on top.
        let rival = myIndex == 0
            ? (standings.count > 1 ? standings[1] : nil)
            : standings.first
        let state = TournamentActivityAttributes.ContentState(
            myTeamName: me.teamName,
            myPoints: me.points,
            myRank: myIndex + 1,
            myFish: me.fishCount,
            rivalName: rival?.teamName,
            rivalPoints: rival?.points,
            teamsCount: standings.count,
            endsAt: tournament.endsAt,
            startedAt: tournament.createdAt,
            biteScore: SharedStore.load()?.score())

        if let activity, activity.attributes.tournamentCode == tournament.id {
            Task { await activity.update(.init(state: state, staleDate: nil)) }
            return
        }
        // A different tournament's activity is up — replace it.
        if activity != nil { end() }
        let attributes = TournamentActivityAttributes(
            tournamentName: tournament.name, tournamentCode: tournament.id)
        activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil))
    }

    func end() {
        guard let activity else { return }
        let final = activity.content.state
        Task { await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate) }
        self.activity = nil
    }
}
