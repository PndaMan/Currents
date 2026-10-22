import SwiftUI

// MARK: - Routes

/// Value routes for pages pushed inside the Crew tab's stack. CommunityView
/// resolves them; anything pushed from a crew page can link to them too.
enum CrewRoute: Hashable {
    case crew(String)
    case crews
    case friends
    case friend(String)
    case requests
    case leaderboard
    case myProfile
    case tripSetup(crewCode: String?)
    case trip(code: String, name: String)
}

// MARK: - Live state per crew

/// What is happening right now in one crew: its tournament (with standings so
/// the rank pill is honest) and any live group trips.
struct CrewLive {
    var tournament: CommunityService.Tournament?
    var standings: [CommunityService.TeamStanding] = []
    var trips: [CommunityService.GroupTrip] = []

    /// 1-based rank of the team I'm on, if I'm on one.
    func myRank(_ myCode: String) -> Int? {
        let sorted = standings.sorted { $0.points > $1.points }
        guard let i = sorted.firstIndex(where: { $0.memberCodes.contains(myCode) }) else { return nil }
        return i + 1
    }
}

enum CrewText {
    static func ordinal(_ n: Int) -> String {
        let tens = n % 100
        if (11...13).contains(tens) { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    /// "4d 08:09:23", "08:09:23", or "Overtime" once past due.
    static func clock(to end: Date, now: Date) -> String {
        let s = Int(end.timeIntervalSince(now))
        guard s > 0 else { return "Overtime" }
        let d = s / 86_400, h = (s / 3600) % 24, m = (s / 60) % 60, sec = s % 60
        let hms = String(format: "%02d:%02d:%02d", h, m, sec)
        return d > 0 ? "\(d)d \(hms)" : hms
    }

    /// "Species, 44 cm" or "Species, 2.1 kg" or just the species.
    static func catchTitle(species: String, lengthCm: Double?, weightKg: Double?) -> String {
        if let l = lengthCm { return "\(species), \(Units.length(cm: l))" }
        if let w = weightKg { return "\(species), \(Units.weight(kg: w))" }
        return species
    }

    static func anglers(_ n: Int) -> String { n == 1 ? "1 angler" : "\(n) anglers" }
}

// MARK: - Reactions

/// Reactions are stored as emoji on the server (older builds read them), but
/// the interface shows each as an SF Symbol.
enum CrewReactionStyle {
    static func symbol(_ emoji: String) -> String {
        switch emoji {
        case "🔥": "flame.fill"  // ui-lint: allow, reaction emoji are user content
        case "🎣": "figure.fishing"  // ui-lint: allow, reaction emoji are user content
        case "👏": "hands.clap.fill"  // ui-lint: allow, reaction emoji are user content
        case "😮": "eyes"  // ui-lint: allow, reaction emoji are user content
        case "🐟": "fish.fill"  // ui-lint: allow, reaction emoji are user content
        default: "hand.thumbsup.fill"
        }
    }

    static func name(_ emoji: String) -> String {
        switch emoji {
        case "🔥": "Fire"  // ui-lint: allow, reaction emoji are user content
        case "🎣": "Tight lines"  // ui-lint: allow, reaction emoji are user content
        case "👏": "Applause"  // ui-lint: allow, reaction emoji are user content
        case "😮": "Wow"  // ui-lint: allow, reaction emoji are user content
        case "🐟": "Fish"  // ui-lint: allow, reaction emoji are user content
        default: "Like"
        }
    }

    static func tint(_ emoji: String) -> Color {
        switch emoji {
        case "🔥": .dsScoreLow  // ui-lint: allow, reaction emoji are user content
        case "🎣": DS.accent  // ui-lint: allow, reaction emoji are user content
        case "👏": .dsScoreFair  // ui-lint: allow, reaction emoji are user content
        case "😮": .dsScoreGood  // ui-lint: allow, reaction emoji are user content
        default: Color.cyan
        }
    }
}

// MARK: - Crew thumbnail

/// A crew's square thumbnail: its icon photo when one is set (disk-cached,
/// refreshed lazily), otherwise its emoji on the accent tint.
struct CrewThumb: View {
    let code: String
    let emoji: String
    var size: CGFloat = 64
    @State private var icon: UIImage?

    var body: some View {
        Group {
            if let icon {
                ThumbView(image: icon, tint: DS.accent, size: size)
            } else {
                ThumbView(tint: DS.accent, size: size) {
                    Text(emoji).font(.system(size: size * 0.46))  // ui-lint: allow, crew icon emoji is stored crew data and scales with the thumb
                }
            }
        }
        .accessibilityHidden(true)
        .task(id: code) {
            icon = CommunityDiskCache.loadImage(key: "crewicon-\(code)")
            if icon == nil {
                icon = await CommunityService.shared.crewArt(code: code).icon
            }
        }
    }
}

// MARK: - Live label and dot

struct CrewLiveLabel: View {
    var body: some View {
        Text("Live")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.dsScoreSlow)
    }
}

/// The red dot pinned to a thumbnail's corner while something is live.
struct CrewLiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.dsScoreSlow)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.dsBackground, lineWidth: 2.5))
            .background(
                Circle()
                    .fill(Color.dsScoreSlow.opacity(0.4))
                    .scaleEffect(pulse ? 2 : 1)
                    .opacity(pulse ? 0 : 1)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
            }
            .accessibilityHidden(true)
    }
}

/// A small capsule for the trailing side of a row ("3rd", "Joined", "Ended").
struct CrewPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.dsText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.dsFill2, in: Capsule())
    }
}

// MARK: - People

/// An angler as a round avatar with a name (and optional role) underneath,
/// for the horizontal friends and members strips.
struct CrewPersonCell: View {
    let image: UIImage?
    let name: String
    var detail: String? = nil
    var size: CGFloat = 56

    var body: some View {
        VStack(spacing: 4) {
            CrewAvatar(image: image, name: name, size: size)
            Text(name)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.dsText)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
            }
        }
        .frame(width: size + 16)
        .accessibilityElement(children: .combine)
    }
}

/// Luma's avatar: the photo, or the first letter on a colour derived from the
/// name, so every angler is recognisable before their picture loads.
struct CrewAvatar: View {
    let image: UIImage?
    let name: String
    var size: CGFloat = 44

    private static let palette: [Color] = [
        Color.cyan, Color.purple,
        .dsScoreSlow, .dsScoreFair, Color.blue, .dsScoreGood,
        .dsScoreLow, Color.gray
    ]

    private var colour: Color {
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Self.palette[sum % Self.palette.count]
    }

    var body: some View {
        ZStack {
            Circle().fill(colour)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(name.first.map { String($0).uppercased() } ?? "A")
                    .font(.system(size: size * 0.42, weight: .bold))  // ui-lint: allow, initial scales with the avatar, not with text
                    .foregroundStyle(Color.black)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

// MARK: - Inline empty, footnote

/// An empty state that sits inside a section (Luma's "Nothing planned yet"),
/// with an optional action.
struct CrewInlineEmpty: View {
    let systemImage: String
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.dsText3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(TonalButtonStyle(fullWidth: false))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s4)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.gutter)
    }
}

struct CrewFootnote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.dsText2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s2)
    }
}

/// A settings-style list row on the page background: tinted icon, title,
/// trailing value or control.
struct CrewListRow<Trailing: View>: View {
    let title: String
    let systemImage: String
    var tint: Color = DS.accent
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 28)
            Text(title)
                .font(.body)
                .foregroundStyle(.dsText)
            Spacer(minLength: DS.Space.s2)
            trailing()
        }
        .padding(.horizontal, DS.Space.s4)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

// MARK: - Feed row

/// One crew catch as a Luma row: the photo or species art, who and when, the
/// catch, and the reaction tally. Tap opens the catch sheet.
struct CrewFeedRow: View {
    let post: CommunityService.CrewPost
    /// The crew name for the subtitle on merged feeds; nil inside a crew page.
    var crewName: String? = nil

    @Environment(AppState.self) private var appState
    private var svc: CommunityService { .shared }
    @State private var photo: UIImage?

    private var who: String {
        post.authorCode == svc.friendCode ? "You" : (post.authorName.split(separator: " ").first.map(String.init) ?? post.authorName)
    }

    private var subtitle: String? {
        if let crewName { return crewName }
        return post.caption.isEmpty ? (post.tripName.isEmpty ? nil : post.tripName) : post.caption
    }

    var body: some View {
        ArtRow(over: "\(who), \(post.caughtAt.formatted(.relative(presentation: .named)))",
               title: CrewText.catchTitle(species: post.species, lengthCm: post.lengthCm, weightKg: post.weightKg),
               subtitle: subtitle) {
            thumb
        } trailing: {
            let total = post.reactions.count
            if total > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame")
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                    Text("\(total)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.dsText2)
                        .contentTransition(.numericText())
                }
                .accessibilityLabel("\(total) reactions")
            }
        }
        .task(id: post.id) {
            if post.hasPhoto, photo == nil {
                photo = await svc.crewPostImage(recordName: post.id)
            }
        }
    }

    @ViewBuilder private var thumb: some View {
        if let photo {
            ThumbView(image: photo, tint: DS.accent)
        } else if let sp = SpeciesArtLookup.species(named: post.species, appState: appState) {
            ThumbView(species: sp)
        } else {
            ThumbView(systemImage: "fish.fill", tint: DS.accent)
        }
    }
}

// MARK: - Sections

/// A title3 section on a Crew page. With `link`, the title becomes a pushed
/// link with a chevron ("Your crews >").
struct CrewSection<Content: View>: View {
    let title: String
    var detail: String? = nil
    var link: CrewRoute? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let link {
                NavigationLink(value: link) {
                    SectionTitle(title, detail: detail, chevron: true)
                }
                .buttonStyle(.dim)
            } else {
                SectionTitle(title, detail: detail)
            }
            content()
        }
        .padding(.top, DS.Space.s6)
    }
}

/// A row for something with a time attached: a tournament, a live trip, a
/// planned trip. Live rows get the red dot and label; `endsAt` ticks a
/// countdown every second.
struct CrewEventRow<Leading: View>: View {
    var isLive = false
    var over: String? = nil
    let title: String
    var subtitle: String? = nil
    var endsAt: Date? = nil
    var pill: String? = nil
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        HStack(spacing: 14) {
            leading()
                .overlay(alignment: .topTrailing) {
                    if isLive { CrewLiveDot().offset(x: 3, y: -3) }
                }
            VStack(alignment: .leading, spacing: 2) {
                if isLive || over != nil {
                    HStack(spacing: 6) {
                        if isLive { CrewLiveLabel() }
                        if let over {
                            Text(over)
                                .font(.footnote)
                                .foregroundStyle(.dsText2)
                                .lineLimit(1)
                        }
                    }
                }
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.dsText)
                    .lineLimit(2)
                if let endsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(endsAt > ctx.date ? "Ends in \(CrewText.clock(to: endsAt, now: ctx.date))" : "In overtime")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.dsText2)
                            .contentTransition(.numericText())
                    }
                } else if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let pill { CrewPill(text: pill) }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Inputs and buttons

/// A labelled single-line field on a filled rounded rectangle.
struct CrewTextField: View {
    let label: String
    var placeholder = ""
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.dsText2)
            TextField(placeholder.isEmpty ? label : placeholder, text: $text)
                .font(.body)
                .padding(.horizontal, DS.Space.s4)
                .frame(minHeight: 50)
                .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                .accessibilityLabel(label)
        }
    }
}

/// A full-width red tonal button at the foot of a page (Leave crew, Remove
/// friend). Always confirmed with a dialog by the caller.
struct CrewDangerButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.dsScoreSlow)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.dsScoreSlow.opacity(scheme == .dark ? 0.18 : 0.12),
                            in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        }
        .buttonStyle(.dim)
        .padding(.horizontal, DS.gutter)
    }
}

/// Icon-and-text facts on one line (home water, region). Empty items drop out.
struct CrewMetaLine: View {
    let items: [(String, String)]

    var body: some View {
        let shown = items.filter { !$0.1.isEmpty }
        if !shown.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s4) { labels(shown) }
                VStack(alignment: .leading, spacing: DS.Space.s1) { labels(shown) }
            }
        }
    }

    @ViewBuilder private func labels(_ shown: [(String, String)]) -> some View {
        ForEach(shown.indices, id: \.self) { i in
            Label(shown[i].1, systemImage: shown[i].0)
                .font(.subheadline)
                .foregroundStyle(.dsText2)
                .lineLimit(1)
        }
    }
}

extension CrewText {
    /// "6 anglers, tournament live" or "6 anglers".
    @MainActor static func crewSubtitle(_ crew: CommunityService.Crew, tournamentLive: Bool) -> String {
        let n = CommunityService.shared.cachedCrewMembers(crew.code).count
        let people = n > 0 ? anglers(n) : "Crew code \(crew.code)"
        return tournamentLive ? "\(people), tournament live" : people
    }
}
