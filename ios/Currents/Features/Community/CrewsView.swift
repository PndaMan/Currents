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
                DetailHeader(title: "Your crews",
                             subtitle: svc.myCrews.isEmpty ? nil
                                : "\(svc.myCrews.count) \(svc.myCrews.count == 1 ? "crew" : "crews")")
                ActionTriple {
                    Button { setup = .start } label: {
                        Label("New crew", systemImage: "plus")
                    }
                    .buttonStyle(ActionTileStyle(.primary))
                    Button { setup = .join } label: {
                        Label("Join with code", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(ActionTileStyle())
                }
                .padding(.top, DS.Space.s5)

                if svc.myCrews.isEmpty {
                    ContentUnavailableView {
                        Label("No crews yet", systemImage: "person.3")
                    } description: {
                        Text("A crew is your fishing group: a shared catch feed, weekly challenges, tournaments and live sessions.")
                    }
                    .padding(.top, DS.Space.s8)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(svc.myCrews) { crew in
                            NavigationLink(value: CrewRoute.crew(crew.code)) {
                                ArtRow(title: crew.name,
                                       subtitle: CrewText.crewSubtitle(crew, tournamentLive: false),
                                       chevron: true) {
                                    CrewThumb(code: crew.code, emoji: crew.emoji)
                                }
                            }
                            .buttonStyle(.dsRow)
                        }
                    }
                    .padding(.top, DS.Space.s5)
                }
            }
            .padding(.bottom, DS.Space.s8)
        }
        .detailTint(DS.accent)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $setup) { mode in CrewSetupView(joining: mode == .join) }
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
    @State private var emoji = "🎣"  // ui-lint: allow, crew icon emoji is stored crew data
    @State private var joinCode = ""
    @State private var busy = false
    @State private var joinError: String?

    /// The crew's own icon when it has no photo. Stored as an emoji on the
    /// crew record, so older builds still show it.
    private let emojis = ["🎣", "🐟", "🐠", "🦈", "🌊", "⚓️", "🛥️", "🏆"]  // ui-lint: allow, crew icon emoji is stored crew data

    init(joining: Bool = false) {
        self.joining = joining
        _mode = State(initialValue: joining ? .join : .start)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s5) {
                    Picker("Start or join", selection: $mode) {
                        Text("Start a crew").tag(CrewSetupMode.start)
                        Text("Join a crew").tag(CrewSetupMode.join)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if mode == .start { startForm } else { joinForm }
                }
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s3)
                .padding(.bottom, DS.Space.s6)
            }
            .background(Color.dsBackground)
            .navigationTitle(mode == .start ? "New crew" : "Join a crew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var startForm: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            CrewTextField(label: "Crew name", placeholder: "The Usual Suspects", text: $name)
            VStack(alignment: .leading, spacing: 6) {
                Text("Crew icon")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.dsText2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(emojis, id: \.self) { e in
                            Button { emoji = e } label: {
                                Text(e)
                                    .font(.title2)
                                    .frame(width: 52, height: 52)
                                    .background(emoji == e ? DS.accent.opacity(0.22) : Color.dsFill,
                                                in: RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous)
                                        .stroke(emoji == e ? DS.accent : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.dim)
                            .accessibilityAddTraits(emoji == e ? .isSelected : [])
                        }
                    }
                }
                .sensoryFeedback(.selection, trigger: emoji)
            }
            Button {
                Task {
                    busy = true
                    let crew = await svc.createCrew(name: name.trimmingCharacters(in: .whitespaces), emoji: emoji)
                    busy = false
                    if crew != nil {
                        Haptics.success()
                        ToastCenter.shared.show("Crew created", style: .success, haptic: false)
                        dismiss()
                    } else {
                        ToastCenter.shared.show("Couldn't create the crew", style: .error)
                    }
                }
            } label: {
                if busy { ProgressView() } else { Text("Create crew") }
            }
            .buttonStyle(.dsPrimary)
            .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
            Text("Invite friends afterwards. Everyone's catches show up in the crew's feed automatically. You can turn that off per crew.")
                .font(.footnote)
                .foregroundStyle(.dsText2)
        }
    }

    private var joinForm: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text("Enter the 6-character code a friend shared with you.")
                .font(.body)
                .foregroundStyle(.dsText2)
            CodeField(text: $joinCode, placeholder: "Crew code")
                .onChange(of: joinCode) { _, _ in joinError = nil }
            if let joinError {
                Label(joinError, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.dsScoreSlow)
            }
            Button {
                Task {
                    busy = true
                    let crew = await svc.joinCrew(code: joinCode)
                    busy = false
                    if crew != nil {
                        Haptics.success()
                        ToastCenter.shared.show("Joined the crew", style: .success, haptic: false)
                        dismiss()
                    } else {
                        Haptics.warning()
                        joinError = "No crew matches that code. Check it with whoever sent it."
                    }
                }
            } label: {
                if busy { ProgressView() } else { Text("Join crew") }
            }
            .buttonStyle(.dsPrimary)
            .disabled(busy || joinCode.trimmingCharacters(in: .whitespaces).count != 6)
        }
    }
}

// MARK: - Crew page

/// One crew, pushed from the Crew tab or a crew push notification: who's in
/// it, the tournament, the weekly challenge, who's fishing now and the
/// catch feed.
struct CrewDetailView: View {
    let code: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var svc = CommunityService.shared
    @State private var crew: CommunityService.Crew?
    @State private var members: [CommunityService.GroupMember] = []
    @State private var memberAvatars: [String: UIImage] = [:]
    @State private var feed: [CommunityService.CrewPost] = []
    @State private var isLoading = true
    @State private var canLoadMore = false
    @State private var loadingMore = false
    @State private var banner: UIImage?
    @State private var liveTrips: [CommunityService.GroupTrip] = []
    @State private var tournament: CommunityService.Tournament?
    @State private var standings: [CommunityService.TeamStanding] = []
    @State private var showingSettings = false
    @State private var showingTournamentSetup = false
    @State private var showingTripSetup = false
    @State private var showingTournament = false
    @State private var showingHistory = false
    @State private var confirmLeave = false
    @State private var openedPost: CommunityService.CrewPost?
    @State private var copied = 0

    private let pageSize = 30

    private var myRole: CrewRole { crew.map { svc.myRole(in: $0) } ?? .member }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                cover
                DetailHeader(title: crew?.name ?? "Crew", subtitle: headerSubtitle)
                    .padding(.top, DS.Space.s4)
                actions
                    .padding(.top, DS.Space.s5)
                membersSection
                if let crew { tournamentsSection(crew) }
                challengeSection
                fishingNowSection
                feedSection
                settingsSection
                CrewDangerButton(title: "Leave crew", systemImage: "rectangle.portrait.and.arrow.right") {
                    confirmLeave = true
                }
                .padding(.top, DS.Space.s8)
            }
            .padding(.bottom, DS.Space.s8)
        }
        .detailTint(DS.accent)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let crew {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: svc.crewInviteMessage(code: crew.code, name: crew.name)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share crew invite")
                }
            }
        }
        .navigationDestination(isPresented: $showingTournament) {
            if let crew, let tournament { TournamentView(tournament: tournament, crew: crew) }
        }
        .navigationDestination(isPresented: $showingHistory) {
            if let crew { TournamentHistoryView(crew: crew) }
        }
        .navigationDestination(isPresented: $showingTripSetup) {
            GroupTripSetupView(crewCode: code)
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
            Button("Leave crew", role: .destructive) {
                Task {
                    await svc.leaveCrew(code: code)
                    Haptics.warning()
                    ToastCenter.shared.show("Left the crew", style: .info, haptic: false)
                    dismiss()
                }
            }
        } message: {
            Text("You stop seeing this crew's feed. You can join again with the crew code.")
        }
        .sensoryFeedback(.success, trigger: copied)
        // No pull-to-refresh: the 20s poll below plus push-driven revision
        // bumps keep the page current on their own.
        .onChange(of: svc.revision) { _, _ in
            Task { mergeFirstPage(await svc.crewFeedPage(code: code)) }
        }
        .task {
            // Instant from cache, then refresh.
            crew = svc.crew(withCode: code)
            members = svc.cachedCrewMembers(code)
            let cached = CommunityDiskCache.loadFeed(code)
            if !cached.isEmpty { feed = cached }
            banner = CommunityDiskCache.loadImage(key: "crewbanner-\(code)")
            if !feed.isEmpty || !members.isEmpty { isLoading = false }
            await refresh()
            await pollLoop()
        }
    }

    private var headerSubtitle: String {
        let people = members.isEmpty ? nil : CrewText.anglers(members.count)
        let role: String
        switch myRole {
        case .captain: role = "You're the captain."
        case .mate: role = "You're a mate."
        case .admin: role = "You're an admin."
        case .member: role = "You're a member."
        }
        return [people.map { "\($0)." }, role].compactMap { $0 }.joined(separator: " ")
    }

    /// Every 20s: re-fetch only the first feed page (merged into what's
    /// loaded) plus the live-session and tournament state.
    private func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            mergeFirstPage(await svc.crewFeedPage(code: code))
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

        if let fresh = await freshCrew { crew = fresh }
        members = await freshMembers
        banner = await art.banner
        let page = await firstPage
        mergeFirstPage(page)
        canLoadMore = page.count == pageSize
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
    }

    /// Replace the newest page in place, keeping any older pages already
    /// loaded (dropping posts the server no longer returns for that window).
    private func mergeFirstPage(_ page: [CommunityService.CrewPost]) {
        let oldest = page.last?.caughtAt ?? .distantPast
        let ids = Set(page.map(\.id))
        feed = page + feed.filter { !ids.contains($0.id) && $0.caughtAt < oldest }
    }

    private func loadMoreIfNeeded(after post: CommunityService.CrewPost) {
        guard canLoadMore, !loadingMore, post.id == feed.last?.id else { return }
        loadingMore = true
        Task {
            let page = await svc.crewFeedPage(code: code, before: feed.last?.caughtAt)
            let ids = Set(feed.map(\.id))
            feed.append(contentsOf: page.filter { !ids.contains($0.id) })
            canLoadMore = page.count == pageSize
            loadingMore = false
        }
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

    // MARK: Cover and actions

    @ViewBuilder private var cover: some View {
        if let banner {
            Image(uiImage: banner)
                .resizable().scaledToFill()
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .zoomableOnTap(banner)
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s2)
                .accessibilityLabel("Crew banner")
        } else {
            CrewThumb(code: code, emoji: crew?.emoji ?? "🎣", size: 120)  // ui-lint: allow, crew icon emoji is stored crew data
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s2)
        }
    }

    @ViewBuilder private var actions: some View {
        if let crew {
            ActionTriple {
                ShareLink(item: svc.crewInviteMessage(code: crew.code, name: crew.name)) {
                    ActionTileLabel("Invite", systemImage: "person.badge.plus", kind: .primary)
                }
                .buttonStyle(.dim)
                tournamentTile(crew)
                Menu {
                    Button { showingSettings = true } label: {
                        Label("Crew settings", systemImage: "gearshape")
                    }
                    Button { showingTripSetup = true } label: {
                        Label("Start a live session", systemImage: "dot.radiowaves.left.and.right")
                    }
                    Button { copyCode() } label: {
                        Label("Copy crew code", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button(role: .destructive) { confirmLeave = true } label: {
                        Label("Leave crew", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    ActionTileLabel("More", systemImage: "ellipsis")
                }
                .buttonStyle(.dim)
            }
        }
    }

    @ViewBuilder private func tournamentTile(_ crew: CommunityService.Crew) -> some View {
        if let t = tournament, !t.isEnded {
            Button { showingTournament = true } label: {
                Label("Tournament", systemImage: "trophy.fill")
            }
            .buttonStyle(ActionTileStyle())
        } else if svc.myRole(in: crew).canRunTournaments {
            Button {
                Haptics.tap()
                showingTournamentSetup = true
            } label: {
                Label("Tournament", systemImage: "trophy")
            }
            .buttonStyle(ActionTileStyle())
        } else {
            Button { showingHistory = true } label: {
                Label("Tournaments", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(ActionTileStyle())
        }
    }

    private func copyCode() {
        UIPasteboard.general.string = code
        copied += 1
        ToastCenter.shared.show("Crew code copied", style: .success, haptic: false)
    }

    // MARK: Members

    private var membersSection: some View {
        CrewSection(title: "Members", detail: members.isEmpty ? nil : "\(members.count)") {
            if members.isEmpty && isLoading {
                FishLoader(message: "Loading the crew")
                    .frame(height: 80).frame(maxWidth: .infinity)
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

    // MARK: Tournaments

    /// The crew's tournament area: the active one up front, a start row for
    /// those who may run one, and the full history behind one link.
    private func tournamentsSection(_ crew: CommunityService.Crew) -> some View {
        CrewSection(title: "Tournaments") {
            if let t = tournament {
                NavigationLink {
                    TournamentView(tournament: t, crew: crew)
                } label: {
                    CrewEventRow(isLive: !t.isEnded,
                                 over: t.isEnded ? "Ended" : nil,
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
            if tournament == nil || tournament?.isEnded == true {
                if svc.myRole(in: crew).canRunTournaments {
                    Button {
                        Haptics.tap()
                        showingTournamentSetup = true
                    } label: {
                        ArtRow(title: "Start a tournament",
                               subtitle: "Teams are live sessions. Every catch scores points.") {
                            ThumbView(systemImage: "plus", tint: .dsScoreFair)
                        }
                    }
                    .buttonStyle(.dsRow)
                } else if tournament == nil {
                    CrewInlineEmpty(systemImage: "trophy",
                                    text: "No tournament running. A crew admin can start one.")
                }
            }
            NavigationLink {
                TournamentHistoryView(crew: crew)
            } label: {
                ArtRow(title: "All tournaments", chevron: true) {
                    ThumbView(systemImage: "clock.arrow.circlepath", tint: .dsText2)
                }
            }
            .buttonStyle(.dsRow)
            NavigationLink(value: CrewRoute.leaderboard) {
                ArtRow(title: "Friends leaderboard", chevron: true) {
                    ThumbView(systemImage: "list.number", tint: .dsText2)
                }
            }
            .buttonStyle(.dsRow)
        }
    }

    /// "Leading: Team name, 42 points" from the current standings.
    private var leaderLine: String? {
        guard let top = standings.max(by: { $0.points < $1.points }) else { return nil }
        return "Leading: \(top.teamName), \(top.points) points"
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

    // MARK: Live sessions

    private var fishingNowSection: some View {
        CrewSection(title: "Fishing right now") {
            if liveTrips.isEmpty {
                CrewInlineEmpty(systemImage: "dot.radiowaves.left.and.right",
                                text: "No live sessions right now. Start one when you're fishing together.",
                                actionTitle: "Start a live session") { showingTripSetup = true }
            } else {
                ForEach(liveTrips) { trip in
                    let amIn = svc.myGroups.contains { $0.code == trip.id }
                    NavigationLink(value: CrewRoute.trip(code: trip.id, name: trip.name)) {
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
                Button { showingTripSetup = true } label: {
                    ArtRow(title: "Start a live session") {
                        ThumbView(systemImage: "plus", tint: .dsText2)
                    }
                }
                .buttonStyle(.dsRow)
            }
        }
    }

    // MARK: Feed (paginated)

    private var feedSection: some View {
        CrewSection(title: "Recent catches") {
            if feed.isEmpty {
                if isLoading {
                    FishLoader(message: "Loading the feed")
                        .frame(height: 90).frame(maxWidth: .infinity)
                } else {
                    CrewInlineEmpty(systemImage: "fish",
                                    text: "No catches yet. When you or a crewmate log a catch, it shows up here.")
                }
            } else {
                ForEach(feed) { post in
                    Button { openedPost = post } label: {
                        CrewFeedRow(post: post)
                    }
                    .buttonStyle(.dsRow)
                    .onAppear { loadMoreIfNeeded(after: post) }
                }
                if loadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Space.s4)
                } else if !canLoadMore, feed.count > 20 {
                    CrewFootnote(text: "You're all caught up.")
                }
            }
        }
    }

    // MARK: Settings

    @ViewBuilder private var settingsSection: some View {
        if let crew {
            CrewSection(title: "Settings") {
                VStack(spacing: 0) {
                    CrewListRow(title: "Post my catches here", systemImage: "arrow.up.circle.fill") {
                        Toggle("Post my catches here", isOn: Binding(
                            get: { svc.crew(withCode: crew.code)?.autoPost ?? crew.autoPost },
                            set: { on in
                                svc.setAutoPost(on, forCrew: crew.code)
                                self.crew?.autoPost = on
                                Haptics.tap()
                                ToastCenter.shared.show(on ? "Your catches post to this crew" : "Your catches no longer post here",
                                                        style: .info, haptic: false)
                            }
                        ))
                        .labelsHidden()
                        .tint(DS.accent)
                    }
                    Divider().overlay(Color.dsSeparator).padding(.leading, 56)
                    Button { copyCode() } label: {
                        CrewListRow(title: "Crew code", systemImage: "number") {
                            Text(crew.code)
                                .font(.body.monospaced().weight(.semibold))
                                .foregroundStyle(.dsText2)
                        }
                    }
                    .buttonStyle(.dim)
                    .accessibilityHint("Copies the crew code")
                    Divider().overlay(Color.dsSeparator).padding(.leading, 56)
                    Button { showingSettings = true } label: {
                        CrewListRow(title: "Crew settings", systemImage: "gearshape") {
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.dsText3)
                        }
                    }
                    .buttonStyle(.dim)
                }
                .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .padding(.horizontal, DS.gutter)
                CrewFootnote(text: "New catches you log are shared to this crew's feed while posting is on.")
            }
        }
    }

    static func roleColor(_ role: CrewRole) -> Color {
        switch role {
        case .captain: .dsScoreFair
        case .mate:    .dsScoreLow
        case .admin:   Color.blue
        case .member:  .dsText2
        }
    }
}

// MARK: - Crew settings (identity, members, roles)

struct CrewSettingsView: View {
    let crew: CommunityService.Crew
    let members: [CommunityService.GroupMember]
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var svc = CommunityService.shared

    @State private var currentCrew: CommunityService.Crew
    @State private var name: String
    @State private var emoji: String
    @State private var iconItem: PhotosPickerItem?
    @State private var bannerItem: PhotosPickerItem?
    @State private var newIcon: UIImage?
    @State private var newBanner: UIImage?
    @State private var removeIcon = false
    @State private var removeBanner = false
    @State private var hasIcon: Bool
    @State private var hasBanner: Bool
    @State private var saving = false
    @State private var confirmingRemove: CommunityService.GroupMember?
    @State private var confirmingTransfer: CommunityService.GroupMember?
    @State private var showingIconPicker = false
    @State private var showingBannerPicker = false
    @State private var showingEmojiRow = false

    /// The crew's own icon when it has no photo, stored as an emoji on the
    /// crew record.
    private let emojis = ["🎣", "🐟", "🐠", "🦈", "🌊", "⚓️", "🛥️", "🏆"]  // ui-lint: allow, crew icon emoji is stored crew data

    init(crew: CommunityService.Crew, members: [CommunityService.GroupMember],
         onChange: @escaping () -> Void) {
        self.crew = crew
        self.members = members
        self.onChange = onChange
        _currentCrew = State(initialValue: crew)
        _name = State(initialValue: crew.name)
        _emoji = State(initialValue: crew.emoji)
        _hasIcon = State(initialValue: CommunityDiskCache.loadImage(key: "crewicon-\(crew.code)") != nil)
        _hasBanner = State(initialValue: CommunityDiskCache.loadImage(key: "crewbanner-\(crew.code)") != nil)
    }

    private var myRole: CrewRole { svc.myRole(in: currentCrew) }

    var body: some View {
        NavigationStack {
            Form {
                yourRoleSection
                if myRole.canManage { identitySection }
                membersSection
                rolesGuideSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.dsBackground)
            .navigationTitle("Crew settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
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
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Identity

    /// What the banner and icon currently look like, folding in pending picks
    /// and removals so the header previews what Save does.
    private var currentBanner: UIImage? {
        newBanner ?? (removeBanner || !hasBanner ? nil
                      : CommunityDiskCache.loadImage(key: "crewbanner-\(crew.code)"))
    }
    private var currentIcon: UIImage? {
        newIcon ?? (removeIcon || !hasIcon ? nil
                    : CommunityDiskCache.loadImage(key: "crewicon-\(crew.code)"))
    }

    /// The banner is the banner control, the icon is the icon control (photo
    /// or emoji), and the name sits beneath: edit what you're looking at.
    private var identitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    bannerCanvas
                    iconTile
                        .padding(.leading, 14)
                        .offset(y: 32)
                }
                .padding(.bottom, 34)

                TextField("Crew name", text: $name)
                    .font(.headline)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.dsFill2,
                                in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))

                if showingEmojiRow { emojiRow }

                Button {
                    save()
                } label: {
                    if saving { ProgressView() } else { Text("Save changes") }
                }
                .buttonStyle(.dsPrimary)
                .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        } header: {
            Text("Identity")
        } footer: {
            Text("Tap the banner or the icon to change them. Only the captain and mates can change the crew's name and look.")
        }
    }

    private var bannerCanvas: some View {
        ZStack(alignment: .topTrailing) {
            // A real Button, not onTapGesture: in a Form row a bare tap
            // gesture becomes the whole row's primary action.
            Button {
                showingBannerPicker = true
            } label: {
                Group {
                    if let banner = currentBanner {
                        Image(uiImage: banner).resizable().scaledToFill()
                    } else {
                        DS.accent.opacity(0.25)
                            .overlay {
                                Label("Add a banner", systemImage: "photo.badge.plus")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.dsText2)
                            }
                    }
                }
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
            }
            .buttonStyle(.dim)
            .accessibilityLabel(currentBanner == nil ? "Add a banner" : "Change banner")

            Menu {
                Button {
                    showingBannerPicker = true
                } label: {
                    Label(currentBanner == nil ? "Choose banner" : "Change banner",
                          systemImage: "photo")
                }
                if currentBanner != nil {
                    Button(role: .destructive) {
                        removeBanner = true
                        newBanner = nil
                        bannerItem = nil
                    } label: {
                        Label("Remove banner", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "camera.fill")
                    .font(.footnote)
                    .foregroundStyle(.dsText)
                    .frame(width: 32, height: 32)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .accessibilityLabel("Banner options")
            .padding(8)
        }
    }

    private var iconTile: some View {
        Menu {
            Button {
                showingIconPicker = true
            } label: {
                Label(currentIcon == nil ? "Choose a photo" : "Change photo", systemImage: "photo")
            }
            Button {
                withAnimation(DS.Motion.spring) { showingEmojiRow.toggle() }
            } label: {
                Label("Pick an icon", systemImage: "square.grid.2x2")
            }
            if currentIcon != nil {
                Button(role: .destructive) {
                    removeIcon = true
                    newIcon = nil
                    iconItem = nil
                } label: {
                    Label("Remove photo", systemImage: "trash")
                }
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let icon = currentIcon {
                        ThumbView(image: icon, tint: DS.accent, size: 66)
                    } else {
                        ThumbView(tint: DS.accent, size: 66) {
                            Text(emoji).font(.system(size: 30))  // ui-lint: allow, crew icon emoji is stored crew data and scales with the thumb
                        }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous)
                    .stroke(Color.dsBackground, lineWidth: 3))

                Image(systemName: "plus")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.dsOnPrimary)
                    .frame(width: 22, height: 22)
                    .background(Color.dsPrimaryButton, in: Circle())
                    .offset(x: 4, y: 4)
            }
        }
        .accessibilityLabel("Crew icon options")
    }

    private var emojiRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(emojis, id: \.self) { e in
                    Button { emoji = e } label: {
                        Text(e)
                            .font(.title2)
                            .frame(width: 48, height: 48)
                            .background(emoji == e ? DS.accent.opacity(0.22) : Color.dsFill2,
                                        in: RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous)
                                .stroke(emoji == e ? DS.accent : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.dim)
                }
            }
            .padding(.vertical, 2)
        }
        .sensoryFeedback(.selection, trigger: emoji)
    }

    private func save() {
        saving = true
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        Task {
            let ok = await svc.updateCrewIdentity(
                currentCrew,
                name: trimmedName != currentCrew.name ? trimmedName : nil,
                emoji: emoji != currentCrew.emoji && !emoji.isEmpty ? emoji : nil,
                banner: newBanner, iconPhoto: newIcon,
                removeBanner: removeBanner, removeIcon: removeIcon)
            saving = false
            if ok {
                Haptics.success()
                ToastCenter.shared.show("Crew updated", style: .success)
                currentCrew.name = trimmedName
                if !emoji.isEmpty { currentCrew.emoji = emoji }
                if newIcon != nil { hasIcon = true }
                if removeIcon { hasIcon = false; removeIcon = false }
                if newBanner != nil { hasBanner = true }
                if removeBanner { hasBanner = false; removeBanner = false }
                newIcon = nil; newBanner = nil
                onChange()
            } else {
                ToastCenter.shared.show("Couldn't update the crew", style: .error)
            }
        }
    }

    // MARK: Roles

    /// What you are in this crew and what that lets you do.
    private var yourRoleSection: some View {
        Section {
            HStack(spacing: 12) {
                ThumbView(systemImage: myRole.icon, tint: CrewDetailView.roleColor(myRole), size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You're \(myRole == .admin ? "an" : myRole == .member ? "a" : "the") \(myRole.label.lowercased())")
                        .font(.headline)
                    Text(Self.roleSummary(myRole))
                        .font(.subheadline).foregroundStyle(.dsText2)
                }
            }
        }
    }

    static func roleSummary(_ role: CrewRole) -> String {
        switch role {
        case .captain: "Full control: identity, roles, members, posts and tournaments. You can also hand the crew over."
        case .mate:    "Everything but the wheel: edit the crew's look, manage roles, moderate posts and members, run tournaments."
        case .admin:   "Keeper of the peace: delete any post, remove members, run tournaments."
        case .member:  "Post catches, react, join sessions and tournaments."
        }
    }

    /// The whole ladder, so everyone knows what each role means.
    private var rolesGuideSection: some View {
        Section {
            DisclosureGroup {
                ForEach([CrewRole.captain, .mate, .admin, .member], id: \.self) { role in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: role.icon)
                            .font(.subheadline)
                            .foregroundStyle(CrewDetailView.roleColor(role))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(role.label).font(.subheadline.weight(.semibold))
                            Text(Self.roleSummary(role)).font(.footnote).foregroundStyle(.dsText2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } label: {
                Label("How roles work", systemImage: "person.badge.shield.checkmark")
            }
        } footer: {
            Text("The captain and mates set roles from the More button beside a member. Admins and up can remove members and delete posts.")
        }
    }

    private var membersSection: some View {
        Section("Members (\(members.count))") {
            ForEach(members) { m in memberRow(m) }
        }
        .confirmationDialog(
            "Remove from crew?",
            isPresented: Binding(get: { confirmingRemove != nil },
                                 set: { if !$0 { confirmingRemove = nil } }),
            titleVisibility: .visible,
            presenting: confirmingRemove
        ) { m in
            Button("Remove \(m.name)", role: .destructive) {
                Task {
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
                Task {
                    if let updated = await svc.transferCaptaincy(to: m.id, name: m.name, in: currentCrew) {
                        currentCrew = updated
                        Haptics.success()
                        ToastCenter.shared.show("\(m.name) is captain now. You stay aboard as a mate.",
                                                style: .success)
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

    @ViewBuilder private func memberRow(_ m: CommunityService.GroupMember) -> some View {
        let role = svc.role(of: m.id, in: currentCrew)
        let isSelf = m.id == svc.friendCode
        let isCaptain = m.id == currentCrew.createdByCode
        HStack(spacing: 12) {
            CrewAvatar(image: svc.cachedProfiles(for: [m.id]).first?.avatar, name: m.name, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(isSelf ? "You" : m.name).font(.body.weight(.medium))
                Text(role.label).font(.subheadline)
                    .foregroundStyle(CrewDetailView.roleColor(role))
            }
            Spacer()
            if !isSelf, !isCaptain, myRole.canModerate {
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
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.dsText2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More for \(m.name)")
            }
        }
    }

    private func apply(_ role: CrewRole, to m: CommunityService.GroupMember) {
        Task {
            if let updated = await svc.setRole(role, for: m.id, in: currentCrew) {
                currentCrew = updated
                Haptics.success()
                ToastCenter.shared.show(role == .member ? "\(m.name) is a member again"
                                                        : "\(m.name) is now \(role == .admin ? "an" : "a") \(role.label.lowercased())",
                                        style: .success)
                onChange()
            } else {
                ToastCenter.shared.show("Couldn't change that role", style: .error)
            }
        }
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
    private var svc: CommunityService { .shared }
    @State private var photo: UIImage?
    @State private var caption: String?
    @State private var editingCaption = false
    @State private var captionDraft = ""
    @State private var confirmingDelete = false
    @State private var showingComments = false
    /// Optimistic comment count while the thread is open.
    @State private var localCommentCount: Int?
    /// Optimistic reactions, shown the instant you tap. The sheet holds a
    /// snapshot of the post, so these stay the truth until it closes.
    @State private var localReactions: [CommunityService.CrewReaction]?
    @State private var reacted = 0

    private var isMine: Bool { post.authorCode == svc.friendCode }
    private var canModerate: Bool { crew.map { svc.myRole(in: $0).canModerate } ?? false }
    private var reactions: [CommunityService.CrewReaction] { localReactions ?? post.reactions }
    private var shownCaption: String { caption ?? post.caption }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                        .padding(.horizontal, DS.gutter)
                        .padding(.top, DS.Space.s2)
                    DetailHeader(over: post.caughtAt.formatted(.relative(presentation: .named)),
                                 title: CrewText.catchTitle(species: post.species, lengthCm: post.lengthCm, weightKg: post.weightKg),
                                 subtitle: post.tripName.isEmpty ? crew?.name : "On \(post.tripName)")
                        .padding(.top, DS.Space.s4)

                    NavigationLink {
                        FriendProfileView(code: post.authorCode)
                    } label: {
                        ArtRow(over: "Caught by", title: isMine ? "You" : post.authorName, chevron: true) {
                            CrewAvatar(image: isMine ? svc.myAvatar : svc.cachedProfiles(for: [post.authorCode]).first?.avatar,
                                       name: post.authorName, size: 44)
                        }
                    }
                    .buttonStyle(.dsRow)
                    .padding(.top, DS.Space.s3)

                    captionBlock
                    reactionRow
                        .padding(.top, DS.Space.s5)
                    sizeTiles
                }
                .padding(.bottom, DS.Space.s6)
            }
            .background(Color.dsBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { moreMenu }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: post.id) {
            if post.hasPhoto, photo == nil {
                photo = await svc.crewPostImage(recordName: post.id)
            }
        }
        .sheet(isPresented: $showingComments) {
            CrewCommentsSheet(post: post, crew: crew) { count in
                localCommentCount = count
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Caption", isPresented: $editingCaption) {
            TextField("Say something", text: $captionDraft)
            Button("Save") {
                let text = captionDraft
                caption = text
                Task { await svc.setCrewCaption(text, postId: post.id); await reload() }
            }
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
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color.dsFill).overlay(ProgressView())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .zoomableOnTap(photo)
            .accessibilityLabel("Catch photo")
        } else if let sp = SpeciesArtLookup.species(named: post.species, appState: appState) {
            ThumbView(species: sp, size: 120)
        } else {
            ThumbView(systemImage: "fish.fill", tint: DS.accent, size: 120)
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
                    let p = Units.weightParts(kg: w)
                    StatTile("Weight", systemImage: "scalemass", value: p.0, unit: p.1, width: nil)
                }
                if let l = post.lengthCm {
                    let p = Units.lengthParts(cm: l)
                    StatTile("Length", systemImage: "ruler", value: p.0, unit: p.1, width: nil)
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
            ShareLink(item: "\(isMine ? svc.myName : post.authorName) caught a \(post.species) on Currents") {
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

    /// The five reactions, always visible, tap to toggle. Counts appear once
    /// someone's used one; yours is filled. Comments sit at the end.
    private var reactionRow: some View {
        let grouped = Dictionary(grouping: reactions, by: \.emoji)
        let mine = reactions.first { $0.reactorCode == svc.friendCode }?.emoji
        let commentCount = localCommentCount ?? post.commentCount ?? 0
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                ForEach(CommunityService.crewReactionEmojis, id: \.self) { emoji in
                    let count = grouped[emoji]?.count ?? 0
                    let selected = mine == emoji
                    Button { toggle(emoji) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: CrewReactionStyle.symbol(emoji))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(selected ? CrewReactionStyle.tint(emoji) : .dsText2)
                                .symbolEffect(.bounce, value: selected)
                            if count > 0 {
                                Text("\(count)")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(selected ? Color.dsText : Color.dsText2)
                                    .contentTransition(.numericText())
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(selected ? CrewReactionStyle.tint(emoji).opacity(0.2) : Color.dsFill,
                                    in: Capsule())
                    }
                    .buttonStyle(.dim)
                    .accessibilityLabel("\(CrewReactionStyle.name(emoji)), \(count)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Button {
                    Haptics.tap()
                    showingComments = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.right")
                            .font(.body.weight(.semibold))
                        Text(commentCount > 0 ? "\(commentCount)" : "Comment")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.dsText)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Color.dsFill, in: Capsule())
                }
                .buttonStyle(.dim)
                .accessibilityLabel(commentCount == 1 ? "1 comment" : "\(commentCount) comments")
            }
            .padding(.horizontal, DS.gutter)
        }
        .sensoryFeedback(.selection, trigger: reacted)
    }

    private func toggle(_ emoji: String) {
        reacted += 1
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
        withAnimation(DS.Motion.spring) { localReactions = rs }
        Task {
            await svc.toggleCrewReaction(emoji: emoji, postId: post.id,
                                         crewCode: post.crewCode, postAuthorCode: post.authorCode)
            await reload()
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
/// anyone's.
struct CrewCommentsSheet: View {
    let post: CommunityService.CrewPost
    var crew: CommunityService.Crew? = nil
    /// Reports the live count so the post's comment badge stays honest.
    var onCountChange: (Int) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    private var svc: CommunityService { .shared }
    @State private var comments: [CommunityService.CrewComment] = []
    @State private var loading = true
    @State private var draft = ""
    @State private var sending = false
    @FocusState private var composerFocused: Bool
    /// Composer modes: replying attaches to a thread; editing rewrites in place.
    @State private var replyingTo: CommunityService.CrewComment?
    @State private var editing: CommunityService.CrewComment?

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
        NavigationStack {
            VStack(spacing: 0) {
                if loading && comments.isEmpty {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if comments.isEmpty {
                    Spacer()
                    ContentUnavailableView("No comments yet", systemImage: "bubble.left.and.bubble.right",
                                           description: Text("Say something about this \(post.species.lowercased())."))
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(threads, id: \.parent.id) { thread in
                                commentRow(thread.parent, isReply: false)
                                    .id(thread.parent.id)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 8, leading: DS.gutter, bottom: 4, trailing: 12))
                                ForEach(thread.replies) { reply in
                                    commentRow(reply, isReply: true)
                                        .id(reply.id)
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets(top: 4, leading: DS.gutter + 40, bottom: 4, trailing: 12))
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
            .background(Color.dsBackground)
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task {
            comments = await svc.comments(postId: post.id)
            loading = false
            onCountChange(comments.count)
        }
    }

    private func commentRow(_ comment: CommunityService.CrewComment, isReply: Bool) -> some View {
        let mine = comment.authorCode == svc.friendCode
        return HStack(alignment: .top, spacing: 10) {
            CrewAvatar(image: mine ? svc.myAvatar : svc.cachedProfiles(for: [comment.authorCode]).first?.avatar,
                       name: comment.authorName, size: isReply ? 28 : 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(mine ? "You" : comment.authorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.dsText)
                    Text(comment.createdAt.formatted(.relative(presentation: .named)))
                        .font(.footnote).foregroundStyle(.dsText3)
                    if comment.editedAt != nil {
                        Text("Edited")
                            .font(.footnote).foregroundStyle(.dsText3)
                    }
                }
                Text(comment.text).font(.body).foregroundStyle(.dsText)
                // Reply sits under the comment, always visible.
                Button {
                    Haptics.tap()
                    editing = nil
                    replyingTo = comment
                    composerFocused = true
                } label: {
                    Text("Reply")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DS.accent)
                }
                .buttonStyle(.dim)
                .padding(.top, 1)
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
                    Button(role: .destructive) { delete(comment) } label: {
                        Label("Delete comment", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .frame(width: 36, height: 36)
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
                    }
                    .buttonStyle(.dim)
                    .accessibilityLabel(editing != nil ? "Cancel editing" : "Cancel reply")
                }
                .foregroundStyle(.dsText2)
                .padding(.horizontal, DS.gutter).padding(.top, 8)
            }
            HStack(spacing: 10) {
                TextField(editing != nil ? "Edit your comment"
                          : replyingTo != nil ? "Write a reply" : "Add a comment",
                          text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                Button {
                    send()
                } label: {
                    Image(systemName: editing != nil ? "checkmark" : "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(draftEmpty ? Color.dsText3 : Color.dsOnPrimary)
                        .frame(width: 36, height: 36)
                        .background(draftEmpty ? Color.dsFill : Color.dsPrimaryButton, in: Circle())
                }
                .buttonStyle(.dim)
                .disabled(sending || draftEmpty)
                .accessibilityLabel(editing != nil ? "Save comment" : "Post comment")
            }
            .padding(.horizontal, DS.gutter).padding(.vertical, 10)
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
        Haptics.tap()
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

    @State private var crew: CommunityService.Crew?
    @State private var members = 0
    @State private var loading = true
    @State private var joining = false
    @State private var joined = false
    @State private var joinName = ""

    private var alreadyIn: Bool { svc.myCrews.contains { $0.code == code.uppercased() } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CrewThumb(code: code.uppercased(), emoji: crew?.emoji ?? "🎣", size: 96)  // ui-lint: allow, crew icon emoji is stored crew data
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s4)
                DetailHeader(over: svc.joined ? "Crew invite" : "Join the community",
                             title: crew?.name ?? (loading ? "Loading crew" : "Crew"),
                             subtitle: subtitle)
                    .padding(.top, DS.Space.s4)
                if svc.joined { confirmBody } else { joinGate }
            }
            .padding(.bottom, DS.Space.s6)
        }
        .background(Color.dsBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(joined || alreadyIn ? "Done" : "Cancel") { dismiss() } }
        }
        .presentationDragIndicator(.visible)
        .task {
            crew = await svc.fetchCrew(code: code)
            members = await svc.crewMembers(code: code).count
            loading = false
        }
    }

    private var subtitle: String? {
        guard !loading else { return nil }
        guard let crew else { return "No crew matches code \(code.uppercased())." }
        return "\(CrewText.anglers(members)). Started by \(crew.createdByName)."
    }

    private var joinGate: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text("Set up your free Currents profile to join this crew and share catches. No account or password, just a name.")
                .font(.body).foregroundStyle(.dsText2)
            CrewTextField(label: "Angler name", placeholder: "Your name", text: $joinName)
                .textContentType(.givenName)
            Button {
                joining = true
                Task {
                    await svc.join(name: joinName, region: svc.myRegion)
                    Haptics.success()
                    joining = false
                }
            } label: {
                if joining { ProgressView() } else { Text("Join and continue") }
            }
            .buttonStyle(.dsPrimary)
            .disabled(joining || joinName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s5)
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
                    joining = true
                    Task {
                        let ok = await svc.joinCrew(code: code) != nil
                        joining = false
                        if ok {
                            joined = true
                            Haptics.success()
                            ToastCenter.shared.show("Joined the crew", style: .success, haptic: false)
                        } else {
                            ToastCenter.shared.show("Couldn't join that crew", style: .error)
                        }
                    }
                } label: {
                    if joining { ProgressView() } else { Text("Join crew") }
                }
                .buttonStyle(.dsPrimary)
                .disabled(joining || crew == nil)
            }
            Text("Find the crew on the Crew tab once you've joined.")
                .font(.footnote).foregroundStyle(.dsText2)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s5)
    }
}
