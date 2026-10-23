import SwiftUI
import CloudKit

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
        case "🎣": .teal  // ui-lint: allow, reaction emoji are user content
        case "👏": .dsScoreFair  // ui-lint: allow, reaction emoji are user content
        case "😮": .pink  // ui-lint: allow, reaction emoji are user content
        case "🐟": .blue  // ui-lint: allow, reaction emoji are user content
        default: DS.accent
        }
    }
}

// MARK: - Crew thumbnail

/// A crew's square thumbnail: its icon photo when one is set (disk-cached,
/// refreshed lazily), otherwise its emoji on the accent tint.
struct CrewThumb: View {
    let code: String
    /// The crew's stored icon emoji; nil while the crew is still loading.
    let emoji: String?
    var size: CGFloat = 64
    @State private var icon: UIImage?

    var body: some View {
        Group {
            if let icon {
                ThumbView(image: icon, tint: DS.accent, size: size)
            } else if let emoji, !emoji.isEmpty {
                ThumbView(tint: DS.accent, size: size) {
                    Text(emoji).font(.system(size: size * 0.46))  // ui-lint: allow, crew icon emoji is stored crew data and scales with the thumb
                }
            } else {
                ThumbView(systemImage: "person.3.fill", tint: DS.accent, size: size)
            }
        }
        .accessibilityHidden(true)
        .task(id: code) {
            icon = CommunityDiskCache.loadImage(key: "crewicon-\(code)")
            if icon == nil, CrewCloud.shared.isAvailable {
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

    private static var palette: [Color] {
        [DS.accent, .dsScoreSlow, .dsScoreLow, .dsScoreFair, .dsScoreGood, .dsText2]
    }

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
                    .foregroundStyle(Color.black)  // ui-lint: allow, initials sit on bright score fills in both modes
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

// MARK: - Inline empty, footnote

/// An empty state that sits inside a section (Luma's "Nothing planned yet"),
/// with an optional action. It draws the design system's `InlineEmpty`.
struct CrewInlineEmpty: View {
    let systemImage: String
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        InlineEmpty(systemImage: systemImage, text: text, actionTitle: actionTitle, action: action)
    }
}

/// A short secondary note under a section: the design system's
/// `SectionFootnote`, so long notes wrap the same way on every page.
struct CrewFootnote: View {
    let text: String
    var body: some View {
        SectionFootnote(text)
    }
}

/// A plain settings row on the page background: tinted icon, title, and a
/// trailing value or control, in the gutter like every other row.
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
                .accessibilityHidden(true)
            Text(title)
                .font(.body)
                .foregroundStyle(.dsText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Space.s2)
            trailing()
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, DS.Space.s2)
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
                    Image(systemName: "flame.fill")
                        .font(.subheadline)
                        .foregroundStyle(CrewReactionStyle.tint("🔥")) // ui-lint: allow, reaction key stored as emoji
                    Text("\(total)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.dsText2)
                        .contentTransition(.numericText())
                }
                .accessibilityLabel("\(total) reactions")
            }
        }
        .task(id: post.id) {
            if post.hasPhoto, photo == nil, CrewCloud.shared.isAvailable {
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
            ThumbView(systemImage: "fish.fill", tint: CrewTint.fish)
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

/// A labelled field on a filled rounded rectangle. `multiline` grows it to
/// four lines (bios, notes).
struct CrewTextField: View {
    let label: String
    var placeholder = ""
    @Binding var text: String
    var multiline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.dsText2)
            TextField(placeholder.isEmpty ? label : placeholder, text: $text,
                      axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 2...4 : 1...1)
                .font(.body)
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, multiline ? 14 : 0)
                .frame(minHeight: 50)
                .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                .accessibilityLabel(label)
        }
    }
}

/// A full-width red tonal button at the foot of a page (Leave crew, Remove
/// friend): the design system's `DangerButton`. Always confirmed with a
/// dialog by the caller.
struct CrewDangerButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        DangerButton(title: title, systemImage: systemImage, action: action)
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

// MARK: - iCloud availability

/// Whether Crew can reach iCloud on this install. Crews, friends and the feed
/// all live in CloudKit, and a build re-signed for sideloading carries no
/// iCloud entitlement: any CloudKit call there is an uncatchable crash. Crew
/// asks here first and shows a calm state instead of touching the container.
@MainActor
final class CrewCloud: ObservableObject {
    enum Status: Equatable {
        case available
        /// This build has no iCloud entitlement (sideloaded or unsigned).
        case unsupportedBuild
        case signedOut
        case restricted
        /// Signed in, but iCloud wants the account confirmed in Settings.
        case needsVerification
    }

    static let shared = CrewCloud()

    @Published private(set) var status: Status
    var isAvailable: Bool { status == .available }

    private init() {
        // Screenshot mode seeds a joined account and never calls CloudKit.
        let usable = ScreenshotSupport.isActive || Self.buildHasCloudKit
        status = usable ? .available : .unsupportedBuild
        if Self.buildHasCloudKit && !ScreenshotSupport.isActive {
            NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { _ in
                Task { @MainActor in await CrewCloud.shared.refresh() }
            }
        }
    }

    /// Asks CloudKit for the account state, only on builds that carry the
    /// entitlement, so the container is never created where it would crash.
    func refresh() async {
        guard !ScreenshotSupport.isActive else { status = .available; return }
        guard let container = CloudCapability.container() else { status = .unsupportedBuild; return }
        guard let account = try? await container.accountStatus() else { return }
        switch account {
        case .available: status = .available
        case .noAccount: status = .signedOut
        case .restricted: status = .restricted
        case .temporarilyUnavailable: status = .needsVerification
        default: break  // Could not determine: keep the last answer.
        }
    }

    /// Whether this build carries the iCloud entitlement at all. Without it
    /// nothing may touch CloudKit (see CloudCapability).
    nonisolated static var buildHasCloudKit: Bool { CloudCapability.isAvailable }
}

/// What Crew shows when iCloud can't be reached: the sign-up art with a cloud
/// badge, why, and a way to check again when the user can fix it.
struct CrewUnavailableState: View {
    let status: CrewCloud.Status
    @State private var checking = false

    private var title: String {
        switch status {
        case .signedOut: "Sign in to iCloud"
        case .restricted: "iCloud is restricted"
        case .needsVerification: "Confirm your iCloud account"
        case .available, .unsupportedBuild: "Crew needs iCloud"
        }
    }

    private var message: String {
        switch status {
        case .signedOut: "Crews and friends sync through iCloud. Sign in from the Settings app, then come back."
        case .restricted: "This iPhone doesn't allow iCloud, so crews and friends can't sync."
        case .needsVerification: "Open the Settings app and confirm your Apple Account, then come back."
        case .available, .unsupportedBuild:
            "Crews, friends and the catch feed sync through iCloud, which this version of Currents can't use. Everything else works as normal."
        }
    }

    var body: some View {
        VStack(spacing: DS.Space.s3) {
            CrewGateArt(badge: "icloud.slash")
                .padding(.bottom, DS.Space.s3)
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.dsText)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundStyle(.dsText2)
                .multilineTextAlignment(.center)
            if status != .unsupportedBuild {
                Button {
                    checking = true
                    Task {
                        await CrewCloud.shared.refresh()
                        checking = false
                    }
                } label: {
                    if checking { ProgressView() } else { Text("Check again") }
                }
                .buttonStyle(TonalButtonStyle(fullWidth: false))
                .disabled(checking)
                .padding(.top, DS.Space.s2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.gutter + DS.Space.s3)
        .padding(.top, DS.Space.s8)
    }
}

/// A Crew page or sheet that needs iCloud. Without it the unavailable state
/// shows instead, and the content (with every load it starts) is never built.
struct CrewCloudGate<Content: View>: View {
    /// Sheets get a Close button; pushed pages already have Back.
    var closeButton = false
    private let content: () -> Content
    @ObservedObject private var cloud = CrewCloud.shared
    @Environment(\.dismiss) private var dismiss

    init(closeButton: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.closeButton = closeButton
        self.content = content
    }

    var body: some View {
        if cloud.isAvailable {
            content()
        } else {
            ScrollView {
                CrewUnavailableState(status: cloud.status)
                    .padding(.bottom, DS.Space.s8)
            }
            .dsScreenBackground()
            .detailScrollEdge()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if closeButton {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                }
            }
            .task { await cloud.refresh() }
        }
    }
}

// MARK: - Sign-up art and form

/// Three species cards fanned out, from the bundled species art: the picture
/// on the Crew sign-up and unavailable states. `badge` pins a symbol to the
/// middle card.
struct CrewGateArt: View {
    var badge: String? = nil
    @Environment(AppState.self) private var appState
    @State private var species: [Species] = []

    private let size: CGFloat = 84
    /// Largemouth bass, galjoen and snoek: fresh water and both coasts.
    private static let ids: [Int64] = [1, 122, 130]

    var body: some View {
        HStack(spacing: -size * 0.2) {
            card(0, fallback: "fish.fill", tint: .dsScoreGood)
                .rotationEffect(.degrees(-7))
                .offset(y: 6)
            card(2, fallback: "water.waves", tint: DS.accent)
                .rotationEffect(.degrees(7))
                .offset(y: 6)
        }
        .overlay {
            card(1, fallback: "figure.fishing", tint: .dsScoreFair)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous)
                    .stroke(Color.dsBackground, lineWidth: 4))
                .overlay(alignment: .bottomTrailing) {
                    if let badge {
                        Image(systemName: badge)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.dsText)
                            .frame(width: 36, height: 36)
                            .background(Color.dsElevated, in: Circle())
                            .overlay(Circle().stroke(Color.dsBackground, lineWidth: 3))
                            .offset(x: 10, y: 10)
                    }
                }
        }
        .padding(.horizontal, size * 0.3)
        .accessibilityHidden(true)
        .task {
            species = Self.ids.compactMap { (try? appState.speciesRepository.fetch(id: $0)) ?? nil }
        }
    }

    @ViewBuilder private func card(_ index: Int, fallback: String, tint: Color) -> some View {
        if species.count == Self.ids.count {
            ThumbView(species: species[index], size: size)
        } else {
            ThumbView(systemImage: fallback, tint: tint, size: size)
        }
    }
}

/// Joining the community: one name and a button. Shared by the Crew tab and
/// the invite-link sheets.
struct CrewJoinForm: View {
    var buttonTitle = "Continue"
    /// Runs once the join lands (publish the profile, say so).
    var afterJoin: () async -> Void = {}

    private var svc: CommunityService { .shared }
    @State private var name = ""
    @State private var joining = false

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: DS.Space.s4) {
            CrewTextField(label: "Angler name", placeholder: "Your name", text: $name)
                .textContentType(.givenName)
                .submitLabel(.continue)
                .onSubmit(join)
            Button(action: join) {
                if joining { ProgressView() } else { Text(buttonTitle) }
            }
            .buttonStyle(.dsPrimary)
            // Without a name you'd silently become "Angler XXXXXX".
            .disabled(joining || trimmed.isEmpty)
            Text("Your name, best catches and region sync through iCloud. Spots stay private unless you share them.")
                .font(.footnote)
                .foregroundStyle(.dsText2)
                .multilineTextAlignment(.center)
        }
    }

    private func join() {
        guard !joining, !trimmed.isEmpty else { return }
        joining = true
        Task {
            await svc.join(name: trimmed, region: svc.myRegion)
            await afterJoin()
            Haptics.success()
            joining = false
        }
    }
}

// MARK: - Photos and avatar stacks

/// A photo filling a fixed-height rounded box. The image sits in an overlay,
/// so a wide photo can never make the page wider than the screen.
struct CrewHeroImage: View {
    let image: UIImage
    let height: CGFloat
    var radius: CGFloat = DS.Radius.card

    var body: some View {
        Color.dsFill
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Up to three overlapping member avatars for the end of a crew row.
struct CrewAvatarStack: View {
    let members: [CommunityService.GroupMember]
    var size: CGFloat = 26

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(members.prefix(3)) { m in
                CrewAvatar(image: CommunityService.shared.cachedProfiles(for: [m.id]).first?.avatar,
                           name: m.name, size: size)
                    .overlay(Circle().stroke(Color.dsBackground, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Crew art

/// Species art a crew can wear as its icon. It is saved as the crew's icon
/// photo, so every build shows it; the stored emoji stays for older builds.
enum CrewArt {
    /// Galjoen, largemouth bass, snoek, dusky kob, rainbow trout, common
    /// carp, yellowfin tuna, northern pike, bluegill and striped bass.
    static let speciesIDs: [Int64] = [122, 1, 130, 120, 17, 34, 75, 11, 6, 26]
    /// Written to new crews for builds that predate crew art.
    static let legacyEmoji = "🎣"  // ui-lint: allow, stored crew icon value read by older builds

    /// The thumbnail as a square image, drawn on the dark tile so it reads the
    /// same on every phone.
    @MainActor static func image(for species: Species) -> UIImage? {
        let renderer = ImageRenderer(content: ThumbView(species: species, size: 400)
            .environment(\.colorScheme, .dark))
        renderer.scale = 1
        return renderer.uiImage
    }

    /// The art colour of a crew icon made by `image(for:)`, read back from the
    /// tile's corners: the art tint at the dark thumbnail opacity on black.
    /// Nil for photos and older emoji icons, whose corners do not agree.
    @MainActor static func tint(of icon: UIImage) -> Color? {
        guard let cg = icon.cgImage else { return nil }
        let side = 20
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        let corners = [(1, 1), (side - 2, 1), (1, side - 2), (side - 2, side - 2)]
        let samples: [[Double]] = corners.map { point in
            let i = (point.1 * side + point.0) * 4
            return [Double(pixels[i]), Double(pixels[i + 1]), Double(pixels[i + 2])].map { $0 / 255 }
        }
        // The corners of a crew-art tile share one flat colour; a photo's do
        // not. Compare each corner with the per-channel median.
        var middle: [Double] = []
        for c in 0..<3 {
            let sorted = samples.map { $0[c] }.sorted()
            middle.append((sorted[1] + sorted[2]) / 2)
        }
        let agreeing = samples.filter { s in (0..<3).allSatisfy { abs(s[$0] - middle[$0]) < 0.04 } }
        guard agreeing.count >= 3 else { return nil }
        var mean: [Double] = []
        for c in 0..<3 {
            mean.append(agreeing.map { $0[c] }.reduce(0, +) / Double(agreeing.count))
        }
        guard let brightest = mean.max(), brightest > 0.02, brightest < 0.36 else { return nil }

        let opacity = DS.thumbTintOpacity(.dark)
        let channel = mean.map { min(1, $0 / opacity) }
        return Color(uiColor: UIColor(red: channel[0], green: channel[1], blue: channel[2], alpha: 1))  // ui-lint: allow, colour read back from the crew's own art
    }
}

/// A row of species art to pick a crew icon from, each with its name.
struct CrewArtPicker: View {
    @Binding var selection: Species?
    /// Pick the first option when nothing is chosen yet (a new crew).
    var preselect = true
    @Environment(AppState.self) private var appState
    @State private var options: [Species] = []

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                ForEach(options) { sp in
                    let picked = selection?.id == sp.id
                    Button { selection = sp } label: {
                        VStack(spacing: 6) {
                            ThumbView(species: sp, size: 76)
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous)
                                    .stroke(picked ? DS.accent : Color.clear, lineWidth: 3))
                            Text(sp.commonName)
                                .font(picked ? .footnote.weight(.semibold) : .footnote)
                                .foregroundStyle(picked ? Color.dsText : Color.dsText2)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 84)
                        }
                    }
                    .buttonStyle(.dim)
                    .buttonHaptic(.selection)
                    .accessibilityLabel(sp.commonName)
                    .accessibilityAddTraits(picked ? .isSelected : [])
                }
            }
            .padding(.horizontal, DS.gutter)
            .padding(.vertical, 3)
        }
        // Bleeds to the screen edges from inside a padded form; the layout
        // width stays the container's, so nothing overflows.
        .padding(.horizontal, -DS.gutter)
        .task {
            options = CrewArt.speciesIDs.compactMap { (try? appState.speciesRepository.fetch(id: $0)) ?? nil }
            if preselect, selection == nil { selection = options.first }
        }
    }
}
