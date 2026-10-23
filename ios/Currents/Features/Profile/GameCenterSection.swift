import SwiftUI

/// Profile's Game Center card: sign-in while signed out, then the angler's
/// achievements and the leaderboards, both opening Game Center's own pages.
struct GameCenterSection: View {
    private var gameCenter: GameCenter { .shared }

    var body: some View {
        CardSection("Game Center", note: note) {
            switch gameCenter.status {
            case .checking:
                CardRow("Game Center", subtitle: "Checking sign-in", systemImage: "gamecontroller.fill",
                        tint: .green) {
                    ProgressView()
                }
            case .signedOut:
                Button { gameCenter.signIn() } label: {
                    CardRow("Sign in to Game Center",
                            subtitle: "Earn your badges as achievements and climb the catch leaderboards",
                            systemImage: "gamecontroller.fill", tint: .green, chevron: true)
                }
                .buttonStyle(.dsCardRow)
            case .signedIn:
                Button { gameCenter.openAchievements() } label: {
                    CardRow("Achievements", systemImage: "medal.fill", tint: .orange, chevron: true)
                }
                .buttonStyle(.dsCardRow)
                Button { gameCenter.openLeaderboards() } label: {
                    CardRow("Leaderboards", subtitle: "Most fish, heaviest, longest and this week",
                            systemImage: "list.number", tint: .blue, chevron: true)
                }
                .buttonStyle(.dsCardRow)
            case .restricted:
                CardRow("Game Center is off", subtitle: "Screen Time limits Game Center on this iPhone",
                        systemImage: "gamecontroller.fill", tint: .gray)
            }
        }
    }

    private var note: String? {
        switch gameCenter.status {
        case .signedIn:
            let name = gameCenter.playerName.map { "Signed in as \($0)." } ?? "Signed in."
            return gameCenter.isLimited ? "\(name) Some Game Center features are limited by Screen Time." : name
        case .signedOut where !gameCenter.canSignIn:
            return "Sign in under Settings, Game Center, then come back here."
        default:
            return nil
        }
    }
}
