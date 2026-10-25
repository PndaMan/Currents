import SwiftUI
import UIKit

/// A shareable tournament card, laid out like its event page: a trophy
/// cover, the live or final tag, the title, the top teams with their faces,
/// the biggest fish and the scoring. 1080 by 1350 for stories and chats.
@MainActor
enum TournamentShareCard {

    static func render(tournament: CommunityService.Tournament,
                       crewName: String,
                       standings: [CommunityService.TeamStanding]) -> UIImage? {
        render(tournament: tournament, crewName: crewName, standings: standings, images: { _ in [] })
    }

    /// The same card with each team's faces next to its name.
    static func render(tournament: CommunityService.Tournament,
                       crewName: String,
                       standings: [CommunityService.TeamStanding],
                       images: (CommunityService.TeamStanding) -> [UIImage?]) -> UIImage? {
        let biggest = standings.flatMap(\.catches)
            .filter { ($0.weightKg ?? 0) > 0 }
            .max { ($0.weightKg ?? 0) < ($1.weightKg ?? 0) }
        let card = TournamentShareCardView(
            tournament: tournament, crewName: crewName,
            rows: standings.prefix(4).map { (team: $0, images: images($0)) },
            biggest: biggest,
            teamCount: standings.count,
            fishCount: standings.reduce(0) { $0 + $1.fishCount })
        return ShareCardRenderer.image(card)
    }

    static func caption(tournament: CommunityService.Tournament,
                        standings: [CommunityService.TeamStanding]) -> String {
        if let winner = tournament.winnerTeam {
            return "\(tournament.name): \(winner) takes it! Run with Currents"
        }
        let fish = standings.reduce(0) { $0 + $1.fishCount }
        let teams = standings.count == 1 ? "1 team" : "\(standings.count) teams"
        return "\(tournament.name) is live: \(teams), \(fish) fish and counting. Run with Currents"
    }
}

private struct TournamentShareCardView: View {
    let tournament: CommunityService.Tournament
    let crewName: String
    let rows: [(team: CommunityService.TeamStanding, images: [UIImage?])]
    let biggest: CommunityService.GroupCatch?
    let teamCount: Int
    let fishCount: Int

    private var subtitle: String {
        if let winner = tournament.winnerTeam {
            let points = rows.first { $0.team.teamName == winner }?.team.points
            return points.map { "\(winner) won with \($0) points" } ?? "\(winner) won"
        }
        if teamCount == 0 { return tournament.isEnded ? "No teams fished" : "Teams are forming" }
        let teams = teamCount == 1 ? "1 team" : "\(teamCount) teams"
        // An ended tournament's haul is final, so only a live one says "so far".
        return tournament.isEnded ? "\(teams), \(fishCount) fish" : "\(teams), \(fishCount) fish so far"
    }

    var body: some View {
        ShareCardCanvas {
            ShareCardCover(systemImage: tournament.isEnded ? "trophy.fill" : "trophy",
                           tint: .dsScoreFair, height: 96)
            HStack(spacing: DS.Space.s2) {
                if tournament.isEnded {
                    Text("Final").fontWeight(.semibold).foregroundStyle(Color.dsScoreFair)
                } else {
                    ShareCardLiveTag()
                }
                if !crewName.isEmpty { Text(crewName).lineLimit(1) }
            }
            .font(.subheadline)
            .foregroundStyle(Color.dsText2)
            .padding(.top, DS.Space.s4)
            Text(tournament.name)
                .font(.title.bold())
                .foregroundStyle(Color.dsText)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(Color.dsText2)
                .lineLimit(1)
                .padding(.top, 2)

            VStack(spacing: DS.Space.s1) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    teamRow(row.team, rank: i + 1, images: row.images)
                }
            }
            .padding(.top, DS.Space.s4)

            Spacer(minLength: DS.Space.s3)
            if let biggest, let kg = biggest.weightKg {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "scalemass.fill")
                        .foregroundStyle(Color.dsScoreGood)
                    Text("Biggest")
                        .foregroundStyle(Color.dsText2)
                        .fixedSize()
                    Text("\(biggest.species), \(Units.weight(kg: kg)), \(biggest.anglerName)")
                        .foregroundStyle(Color.dsText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.footnote.weight(.medium))
                .padding(.bottom, DS.Space.s3)
            }
            let r = tournament.rates
            ShareCardFooter(detail: "+\(r.perFish) per fish, +\(r.perKg) per kg, +\(r.newSpeciesBonus) per new species")
        }
    }

    private func teamRow(_ team: CommunityService.TeamStanding, rank: Int, images: [UIImage?]) -> some View {
        HStack(spacing: DS.Space.s3) {
            Text("\(rank)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(rank == 1 || rank == 3 ? Color.black : Color.dsText)
                .frame(width: 24, height: 24)
                .background(medal(rank), in: Circle())
            EventAvatarStack(images: images, size: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(team.teamName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsText)
                    .lineLimit(1)
                Text(team.totalWeightKg > 0
                     ? "\(team.fishCount) fish, \(Units.weight(kg: team.totalWeightKg))"
                     : "\(team.fishCount) fish")
                    .font(.caption)
                    .foregroundStyle(Color.dsText2)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(team.points)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(rank == 1 ? Color.dsScoreFair : Color.dsText)
                Text(team.points == 1 ? "point" : "points")
                    .font(.caption)
                    .foregroundStyle(Color.dsText2)
            }
        }
        .padding(.vertical, DS.Space.s1)
    }

    private func medal(_ rank: Int) -> Color {
        switch rank {
        case 1: return .dsScoreFair
        case 2: return .dsFill2
        case 3: return .dsScoreLow
        default: return .dsFill
        }
    }
}

// MARK: - Share card chrome

// Shared by the tournament, trip recap and spot cards so every image the app
// shares looks like one family: the dark page, a fixed type size, a tinted
// cover, and the wordmark footer.

/// Renders a share card at 3x, so a 360 by 450 card becomes 1080 by 1350.
@MainActor
enum ShareCardRenderer {
    static func image<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// The card's page: 360 points wide, dark, with the same type sizes whatever
/// the sharer's text size setting. Pass nil for a height that fits the
/// content.
struct ShareCardCanvas<Content: View>: View {
    var height: CGFloat? = 450
    private let content: Content

    init(height: CGFloat? = 450, @ViewBuilder content: () -> Content) {
        self.height = height
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(DS.Space.s5)
            .frame(width: 360, height: height, alignment: .topLeading)
            .background(Color.dsBackground)
            .environment(\.colorScheme, .dark)
            .dynamicTypeSize(.large)
    }
}

/// A rounded cover on the card's tint, with a symbol, for cards with no map.
struct ShareCardCover: View {
    let systemImage: String
    let tint: Color
    var height: CGFloat = 96

    var body: some View {
        ZStack {
            Color.dsFill
            tint.opacity(0.3)
            Image(systemName: systemImage)
                .resizable()
                .scaledToFit()
                .frame(width: height * 0.54, height: height * 0.54)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

/// The red live dot and label, drawn still: a rendered image never runs the
/// page tag's pulse.
struct ShareCardLiveTag: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Color.dsScoreSlow).frame(width: 7, height: 7)
            Text("Live").fontWeight(.semibold).foregroundStyle(Color.dsScoreSlow)
        }
    }
}

/// A stat on a card: the value over a small label, on the fill.
struct ShareCardStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.dsText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.dsText2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.s3)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
    }
}

/// The app's mark and name, with an optional small line on the right.
struct ShareCardFooter: View {
    var detail: String? = nil

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            CurrentsMark()
                .filled(ThemeOption.current.primary)
                .frame(width: 22, height: 22)
            Text("Currents")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.dsText)
            Spacer(minLength: DS.Space.s2)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Color.dsText3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}
