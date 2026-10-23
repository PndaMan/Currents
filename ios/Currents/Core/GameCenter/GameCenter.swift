import Foundation
import GameKit
import GRDB
import UIKit

/// Game Center: sign-in, the badges mirrored as achievements, and the catch
/// leaderboards. Everything stays local until the angler signs in; nothing
/// pops up at launch. Already signed in on this phone means signed in here
/// without a prompt; otherwise the sign-in sheet waits for a tap on "Sign in
/// to Game Center".
///
/// The achievement and leaderboard ids match ios/AppStore/game-center, which
/// `make appstore-gamecenter` sends to App Store Connect.
@MainActor
@Observable
final class GameCenter {
    static let shared = GameCenter()

    enum Status: Equatable {
        /// Waiting for GameKit's first answer.
        case checking
        /// Not signed in. `canSignIn` says whether a tap can show the sheet.
        case signedOut
        case signedIn
        /// Screen Time or a managed device turned Game Center off.
        case restricted
    }

    private(set) var status: Status = .checking
    var isAuthenticated: Bool { status == .signedIn }
    /// The sign-in sheet GameKit handed over, shown only on a tap. Nil once
    /// the angler has dismissed it: after that, sign-in is in Settings.
    var canSignIn: Bool { signInController != nil }
    private(set) var playerName: String?
    /// Screen Time limits on a signed-in account (underage, or multiplayer and
    /// messaging restricted). Scores still go up; the page says so.
    private(set) var isLimited = false

    private var signInController: UIViewController?
    private var started = false
    private var catches: CatchRepository?
    private var observation: AnyDatabaseCancellable?
    private var syncTask: Task<Void, Never>?

    private init() {}

    // MARK: - Start

    /// Called once at launch. Hands GameKit its handler (which signs in
    /// silently when the phone already is) and watches the catch table so
    /// achievements and scores follow every logged, edited or synced catch.
    func start(db: AppDatabase, catches: CatchRepository) {
        guard !ScreenshotSupport.isActive else {
            // The unsigned screenshot build has no Game Center.
            status = .signedOut
            return
        }
        guard !started else { return }
        started = true
        self.catches = catches
        GKLocalPlayer.local.authenticateHandler = { [weak self] controller, error in
            Task { @MainActor in self?.authenticated(controller: controller, error: error) }
        }
        observation = DatabaseRegionObservation(tracking: Table(Catch.databaseTableName))
            .start(in: db.db, onError: { _ in }, onChange: { [weak self] _ in
                Task { @MainActor in self?.scheduleSync() }
            })
    }

    private func authenticated(controller: UIViewController?, error: Error?) {
        let player = GKLocalPlayer.local
        if let controller {
            signInController = controller
            status = .signedOut
        } else if player.isAuthenticated {
            signInController = nil
            playerName = player.displayName
            isLimited = player.isUnderage || player.isMultiplayerGamingRestricted
                || player.isPersonalizedCommunicationRestricted
            status = .signedIn
            scheduleSync(after: .seconds(1))
        } else if let code = (error as? GKError)?.code, code == .parentalControlsBlocked {
            signInController = nil
            status = .restricted
        } else {
            // Cancelled, offline or signed out in Settings. GameKit calls
            // again if that changes.
            signInController = nil
            playerName = nil
            status = .signedOut
        }
    }

    // MARK: - Sign-in and Game Center pages

    /// Shows GameKit's sign-in sheet. Without one (dismissed earlier this
    /// launch) opens Settings, where Game Center sign-in lives.
    func signIn() {
        guard let controller = signInController else {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return
        }
        topViewController()?.present(controller, animated: true)
    }

    func openDashboard() { open(.dashboard) }
    func openLeaderboards() { open(.leaderboards) }
    func openAchievements() { open(.achievements) }

    /// The Game Center overlay opened through the access point, which is
    /// never shown on screen. Signed out, a tap signs in first.
    private func open(_ state: GKGameCenterViewControllerState) {
        guard isAuthenticated else {
            signIn()
            return
        }
        GKAccessPoint.shared.trigger(state: state) {}
    }

    private func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // MARK: - Reporting

    /// Achievements and scores, a few seconds after the last catch change so
    /// a sync or an import reports once.
    func scheduleSync(after delay: Duration = .seconds(3)) {
        guard isAuthenticated else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    private func sync() async {
        guard isAuthenticated, let catches,
              let all = try? await catches.fetchAllInBackground(limit: 100_000) else { return }
        let progress = await Task.detached(priority: .utility) {
            GameCenterProgress(catches: all, now: .now)
        }.value
        await reportAchievements(progress.achievements)
        await submitScores(progress.scores)
    }

    /// Reports achievement progress, percent complete by id. Only values that
    /// changed since the last report are sent; Game Center keeps the highest.
    func reportAchievements(_ percents: [String: Double]) async {
        guard isAuthenticated else { return }
        var sent = reported
        let changed = percents.filter { id, percent in percent > (sent["a." + id] ?? 0) }
        guard !changed.isEmpty else { return }
        let achievements = changed.map { id, percent in
            let achievement = GKAchievement(identifier: id)
            achievement.percentComplete = percent
            // The app shows its own celebration when a badge is earned.
            achievement.showsCompletionBanner = false
            return achievement
        }
        do {
            try await GKAchievement.report(achievements)
            for (id, percent) in changed { sent["a." + id] = percent }
            reported = sent
        } catch {
            // Offline or not set up in App Store Connect yet; tried again on
            // the next change or launch.
        }
    }

    /// Submits leaderboard scores by id. A score already sent is skipped; the
    /// weekly board is keyed by its week so each week gets its first score.
    func submitScores(_ scores: [GameCenterProgress.Score]) async {
        guard isAuthenticated else { return }
        var sent = reported
        for score in scores where score.value > 0 && Double(score.value) != sent["s." + score.key] {
            do {
                try await GKLeaderboard.submitScore(score.value, context: 0, player: GKLocalPlayer.local,
                                                    leaderboardIDs: [score.leaderboardID])
                sent["s." + score.key] = Double(score.value)
            } catch {
                continue
            }
        }
        reported = sent
    }

    /// What was last sent, per signed-in player, so another account on the
    /// same phone gets its own reports.
    private var reported: [String: Double] {
        get {
            UserDefaults.standard.dictionary(forKey: reportedKey) as? [String: Double] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: reportedKey)
        }
    }

    private var reportedKey: String { "gameCenter.reported.\(GKLocalPlayer.local.gamePlayerID)" }
}

// MARK: - Progress

/// The achievement percentages and leaderboard scores for a set of catches.
/// Worked out off the main thread.
struct GameCenterProgress {
    struct Score {
        let leaderboardID: String
        let value: Int
        /// The cache key: the leaderboard id, plus the week for the weekly board.
        let key: String
    }

    enum Leaderboard {
        static let mostFish = "catches.total"
        static let heaviest = "catches.heaviest"
        static let longest = "catches.longest"
        static let thisWeek = "catches.week"
    }

    let achievements: [String: Double]
    let scores: [Score]

    init(catches: [CatchDetail], now: Date) {
        let metrics = BadgeMetrics(catches: catches, streakWeeks: BadgeDefinition.streakWeeks(from: catches))
        var percents: [String: Double] = [:]
        // The secret and supporter badges stay in the app.
        for spec in BadgeDefinition.specs where !spec.metric.isHidden && spec.target > 0 {
            percents[Self.achievementID(for: spec.title)] = min(100, metrics.value(spec.metric) / spec.target * 100)
        }
        achievements = percents

        let records = catches.map(\.catchRecord)
        let grams = Int(((records.compactMap(\.weightKg).max() ?? 0) * 1000).rounded())
        let millimetres = Int(((records.compactMap(\.lengthCm).max() ?? 0) * 10).rounded())
        // The weekly board restarts on Monday at 00:00 UTC.
        var utc = Calendar(identifier: .iso8601)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let week = utc.dateInterval(of: .weekOfYear, for: now)
        let thisWeek = week.map { interval in records.filter { interval.contains($0.caughtAt) }.count } ?? 0
        let weekKey = Leaderboard.thisWeek + "@" + String(Int(week?.start.timeIntervalSince1970 ?? 0))
        scores = [
            Score(leaderboardID: Leaderboard.mostFish, value: catches.count, key: Leaderboard.mostFish),
            Score(leaderboardID: Leaderboard.heaviest, value: grams, key: Leaderboard.heaviest),
            Score(leaderboardID: Leaderboard.longest, value: millimetres, key: Leaderboard.longest),
            Score(leaderboardID: Leaderboard.thisWeek, value: thisWeek, key: weekKey),
        ]
    }

    /// "badge.first_catch" for "First Catch". Stable as long as the title is;
    /// scripts/render_achievement_art.py makes the same id.
    static func achievementID(for title: String) -> String {
        let words = title.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return "badge." + words.joined(separator: "_")
    }
}
