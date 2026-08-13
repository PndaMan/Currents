import SwiftUI

/// A shareable tournament card: name, status, podium standings, headline
/// catch, and the scoring rules — rendered to an Instagram-friendly image.
@MainActor
enum TournamentShareCard {

    static func render(tournament: CommunityService.Tournament,
                       crewName: String,
                       standings: [CommunityService.TeamStanding]) -> UIImage? {
        let card = TournamentShareCardView(tournament: tournament,
                                           crewName: crewName,
                                           standings: standings)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }

    static func caption(tournament: CommunityService.Tournament,
                        standings: [CommunityService.TeamStanding]) -> String {
        if let winner = tournament.winnerTeam {
            return "\(tournament.name) — \(winner) takes it! 🏆 Run with Currents 🎣"
        }
        let fish = standings.reduce(0) { $0 + $1.fishCount }
        return "\(tournament.name) is live — \(standings.count) teams, \(fish) fish and counting. Run with Currents 🎣"
    }
}

private struct TournamentShareCardView: View {
    let tournament: CommunityService.Tournament
    let crewName: String
    let standings: [CommunityService.TeamStanding]

    private var biggest: (species: String, kg: Double, angler: String)? {
        let all = standings.flatMap(\.catches)
        guard let big = all.max(by: { ($0.weightKg ?? 0) < ($1.weightKg ?? 0) }),
              let kg = big.weightKg, kg > 0 else { return nil }
        return (big.species, kg, big.anglerName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            titleBlock
            standingsBlock
            if let biggest {
                highlightRow(biggest)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(26)
        .frame(width: 360, height: 450)
        .background(
            LinearGradient(colors: [Color(red: 0.05, green: 0.12, blue: 0.22),
                                    Color(red: 0.02, green: 0.05, blue: 0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 18))
                .foregroundStyle(.yellow)
            Text("Currents Tournament")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            if tournament.isEnded {
                Text("FINAL")
                    .font(.system(size: 11, weight: .heavy))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.15), in: Capsule())
                    .foregroundStyle(.white)
            } else {
                Text("LIVE")
                    .font(.system(size: 11, weight: .heavy))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.red, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tournament.name)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(crewName.isEmpty ? tournament.createdAt.formatted(date: .abbreviated, time: .omitted)
                 : "\(crewName) · \(tournament.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
            if let winner = tournament.winnerTeam {
                HStack(spacing: 6) {
                    Text("🏆")
                    Text("\(winner) wins")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.yellow)
                }
                .padding(.top, 2)
            }
        }
    }

    private var standingsBlock: some View {
        VStack(spacing: 8) {
            ForEach(Array(standings.prefix(4).enumerated()), id: \.element.id) { i, team in
                HStack(spacing: 10) {
                    Text(i == 0 ? "🥇" : i == 1 ? "🥈" : i == 2 ? "🥉" : "#\(i + 1)")
                        .font(.system(size: 15))
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(team.teamName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(team.fishCount) fish · \(Units.weight(kg: team.totalWeightKg)) · \(team.speciesCount) species")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Text("\(team.points)")
                        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(i == 0 ? .yellow : .white.opacity(0.9))
                    Text("pts")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.white.opacity(i == 0 ? 0.12 : 0.06),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if standings.isEmpty {
                Text("Teams are forming — first fish incoming.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func highlightRow(_ big: (species: String, kg: Double, angler: String)) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "scalemass.fill")
                .font(.system(size: 13))
                .foregroundStyle(.teal)
            Text("Biggest: \(big.species) · \(Units.weight(kg: big.kg)) — \(big.angler)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
    }

    private var footer: some View {
        let rates = tournament.rates
        return HStack {
            Text("\(rates.perFish)/fish · +\(rates.perKg)/kg · +\(rates.newSpeciesBonus) new species")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "water.waves")
                    .font(.system(size: 11, weight: .bold))
                Text("Currents")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.7))
        }
    }
}
