import SwiftUI
import PhotosUI

// MARK: - All crews

/// Every crew you're in, pushed from "Your crews" on the Crew tab.
struct CrewsListPage: View {
    @StateObject private var svc = CommunityService.shared
    @State private var setup: CrewSetupMode?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PageHero(label: "Fish together", value: "Your crews", callout: crewCountLine) {
                    ThumbView(systemImage: "person.3.fill", tint: CrewTint.people, size: 92)
                }
                .padding(.top, DS.Space.s2)
                ActionTriple {
                    Button { setup = .start } label: {
                        Label("New crew", systemImage: "plus")
                    }
                    .buttonStyle(ActionTileStyle(.primary))
                    Button { setup = .join } label: {
                        Label("Join crew", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(ActionTileStyle())
                    NavigationLink(value: CrewRoute.tripSetup(crewCode: nil)) {
                        ActionTileLabel("Group trip", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.dim)
                }
                .padding(.top, DS.Space.s5)

                if svc.myCrews.isEmpty {
                    CardGroup {
                        CardRow("No crews yet", systemImage: "person.3.fill", tint: CrewTint.people)
                    }
                    .padding(.top, DS.Space.s6)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(svc.myCrews) { crew in
                            NavigationLink(value: CrewRoute.crew(crew.code)) {
                                ArtRow(title: crew.name,
                                       subtitle: CrewText.crewSubtitle(crew, tournamentLive: false),
                                       chevron: true) {
                                    CrewThumb(code: crew.code, emoji: crew.emoji)
                                } trailing: {
                                    CrewAvatarStack(members: svc.cachedCrewMembers(crew.code))
                                }
                            }
                            .buttonStyle(.dsRow)
                        }
                    }
                    .padding(.top, DS.Space.s5)
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(nil)
        .eventPageTitle("Your crews")
        .sheet(item: $setup) { mode in CrewSetupView(joining: mode == .join) }
    }

    private var crewCountLine: String? {
        let n = svc.myCrews.count
        return n == 0 ? nil : (n == 1 ? "1 crew" : "\(n) crews")
    }
}

enum CrewSetupMode: String, Identifiable {
    case start, join
    var id: String { rawValue }
}

// MARK: - Create or join a crew

struct CrewSetupView: View {
    var joining = false

    @Environment(\.dismiss) private var dismiss
    private var svc: CommunityService { .shared }

    @State private var mode: CrewSetupMode = .start
    @State private var name = ""
    @State private var art: Species?
    @State private var joinCode = ""
    @State private var busy = false
    @State private var joinError: String?
    /// The join couldn't reach the server, which says nothing about the code.
    @State private var joinFailed = false

    init(joining: Bool = false) {
        self.joining = joining
        _mode = State(initialValue: joining ? .join : .start)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var codeReady: Bool { joinCode.trimmingCharacters(in: .whitespaces).count == 6 }
    /// Typed input a swipe would throw away.
    private var hasChanges: Bool { !trimmedName.isEmpty || !joinCode.isEmpty }

    var body: some View {
        NavigationStack {
            CrewCloudGate(closeButton: true) { form }
        }
        .interactiveDismissDisabled(hasChanges || busy)
        .dsSheet([.large])
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                setupHero
                    .padding(.horizontal, -DS.gutter)
                FilterChips([CrewSetupMode.start, .join], selection: $mode,
                            title: { $0 == .start ? "Start a crew" : "Join a crew" })
                    .padding(.horizontal, -DS.gutter)

                if mode == .start { startForm } else { joinForm }
            }
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s3)
            .padding(.bottom, DS.Space.s6)
            .pageWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .dsScreenBackground()
        .detailScrollEdge()
        .navigationTitle(mode == .start ? "New crew" : "Join a crew")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if busy {
                    ProgressView()
                } else if mode == .start {
                    Button("Create") { create() }
                        .bold()
                        .disabled(trimmedName.isEmpty)
                } else {
                    Button("Join") { join() }
                        .bold()
                        .disabled(!codeReady)
                }
            }
        }
    }

    @ViewBuilder private var setupHero: some View {
        if mode == .start {
            PageHero(label: "New crew", value: "Start a crew", callout: "A shared feed, challenges and tournaments.") {
                ThumbView(systemImage: "person.3.fill", tint: CrewTint.people, size: 72)
            }
        } else {
            PageHero(label: "Got a code?", value: "Join a crew") {
                ThumbView(systemImage: "person.badge.plus", tint: .dsScoreGood, size: 72)
            }
        }
    }

    private var startForm: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            CrewTextField(label: "Crew name", placeholder: "The Usual Suspects", text: $name)
            VStack(alignment: .leading, spacing: 6) {
                Text("Crew art")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.dsText2)
                CrewArtPicker(selection: $art)
            }
        }
    }

    private var joinForm: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            CodeField(text: $joinCode, placeholder: "Crew code")
                .onChange(of: joinCode) { _, _ in
                    joinError = nil
                    joinFailed = false
                }
            if let joinError {
                Label(joinError, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.dsScoreSlow)
            }
            if joinFailed {
                Label("Can't reach Crew right now", systemImage: "wifi.slash")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                Button("Try again") { join() }
                    .buttonStyle(.dsTonal)
                    .disabled(busy)
            }
        }
    }

    /// Creates the crew, then puts the chosen art on its icon photo, which
    /// every build shows.
    private func create() {
        guard !busy, !trimmedName.isEmpty else { return }
        busy = true
        Task {
            let crew = await svc.createCrew(name: trimmedName, emoji: CrewArt.legacyEmoji)
            if let crew, let art, let icon = CrewArt.image(for: art) {
                _ = await svc.updateCrewIdentity(crew, iconPhoto: icon)
            }
            busy = false
            if crew != nil {
                Haptics.success()
                ToastCenter.shared.show("Crew created", style: .success, haptic: false)
                dismiss()
            } else {
                ToastCenter.shared.show("Couldn't create the crew", style: .error)
            }
        }
    }

    /// Joins by code. A code no crew holds and a server that can't be
    /// reached get different messages, so a right code is never retyped.
    private func join() {
        guard !busy, codeReady else { return }
        let code = joinCode.trimmingCharacters(in: .whitespaces).uppercased()
        busy = true
        joinError = nil
        joinFailed = false
        Task {
            let result = await svc.lookupAndJoinCrew(code: code)
            busy = false
            switch result {
            case .found:
                Haptics.success()
                ToastCenter.shared.show("Joined the crew", style: .success, haptic: false)
                dismiss()
            case .notFound:
                Haptics.error()
                joinError = "No crew has code \(code)"
            case .failed, .ownCode:
                Haptics.error()
                joinFailed = true
            }
        }
    }
}

// MARK: - Crew page

/// One crew, pushed from the Crew tab or a crew push notification. Luma's
/// community page: a full-width cover with the crew badge over its edge, the
/// name and three actions, then what's live, recent catches, the members,
/// the weekly challenge and the tournaments.
struct CrewDetailView: View {
    let code: String

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @StateObject private var svc = CommunityService.shared
    @ObservedObject private var connection = CrewConnection.shared
    @State private var crew: CommunityService.Crew?
    @State private var members: [CommunityService.GroupMember] = []
    @State private var memberAvatars: [String: UIImage] = [:]
    @State private var feed: [CommunityService.CrewPost] = []
    /// Coalesces a burst of revision bumps into one feed reload.
    @State private var reloadGen = 0
    @State private var isLoading = true
    /// The crew record could not be fetched, so the page shows what this
    /// phone saved last.
    @State private var isOffline = false
    @State private var canLoadMore = false
    @State private var banner: UIImage?
    @State private var icon: UIImage?
    /// The crew art's colour, read from its icon; nil for photos and emoji.
    @State private var artTint: Color?
    @State private var liveTrips: [CommunityService.GroupTrip] = []
    @State private var tournament: CommunityService.Tournament?
    @State private var standings: [CommunityService.TeamStanding] = []
    /// The top three by most fish, for the leaderboard section's podium.
    @State private var podium: [CommunityService.LeaderRow] = []
    @State private var podiumFaces: [String: UIImage] = [:]
    /// My catches as board rows, read once per visit.
    @State private var myBoardRows: [CommunityService.LeaderRow]?
    @State private var showingSettings = false
    @State private var showingTournamentSetup = false
    @State private var showingTripSetup = false
    @State private var showingAlerts = false
    @State private var openedTrip: CrewTripLink?
    @State private var confirmLeave = false
    @State private var leaving = false
    @State private var openedPost: CommunityService.CrewPost?
    /// 0 while the cover is under the bar, 1 once it has scrolled away, 2
    /// once the name has too (the inline title shows).
    @State private var scrollStage = 0

    private let pageSize = 30
    /// Catches shown on the page; the rest are a tap away.
    private let feedPreview = 5

    private var myRole: CrewRole { crew.map { svc.myRole(in: $0) } ?? .member }

    var body: some View {
        page
            .navigationDestination(isPresented: $showingTripSetup) {
                GroupTripSetupView(crewCode: code)
            }
            .navigationDestination(isPresented: $showingAlerts) {
                AlertSettingsView()
            }
            .navigationDestination(item: $openedTrip) { trip in
                GroupTripView(tripId: svc.tripId(forGroupCode: trip.code), tripName: trip.name,
                              initialCode: trip.code)
            }
            .sheet(isPresented: $showingSettings) {
                if let crew {
                    CrewSettingsView(crew: crew, members: members,
                                     onChange: { Task { await refresh() } })
                }
            }
            .sheet(isPresented: $showingTournamentSetup) {
                if let crew {
                    TournamentSetupView(crew: crew) { t in
                        tournament = t
                        Task { await refresh() }
                    }
                }
            }
            .sheet(item: $openedPost) { post in
                CrewPostSheet(post: post, crew: crew) { await refresh() }
            }
            .confirmationDialog("Leave \(crew?.name ?? "this crew")?", isPresented: $confirmLeave,
                                titleVisibility: .visible) {
                Button("Leave crew", role: .destructive) { leave() }
            } message: {
                Text("You stop seeing this crew's feed. You can join again with the crew code.")
            }
            // No pull-to-refresh: the 20s poll below plus push-driven revision
            // bumps keep the page current on their own.
            .onChange(of: svc.revision) { _, _ in
                reloadGen &+= 1
                let gen = reloadGen
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard gen == reloadGen else { return }
                    // A failed page keeps what's on screen.
                    if let page = await svc.crewFeedPage(code: code) { feed = feed.mergingFirstPage(page) }
                }
            }
            .task {
                await loadCached()
                await refresh()
                await pollLoop()
            }
    }

    // MARK: Page and chrome

    private var page: some View {
        let coverEnd = CrewCoverMetrics.height - 2
        let titleEnd = CrewCoverMetrics.height + CrewCoverMetrics.badge / 2 + 48
        return ScrollView {
            content
                .padding(.bottom, DS.Space.s8)
                .pageWidth()
        }
        .detailTint(artTint)
        // The cover runs under the bar, so the bar's edge only comes in once
        // the cover has scrolled away.
        .scrollEdgeEffectHidden(scrollStage == 0, for: .top)
        .onScrollGeometryChange(for: Int.self) { geo in
            let y = geo.contentOffset.y + geo.contentInsets.top
            if y > titleEnd { return 2 }
            return y > coverEnd ? 1 : 0
        } action: { _, stage in
            scrollStage = stage
        }
        // Keeps the clock legible over a bright cover, as on the map.
        .statusBarScrim()
        .navigationTitle(crew?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(crew?.name ?? "")
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(scrollStage == 2 ? 1 : 0)
                    .animation(.easeOut(duration: DS.Motion.fast), value: scrollStage)
                    .accessibilityHidden(scrollStage != 2)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            CrewCover(code: code, emoji: crew?.emoji, banner: banner, icon: icon, tint: artTint)
            if crew == nil && !isLoading {
                unavailable
            } else {
                header
                sections
            }
        }
    }

    private var unavailable: some View {
        // Offline is never reported as a crew that doesn't exist.
        CardGroup {
            if connection.isOffline {
                CardRow("Can't reach Crew right now", subtitle: "The crew loads once you're back online.",
                        systemImage: "wifi.slash", tint: .orange)
            } else {
                CardRow("Crew not available", subtitle: "It may have been deleted.",
                        systemImage: "person.3.fill", tint: .orange)
            }
        }
        .padding(.top, DS.Space.s8)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: crew?.name ?? "Loading crew")
                .redacted(reason: crew == nil ? .placeholder : [])
                .padding(.top, DS.Space.s3)
            CrewMetaLine(items: [
                ("person.2.fill", members.isEmpty ? "" : CrewText.anglers(members.count)),
                (myRole.icon, crew == nil ? "" : roleLine)
            ])
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s2)
            if isOffline { offlineNotice }
            if let crew {
                actions(crew)
                    .padding(.top, DS.Space.s5)
            }
        }
    }

    private var roleLine: String {
        switch myRole {
        case .captain: "You're the captain"
        case .mate: "You're a mate"
        case .admin: "You're an admin"
        case .member: "You're a member"
        }
    }

    private var offlineNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "icloud.slash")
                .foregroundStyle(.dsText2)
            Text("Can't reach iCloud right now. This is the crew as last saved on this phone.")
                .font(.subheadline)
                .foregroundStyle(.dsText2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        .padding(.horizontal, DS.gutter)
        .padding(.top, 12)
    }

    // MARK: Actions

    private func actions(_ crew: CommunityService.Crew) -> some View {
        ActionTriple {
            ShareLink(item: svc.crewInviteMessage(code: crew.code, name: crew.name)) {
                ActionTileLabel("Invite", systemImage: "person.badge.plus",
                                kind: liveTrips.isEmpty ? .primary : .tonal)
            }
            .buttonStyle(.dim)
            sessionTile
            moreMenu
        }
    }

    /// The session you're in, else the crew's live one, else every live one
    /// in a menu, else a new one.
    @ViewBuilder private var sessionTile: some View {
        if let trip = myLiveTrip ?? (liveTrips.count == 1 ? liveTrips.first : nil) {
            Button { openedTrip = CrewTripLink(trip) } label: {
                Label(trip.id == myLiveTrip?.id ? "Open session" : "Join session",
                      systemImage: "dot.radiowaves.left.and.right")
            }
            .buttonStyle(ActionTileStyle(.primary))
        } else if !liveTrips.isEmpty {
            Menu {
                ForEach(liveTrips) { trip in
                    Button { openedTrip = CrewTripLink(trip) } label: {
                        Label(trip.name, systemImage: "dot.radiowaves.left.and.right")
                    }
                }
            } label: {
                ActionTileLabel("Join session", systemImage: "dot.radiowaves.left.and.right", kind: .primary)
            }
            .buttonStyle(.dim)
        } else {
            Button { showingTripSetup = true } label: {
                Label("Start session", systemImage: "dot.radiowaves.left.and.right")
            }
            .buttonStyle(ActionTileStyle(.tonal))
        }
    }

    private var myLiveTrip: CommunityService.GroupTrip? {
        let mine = Set(svc.myGroups.map(\.code))
        return liveTrips.first { mine.contains($0.id) }
    }

    private var moreMenu: some View {
        Menu {
            if myRole.canRunTournaments, tournament == nil || tournament?.isEnded == true {
                Button { showingTournamentSetup = true } label: {
                    Label("New tournament", systemImage: "trophy")
                }
            }
            if !liveTrips.isEmpty {
                Button { showingTripSetup = true } label: {
                    Label("Start another session", systemImage: "plus")
                }
            }
            Button { showingSettings = true } label: {
                if myRole.canManage {
                    Label("Edit crew", systemImage: "pencil")
                } else {
                    Label("Members and roles", systemImage: "person.2")
                }
            }
            Button { showingAlerts = true } label: {
                Label("Notifications", systemImage: "bell")
            }
        } label: {
            ActionTileLabel("More", systemImage: "ellipsis")
        }
        .buttonStyle(.dim)
    }

    // MARK: Sections

    private var sections: some View {
        VStack(alignment: .leading, spacing: 0) {
            happeningNowSection
            catchesSection
            leaderboardSection
            membersSection
            challengeSection
            if let crew {
                tournamentsSection(crew)
                settingsSection(crew)
                DangerButton(title: leaving ? "Leaving" : "Leave crew",
                             systemImage: "rectangle.portrait.and.arrow.right") {
                    confirmLeave = true
                }
                .disabled(leaving)
                .padding(.top, DS.Space.s8)
            }
        }
    }

    // MARK: Happening now

    private var liveTournament: CommunityService.Tournament? {
        guard let tournament, !tournament.isEnded else { return nil }
        return tournament
    }

    /// The live tournament and sessions; hidden when nothing is live.
    @ViewBuilder private var happeningNowSection: some View {
        if liveTournament != nil || !liveTrips.isEmpty {
            CrewSection(title: "Happening now") {
                if let crew, let t = liveTournament { tournamentRow(t, crew: crew) }
                ForEach(liveTrips) { trip in tripRow(trip) }
            }
        }
    }

    private func tripRow(_ trip: CommunityService.GroupTrip) -> some View {
        let amIn = svc.myGroups.contains { $0.code == trip.id }
        return NavigationLink(value: CrewRoute.trip(code: trip.id, name: trip.name)) {
            CrewEventRow(isLive: true,
                         over: trip.hostCode == svc.friendCode ? "You're hosting" : "Hosted by \(trip.hostName)",
                         title: trip.name,
                         subtitle: amIn ? "You're in" : "Open to join",
                         pill: amIn ? nil : "Join") {
                ThumbView(systemImage: "dot.radiowaves.left.and.right", tint: .dsScoreSlow)
            }
        }
        .buttonStyle(.dsRow)
    }

    private func tournamentRow(_ t: CommunityService.Tournament, crew: CommunityService.Crew) -> some View {
        NavigationLink {
            TournamentView(tournament: t, crew: crew)
        } label: {
            CrewEventRow(isLive: !t.isEnded,
                         over: t.isEnded ? "Ended" : "Tournament",
                         title: t.name,
                         subtitle: t.isEnded ? t.winnerTeam.map { "\($0) won" } : leaderLine,
                         endsAt: t.isEnded ? nil : t.endsAt,
                         pill: t.isEnded ? nil : CrewLive(tournament: t, standings: standings)
                            .myRank(svc.friendCode).map { CrewText.ordinal($0) }) {
                ThumbView(systemImage: "trophy.fill", tint: .dsScoreFair)
            }
        }
        .buttonStyle(.dsRow)
    }

    /// "Team name leads with 42 points" from the current standings.
    private var leaderLine: String? {
        guard let top = standings.max(by: { $0.points < $1.points }) else { return nil }
        return "\(top.teamName) leads with \(top.points == 1 ? "1 point" : "\(top.points) points")"
    }

    // MARK: Recent catches

    private var catchesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            catchesTitle
            if feed.isEmpty {
                if isLoading {
                    FishLoader(message: "Loading the feed")
                        .frame(height: 90).frame(maxWidth: .infinity)
                } else {
                    InlineEmpty(systemImage: "fish",
                                text: "No catches yet. When you or a crewmate log a catch, it shows up here.")
                }
            } else {
                ForEach(Array(feed.prefix(feedPreview))) { post in
                    Button { openedPost = post } label: {
                        CrewFeedRow(post: post)
                    }
                    .buttonStyle(.dsRow)
                }
            }
        }
        .padding(.top, DS.Space.s6)
    }

    @ViewBuilder private var catchesTitle: some View {
        if let crew, feed.count > feedPreview {
            NavigationLink {
                CrewCatchesPage(crew: crew, tint: artTint, feed: feed, canLoadMore: canLoadMore)
            } label: {
                SectionTitle("Recent catches", chevron: true)
            }
            .buttonStyle(.dim)
        } else {
            SectionTitle("Recent catches")
        }
    }

    // MARK: Leaderboard

    /// The crew's podium by most fish; the title opens the full board with
    /// heaviest and longest.
    private var leaderboardSection: some View {
        CrewSection(title: "Leaderboard", link: .leaderboard(code)) {
            if podium.isEmpty {
                NavigationLink(value: CrewRoute.leaderboard(code)) {
                    ArtRow(title: "Most fish, heaviest and longest",
                           subtitle: isLoading ? nil : "Fills up as the crew logs catches",
                           chevron: true) {
                        ThumbView(systemImage: "trophy.fill", tint: CrewTint.trophy)
                    }
                }
                .buttonStyle(.dsRow)
            } else {
                EventPodium(entries: podium.map(podiumEntry)) { e in
                    FriendProfileView(code: e.id)
                }
            }
        }
    }

    private func podiumEntry(_ row: CommunityService.LeaderRow) -> EventPodiumEntry {
        let isSelf = row.friendCode == svc.friendCode
        let first = row.anglerName.split(separator: " ").first.map(String.init) ?? row.anglerName
        return EventPodiumEntry(id: row.friendCode, name: isSelf ? "You" : first,
                                value: "\(row.catchCount ?? 0)", unit: "fish",
                                images: [podiumFaces[row.friendCode]])
    }

    // MARK: Members

    private var membersSection: some View {
        CrewSection(title: "Members", detail: members.isEmpty ? nil : "\(members.count)") {
            if members.isEmpty && isLoading {
                FishLoader(message: "Loading the crew")
                    .frame(height: 80).frame(maxWidth: .infinity)
            } else if members.isEmpty && isOffline {
                InlineEmpty(systemImage: "icloud.slash",
                            text: "The member list loads when you're back online.")
            } else if members.count <= 1 {
                InlineEmpty(systemImage: "person.badge.plus",
                            text: "It's just you so far")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: DS.Space.s2) {
                        ForEach(members) { m in memberCell(m) }
                    }
                    .padding(.horizontal, DS.gutter - 8)
                }
            }
        }
    }

    private func memberCell(_ m: CommunityService.GroupMember) -> some View {
        let role = crew.map { svc.role(of: m.id, in: $0) } ?? .member
        let isSelf = m.id == svc.friendCode
        return NavigationLink(value: isSelf ? CrewRoute.myProfile : CrewRoute.friend(m.id)) {
            CrewPersonCell(image: isSelf ? (svc.myAvatar ?? memberAvatars[m.id]) : memberAvatars[m.id],
                           name: isSelf ? "You" : (m.name.split(separator: " ").first.map(String.init) ?? m.name),
                           detail: role == .member ? nil : role.label)
        }
        .buttonStyle(.dim)
        .accessibilityLabel(role == .member ? m.name : "\(m.name), \(role.label)")
    }

    // MARK: Weekly challenge

    /// The week's one shared goal: deterministic per crew and week, scaled to
    /// the crew's size, progress measured straight off the feed.
    @ViewBuilder private var challengeSection: some View {
        if let challenge = CrewChallengeEngine.weeklyChallenge(
            crewCode: code,
            memberCount: max(members.count, 1),
            memberCodes: members.map(\.id),
            posts: feed) {
            CrewSection(title: "Weekly challenge") {
                CrewChallengeRow(challenge: challenge)
                    .padding(.horizontal, DS.gutter)
            }
        }
    }

    // MARK: Tournaments

    /// The last tournament once it has ended, and the full history. A live
    /// one sits under Happening now; new ones start from More.
    private func tournamentsSection(_ crew: CommunityService.Crew) -> some View {
        CrewSection(title: "Tournaments") {
            if let t = tournament, t.isEnded { tournamentRow(t, crew: crew) }
            NavigationLink {
                TournamentHistoryView(crew: crew)
            } label: {
                ArtRow(title: "All tournaments", subtitle: tournamentHint, chevron: true) {
                    ThumbView(systemImage: "clock.arrow.circlepath", tint: .dsScoreFair)
                }
            }
            .buttonStyle(.dsRow)
        }
    }

    private var tournamentHint: String? {
        liveTournament == nil ? "None running" : nil
    }

    // MARK: Settings

    private func settingsSection(_ crew: CommunityService.Crew) -> some View {
        CardSection("Settings") {
            Button { copyCode() } label: {
                CardRow("Crew code", systemImage: "number", tint: .blue, value: crew.code)
            }
            .buttonStyle(.dsCardRow)
            .accessibilityHint("Copies the crew code")
            CardToggleRow("Post my catches here", systemImage: "arrow.up.circle.fill", tint: .dsScoreGood,
                          isOn: autoPostBinding(crew))
        }
        .padding(.top, DS.Space.s6)
    }

    private func autoPostBinding(_ crew: CommunityService.Crew) -> Binding<Bool> {
        Binding(
            get: { svc.crew(withCode: crew.code)?.autoPost ?? crew.autoPost },
            set: { on in
                svc.setAutoPost(on, forCrew: crew.code)
                self.crew?.autoPost = on
                ToastCenter.shared.show(on ? "Your catches post to this crew" : "Your catches no longer post here",
                                        style: .info, haptic: false)
            }
        )
    }

    static func roleColor(_ role: CrewRole) -> Color {
        switch role {
        case .captain: .dsScoreFair
        case .mate:    .dsScoreLow
        case .admin:   DS.accent
        case .member:  .blue
        }
    }

    // MARK: Loading

    /// Instant from what this phone saved, before the refresh.
    private func loadCached() async {
        crew = svc.crew(withCode: code)
        members = svc.cachedCrewMembers(code)
        let cached = CommunityDiskCache.loadFeed(code)
        if !cached.isEmpty { feed = cached }
        if !feed.isEmpty || !members.isEmpty { isLoading = false }
        // Banner and icon are read and decoded off the main thread; the
        // synchronous decode held up the push into the crew page.
        banner = await CommunityDiskCache.image(key: "crewbanner-\(code)")
        setIcon(await CommunityDiskCache.image(key: "crewicon-\(code)"))
    }

    private func setIcon(_ image: UIImage?) {
        guard let image else { return }
        icon = image
        artTint = CrewArt.tint(of: image)
    }

    /// Every 20s: re-fetch only the first feed page (merged into what's
    /// loaded) plus the live-session and tournament state. While the crew
    /// could not be reached, the whole page is retried instead.
    private func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            if isOffline {
                await refresh()
                continue
            }
            if let page = await svc.crewFeedPage(code: code) { feed = feed.mergingFirstPage(page) }
            liveTrips = await svc.liveCrewTrips(crewCode: code)
            tournament = await svc.activeTournament(crewCode: code)
            if let t = tournament {
                if !t.isEnded { standings = await svc.teamStandings(tournament: t) }
                TournamentActivityManager.shared.sync(
                    tournament: t, standings: standings, myCode: svc.friendCode)
            }
        }
    }

    private func refresh() async {
        // Everything independent goes out in parallel.
        async let freshCrew = svc.fetchCrew(code: code)
        async let freshMembers = svc.crewMembers(code: code)
        async let art = svc.crewArt(code: code)
        async let firstPage = svc.crewFeedPage(code: code)
        async let trips = svc.liveCrewTrips(crewCode: code)
        async let tourney = svc.activeTournament(crewCode: code)

        if let fresh = await freshCrew {
            crew = fresh
            isOffline = false
        } else {
            isOffline = crew != nil
        }
        let freshList = await freshMembers
        if !freshList.isEmpty || !isOffline { members = freshList }
        let freshArt = await art
        banner = freshArt.banner
        setIcon(freshArt.icon)
        // A failed first page keeps the saved feed loadCached put on screen.
        if let page = await firstPage {
            feed = feed.mergingFirstPage(page)
            canLoadMore = page.count == pageSize
        }
        liveTrips = await trips
        tournament = await tourney
        if let t = tournament {
            standings = await svc.teamStandings(tournament: t)
            TournamentActivityManager.shared.sync(
                tournament: t, standings: standings, myCode: svc.friendCode)
        } else {
            standings = []
        }
        isLoading = false
        await loadAvatars()
        await loadPodium()
    }

    private func loadPodium() async {
        if myBoardRows == nil {
            let local = (try? await appState.catchRepository.fetchAllInBackground(limit: 100000)) ?? []
            myBoardRows = CrewBoardData.myRows(local)
        }
        let among = Set(members.map(\.id))
        guard !among.isEmpty else { return }
        let top = Array(await svc.board(metric: .count, myRows: myBoardRows ?? [], among: among).rows.prefix(3))
        podium = top
        podiumFaces = await CrewBoardData.avatars(for: Set(top.map(\.friendCode)))
    }

    /// Fetch each member's profile picture (concurrently) so the roster shows
    /// real avatars, not placeholders.
    private func loadAvatars() async {
        for m in members where memberAvatars[m.id] == nil {
            if let a = svc.cachedProfiles(for: [m.id]).first?.avatar { memberAvatars[m.id] = a }
        }
        let missing = members.map(\.id).filter { memberAvatars[$0] == nil }
        guard !missing.isEmpty else { return }
        let profiles = await svc.profiles(for: missing)
        for (c, p) in profiles where p.avatar != nil { memberAvatars[c] = p.avatar }
    }

    private func copyCode() {
        UIPasteboard.general.string = code
        ToastCenter.shared.show("Crew code copied", style: .success)
    }

    /// Leaves only once the server dropped the membership; otherwise the
    /// page stays, so the crew never vanishes from here but not from iCloud.
    private func leave() {
        guard !leaving else { return }
        leaving = true
        Task {
            let ok = await svc.leaveCrew(code: code)
            leaving = false
            guard ok else {
                ToastCenter.shared.show("Couldn't leave the crew", style: .error)
                return
            }
            Haptics.warning()
            ToastCenter.shared.show("Left the crew", style: .info, haptic: false)
            dismiss()
        }
    }
}

/// A live session to open from the session tile.
private struct CrewTripLink: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }

    init(_ trip: CommunityService.GroupTrip) {
        code = trip.id
        name = trip.name
    }
}

extension Array where Element == CommunityService.CrewPost {
    /// Replaces the newest page in place, keeping any older posts already
    /// loaded (dropping posts the server no longer returns for that window).
    fileprivate func mergingFirstPage(_ page: [CommunityService.CrewPost]) -> [CommunityService.CrewPost] {
        let oldest = page.last?.caughtAt ?? .distantPast
        let ids = Set(page.map(\.id))
        return page + filter { !ids.contains($0.id) && $0.caughtAt < oldest }
    }
}

// MARK: - Cover

private enum CrewCoverMetrics {
    /// The cover's height below the navigation bar.
    static let height: CGFloat = 150
    static let badge: CGFloat = 88
    /// The page-coloured ring between the badge and the cover.
    static let ring: CGFloat = 4
}

/// The crew's cover, edge to edge and running up under the navigation bar,
/// with the crew badge over its bottom-left edge (Luma's community page).
/// The banner photo when there is one; otherwise the crew art on its own
/// colour, as the icon draws it. Pulling the page down stretches it.
private struct CrewCover: View {
    let code: String
    let emoji: String?
    let banner: UIImage?
    let icon: UIImage?
    let tint: Color?

    /// The space between the cover's top and the top of the screen at rest:
    /// the status and navigation bars the cover runs up under.
    @State private var barHeight: CGFloat?
    /// How far the page is pulled down past the top.
    @State private var pull: CGFloat = 0

    private typealias M = CrewCoverMetrics

    /// How far the art reaches above the cover's frame. It stays put while
    /// the page scrolls up, so a photo never re-crops, and grows on a pull.
    private var reach: CGFloat { (barHeight ?? 0) + pull }

    var body: some View {
        coverSpace
            .overlay(alignment: .bottomLeading) { badge }
            .padding(.bottom, M.badge / 2)
            .onGeometryChange(for: CGFloat.self) { proxy in
                max(0, proxy.frame(in: .global).minY).rounded()
            } action: { top in
                measure(top)
            }
    }

    /// The first reading is the page at rest; anything above it is a pull.
    private func measure(_ top: CGFloat) {
        if barHeight == nil, top > 0 { barHeight = top }
        let stretch = max(0, top - (barHeight ?? top))
        if stretch != pull { pull = stretch }
    }

    /// The cover's own space on the page, with the art drawn behind it and
    /// up past its top.
    @ViewBuilder private var coverSpace: some View {
        let space = Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: M.height)
            .background(alignment: .bottom) { art }
        if let banner {
            space
                .zoomableOnTap(banner)
                .accessibilityLabel("Crew banner")
        } else {
            space.accessibilityHidden(true)
        }
    }

    private var art: some View {
        ZStack(alignment: .bottomTrailing) {
            if let banner {
                Color.dsFill
                    .frame(height: M.height + max(reach, 400))
                Color.dsFill
                    .frame(height: M.height + reach)
                    .overlay {
                        Image(uiImage: banner)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
            } else {
                artColour
                    .frame(height: M.height + max(reach, 400))
                if let icon, tint != nil {
                    // The icon is this art on this same colour, so it sits
                    // in the band without an edge.
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: M.height, height: M.height)
                        .padding(.trailing, DS.gutter)
                }
            }
        }
        .mask { cutout }
    }

    /// The crew art's colour drawn the way `CrewArt.image(for:)` draws the
    /// icon tile, so the art reads the same on the cover in either mode.
    private var artColour: some View {
        ZStack {
            Color.dsBackground
            (tint ?? DS.accent).opacity(DS.thumbTintOpacity(.dark))
        }
        .environment(\.colorScheme, .dark)
    }

    /// The whole cover, less a rounded hole around the badge, so the ring
    /// shows the page behind it.
    private var cutout: some View {
        Rectangle()
            .overlay(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: DS.Radius.thumb + M.ring, style: .continuous)
                    .frame(width: M.badge + M.ring * 2, height: M.badge + M.ring * 2)
                    .padding(.leading, DS.gutter - M.ring)
                    .offset(y: M.badge / 2 + M.ring)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
    }

    @ViewBuilder private var badge: some View {
        Group {
            if let icon {
                ThumbView(image: icon, tint: tint ?? DS.accent, size: M.badge)
            } else {
                CrewThumb(code: code, emoji: emoji, size: M.badge)
            }
        }
        .accessibilityHidden(true)
        .padding(.leading, DS.gutter)
        .offset(y: M.badge / 2)
    }
}

// MARK: - All catches

/// Every catch posted to a crew, newest first, paged as it scrolls. Pushed
/// from Recent catches on the crew page.
private struct CrewCatchesPage: View {
    let crew: CommunityService.Crew
    let tint: Color?

    @StateObject private var svc = CommunityService.shared
    @State private var feed: [CommunityService.CrewPost]
    /// Coalesces a burst of revision bumps into one reload.
    @State private var reloadGen = 0
    @State private var canLoadMore: Bool
    @State private var loadingMore = false
    @State private var openedPost: CommunityService.CrewPost?

    private let pageSize = 30

    init(crew: CommunityService.Crew, tint: Color?, feed: [CommunityService.CrewPost], canLoadMore: Bool) {
        self.crew = crew
        self.tint = tint
        _feed = State(initialValue: feed)
        _canLoadMore = State(initialValue: canLoadMore)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                DetailHeader(over: crew.name, title: "Catches")
                    .padding(.bottom, DS.Space.s4)
                rows
                footer
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(tint)
        .eventPageTitle("Catches")
        .sheet(item: $openedPost) { post in
            CrewPostSheet(post: post, crew: crew) { await reload() }
        }
        .onChange(of: svc.revision) { _, _ in
            reloadGen &+= 1
            let gen = reloadGen
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard gen == reloadGen else { return }
                await reload()
            }
        }
    }

    @ViewBuilder private var rows: some View {
        if feed.isEmpty {
            InlineEmpty(systemImage: "fish",
                        text: "No catches yet. When you or a crewmate log a catch, it shows up here.")
        } else {
            ForEach(feed) { post in
                Button { openedPost = post } label: {
                    CrewFeedRow(post: post)
                }
                .buttonStyle(.dsRow)
                .onAppear { loadMoreIfNeeded(after: post) }
            }
        }
    }

    @ViewBuilder private var footer: some View {
        if loadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s4)
        } else if !canLoadMore, feed.count > 20 {
            SectionFootnote("You're all caught up.")
        }
    }

    private func reload() async {
        guard let page = await svc.crewFeedPage(code: crew.code) else { return }
        feed = feed.mergingFirstPage(page)
    }

    private func loadMoreIfNeeded(after post: CommunityService.CrewPost) {
        guard canLoadMore, !loadingMore, post.id == feed.last?.id else { return }
        loadingMore = true
        Task {
            // A failed page is not the end of the history; scrolling back to
            // the bottom tries again.
            if let page = await svc.crewFeedPage(code: crew.code, before: feed.last?.caughtAt) {
                let ids = Set(feed.map(\.id))
                feed.append(contentsOf: page.filter { !ids.contains($0.id) })
                canLoadMore = page.count == pageSize
            }
            loadingMore = false
        }
    }
}

// MARK: - Crew settings (identity, members, roles)

struct CrewSettingsView: View {
    let crew: CommunityService.Crew
    let members: [CommunityService.GroupMember]
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var svc = CommunityService.shared

    @State private var currentCrew: CommunityService.Crew
    @State private var name: String
    @State private var iconItem: PhotosPickerItem?
    @State private var bannerItem: PhotosPickerItem?
    @State private var newIcon: UIImage?
    @State private var newBanner: UIImage?
    @State private var removeIcon = false
    @State private var removeBanner = false
    @State private var hasIcon: Bool
    @State private var hasBanner: Bool
    /// The saved icon and banner, decoded off the main thread once instead
    /// of read from disk in `body`.
    @State private var savedIcon: UIImage?
    @State private var savedBanner: UIImage?
    @State private var saving = false
    @State private var confirmingRemove: CommunityService.GroupMember?
    @State private var confirmingTransfer: CommunityService.GroupMember?
    /// The member whose role or membership is being saved; their menu
    /// shows progress until the server answers.
    @State private var busyMember: String?
    @State private var showingIconPicker = false
    @State private var showingBannerPicker = false
    @State private var showingArt = false
    @State private var art: Species?

    init(crew: CommunityService.Crew, members: [CommunityService.GroupMember],
         onChange: @escaping () -> Void) {
        self.crew = crew
        self.members = members
        self.onChange = onChange
        _currentCrew = State(initialValue: crew)
        _name = State(initialValue: crew.name)
        // Existence checks only; init runs on every parent render, so it
        // must not read and decode the images.
        _hasIcon = State(initialValue: CommunityDiskCache.hasImage(key: "crewicon-\(crew.code)"))
        _hasBanner = State(initialValue: CommunityDiskCache.hasImage(key: "crewbanner-\(crew.code)"))
        _savedIcon = State(initialValue: CommunityDiskCache.memoryImage(key: "crewicon-\(crew.code)"))
        _savedBanner = State(initialValue: CommunityDiskCache.memoryImage(key: "crewbanner-\(crew.code)"))
    }

    private var myRole: CrewRole { svc.myRole(in: currentCrew) }

    private var hasChanges: Bool {
        name.trimmingCharacters(in: .whitespaces) != currentCrew.name
            || newIcon != nil || newBanner != nil || removeIcon || removeBanner
    }

    var body: some View {
        NavigationStack {
            CrewCloudGate(closeButton: true) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if myRole.canManage {
                            identityEditor
                                .padding(.horizontal, DS.gutter)
                                .padding(.top, DS.Space.s2)
                        } else {
                            identitySummary
                        }
                        membersSection
                        rolesSection
                    }
                    .padding(.bottom, DS.Space.s8)
                    .pageWidth()
                }
                .scrollDismissesKeyboard(.interactively)
                .dsScreenBackground()
                .detailScrollEdge()
                .navigationTitle("Crew settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Captains and mates edit the crew's look, so the sheet is
                    // a form for them. Everyone else only views it.
                    if myRole.canManage {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                    }
                    if myRole.canManage {
                        ToolbarItem(placement: .confirmationAction) {
                            if saving {
                                ProgressView()
                            } else {
                                Button("Save") { save() }
                                    .bold()
                                    .disabled(!hasChanges || name.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }
                    if !myRole.canManage {
                        ToolbarItem(placement: .confirmationAction) { SheetDoneButton() }
                    }
                }
            }
            .photosPicker(isPresented: $showingBannerPicker, selection: $bannerItem, matching: .images)
            .photosPicker(isPresented: $showingIconPicker, selection: $iconItem, matching: .images)
            .onChange(of: iconItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        newIcon = img
                        removeIcon = false
                    }
                }
            }
            .onChange(of: bannerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        newBanner = img
                        removeBanner = false
                    }
                }
            }
            .onChange(of: art) { _, picked in
                guard let picked, let img = CrewArt.image(for: picked) else { return }
                newIcon = img
                removeIcon = false
            }
        }
        .interactiveDismissDisabled(hasChanges || saving)
        .task {
            if hasBanner, savedBanner == nil {
                savedBanner = await CommunityDiskCache.image(key: "crewbanner-\(crew.code)")
            }
            if hasIcon, savedIcon == nil {
                savedIcon = await CommunityDiskCache.image(key: "crewicon-\(crew.code)")
            }
        }
        .dsSheet([.large])
    }

    // MARK: Identity

    /// What the banner and icon currently look like, folding in pending picks
    /// and removals so the header previews what Save does.
    private var currentBanner: UIImage? {
        newBanner ?? (removeBanner || !hasBanner ? nil : savedBanner)
    }
    private var currentIcon: UIImage? {
        newIcon ?? (removeIcon || !hasIcon ? nil : savedIcon)
    }

    /// The banner is the banner control, the icon is the icon control, and
    /// the name sits beneath: edit what you're looking at.
    private var identityEditor: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            ZStack(alignment: .bottomLeading) {
                bannerCanvas
                iconTile
                    .padding(.leading, 14)
                    .offset(y: 34)
            }
            .padding(.bottom, 36)

            if showingArt {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Crew art")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.dsText2)
                    CrewArtPicker(selection: $art, preselect: false)
                }
                .transition(.opacity)
            }

            CrewTextField(label: "Crew name", placeholder: "Crew name", text: $name)
        }
    }

    /// For members who can't edit: the crew as it looks, and who can change it.
    private var identitySummary: some View {
        PageHero(label: "Crew code \(currentCrew.code)", value: currentCrew.name,
                 callout: "The captain and mates can change the crew's look.") {
            CrewThumb(code: currentCrew.code, emoji: currentCrew.emoji, size: 72)
        }
        .padding(.top, DS.Space.s2)
    }

    private var bannerCanvas: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                showingBannerPicker = true
            } label: {
                Group {
                    if let banner = currentBanner {
                        CrewHeroImage(image: banner, height: 128)
                    } else {
                        Color.dsFill
                            .frame(maxWidth: .infinity)
                            .frame(height: 128)
                            .overlay {
                                Label("Add a banner", systemImage: "photo.badge.plus")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.dsText2)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            }
            .buttonStyle(.dim)
            .accessibilityLabel(currentBanner == nil ? "Add a banner" : "Change banner")

            if currentBanner != nil {
                Menu {
                    Button {
                        showingBannerPicker = true
                    } label: {
                        Label("Change banner", systemImage: "photo")
                    }
                    Button(role: .destructive) {
                        removeBanner = true
                        newBanner = nil
                        bannerItem = nil
                    } label: {
                        Label("Remove banner", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.dsText)
                        .frame(width: 36, height: 36)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .accessibilityLabel("Banner options")
                .padding(DS.Space.s2)
            }
        }
    }

    private var iconTile: some View {
        Menu {
            Button {
                withAnimation(DS.Motion.softSpring) { showingArt = true }
            } label: {
                Label("Choose fish art", systemImage: "fish")
            }
            Button {
                showingIconPicker = true
            } label: {
                Label(currentIcon == nil ? "Choose a photo" : "Change photo", systemImage: "photo")
            }
            if currentIcon != nil {
                Button(role: .destructive) {
                    removeIcon = true
                    newIcon = nil
                    iconItem = nil
                    art = nil
                } label: {
                    Label("Remove icon", systemImage: "trash")
                }
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let icon = currentIcon {
                        ThumbView(image: icon, tint: DS.accent, size: 72)
                    } else {
                        CrewThumb(code: crew.code, emoji: currentCrew.emoji, size: 72)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous)
                    .stroke(Color.dsBackground, lineWidth: 3))

                Image(systemName: "pencil")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.dsOnPrimary)
                    .frame(width: 26, height: 26)
                    .background(Color.dsPrimaryButton, in: Circle())
                    .overlay(Circle().stroke(Color.dsBackground, lineWidth: 2))
                    .offset(x: 6, y: 6)
            }
        }
        .accessibilityLabel("Crew icon options")
    }

    /// Saves the name, icon and banner, then closes the sheet. A failed
    /// save keeps every edit on screen to try again.
    private func save() {
        guard !saving else { return }
        saving = true
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        Task {
            let ok = await svc.updateCrewIdentity(
                currentCrew,
                name: trimmedName != currentCrew.name ? trimmedName : nil,
                banner: newBanner, iconPhoto: newIcon,
                removeBanner: removeBanner, removeIcon: removeIcon)
            saving = false
            if ok {
                ToastCenter.shared.show("Crew updated", style: .success)
                currentCrew.name = trimmedName
                if let newIcon { hasIcon = true; savedIcon = newIcon }
                if removeIcon { hasIcon = false; removeIcon = false; savedIcon = nil }
                if let newBanner { hasBanner = true; savedBanner = newBanner }
                if removeBanner { hasBanner = false; removeBanner = false; savedBanner = nil }
                newIcon = nil; newBanner = nil
                withAnimation(DS.Motion.softSpring) { showingArt = false }
                onChange()
                dismiss()
            } else {
                ToastCenter.shared.show("Couldn't update the crew", style: .error)
            }
        }
    }

    // MARK: Members

    private var membersSection: some View {
        CrewSection(title: "Members", detail: "\(members.count)") {
            CardGroup(separatorInset: DS.Space.s4 + 44 + DS.Space.s3) {
                ForEach(members, id: \.id) { m in
                    memberRow(m)
                }
            }
        }
        .confirmationDialog(
            "Remove from crew?",
            isPresented: Binding(get: { confirmingRemove != nil },
                                 set: { if !$0 { confirmingRemove = nil } }),
            titleVisibility: .visible,
            presenting: confirmingRemove
        ) { m in
            Button("Remove \(m.name)", role: .destructive) {
                busyMember = m.id
                Task {
                    defer { busyMember = nil }
                    if await svc.removeMember(m.id, fromCrew: currentCrew) {
                        Haptics.warning()
                        ToastCenter.shared.show("Removed from the crew", style: .info, haptic: false)
                        onChange()
                    } else {
                        ToastCenter.shared.show("Couldn't remove them", style: .error)
                    }
                }
            }
        } message: { m in
            Text("\(m.name) can join again with the crew code.")
        }
        .confirmationDialog(
            "Hand over the crew?",
            isPresented: Binding(get: { confirmingTransfer != nil },
                                 set: { if !$0 { confirmingTransfer = nil } }),
            titleVisibility: .visible,
            presenting: confirmingTransfer
        ) { m in
            Button("Make \(m.name) captain", role: .destructive) {
                busyMember = m.id
                Task {
                    defer { busyMember = nil }
                    if let updated = await svc.transferCaptaincy(to: m.id, name: m.name, in: currentCrew) {
                        currentCrew = updated
                        Haptics.warning()
                        ToastCenter.shared.show("\(m.name) is captain now. You stay aboard as a mate.",
                                                style: .success, haptic: false)
                        onChange()
                    } else {
                        ToastCenter.shared.show("Couldn't hand over the crew", style: .error)
                    }
                }
            }
        } message: { m in
            Text("\(m.name) becomes the captain with full control. You stay aboard as a mate.")
        }
    }

    private func memberRow(_ m: CommunityService.GroupMember) -> some View {
        let role = svc.role(of: m.id, in: currentCrew)
        let isSelf = m.id == svc.friendCode
        let isCaptain = m.id == currentCrew.createdByCode
        return HStack(spacing: DS.Space.s3) {
            CrewAvatar(image: isSelf ? svc.myAvatar : svc.cachedProfiles(for: [m.id]).first?.avatar,
                       name: m.name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(isSelf ? "You" : m.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.dsText)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                Text(role.label)
                    .font(.subheadline)
                    .foregroundStyle(DS.ink(CrewDetailView.roleColor(role)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if busyMember == m.id {
                ProgressView()
                    .frame(width: 44, height: 44)
            } else if !isSelf, !isCaptain, myRole.canModerate {
                memberMenu(m, role: role)
                    .disabled(busyMember != nil)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func memberMenu(_ m: CommunityService.GroupMember, role: CrewRole) -> some View {
        Menu {
            if myRole.canManage {
                if myRole == .captain {
                    Button { confirmingTransfer = m } label: {
                        Label("Make captain", systemImage: CrewRole.captain.icon)
                    }
                }
                if myRole == .captain, role != .mate {
                    Button { apply(.mate, to: m) } label: {
                        Label("Make mate", systemImage: CrewRole.mate.icon)
                    }
                }
                if role != .admin {
                    Button { apply(.admin, to: m) } label: {
                        Label("Make admin", systemImage: CrewRole.admin.icon)
                    }
                }
                if role != .member {
                    Button { apply(.member, to: m) } label: {
                        Label("Remove role", systemImage: "person.fill")
                    }
                }
                Divider()
            }
            Button(role: .destructive) { confirmingRemove = m } label: {
                Label("Remove from crew", systemImage: "person.fill.xmark")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.dsText2)
                .frame(width: 36, height: 36)
                .background(Color.dsFill2, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More for \(m.name)")
    }

    private func apply(_ role: CrewRole, to m: CommunityService.GroupMember) {
        busyMember = m.id
        Task {
            defer { busyMember = nil }
            if let updated = await svc.setRole(role, for: m.id, in: currentCrew) {
                currentCrew = updated
                ToastCenter.shared.show(role == .member ? "\(m.name) is a member again"
                                                        : "\(m.name) is now \(role == .admin ? "an" : "a") \(role.label.lowercased())",
                                        style: .success)
                onChange()
            } else {
                ToastCenter.shared.show("Couldn't change that role", style: .error)
            }
        }
    }

    // MARK: Roles

    static func roleSummary(_ role: CrewRole) -> String {
        switch role {
        case .captain: "Full control, and can hand the crew over."
        case .mate:    "Edits the crew's look, sets roles, manages members and runs tournaments."
        case .admin:   "Deletes posts, removes members and runs tournaments."
        case .member:  "Posts catches, reacts and joins sessions and tournaments."
        }
    }

    /// The whole ladder with yours marked, so everyone knows what each role means.
    private var rolesSection: some View {
        CrewSection(title: "Roles") {
            CardGroup(separatorInset: DS.Space.s4 + 40 + DS.Space.s3) {
                ForEach([CrewRole.captain, .mate, .admin, .member], id: \.self) { role in
                    roleRow(role)
                }
            }
        }
    }

    private func roleRow(_ role: CrewRole) -> some View {
                HStack(alignment: .top, spacing: DS.Space.s3) {
                    ThumbView(systemImage: role.icon, tint: CrewDetailView.roleColor(role), size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(role.label)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.dsText)
                        Text(Self.roleSummary(role))
                            .font(.subheadline)
                            .foregroundStyle(.dsText2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if role == myRole { CrewPill(text: "You") }
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
    }
}

// MARK: - Species art lookup

/// Species-by-name lookup for feed rows: a CrewPost only carries the name,
/// and 1,500 species are too many to re-scan per row, so the index builds
/// once and sticks around.
@MainActor
enum SpeciesArtLookup {
    private static var byName: [String: Species] = [:]
    private static var loaded = false

    static func species(named name: String, appState: AppState) -> Species? {
        if !loaded {
            for s in (try? appState.speciesRepository.fetchAll()) ?? [] {
                byName[s.commonName.lowercased()] = s
            }
            loaded = true
        }
        return byName[name.lowercased()]
    }
}

// MARK: - Crew catch sheet

/// One crew catch, opened from a feed row: the photo or species art, who
/// caught it, reactions, comments and the caption.
struct CrewPostSheet: View {
    let post: CommunityService.CrewPost
    /// The crew this post lives in, when known: needed for moderation
    /// (delete others' posts) checks and the delete call itself.
    var crew: CommunityService.Crew? = nil
    let reload: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("units") private var units = "metric"
    private var svc: CommunityService { .shared }
    @State private var photo: UIImage?
    /// True once the photo couldn't be fetched, so the hero stops spinning.
    @State private var photoFailed = false
    @State private var caption: String?
    @State private var editingCaption = false
    @State private var captionDraft = ""
    @State private var confirmingDelete = false
    @State private var showingComments = false
    /// The sheet's height. Opening the comments raises it to full height.
    @State private var detent: PresentationDetent = .medium
    /// Optimistic comment count while the thread is open.
    @State private var localCommentCount: Int?
    /// Optimistic reactions, shown the instant you tap. The sheet holds a
    /// snapshot of the post, so these stay the truth until it closes.
    @State private var localReactions: [CommunityService.CrewReaction]?

    private var isMine: Bool { post.authorCode == svc.friendCode }
    private var canModerate: Bool { crew.map { svc.myRole(in: $0).canModerate } ?? false }
    private var reactions: [CommunityService.CrewReaction] { localReactions ?? post.reactions }
    private var shownCaption: String { caption ?? post.caption }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if post.hasPhoto {
                        hero
                            .padding(.horizontal, DS.gutter)
                            .padding(.top, DS.Space.s2)
                            .padding(.bottom, DS.Space.s5)
                    }
                    PageHero(label: post.caughtAt.formatted(.relative(presentation: .named)),
                             value: CrewText.catchTitle(species: post.species, lengthCm: post.lengthCm,
                                                        weightKg: post.weightKg),
                             callout: post.tripName.isEmpty ? crew?.name : "On \(post.tripName)") {
                        if !post.hasPhoto { hero }
                    }
                    .padding(.top, post.hasPhoto ? 0 : DS.Space.s2)
                    captionBlock
                    sizeTiles
                    SectionTitle("Reactions")
                        .padding(.top, DS.Space.s6)
                    reactionRow
                    CardGroup { commentsRow }
                        .padding(.top, DS.Space.s3)
                    SectionTitle("Caught by")
                        .padding(.top, DS.Space.s6)
                    CardGroup { authorRow }
                }
                .padding(.bottom, DS.Space.s6)
                .pageWidth()
            }
            .dsScreenBackground()
            // The catch's name fades into the bar once the hero scrolls away.
            .eventPageTitle(CrewText.catchTitle(species: post.species, lengthCm: post.lengthCm,
                                                weightKg: post.weightKg))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { moreMenu }
                ToolbarItem(placement: .confirmationAction) { SheetDoneButton() }
            }
            // The thread is pushed inside this sheet rather than stacked as
            // a second sheet on top of it.
            .navigationDestination(isPresented: $showingComments) {
                CrewCommentsSheet(post: post, crew: crew) { count in
                    localCommentCount = count
                }
            }
        }
        // dsSheet's chrome, with the detent bound so opening the comments
        // can raise the sheet.
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.dsBackground)
        .task(id: post.id) {
            guard post.hasPhoto, photo == nil else { return }
            photoFailed = false
            if CrewCloud.shared.isAvailable {
                photo = await svc.crewPostImage(recordName: post.id)
            }
            photoFailed = photo == nil
        }
        .alert("Caption", isPresented: $editingCaption) {
            TextField("Say something", text: $captionDraft)
            Button("Save") { saveCaption(captionDraft) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this post?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete post", role: .destructive) {
                Task {
                    if let crew, await svc.deleteCrewPost(post, in: crew) {
                        Haptics.warning()
                        ToastCenter.shared.show("Post deleted", style: .info, haptic: false)
                        await reload()
                        dismiss()
                    } else {
                        ToastCenter.shared.show("Couldn't delete the post", style: .error)
                    }
                }
            }
        } message: {
            Text("The post disappears from the crew's feed for everyone.")
        }
    }

    @ViewBuilder private var hero: some View {
        if post.hasPhoto {
            Group {
                if let photo {
                    CrewHeroImage(image: photo, height: 260)
                } else {
                    Color.dsFill
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .overlay {
                            if photoFailed {
                                VStack(spacing: DS.Space.s3) {
                                    ThumbView(systemImage: "photo", tint: CrewTint.fish, size: 72)
                                    Text("Photo unavailable offline")
                                        .font(.subheadline)
                                        .foregroundStyle(.dsText2)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.horizontal, DS.Space.s4)
                            } else {
                                ProgressView()
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                }
            }
            .zoomableOnTap(photo)
            .accessibilityLabel(photoFailed ? "Photo unavailable offline" : "Catch photo")
        } else if let sp = SpeciesArtLookup.species(named: post.species, appState: appState) {
            ThumbView(species: sp, size: 100)
        } else {
            ThumbView(systemImage: "fish.fill", tint: CrewTint.fish, size: 100)
        }
    }

    @ViewBuilder private var captionBlock: some View {
        if !shownCaption.isEmpty {
            Text(shownCaption)
                .font(.body)
                .foregroundStyle(.dsText)
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s3)
        } else if isMine {
            Button("Add a caption") { startEditingCaption() }
                .buttonStyle(TonalButtonStyle(fullWidth: false))
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s3)
        }
    }

    @ViewBuilder private var sizeTiles: some View {
        if post.weightKg != nil || post.lengthCm != nil {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                if let w = post.weightKg {
                    let p = Units.weightParts(kg: w, imperial: units == "imperial")
                    StatTile("Weight", systemImage: "scalemass.fill", tint: CrewTint.weight, value: p.0, unit: p.1, width: nil)
                }
                if let l = post.lengthCm {
                    let p = Units.lengthParts(cm: l, imperial: units == "imperial")
                    StatTile("Length", systemImage: "ruler.fill", tint: CrewTint.length, value: p.0, unit: p.1, width: nil)
                }
            }
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s5)
        }
    }

    private var moreMenu: some View {
        Menu {
            if isMine {
                Button { startEditingCaption() } label: {
                    Label(shownCaption.isEmpty ? "Add caption" : "Edit caption", systemImage: "pencil")
                }
            }
            // No article, so a species starting with a vowel never reads "a eel".
            ShareLink(item: "\(isMine ? svc.myName : post.authorName) caught \(post.species.lowercased()) on Currents") {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            if (isMine || canModerate), crew != nil {
                Divider()
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete post", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    /// The five reactions as tiles, always visible, tap to toggle. Each symbol
    /// sits on a faint tile of its own colour; yours fills stronger with a
    /// ring. Counts show once someone's used one.
    private var reactionRow: some View {
        let grouped = Dictionary(grouping: reactions, by: \.emoji)
        let mine = reactions.first { $0.reactorCode == svc.friendCode }?.emoji
        return HStack(spacing: DS.Space.s2) {
            ForEach(CommunityService.crewReactionEmojis, id: \.self) { emoji in
                CrewReactionTile(emoji: emoji, count: grouped[emoji]?.count ?? 0,
                                 selected: mine == emoji) { toggle(emoji) }
            }
        }
        .padding(.horizontal, DS.gutter)
    }

    private var commentsRow: some View {
        let count = localCommentCount ?? post.commentCount ?? 0
        return Button {
            detent = .large
            showingComments = true
        } label: {
            CardRow("Comments", subtitle: count == 0 ? "Start the conversation" : nil,
                    systemImage: "bubble.left.and.bubble.right.fill", tint: .blue,
                    value: count > 0 ? "\(count)" : nil, chevron: true)
        }
        .buttonStyle(.dsCardRow)
        .accessibilityLabel(count == 1 ? "1 comment" : "\(count) comments")
    }

    private var authorRow: some View {
        NavigationLink {
            FriendProfileView(code: post.authorCode)
        } label: {
            // CardRow's anatomy with the angler's face in place of the icon tile.
            HStack(spacing: 14) {
                CrewAvatar(image: isMine ? svc.myAvatar : svc.cachedProfiles(for: [post.authorCode]).first?.avatar,
                           name: post.authorName, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isMine ? "You" : post.authorName)
                        .font(.body)
                        .foregroundStyle(.dsText)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    Text(isMine ? "Your catch" : "See their profile")
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.dsText3)
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, 10)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dsCardRow)
        .accessibilityElement(children: .combine)
    }

    private func toggle(_ emoji: String) {
        // Optimistic: the tap shows immediately.
        var rs = reactions
        if let i = rs.firstIndex(where: { $0.reactorCode == svc.friendCode }) {
            let had = rs[i].emoji
            rs.remove(at: i)
            if had != emoji {
                rs.append(.init(id: "local-\(emoji)", reactorCode: svc.friendCode,
                                reactorName: svc.myName, emoji: emoji))
            }
        } else {
            rs.append(.init(id: "local-\(emoji)", reactorCode: svc.friendCode,
                            reactorName: svc.myName, emoji: emoji))
        }
        let previous = localReactions
        withAnimation(DS.Motion.spring) { localReactions = rs }
        Task {
            let saved = await svc.toggleCrewReaction(emoji: emoji, postId: post.id,
                                                     crewCode: post.crewCode, postAuthorCode: post.authorCode)
            guard saved else {
                withAnimation(DS.Motion.spring) { localReactions = previous }
                ToastCenter.shared.show("Couldn't save the reaction", style: .error)
                return
            }
            await reload()
        }
    }

    /// Shows the new caption at once and puts the old one back if the save
    /// fails.
    private func saveCaption(_ text: String) {
        let previous = caption
        caption = text
        Task {
            if await svc.setCrewCaption(text, postId: post.id) {
                ToastCenter.shared.show("Caption saved", style: .success)
                await reload()
            } else {
                caption = previous
                ToastCenter.shared.show("Couldn't save the caption", style: .error)
            }
        }
    }

    private func startEditingCaption() {
        captionDraft = shownCaption
        editingCaption = true
    }
}

// MARK: - Comments

/// The comment thread on one crew post: conversation-ordered list with the
/// composer pinned underneath. Authors delete their own comments; moderators
/// anyone's. Pushed inside the post sheet's navigation stack, so it has no
/// stack or Done of its own and goes back with the system Back button.
struct CrewCommentsSheet: View {
    let post: CommunityService.CrewPost
    var crew: CommunityService.Crew? = nil
    /// Reports the live count so the post's comment badge stays honest.
    var onCountChange: (Int) -> Void = { _ in }

    private var svc: CommunityService { .shared }
    @State private var comments: [CommunityService.CrewComment] = []
    @State private var loading = true
    /// True when the thread couldn't load and nothing was cached, which is
    /// not the same as a post with no comments.
    @State private var loadFailed = false
    @State private var draft = ""
    @State private var sending = false
    @FocusState private var composerFocused: Bool
    /// Composer modes: replying attaches to a thread; editing rewrites in place.
    @State private var replyingTo: CommunityService.CrewComment?
    @State private var editing: CommunityService.CrewComment?
    /// The comment waiting on the delete confirmation.
    @State private var commentToDelete: CommunityService.CrewComment?

    private var canModerate: Bool { crew.map { svc.myRole(in: $0).canModerate } ?? false }
    private var draftEmpty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Top-level comments with their replies, conversation-ordered. Replies
    /// whose parent was deleted are promoted to top level rather than lost.
    private var threads: [(parent: CommunityService.CrewComment, replies: [CommunityService.CrewComment])] {
        let parentIds = Set(comments.filter { $0.replyToId == nil }.map(\.id))
        let byParent = Dictionary(grouping: comments.filter {
            $0.replyToId != nil && parentIds.contains($0.replyToId!)
        }, by: { $0.replyToId! })
        return comments
            .filter { $0.replyToId == nil || !parentIds.contains($0.replyToId!) }
            .map { ($0, byParent[$0.id] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if loading && comments.isEmpty {
                Spacer()
                FishLoader(message: "Loading comments")
                    .frame(height: 120)
                Spacer()
            } else if comments.isEmpty && loadFailed {
                InlineEmpty(systemImage: "wifi.slash", text: "Comments need a connection",
                            actionTitle: "Try again") { Task { await load() } }
                    .padding(.top, DS.Space.s4)
                Spacer()
            } else if comments.isEmpty {
                Spacer()
                VStack(spacing: DS.Space.s3) {
                    ThumbView(systemImage: "bubble.left.and.bubble.right.fill", tint: .blue, size: 72)
                    Text("No comments yet")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.dsText)
                }
                .padding(.horizontal, DS.gutter)
                .accessibilityElement(children: .combine)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(threads, id: \.parent.id) { thread in
                            commentRow(thread.parent, isReply: false)
                                .id(thread.parent.id)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.gutter,
                                                              bottom: DS.Space.s1, trailing: DS.Space.s3))
                            ForEach(thread.replies) { reply in
                                commentRow(reply, isReply: true)
                                    .id(reply.id)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: DS.Space.s1, leading: DS.gutter + DS.Space.s8 + DS.Space.s2,
                                                                  bottom: DS.Space.s1, trailing: DS.Space.s3))
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: comments.count) { _, _ in
                        if let last = comments.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
            composer
        }
        .dsScreenBackground()
        .navigationTitle("Comments")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog("Delete this comment?",
                            isPresented: Binding(get: { commentToDelete != nil },
                                                 set: { if !$0 { commentToDelete = nil } }),
                            titleVisibility: .visible,
                            presenting: commentToDelete) { comment in
            Button("Delete comment", role: .destructive) { delete(comment) }
        } message: { _ in
            Text("It disappears for everyone in the crew.")
        }
    }

    /// Loads the thread. A failed load with nothing cached leaves the count
    /// on the post alone rather than reporting zero.
    private func load() async {
        loading = true
        if let loaded = await svc.loadComments(postId: post.id) {
            comments = loaded
            loadFailed = false
            onCountChange(loaded.count)
        } else {
            loadFailed = true
        }
        loading = false
    }

    private func commentRow(_ comment: CommunityService.CrewComment, isReply: Bool) -> some View {
        let mine = comment.authorCode == svc.friendCode
        return HStack(alignment: .top, spacing: 10) {
            CrewAvatar(image: mine ? svc.myAvatar : svc.cachedProfiles(for: [comment.authorCode]).first?.avatar,
                       name: comment.authorName, size: isReply ? 28 : 34)
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(mine ? "You" : comment.authorName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.dsText)
                        Text(comment.createdAt.formatted(.relative(presentation: .named)))
                            .font(.footnote).foregroundStyle(.dsText2)
                        if comment.editedAt != nil {
                            Text("Edited")
                                .font(.footnote).foregroundStyle(.dsText2)
                        }
                    }
                    Text(comment.text).font(.body).foregroundStyle(.dsText)
                }
                .padding(.horizontal, DS.Space.s3)
                .padding(.vertical, DS.Space.s2)
                .background(mine ? DS.accent.opacity(0.14) : Color.dsFill,
                            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                // Reply sits under the comment, always visible.
                Button {
                    editing = nil
                    replyingTo = comment
                    composerFocused = true
                } label: {
                    Text("Reply")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DS.accent)
                }
                .buttonStyle(.dim)
                .padding(.leading, DS.Space.s3)
            }
            Spacer(minLength: 0)
            if mine || canModerate {
                Menu {
                    if mine {
                        Button {
                            replyingTo = nil
                            editing = comment
                            draft = comment.text
                            composerFocused = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                    Button(role: .destructive) { commentToDelete = comment } label: {
                        Label("Delete comment", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Comment options")
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            // Mode banner: who you're replying to, or that you're editing,
            // with a way out.
            if replyingTo != nil || editing != nil {
                HStack(spacing: 6) {
                    Image(systemName: editing != nil ? "pencil" : "arrowshape.turn.up.left.fill")
                        .font(.footnote)
                    if let replyingTo {
                        Text("Replying to \(replyingTo.authorCode == svc.friendCode ? "yourself" : replyingTo.authorName)")
                            .font(.footnote)
                    } else if editing != nil {
                        Text("Editing your comment").font(.footnote)
                    }
                    Spacer()
                    Button {
                        cancelComposerMode()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.dsText3)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.dim)
                    .accessibilityLabel(editing != nil ? "Cancel editing" : "Cancel reply")
                }
                .foregroundStyle(.dsText2)
                // Same trailing inset as the composer row, so the close
                // target sits in one column with the send button below.
                .padding(.leading, DS.gutter)
                .padding(.trailing, DS.gutter - DS.Space.s1)
            }
            HStack(spacing: DS.Space.s2) {
                TextField(editing != nil ? "Edit your comment"
                          : replyingTo != nil ? "Write a reply" : "Add a comment",
                          text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, DS.Space.s3)
                    .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                Button {
                    send()
                } label: {
                    Image(systemName: editing != nil ? "checkmark" : "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(draftEmpty ? Color.dsText3 : Color.dsOnPrimary)
                        .frame(width: 36, height: 36)
                        .background(draftEmpty ? Color.dsFill : Color.dsPrimaryButton, in: Circle())
                        // A 44 pt target around the 36 pt circle.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dim)
                .buttonHaptic(.press)
                .disabled(sending || draftEmpty)
                .accessibilityLabel(editing != nil ? "Save comment" : "Post comment")
            }
            // The send circle sits 4 pt inside its target, so the trailing
            // gutter is 4 pt short to keep the circle on the gutter line.
            .padding(.leading, DS.gutter)
            .padding(.trailing, DS.gutter - DS.Space.s1)
            .padding(.vertical, DS.Space.s2)
        }
        .background(Color.dsBackground)
        .overlay(alignment: .top) { Divider().overlay(Color.dsSeparator) }
    }

    private func cancelComposerMode() {
        if editing != nil { draft = "" }
        replyingTo = nil
        editing = nil
    }

    private func send() {
        let text = draft
        draft = ""
        sending = true
        if let editing {
            let target = editing
            self.editing = nil
            Task {
                if let updated = await svc.editComment(target, text: text) {
                    if let i = comments.firstIndex(where: { $0.id == updated.id }) {
                        comments[i] = updated
                    }
                } else {
                    draft = text
                    self.editing = target
                    ToastCenter.shared.show("Couldn't save the edit", style: .error)
                }
                sending = false
            }
            return
        }
        let parent = replyingTo
        replyingTo = nil
        Task {
            if let added = await svc.addComment(text, post: post, replyTo: parent) {
                comments.append(added)
                onCountChange(comments.count)
            } else {
                draft = text     // give the words back rather than losing them
                replyingTo = parent
                ToastCenter.shared.show("Couldn't post the comment", style: .error)
            }
            sending = false
        }
    }

    private func delete(_ comment: CommunityService.CrewComment) {
        Task {
            if await svc.deleteComment(comment, in: crew) {
                Haptics.warning()
                // A deleted parent's replies get promoted by `threads`, so
                // nothing vanishes silently.
                comments.removeAll { $0.id == comment.id }
                onCountChange(comments.count)
            } else {
                ToastCenter.shared.show("Couldn't delete the comment", style: .error)
            }
        }
    }
}

// MARK: - Join a crew from an invite link

/// Presented when the app opens a `currents://crew/<CODE>` deep link. Shows
/// the crew, then joins with one tap (setting up a community profile first if
/// the angler hasn't got one yet).
struct JoinCrewConfirmView: View {
    let code: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var svc = CommunityService.shared

    @ObservedObject private var connection = CrewConnection.shared

    @State private var crew: CommunityService.Crew?
    @State private var members = 0
    @State private var loading = true
    /// The crew couldn't be fetched, which is not the same as no crew
    /// holding the code.
    @State private var lookupFailed = false
    @State private var joining = false
    @State private var joined = false

    private var shownCode: String { code.uppercased() }
    private var alreadyIn: Bool { svc.myCrews.contains { $0.code == shownCode } }
    private var isIn: Bool { joined || alreadyIn }

    var body: some View {
        CrewCloudGate(closeButton: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if svc.joined {
                        invite
                    } else {
                        joinGate
                    }
                }
                .padding(.bottom, DS.Space.s6)
                .pageWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .dsScreenBackground()
            .eventPageTitle(crew?.name ?? "Crew invite")
            .toolbar {
                if !isIn {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                if isIn {
                    ToolbarItem(placement: .confirmationAction) { SheetDoneButton() }
                }
            }
            .task { await loadPreview() }
        }
        .dsSheet([.large])
    }

    /// On Crew already: the crew with a Join button, or why there's nothing
    /// to join. Each state has its own hero, so nothing dead sits on screen.
    @ViewBuilder private var invite: some View {
        if let crew {
            PageHero(label: "Crew invite", value: crew.name) {
                CrewThumb(code: shownCode, emoji: crew.emoji, size: 92)
            }
            .padding(.top, DS.Space.s4)
            inviteFacts(crew)
            confirmBody
        } else if loading {
            PageHero(label: "Crew invite", value: "Loading crew") {
                CrewThumb(code: shownCode, emoji: nil, size: 92)
            }
            .padding(.top, DS.Space.s4)
        } else if lookupFailed {
            PageHero(label: "Crew code \(shownCode)", value: "Can't reach Crew right now") {
                ThumbView(systemImage: "wifi.slash", tint: .orange, size: 92)
            }
            .padding(.top, DS.Space.s4)
            Button("Try again") { Task { await loadPreview() } }
                .buttonStyle(.dsTonal)
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s5)
        } else {
            PageHero(label: "Crew code \(shownCode)", value: "No crew found") {
                ThumbView(systemImage: "person.3.fill", tint: CrewTint.people, size: 92)
            }
            .padding(.top, DS.Space.s4)
        }
    }

    /// `fetchCrew` folds a failed fetch into nil, so the connection is what
    /// tells a crew that can't be reached from a code no crew holds.
    private func loadPreview() async {
        loading = true
        lookupFailed = false
        if let fetched = await svc.fetchCrew(code: shownCode) {
            crew = fetched
            members = await svc.crewMembers(code: shownCode).count
        } else {
            lookupFailed = connection.isOffline
        }
        loading = false
    }

    /// Joins and re-checks the code in one step, so a crew deleted since the
    /// invite opened shows as gone and a lost connection says so.
    private func join() {
        guard !joining else { return }
        joining = true
        Task {
            let result = await svc.lookupAndJoinCrew(code: shownCode)
            joining = false
            switch result {
            case .found(let joinedCrew):
                crew = joinedCrew
                joined = true
                Haptics.success()
                ToastCenter.shared.show("Joined the crew", style: .success, haptic: false)
            case .notFound:
                Haptics.error()
                crew = nil
                lookupFailed = false
            case .failed, .ownCode:
                ToastCenter.shared.show("Can't reach Crew right now", style: .error)
            }
        }
    }

    private func inviteFacts(_ crew: CommunityService.Crew) -> some View {
        CardGroup {
            CardRow("Anglers", systemImage: "person.2.fill", tint: CrewTint.people, value: "\(members)")
            CardRow("Started by", systemImage: "flag.fill", tint: .orange, value: crew.createdByName)
        }
        .padding(.top, DS.Space.s5)
        .accessibilityElement(children: .combine)
    }

    /// Not on Crew yet: the invite up top, then pick a name. Once joined,
    /// confirmBody takes over with the Join crew button.
    private var joinGate: some View {
        VStack(spacing: DS.Space.s3) {
            CrewThumb(code: code.uppercased(), emoji: crew?.emoji, size: 96)
                .padding(.top, DS.Space.s4)
                .padding(.bottom, DS.Space.s2)
            Text(crew.map { "Join \($0.name)" } ?? "Join a crew")
                .font(.title.bold())
                .foregroundStyle(.dsText)
                .multilineTextAlignment(.center)
            Text("Pick the name your crew will see.")
                .font(.body)
                .foregroundStyle(.dsText2)
                .multilineTextAlignment(.center)
            CrewJoinForm(buttonTitle: "Continue")
                .padding(.top, DS.Space.s3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.gutter)
    }

    private var confirmBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if joined || alreadyIn {
                Label("You're in this crew", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.dsScoreGood)
                    .frame(maxWidth: .infinity, minHeight: 52)
            } else {
                Button {
                    join()
                } label: {
                    if joining { ProgressView() } else { Text("Join crew") }
                }
                .buttonStyle(.dsPrimary)
                .disabled(joining)
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s5)
    }
}
