import SwiftUI

/// Profile's Game Center card: sign-in while signed out, then the angler's
/// achievements and the leaderboards, both opening Game Center's own pages.
/// Each row carries one short subtitle and the card has no footnote.
struct GameCenterSection: View {
    private var gameCenter: GameCenter { .shared }

    var body: some View {
        CardSection("Game Center") {
            switch gameCenter.status {
            case .checking:
                CardRow("Game Center", subtitle: "Checking sign-in", systemImage: "gamecontroller.fill",
                        tint: .green) {
                    ProgressView()
                }
            case .signedOut where gameCenter.canSignIn:
                Button { gameCenter.signIn() } label: {
                    CardRow("Sign in to Game Center", subtitle: "Badges and catch leaderboards",
                            systemImage: "gamecontroller.fill", tint: .green, chevron: true)
                }
                .buttonStyle(.dsCardRow)
            case .signedOut:
                // GameKit has no sign-in sheet to show, so the row says
                // where to sign in instead of going nowhere.
                CardRow("Not signed in to Game Center", subtitle: "Sign in under Settings, Game Center",
                        systemImage: "gamecontroller.fill", tint: .green)
            case .signedIn:
                Button { gameCenter.openAchievements() } label: {
                    CardRow("Game Center achievements", subtitle: signedInLine,
                            systemImage: "medal.fill", tint: .orange, chevron: true)
                }
                .buttonStyle(.dsCardRow)
                Button { gameCenter.openLeaderboards() } label: {
                    CardRow("Leaderboards", subtitle: "Most fish, heaviest and longest",
                            systemImage: "list.number", tint: .blue, chevron: true)
                }
                .buttonStyle(.dsCardRow)
            case .restricted:
                CardRow("Game Center is off", subtitle: "Screen Time limits it on this iPhone",
                        systemImage: "gamecontroller.fill", tint: .green)
            }
        }
    }

    /// Who is signed in, or that Screen Time limits some of Game Center.
    private var signedInLine: String? {
        if gameCenter.isLimited { return "Screen Time limits some features" }
        return gameCenter.playerName.map { "Signed in as \($0)" }
    }
}
