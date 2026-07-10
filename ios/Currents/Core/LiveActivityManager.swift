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

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(sessionName: String, startDate: Date, biteScore: Int) {
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
        guard let activity else { return }
        let final = activity.content.state
        Task { await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate) }
        self.activity = nil
    }
}
