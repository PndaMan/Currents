import SwiftUI
import PhotosUI
import MapKit

/// The Crew tab root: what is happening now, group trips, your crews, friends
/// and the merged catch feed from every crew. Crew, friend and request pages
/// push on this tab's stack.
struct CommunityView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var svc = CommunityService.shared
    @ObservedObject private var cloud = CrewCloud.shared

    private enum CrewSheet: String, Identifiable {
        case add, newCrew, joinCrew, addFriend
        var id: String { rawValue }
    }

    @State private var sheet: CrewSheet?
    /// Set by the Add sheet; runs once that sheet has gone.
    @State private var pendingChoice: CrewAddChoice?
    @State private var showingTripSetup = false
    @State private var deepLinkedCrew: String?
    @State private var openedPost: CommunityService.CrewPost?
    @State private var confirmRemoveTrip: CommunityService.GroupRef?

    @State private var pendingRequests: [CommunityService.FriendRequest] = []
    @State private var pendingInvites: [CommunityService.TripInvite] = []
    @State private var friendProfiles: [CommunityService.Profile] = []
    /// Live tournaments and trips per crew code.
    @State private var live: [String: CrewLive] = [:]
    /// Cached angler stats so a full catch-table scan doesn't run on every
    /// SwiftUI body re-render; refreshed on appear and when catches change.
    @State private var cachedStats: CommunityService.MyStats?
    /// Local catches, used for achievements on your own profile page.
    @State private var myCatches: [CatchDetail] = []
    /// The merged cross-crew feed.
    @State private var mergedFeed: [CommunityService.CrewPost] = []
    @State private var feedLoading = false
    /// Per-crew "older pages exist" flags and the in-flight guard for the
    /// feed's infinite scroll.
    @State private var feedHasMore: [String: Bool] = [:]
    @State private var feedLoadingMore = false

    private var region: String { svc.myRegion }
    /// Joined and iCloud reachable: the only time anything here may load.
    private var canSync: Bool { svc.joined && cloud.isAvailable }
    private var notificationCount: Int { pendingRequests.count + pendingInvites.count }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !cloud.isAvailable {
                    LargeTitleHeader("Crew")
                    CrewUnavailableState(status: cloud.status)
                } else if svc.joined {
                    LargeTitleHeader("Crew") {
                        NavigationLink(value: CrewRoute.requests) {
                            HeaderIconLabel(systemImage: "bell", showsDot: notificationCount > 0)
                        }
                        .buttonStyle(.dim)
                        .accessibilityLabel(notificationCount > 0 ? "Requests, \(notificationCount) waiting" : "Requests")
                        HeaderIconButton("New crew, trip or friend", systemImage: "plus") { sheet = .add }
                    }
                    joinedContent
                } else {
                    LargeTitleHeader("Crew")
                    joinGate
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .largeTitleChrome("Crew")
        .dsScreenBackground()
        .navigationDestination(for: CrewRoute.self) { route in CrewCloudGate { destination(route) } }
        .navigationDestination(item: $deepLinkedCrew) { code in CrewCloudGate { CrewDetailView(code: code) } }
        .navigationDestination(isPresented: $showingTripSetup) { GroupTripSetupView() }
        .sheet(item: $sheet, onDismiss: runPendingChoice) { s in
            switch s {
            case .add:
                CrewAddSheet { choice in
                    pendingChoice = choice
                    sheet = nil
                }
            case .newCrew: CrewSetupView()
            case .joinCrew: CrewSetupView(joining: true)
            case .addFriend: CrewAddFriendSheet()
            }
        }
        .sheet(item: $openedPost) { post in
            CrewPostSheet(post: post, crew: svc.crew(withCode: post.crewCode)) {
                await loadMergedFeed()
            }
        }
        .confirmationDialog("Remove this trip?",
                            isPresented: Binding(get: { confirmRemoveTrip != nil },
                                                 set: { if !$0 { confirmRemoveTrip = nil } }),
                            titleVisibility: .visible,
                            presenting: confirmRemoveTrip) { g in
            Button("Remove trip", role: .destructive) {
                Task { await leaveGroupAndCleanup(code: g.code, tripId: nil, appState: appState) }
            }
        } message: { _ in
            Text("You leave the trip. A planned session that never started is deleted too.")
        }
        .task { await cloud.refresh() }
        .onChange(of: scenePhase) { _, phase in
            // Signing in to iCloud happens in Settings; pick it up on return.
            if phase == .active { Task { await cloud.refresh() } }
        }
        .task(id: canSync) {
            refreshStats()
            guard canSync else { return }
            // Visible content first: cached friends and feed, then the network.
            friendProfiles = CrewFriendsLoader.cached()
            await loadMergedFeed()
            await loadNotifications()
            friendProfiles = await CrewFriendsLoader.load()
            await loadLive()
            // Maintenance in the background: publish history, heal grants and
            // spot shares, and rebuild membership from the server once per
            // launch (a reinstall used to show zero crews or trips while the
            // server still counted and pushed to this angler).
            Task {
                await syncCatches()
                await svc.reconcileMemberships()
            }
            // Light poll while the tab is open; fills the gaps CloudKit
            // subscriptions can't cover.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                guard !Task.isCancelled, canSync else { continue }
                await loadMergedFeed()
                await loadNotifications()
                await loadLive()
            }
        }
        // Pushes bump the revision; no pull-to-refresh needed.
        .onChange(of: svc.revision) { _, _ in
            guard canSync else { return }
            Task {
                refreshStats()
                friendProfiles = CrewFriendsLoader.cached()
                await loadMergedFeed()
                await loadNotifications()
            }
        }
        // A crew push tap (currents://crewfeed/<CODE>) lands in that crew.
        .onChange(of: appState.openCrewCode) { _, code in
            if let code { deepLinkedCrew = code; appState.openCrewCode = nil }
        }
        .onAppear {
            if let code = appState.openCrewCode {
                deepLinkedCrew = code; appState.openCrewCode = nil
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: CrewRoute) -> some View {
        switch route {
        case .crew(let code): CrewDetailView(code: code)
        case .crews: CrewsListPage()
        case .friends: CrewFriendsPage()
        case .friend(let code): FriendProfileView(code: code)
        case .requests: CrewRequestsPage()
        case .leaderboard: LeaderboardView()
        case .myProfile: MyProfileView(stats: stats, catches: myCatches)
        case .tripSetup(let crewCode): GroupTripSetupView(crewCode: crewCode)
        case .trip(let code, let name):
            GroupTripView(tripId: svc.tripId(forGroupCode: code), tripName: name, initialCode: code)
        }
    }

    private func runPendingChoice() {
        guard let choice = pendingChoice else { return }
        pendingChoice = nil
        switch choice {
        case .newCrew: sheet = .newCrew
        case .addFriend: sheet = .addFriend
        case .groupTrip: showingTripSetup = true
        }
    }

    // MARK: Join gate

    private var joinGate: some View {
        VStack(spacing: DS.Space.s3) {
            CrewGateArt()
                .padding(.top, DS.Space.s6)
                .padding(.bottom, DS.Space.s3)
            Text("Fish with friends")
                .font(.title.bold())
                .foregroundStyle(.dsText)
                .multilineTextAlignment(.center)
            Text("Crews, tournaments and group trips. Pick the name your crew will see.")
                .font(.body)
                .foregroundStyle(.dsText2)
                .multilineTextAlignment(.center)
            CrewJoinForm {
                await svc.updateProfile(name: svc.myName, bio: svc.myBio, homeWater: svc.myHomeWater,
                                        region: region, avatar: nil, stats: stats)
                ToastCenter.shared.show("You're in. Add a friend or start a crew.", style: .success, haptic: false)
            }
            .padding(.top, DS.Space.s3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.gutter)
    }

    // MARK: Joined

    private var hasAnything: Bool {
        !svc.myCrews.isEmpty || !svc.friends.isEmpty || !svc.myGroups.isEmpty || notificationCount > 0
    }

    private var summaryLine: String {
        let crews = svc.myCrews.count, friends = svc.friends.count
        return "\(crews) \(crews == 1 ? "crew" : "crews"), \(friends) \(friends == 1 ? "friend" : "friends")"
    }

    @ViewBuilder private var joinedContent: some View {
        Text(summaryLine)
            .font(.subheadline)
            .foregroundStyle(.dsText2)
            .padding(.horizontal, DS.gutter)
            .padding(.bottom, DS.Space.s2)

        if !hasAnything {
            emptyState
        } else {
            inboxRow
            happeningNow
            groupTrips
            crewsSection
            friendsSection
            feedSection
        }
    }

    /// Joined, but no crews, friends or trips yet.
    private var emptyState: some View {
        VStack(spacing: DS.Space.s3) {
            CrewGateArt()
                .padding(.bottom, DS.Space.s3)
            Text("Fish with friends")
                .font(.title2.bold())
                .foregroundStyle(.dsText)
            Text("Start a crew or add a friend. Their catches, trips and tournaments land here.")
                .font(.body)
                .foregroundStyle(.dsText2)
                .multilineTextAlignment(.center)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s2) { emptyStateButtons }
                VStack(spacing: DS.Space.s2) { emptyStateButtons }
            }
            .padding(.top, DS.Space.s2)
            Button("Join a crew with a code") { sheet = .joinCrew }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.accent)
                .buttonStyle(.dim)
                .padding(.top, DS.Space.s1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s6)
    }

    @ViewBuilder private var emptyStateButtons: some View {
        Button("Start a crew") { sheet = .newCrew }
            .buttonStyle(PrimaryButtonStyle(fullWidth: true))
        Button("Add a friend") { sheet = .addFriend }
            .buttonStyle(TonalButtonStyle(fullWidth: true))
    }

    // MARK: Inbox

    @ViewBuilder private var inboxRow: some View {
        if notificationCount > 0 {
            NavigationLink(value: CrewRoute.requests) {
                ArtRow(title: "\(notificationCount) waiting for you", subtitle: inboxSummary, chevron: true) {
                    ZStack(alignment: .bottomTrailing) {
                        CrewAvatar(image: nil,
                                   name: pendingRequests.first?.fromName ?? pendingInvites.first?.fromName ?? "A",
                                   size: 56)
                        Image(systemName: "tray.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(DS.accent, in: Circle())
                            .overlay(Circle().stroke(Color.dsBackground, lineWidth: 2.5))
                            .offset(x: 4, y: 4)
                    }
                    .frame(width: 64, height: 64)
                }
            }
            .buttonStyle(.dsRow)
            .padding(.top, DS.Space.s2)
        }
    }

    private var inboxSummary: String {
        var parts: [String] = []
        if let r = pendingRequests.first {
            parts.append(pendingRequests.count == 1 ? "\(r.fromName) wants to be friends"
                                                    : "\(pendingRequests.count) friend requests")
        }
        if let i = pendingInvites.first {
            parts.append(pendingInvites.count == 1 ? "\(i.fromName) invited you to \(i.tripName)"
                                                   : "\(pendingInvites.count) trip invites")
        }
        return parts.joined(separator: ". ")
    }

    // MARK: Happening now

    private struct LiveTournament: Identifiable {
        let crew: CommunityService.Crew
        let tournament: CommunityService.Tournament
        let rank: Int?
        var id: String { tournament.id }
    }

    private var liveTournaments: [LiveTournament] {
        svc.myCrews.compactMap { crew in
            guard let state = live[crew.code], let t = state.tournament, !t.isEnded else { return nil }
            return LiveTournament(crew: crew, tournament: t, rank: state.myRank(svc.friendCode))
        }
    }

    private struct LiveTrip: Identifiable {
        let crew: CommunityService.Crew
        let trip: CommunityService.GroupTrip
        var id: String { trip.id }
    }

    private var liveTrips: [LiveTrip] {
        svc.myCrews.flatMap { crew in (live[crew.code]?.trips ?? []).map { LiveTrip(crew: crew, trip: $0) } }
    }

    @ViewBuilder private var happeningNow: some View {
        if !liveTournaments.isEmpty || !liveTrips.isEmpty {
            CrewSection(title: "Happening now") {
                ForEach(liveTournaments) { item in
                    NavigationLink {
                        TournamentView(tournament: item.tournament, crew: item.crew)
                    } label: {
                        CrewEventRow(isLive: true, over: item.crew.name, title: item.tournament.name,
                                     endsAt: item.tournament.endsAt,
                                     pill: item.rank.map { CrewText.ordinal($0) }) {
                            ThumbView(systemImage: "trophy.fill", tint: .dsScoreFair)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
                ForEach(liveTrips) { item in
                    NavigationLink(value: CrewRoute.trip(code: item.trip.id, name: item.trip.name)) {
                        CrewEventRow(isLive: true, over: item.crew.name, title: item.trip.name,
                                     subtitle: item.trip.hostCode == svc.friendCode
                                        ? "You're hosting" : "Hosted by \(item.trip.hostName)") {
                            ThumbView(systemImage: "dot.radiowaves.left.and.right", tint: .dsScoreGood)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
            }
        }
    }

    // MARK: Group trips

    private var groupTrips: some View {
        CrewSection(title: "Group trips") {
            ForEach(svc.myGroups) { g in
                NavigationLink(value: CrewRoute.trip(code: g.code, name: g.name)) {
                    CrewEventRow(over: g.isHost ? "You're hosting" : "Hosted by \(g.hostName)",
                                 title: g.name,
                                 subtitle: g.teamName.map { "Tournament team \($0)" } ?? "Trip code \(g.code)",
                                 pill: g.endedAt != nil ? "Ended" : nil) {
                        ThumbView(systemImage: g.teamName != nil ? "trophy.fill" : "person.3.fill",
                                  tint: g.endedAt != nil ? .dsText2 : .dsScoreLow)
                    }
                }
                .buttonStyle(.dsRow)
                .contextMenu {
                    Button(role: .destructive) { confirmRemoveTrip = g } label: {
                        Label("Remove trip", systemImage: "trash")
                    }
                }
            }
            NavigationLink(value: CrewRoute.tripSetup(crewCode: nil)) {
                ArtRow(title: "Plan a group trip", subtitle: "Start now or pick a day, then invite friends") {
                    ThumbView(systemImage: "calendar.badge.plus", tint: .dsText2)
                }
            }
            .buttonStyle(.dsRow)
        }
    }

    // MARK: Crews

    private var crewsSection: some View {
        CrewSection(title: "Your crews", link: .crews) {
            if svc.myCrews.isEmpty {
                InlineEmpty(systemImage: "person.3",
                                text: "No crews yet. Start one, or join with a code from a friend.",
                                actionTitle: "Start a crew") { sheet = .newCrew }
            } else {
                ForEach(svc.myCrews) { crew in
                    NavigationLink(value: CrewRoute.crew(crew.code)) {
                        ArtRow(title: crew.name,
                               subtitle: CrewText.crewSubtitle(crew, tournamentLive: live[crew.code]?.tournament.map { !$0.isEnded } ?? false),
                               chevron: true) {
                            CrewThumb(code: crew.code, emoji: crew.emoji)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
            }
        }
    }

    // MARK: Friends

    private var friendsSection: some View {
        CrewSection(title: "Friends", link: .friends) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DS.Space.s2) {
                    Button { sheet = .addFriend } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "person.badge.plus")
                                .font(.title2.weight(.medium))
                                .foregroundStyle(.dsText)
                                .frame(width: 56, height: 56)
                                .background(Color.dsFill2, in: Circle())
                            Text("Add")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.dsText)
                        }
                        .frame(width: 72)
                    }
                    .buttonStyle(.dim)
                    .accessibilityLabel("Add a friend")
                    ForEach(friendProfiles) { p in
                        NavigationLink(value: CrewRoute.friend(p.id)) {
                            CrewPersonCell(image: p.avatar, name: CrewFriendsLoader.shortName(p))
                        }
                        .buttonStyle(.dim)
                    }
                }
                .padding(.horizontal, DS.gutter - 8)
                .padding(.bottom, DS.Space.s2)
            }
            NavigationLink(value: CrewRoute.leaderboard) {
                ArtRow(title: "Friends leaderboard", subtitle: "Most fish, heaviest and longest", chevron: true) {
                    ThumbView(systemImage: "trophy.fill", tint: .dsScoreFair)
                }
            }
            .buttonStyle(.dsRow)
        }
    }

    // MARK: Feed

    private var feedSection: some View {
        CrewSection(title: "Crew catches") {
            if svc.myCrews.isEmpty {
                InlineEmpty(systemImage: "fish",
                                text: "Join or start a crew and everyone's catches land here.",
                                actionTitle: "Join a crew") { sheet = .joinCrew }
            } else if mergedFeed.isEmpty && feedLoading {
                FishLoader(message: "Loading the feed")
                    .frame(height: 90)
            } else if mergedFeed.isEmpty {
                InlineEmpty(systemImage: "fish",
                                text: "Nothing in the feed yet. When you or a crewmate log a catch, it shows up here.")
            } else {
                ForEach(mergedFeed) { post in
                    Button { openedPost = post } label: {
                        CrewFeedRow(post: post, crewName: svc.crew(withCode: post.crewCode)?.name)
                    }
                    .buttonStyle(.dsRow)
                    .onAppear {
                        // Infinite scroll: nearing the bottom pulls the next
                        // 30-post page from every crew that still has more.
                        if post.id == mergedFeed.suffix(5).first?.id {
                            Task { await loadMoreFeed() }
                        }
                    }
                }
                if feedLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Space.s4)
                } else if !feedHasMore.values.contains(true), mergedFeed.count > 20 {
                    SectionFootnote("You're all caught up.")
                }
            }
        }
    }

    // MARK: Loading

    private func refreshStats() {
        myCatches = (try? appState.catchRepository.fetchAll(limit: 100000)) ?? []
        cachedStats = computeStatsFrom(myCatches)
    }
    private var stats: CommunityService.MyStats { cachedStats ?? computeStats() }

    private func loadNotifications() async {
        guard canSync else { return }
        pendingRequests = await svc.refreshFriendRequests()
        pendingInvites = await svc.refreshTripInvites()
    }

    /// Each crew's tournament (with standings, for the rank pill) and live
    /// trips. Crews are few, so one crew at a time keeps this simple.
    private func loadLive() async {
        guard canSync, !ScreenshotSupport.isActive else { return }
        var next: [String: CrewLive] = [:]
        for crew in svc.myCrews {
            async let tourney = svc.activeTournament(crewCode: crew.code)
            async let trips = svc.liveCrewTrips(crewCode: crew.code)
            var state = CrewLive()
            state.tournament = await tourney
            state.trips = await trips
            if let t = state.tournament, !t.isEnded {
                state.standings = await svc.teamStandings(tournament: t)
            }
            next[crew.code] = state
        }
        live = next
    }

    /// Publish the full local catch history so the leaderboards reflect
    /// everything, not just catches logged after joining. Throttled service-side.
    private func syncCatches() async {
        guard canSync else { return }
        let catches = (try? appState.catchRepository.fetchAll(limit: 100000)) ?? []
        let details = catches.map {
            (id: $0.catchRecord.id,
             species: $0.species?.commonName ?? "Fish",
             weightKg: $0.catchRecord.weightKg,
             lengthCm: $0.catchRecord.lengthCm,
             caughtAt: $0.catchRecord.caughtAt,
             latitude: $0.catchRecord.latitude,
             longitude: $0.catchRecord.longitude,
             photoPath: $0.catchRecord.photoPath)
        }
        await svc.syncAllCatches(details)
        // Keep catch-visibility grants in step with the global sharing setting
        // and current friend list.
        await svc.syncCatchGrants()
        // And spot shares: creating, editing or deleting a spot doesn't
        // republish on its own, so heal the shared set on every visit.
        let spots = (try? appState.spotRepository.fetchAll()) ?? []
        await svc.republishSharedSpots(spots: spots)
    }

    /// One page from every crew, fetched concurrently and merged newest first.
    private func loadMergedFeed() async {
        guard canSync else { return }
        let crews = svc.myCrews
        guard !crews.isEmpty else { mergedFeed = []; return }
        // Instant: last-seen pages from disk, so the feed is on screen before
        // the network round trips come back.
        if mergedFeed.isEmpty {
            let cached = crews.flatMap { CommunityDiskCache.loadFeed($0.code) }
            if !cached.isEmpty { mergedFeed = cached.sorted { $0.caughtAt > $1.caughtAt } }
        }
        // Screenshot mode: the seeded disk feed is the feed; a network
        // refresh would come back empty and wipe it mid-capture.
        if ScreenshotSupport.isActive { feedLoading = false; return }
        feedLoading = true
        var all: [CommunityService.CrewPost] = []
        var hasMore: [String: Bool] = [:]
        await withTaskGroup(of: (String, [CommunityService.CrewPost]).self) { group in
            for crew in crews {
                let code = crew.code
                group.addTask { (code, await CommunityService.shared.crewFeedPage(code: code)) }
            }
            for await (code, page) in group {
                all.append(contentsOf: page)
                // A full page means older posts likely exist behind it.
                hasMore[code] = page.count >= 30
            }
        }
        mergedFeed = all.sorted { $0.caughtAt > $1.caughtAt }
        feedHasMore = hasMore
        feedLoading = false
    }

    /// Pull the next page of older posts from every crew that still has more,
    /// merge, and keep going until each crew's history runs dry, 30 at a time
    /// per crew.
    private func loadMoreFeed() async {
        guard canSync, !feedLoadingMore, feedHasMore.values.contains(true) else { return }
        feedLoadingMore = true
        var appended: [CommunityService.CrewPost] = []
        for crew in svc.myCrews where feedHasMore[crew.code] == true {
            let oldest = mergedFeed.filter { $0.crewCode == crew.code }.map(\.caughtAt).min()
            let page = await svc.crewFeedPage(code: crew.code, before: oldest)
            feedHasMore[crew.code] = page.count >= 30
            appended.append(contentsOf: page)
        }
        let ids = Set(mergedFeed.map(\.id))
        mergedFeed.append(contentsOf: appended.filter { !ids.contains($0.id) })
        mergedFeed.sort { $0.caughtAt > $1.caughtAt }
        feedLoadingMore = false
    }

    // MARK: Stats from local data

    private func computeStats() -> CommunityService.MyStats {
        computeStatsFrom((try? appState.catchRepository.fetchAll(limit: 100000)) ?? [])
    }

    private func computeStatsFrom(_ catches: [CatchDetail]) -> CommunityService.MyStats {
        let species = Dictionary(grouping: catches, by: { $0.species?.commonName ?? "" })
        let fav = species.filter { !$0.key.isEmpty }.max { $0.value.count < $1.value.count }?.key ?? ""
        return .init(
            totalCatches: catches.count,
            speciesCount: species.keys.filter { !$0.isEmpty }.count,
            bestWeightKg: catches.compactMap { $0.catchRecord.weightKg }.max() ?? 0,
            bestLengthCm: catches.compactMap { $0.catchRecord.lengthCm }.max() ?? 0,
            favoriteSpecies: fav
        )
    }
}

// MARK: - My profile

/// Your own angler page: avatar, bio, title, stats and achievements, plus the
/// way out of the community.
struct MyProfileView: View {
    let stats: CommunityService.MyStats
    let catches: [CatchDetail]

    @Environment(\.dismiss) private var dismiss
    @StateObject private var svc = CommunityService.shared
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }

    @State private var showingEdit = false
    @State private var confirmLeave = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CrewAvatar(image: svc.myAvatar, name: svc.myName, size: 96)
                    .zoomableOnTap(svc.myAvatar)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s4)
                DetailHeader(title: svc.myName, subtitle: "Angler code \(svc.friendCode)")
                    .padding(.top, DS.Space.s4)
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    if !svc.myTitle.isEmpty {
                        TitleFlairChip(title: svc.myTitle)
                    }
                    if !svc.myBio.isEmpty {
                        Text(svc.myBio)
                            .font(.body)
                            .foregroundStyle(.dsText)
                    }
                    CrewMetaLine(items: [
                        ("water.waves", svc.myHomeWater),
                        ("globe", svc.myRegion)
                    ])
                }
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s3)

                ActionTriple {
                    Button { showingEdit = true } label: {
                        Label("Edit profile", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(ActionTileStyle(.primary))
                    Button {
                        UIPasteboard.general.string = svc.friendCode
                        ToastCenter.shared.show("Angler code copied", style: .success)
                    } label: {
                        Label("Copy code", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(ActionTileStyle())
                    ShareLink(item: svc.friendInviteMessage()) {
                        ActionTileLabel("Invite", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.dim)
                }
                .padding(.top, DS.Space.s5)

                CrewSection(title: "Your stats") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        StatTile("Catches", systemImage: "fish.fill", value: "\(stats.totalCatches)", width: nil)
                        StatTile("Species", systemImage: "square.grid.2x2", value: "\(stats.speciesCount)", width: nil)
                        if stats.bestWeightKg > 0 {
                            let w = Units.weightParts(kg: stats.bestWeightKg, imperial: imperial)
                            StatTile("Heaviest", systemImage: "scalemass", value: w.0, unit: w.1, width: nil)
                        }
                        if stats.bestLengthCm > 0 {
                            let l = Units.lengthParts(cm: stats.bestLengthCm, imperial: imperial)
                            StatTile("Longest", systemImage: "ruler", value: l.0, unit: l.1, width: nil)
                        }
                    }
                    .padding(.horizontal, DS.gutter)
                    if !stats.favoriteSpecies.isEmpty {
                        SectionFootnote("Favourite species: \(stats.favoriteSpecies)")
                    }
                }

                CrewSection(title: "Achievements") {
                    AchievementsCard(catches: catches)
                        .padding(DS.Space.s4)
                        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                        .padding(.horizontal, DS.gutter)
                }

                DangerButton(title: "Leave the community", systemImage: "rectangle.portrait.and.arrow.right") {
                    confirmLeave = true
                }
                .padding(.top, DS.Space.s8)
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(DS.accent)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEdit) { ProfileEditView(stats: stats) }
        .confirmationDialog("Leave the community?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                Haptics.warning()
                svc.leave()
                ToastCenter.shared.show("Left the community", style: .info, haptic: false)
                dismiss()
            }
        } message: {
            Text("Nothing new is shared and notifications stop. What you've already shared stays until you delete it.")
        }
    }
}

/// The title worn under an angler's name, tinted by the unlocking
/// achievement's rarity. Tapping it opens the achievement that earned it.
struct TitleFlairChip: View {
    let title: String
    @State private var showingBadge = false

    private var flair: TitleFlair? { TitleFlair.resolve(title) }
    private var tint: Color { flair?.rarity.color ?? .gray }

    var body: some View {
        Button {
            guard flair != nil else { return }
            showingBadge = true
        } label: {
            Label(flair?.name ?? title, systemImage: flair?.icon ?? "rosette")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(tint.opacity(0.16), in: Capsule())
                .foregroundStyle(tint)
                .contentShape(Capsule())
        }
        .buttonStyle(.dim)
        .accessibilityHint("Shows the achievement that unlocked this title")
        .sheet(isPresented: $showingBadge) {
            if let flair {
                BadgeDetailView(badge: flair.badge)
            }
        }
    }
}

/// An angler's round avatar: their photo, or a fishing figure on the accent.
struct AnglerAvatar: View {
    let image: UIImage?
    var size: CGFloat = 56
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(DS.accent.opacity(0.22))
                    Image(systemName: "figure.fishing")
                        .font(.system(size: size * 0.42, weight: .medium))  // ui-lint: allow, symbol scales with the avatar, not with text
                        .foregroundStyle(DS.accent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

// MARK: - Reusable: code field + copyable code

/// A centred, monospaced input for 6-character friend, crew and trip codes.
/// Uppercases and caps at 6 characters.
struct CodeField: View {
    @Binding var text: String
    var placeholder = "CODE"
    var body: some View {
        TextField(placeholder, text: $text)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .font(.system(.title3, design: .monospaced).weight(.semibold))
            .tracking(6)
            .multilineTextAlignment(.center)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
            .onChange(of: text) { _, v in
                let up = String(v.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.prefix(6))
                if up != text { text = up }
            }
    }
}

/// A friend, crew or trip code shown as monospaced text. Tap or long-press to
/// copy it, with a brief "Copied" confirmation.
struct CopyableCode: View {
    let code: String
    var font: Font = .body.monospaced().bold()
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = code
            withAnimation { copied = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation { copied = false }
            }
        } label: {
            Text(copied ? "Copied" : code).font(font)
                .foregroundStyle(copied ? Color.dsScoreGood : DS.accent)
                .contentTransition(.opacity)
        }
        .buttonStyle(.dim)
        .haptic(.success, trigger: copied) { _, new in new }
        .contextMenu {
            Button {
                UIPasteboard.general.string = code
            } label: { Label("Copy code", systemImage: "doc.on.doc") }
        }
        .accessibilityLabel("Copy code \(code)")
    }
}


// MARK: - Profile edit

struct ProfileEditView: View {
    let stats: CommunityService.MyStats
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    private var svc: CommunityService { .shared }

    @State private var name = ""
    @State private var bio = ""
    @State private var homeWater = ""
    @State private var region = ""
    @State private var title = ""
    @State private var earnedFlairs: [TitleFlair] = []
    @State private var showingTitlePicker = false
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatar: UIImage?
    @State private var saving = false

    @ObservedObject private var cloud = CrewCloud.shared
    private var flair: TitleFlair? { TitleFlair.resolve(title) }

    var body: some View {
        NavigationStack {
            CrewCloudGate {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s5) {
                        avatarPicker
                        CrewTextField(label: "Angler name", placeholder: "Your name", text: $name)
                            .textContentType(.name)
                        CrewTextField(label: "Bio", placeholder: "What you fish for and where", text: $bio,
                                      multiline: true)
                        CrewTextField(label: "Home water", placeholder: "Theewaterskloof Dam", text: $homeWater)
                        CrewTextField(label: "Region", placeholder: "Western Cape", text: $region)
                        titleRow
                    }
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s2)
                    .padding(.bottom, DS.Space.s8)
                    .pageWidth()
                }
                .scrollDismissesKeyboard(.interactively)
                .dsScreenBackground()
                .detailScrollEdge()
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.bold()
                        .disabled(saving || !cloud.isAvailable || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task {
                name = svc.myName; bio = svc.myBio; homeWater = svc.myHomeWater; region = svc.myRegion
                title = svc.myTitle
                avatar = svc.myAvatar
                // Titles you can wear are achievements you've actually earned.
                let all = (try? appState.catchRepository.fetchAll(limit: 2000)) ?? []
                let streak = BadgeDefinition.streakWeeks(from: all)
                let earnedAchievements = Set(
                    BadgeDefinition.compute(from: all, streakWeeks: streak)
                        .filter(\.earned).map(\.title))
                earnedFlairs = TitleFlair.all
                    .filter { earnedAchievements.contains($0.achievement) }
                    .sorted { $0.rarity.rawValue > $1.rarity.rawValue }
                // Keep a previously picked title selectable even if the log
                // changed underneath it (catches deleted, say).
                if let current = TitleFlair.resolve(title),
                   !earnedFlairs.contains(where: { $0.id == current.id }) {
                    earnedFlairs.append(current)
                }
            }
            .sheet(isPresented: $showingTitlePicker) {
                TitleFlairPickerSheet(selection: $title, flairs: earnedFlairs)
            }
            .onChange(of: avatarItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) { avatar = UIImage(data: data) }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// The photo, centred, with a camera badge; tap to pick a new one.
    private var avatarPicker: some View {
        PhotosPicker(selection: $avatarItem, matching: .images) {
            VStack(spacing: DS.Space.s2) {
                ZStack(alignment: .bottomTrailing) {
                    CrewAvatar(image: avatar, name: name.isEmpty ? svc.myName : name, size: 104)
                    Image(systemName: "camera.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.dsOnPrimary)
                        .frame(width: 34, height: 34)
                        .background(Color.dsPrimaryButton, in: Circle())
                        .overlay(Circle().stroke(Color.dsBackground, lineWidth: 3))
                }
                Text(avatar == nil ? "Add photo" : "Change photo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.accent)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.dim)
        .accessibilityLabel(avatar == nil ? "Add profile photo" : "Change profile photo")
    }

    /// The title worn under your name, as a row that opens the picker.
    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Title")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.dsText2)
            Button { showingTitlePicker = true } label: {
                HStack(spacing: DS.Space.s3) {
                    ThumbView(systemImage: flair?.icon ?? "rosette",
                              tint: flair?.rarity.color ?? .dsText2, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flair?.name ?? "No title")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.dsText)
                        Text(earnedFlairs.isEmpty ? "Earn achievements to unlock titles"
                                                  : "\(earnedFlairs.count) unlocked")
                            .font(.subheadline)
                            .foregroundStyle(.dsText2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !earnedFlairs.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.dsText3)
                    }
                }
                .padding(DS.Space.s3)
                .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            }
            .buttonStyle(.dim)
            .disabled(earnedFlairs.isEmpty)
            .accessibilityHint("Choose the title shown under your name")
        }
    }

    private func save() {
        saving = true
        Task {
            await svc.updateProfile(name: name, bio: bio, homeWater: homeWater, region: region, avatar: avatar, stats: stats, title: title)
            // Refresh shared spots to reflect any privacy changes.
            let spots = (try? appState.spotRepository.fetchAll()) ?? []
            await svc.republishSharedSpots(spots: spots)
            ToastCenter.shared.show("Profile updated", style: .success)
            dismiss()
        }
    }
}

/// Pick the title you wear: every unlocked title with its icon, rarity colour
/// and the achievement that earned it.
struct TitleFlairPickerSheet: View {
    @Binding var selection: String
    let flairs: [TitleFlair]
    @Environment(\.dismiss) private var dismiss

    private var selected: TitleFlair? { TitleFlair.resolve(selection) }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selection = ""
                    dismiss()
                } label: {
                    ArtRow(title: "No title") {
                        ThumbView(systemImage: "xmark", tint: .dsText2, size: 44)
                    } trailing: {
                        if selected == nil { checkmark }
                    }
                }
                .buttonStyle(.dsRow)
                .buttonHaptic(.selection)
                .dsListRow()
                ForEach(flairs) { flair in
                    Button {
                        selection = flair.name
                        dismiss()
                    } label: {
                        ArtRow(over: flair.rarity.label, title: flair.name,
                               subtitle: "Unlocked by \(flair.achievement)") {
                            ThumbView(systemImage: flair.icon, tint: flair.rarity.color, size: 44)
                        } trailing: {
                            if selected?.id == flair.id { checkmark }
                        }
                    }
                    .buttonStyle(.dsRow)
                    .buttonHaptic(.selection)
                    .dsListRow()
                }
            }
            .dsPlainList()
            .detailScrollEdge()
            .navigationTitle("Title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(DS.accent)
            .accessibilityLabel("Selected")
    }
}

// MARK: - Friend profile + per-friend privacy

/// An angler's page, pushed from friends, crews, trips and leaderboards: who
/// they are, their bests and badges, the catches and spots they share with
/// you, and what you share back.
struct FriendProfileView: View {
    let code: String
    @Environment(AppState.self) private var appState
    @StateObject private var svc = CommunityService.shared

    @State private var profile: CommunityService.Profile?
    @State private var privacy = CommunityService.FriendPrivacy()
    @State private var override = CommunityService.FriendPrivacyOverride()
    /// Set once the initial .task assignment has landed, so onChange(of:
    /// override) only reacts to edits the user actually made.
    @State private var overrideLoaded = false
    @State private var sharedSpots: [CommunityService.SharedSpot] = []
    @State private var catches: [CommunityService.LeaderRow] = []
    @State private var catchAccess = false
    @State private var catchesLoading = true
    @State private var profileLoading = true
    @State private var selectedSpot: CommunityService.SharedSpot?
    @State private var showingSettings = false
    @State private var confirmRemove = false
    @State private var requestSent = false
    @State private var showAllCatches = false
    /// Own catches with full local detail, for the real achievements card when
    /// the profile being viewed is yours.
    @State private var ownDetails: [CatchDetail] = []
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }

    /// Viewing yourself (from a crew roster or leaderboard): it's your own
    /// account, so everything shows, with no grant checks against you.
    private var isSelf: Bool { code == svc.friendCode }
    private var isFriend: Bool { svc.isFriend(code) }
    private var displayName: String { isSelf ? svc.myName : (profile?.name ?? "Angler \(code)") }

    var body: some View {
        CrewCloudGate { page }
    }

    private var page: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                CrewAvatar(image: isSelf ? (svc.myAvatar ?? profile?.avatar) : profile?.avatar,
                           name: displayName, size: 96)
                    .zoomableOnTap(profile?.avatar)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s4)
                DetailHeader(over: privacy.nickname.isEmpty ? nil : privacy.nickname,
                             title: displayName,
                             subtitle: profile.map { "Angler since \($0.memberSince.formatted(.dateTime.month(.wide).year()))" })
                    .padding(.top, DS.Space.s4)
                about
                actions
                if let p = profile {
                    statsGrid(p)
                    if !p.favoriteSpecies.isEmpty { favourite(p.favoriteSpecies) }
                    CrewSection(title: "Achievements") {
                        Group {
                            if isSelf {
                                AchievementsCard(catches: ownDetails)
                                    .padding(DS.Space.s4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                            } else {
                                FriendBadgesCard(badges: BadgeDefinition.computeFriend(
                                    totalCatches: p.totalCatches, speciesCount: p.speciesCount,
                                    bestWeightKg: p.bestWeightKg, bestLengthCm: p.bestLengthCm,
                                    rows: catches))
                            }
                        }
                        .padding(.horizontal, DS.gutter)
                    }
                } else if profileLoading {
                    FishLoader(message: "Loading profile")
                        .frame(height: 90)
                        .frame(maxWidth: .infinity)
                        .padding(.top, DS.Space.s5)
                } else {
                    InlineEmpty(systemImage: "wifi.slash",
                                    text: "Couldn't load this profile. Check your connection and come back.")
                        .padding(.top, DS.Space.s5)
                }
                catchesSection
                if !sharedSpots.isEmpty { spotsSection }
                if isFriend && !isSelf {
                    DangerButton(title: "Remove friend", systemImage: "person.badge.minus") {
                        confirmRemove = true
                    }
                    .padding(.top, DS.Space.s8)
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(DS.accent)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSettings) { friendSettingsSheet }
        .sheet(item: $selectedSpot) { s in
            NavigationStack { SharedSpotDetailView(spot: s, friendName: profile?.name ?? "a friend") }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Remove \(displayName)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove friend", role: .destructive) {
                Haptics.warning()
                svc.removeFriend(code)
                ToastCenter.shared.show("Friend removed", style: .info, haptic: false)
            }
        } message: {
            Text("They stop seeing your catches and shared spots. You can add them again later.")
        }
        .task { await load() }
    }

    private func load() async {
        if profile == nil { profile = svc.cachedProfiles(for: [code]).first }
        if isSelf {
            // Owner sees everything: catches straight from the local log,
            // profile from the published record (or built locally).
            catchAccess = true
            ownDetails = (try? appState.catchRepository.fetchAll(limit: 2000)) ?? []
            catches = ownLocalRows()
            if let fresh = await svc.fetchProfile(code: code) { profile = fresh }
            if profile == nil { profile = ownFallbackProfile() }
            catchesLoading = false
            profileLoading = false
            return
        }
        privacy = svc.privacy(for: code)
        override = svc.override(for: code)
        overrideLoaded = true
        // Instant: last-seen profile, grant answer and catches from disk, so
        // the page fills immediately and quietly swaps in fresh data.
        catchAccess = svc.cachedCatchAccess(code)
        if catchAccess, catches.isEmpty { catches = svc.cachedAnglerCatches(code: code) }
        // Refresh everything in parallel, not one round trip after another.
        async let freshProfile = svc.fetchProfile(code: code)
        async let freshSpots = svc.sharedSpots(fromFriend: code)
        async let freshAccess = svc.hasCatchAccess(to: code)
        if let fresh = await freshProfile { profile = fresh }
        profileLoading = false
        sharedSpots = await freshSpots
        catchAccess = await freshAccess
        if catchAccess { catches = await svc.anglerCatches(code: code) }
        catchesLoading = false
    }

    /// Your catches, straight from the local log, newest first, photos and
    /// species art included.
    private func ownLocalRows() -> [CommunityService.LeaderRow] {
        let all = ownDetails.isEmpty
            ? ((try? appState.catchRepository.fetchAll(limit: 2000)) ?? [])
            : ownDetails
        return all.map {
            CommunityService.LeaderRow(
                id: "me-\($0.catchRecord.id)",
                anglerName: svc.myName,
                friendCode: svc.friendCode,
                species: $0.species?.commonName ?? "Fish",
                weightKg: $0.catchRecord.weightKg,
                lengthCm: $0.catchRecord.lengthCm,
                catchCount: nil,
                region: svc.myRegion,
                date: $0.catchRecord.caughtAt,
                localPhotoPath: $0.catchRecord.photoPath)
        }
    }

    /// A profile built from local data, for an owner who never published one.
    private func ownFallbackProfile() -> CommunityService.Profile {
        .init(id: code, name: svc.myName, bio: svc.myBio, region: svc.myRegion,
              homeWater: svc.myHomeWater, avatar: svc.myAvatar, memberSince: .now,
              totalCatches: catches.count,
              speciesCount: Set(catches.map(\.species)).count,
              bestWeightKg: catches.compactMap(\.weightKg).max() ?? 0,
              bestLengthCm: catches.compactMap(\.lengthCm).max() ?? 0,
              favoriteSpecies: "", title: svc.myTitle)
    }

    /// The badge-earned title under the name: your locally stored pick when
    /// it's you (instant, even before the profile record round-trips).
    private var flairTitle: String? {
        let t = isSelf ? (svc.myTitle.isEmpty ? (profile?.title ?? "") : svc.myTitle)
                       : (profile?.title ?? "")
        return t.isEmpty ? nil : t
    }

    // MARK: Header pieces

    @ViewBuilder private var about: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if let flair = flairTitle { TitleFlairChip(title: flair) }
            if let p = profile, !p.bio.isEmpty {
                Text(p.bio).font(.body).foregroundStyle(.dsText)
            }
            if let p = profile {
                CrewMetaLine(items: [("water.waves", p.homeWater), ("globe", p.region)])
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s3)
    }

    @ViewBuilder private var actions: some View {
        if !isSelf {
            ActionTriple {
                if isFriend {
                    Button { showingSettings = true } label: {
                        Label("Sharing", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(ActionTileStyle(.primary))
                } else {
                    Button {
                        Task {
                            requestSent = await svc.sendFriendRequest(to: code)
                            ToastCenter.shared.show(requestSent ? "Friend request sent" : "Couldn't send the request",
                                                    style: requestSent ? .success : .error)
                        }
                    } label: {
                        Label(requestSent ? "Request sent" : "Add friend",
                              systemImage: requestSent ? "checkmark" : "person.badge.plus")
                    }
                    .buttonStyle(ActionTileStyle(.primary))
                    .disabled(requestSent)
                }
                Button {
                    UIPasteboard.general.string = code
                    ToastCenter.shared.show("Angler code copied", style: .success)
                } label: {
                    Label("Copy code", systemImage: "doc.on.doc")
                }
                .buttonStyle(ActionTileStyle())
                Menu {
                    if isFriend {
                        Button { showingSettings = true } label: {
                            Label("Nickname and sharing", systemImage: "pencil")
                        }
                        Button(role: .destructive) { confirmRemove = true } label: {
                            Label("Remove friend", systemImage: "person.badge.minus")
                        }
                    } else {
                        Button {
                            UIPasteboard.general.string = code
                            Haptics.success()
                        } label: { Label("Copy angler code", systemImage: "doc.on.doc") }
                    }
                } label: {
                    ActionTileLabel("More", systemImage: "ellipsis")
                }
                .buttonStyle(.dim)
            }
            .padding(.top, DS.Space.s5)
        }
    }

    private func statsGrid(_ p: CommunityService.Profile) -> some View {
        CrewSection(title: "Bests") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                StatTile("Catches", systemImage: "fish.fill", value: "\(p.totalCatches)", width: nil)
                StatTile("Species", systemImage: "square.grid.2x2", value: "\(p.speciesCount)", width: nil)
                if p.bestWeightKg > 0 {
                    let w = Units.weightParts(kg: p.bestWeightKg, imperial: imperial)
                    StatTile("Heaviest", systemImage: "scalemass", value: w.0, unit: w.1, width: nil)
                }
                if p.bestLengthCm > 0 {
                    let l = Units.lengthParts(cm: p.bestLengthCm, imperial: imperial)
                    StatTile("Longest", systemImage: "ruler", value: l.0, unit: l.1, width: nil)
                }
            }
            .padding(.horizontal, DS.gutter)
        }
    }

    private func favourite(_ name: String) -> some View {
        ArtRow(over: "Favourite species", title: name) {
            if let sp = SpeciesArtLookup.species(named: name, appState: appState) {
                ThumbView(species: sp)
            } else {
                ThumbView(systemImage: "star.fill", tint: .dsScoreFair)
            }
        }
        .padding(.top, DS.Space.s3)
    }

    // MARK: Catches

    private var visibleCatches: [CommunityService.LeaderRow] {
        showAllCatches ? catches : Array(catches.prefix(10))
    }

    private var catchesSection: some View {
        CrewSection(title: "Catches", detail: catchAccess && !catches.isEmpty ? "\(catches.count)" : nil) {
            if !catchAccess && !catchesLoading {
                InlineEmpty(systemImage: "lock",
                                text: "\(isSelf ? "You haven't" : "This angler hasn't") shared their catch history with you.")
            } else if catches.isEmpty && catchesLoading {
                FishLoader(message: "Reeling in their catches")
                    .frame(height: 84).frame(maxWidth: .infinity)
            } else if catches.isEmpty {
                InlineEmpty(systemImage: "fish", text: "No catches shared yet.")
            } else {
                ForEach(visibleCatches) { c in
                    NavigationLink { CommunityCatchDetailView(row: c) } label: {
                        ArtRow(over: c.date.formatted(date: .abbreviated, time: .omitted),
                               title: CrewText.catchTitle(species: c.species, lengthCm: c.lengthCm, weightKg: c.weightKg),
                               subtitle: c.region.isEmpty ? nil : c.region,
                               chevron: true) {
                            CommunityCatchThumb(row: c, size: 64)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
                if catches.count > 10 && !showAllCatches {
                    Button("Show all \(catches.count) catches") {
                        withAnimation(DS.Motion.spring) { showAllCatches = true }
                    }
                    .buttonStyle(TonalButtonStyle())
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s2)
                }
            }
        }
    }

    private var spotsSection: some View {
        CrewSection(title: "Spots they share with you") {
            ForEach(sharedSpots) { s in
                Button { selectedSpot = s } label: {
                    ArtRow(title: s.name,
                           subtitle: s.isApproximate ? "\(s.type), approximate area" : s.type,
                           chevron: true) {
                        ThumbView(systemImage: s.isApproximate ? "mappin.circle" : "mappin.circle.fill",
                                  tint: .dsScoreGood)
                    }
                }
                .buttonStyle(.dsRow)
            }
        }
    }

    // MARK: Nickname + sharing sheet

    private var friendSettingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s5) {
                    CrewTextField(label: "Nickname", placeholder: "Only you see it", text: $privacy.nickname)
                        .submitLabel(.done)
                        .onSubmit { svc.setNickname(privacy.nickname, for: code) }
                    if isFriend {
                        VStack(alignment: .leading, spacing: DS.Space.s3) {
                            Text("What you share")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.dsText)
                                .accessibilityAddTraits(.isHeader)
                            overrideRow("Catch history", systemImage: "fish",
                                        globalOn: svc.shareCatchesWithFriends,
                                        value: $override.shareCatches)
                            overrideRow("Spots", systemImage: "mappin.and.ellipse",
                                        globalOn: svc.shareSpotsWithFriends,
                                        value: $override.shareSpots)
                            overrideRow("Exact spot locations", systemImage: "scope",
                                        globalOn: svc.shareSpotExactLocations,
                                        value: $override.shareExactLocations)
                            Text("Default follows your privacy settings.")
                                .font(.footnote)
                                .foregroundStyle(.dsText2)
                        }
                    }
                }
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s2)
                .padding(.bottom, DS.Space.s8)
                .pageWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .dsScreenBackground()
            .detailScrollEdge()
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingSettings = false }
                }
            }
            .onChange(of: override) { _, o in
                // The initial .task assignment lands here too; only react to
                // changes the user actually made.
                guard overrideLoaded else { return }
                svc.setOverride(o, for: code)
                ToastCenter.shared.show("Sharing updated", style: .info, haptic: false)
                let spots = (try? appState.spotRepository.fetchAll()) ?? []
                Task { await svc.applyPrivacy(for: code, spots: spots) }
            }
            .onDisappear { svc.setNickname(privacy.nickname, for: code) }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// A three-way per-friend override on its own card: Default (follow the
    /// global setting), Share or Hide.
    private func overrideRow(_ title: String, systemImage: String, globalOn: Bool,
                             value: Binding<Bool?>) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(.dsText)
            Picker(title, selection: Binding(
                get: { value.wrappedValue == nil ? 0 : (value.wrappedValue! ? 1 : 2) },
                set: { value.wrappedValue = $0 == 0 ? nil : ($0 == 1) }
            ).haptic()) {
                Text(globalOn ? "Default, on" : "Default, off").tag(0)
                Text("Share").tag(1)
                Text("Hide").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(DS.Space.s3)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

/// A friend's achievements, computed from their public stats and published
/// catches: earned medals up front, the locked remainder counted, every
/// bubble opening the same explainer your own badges use.
struct FriendBadgesCard: View {
    let badges: [BadgeDefinition]
    @State private var selected: BadgeDefinition?
    @State private var showingAll = false

    private var earned: [BadgeDefinition] {
        badges.filter(\.earned).sorted { $0.rarity.rawValue > $1.rarity.rawValue }
    }
    private var locked: [BadgeDefinition] {
        badges.filter { !$0.earned }.sorted { $0.rarity.rawValue < $1.rarity.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text("\(earned.count) of \(badges.count) earned")
                .font(.subheadline)
                .foregroundStyle(.dsText2)
            if earned.isEmpty {
                Text("No badges yet.")
                    .font(.subheadline).foregroundStyle(.dsText2)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: DS.Space.s3) {
                        ForEach(earned.prefix(6)) { badge in
                            Button { selected = badge } label: { bubble(badge) }
                                .buttonStyle(.dim)
                        }
                    }
                }
            }
            Button("Show all achievements") { showingAll = true }
                .buttonStyle(TonalButtonStyle())
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .sheet(item: $selected) { badge in
            BadgeDetailView(badge: badge)
        }
        .sheet(isPresented: $showingAll) { allBadgesSheet }
    }

    /// Everything computable from their public data: earned first, then what
    /// they haven't unlocked yet.
    private var allBadgesSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    if !earned.isEmpty {
                        grid(earned)
                    }
                    if !locked.isEmpty {
                        Text("Locked")
                            .font(.headline)
                            .foregroundStyle(.dsText2)
                            .padding(.top, DS.Space.s2)
                        grid(locked)
                    }
                }
                .padding(DS.gutter)
            }
            .background(Color.dsBackground)
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func grid(_ list: [BadgeDefinition]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
            ForEach(list) { badge in
                Button { selected = badge } label: { gridCell(badge) }
                    .buttonStyle(.dim)
            }
        }
    }

    private func gridCell(_ badge: BadgeDefinition) -> some View {
        let tint = badge.earned ? badge.rarity.color : Color.dsText3
        return VStack(spacing: 6) {
            Image(systemName: badge.icon)
                .font(.title2)
                .foregroundStyle(tint)
            Text(badge.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(badge.earned ? Color.dsText : Color.dsText3)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(badge.rarity.label)
                .font(.caption2)
                .foregroundStyle(tint)
        }
        .padding(.vertical, DS.Space.s3)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 104)
        .background(badge.earned ? badge.rarity.color.opacity(0.14) : Color.dsFill,
                    in: RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func bubble(_ badge: BadgeDefinition) -> some View {
        VStack(spacing: 6) {
            Image(systemName: badge.icon)
                .font(.title3)
                .foregroundStyle(badge.rarity.color)
                .frame(width: 56, height: 56)
                .background(badge.rarity.color.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
            Text(badge.title)
                .font(.caption)
                .foregroundStyle(.dsText2)
                .lineLimit(1)
                .frame(width: 72)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shared spot detail (map + copy)

/// A friend's shared spot on a map. When the owner only shared an approximate
/// area, the pin sits on an obfuscated point with a radius circle and a clear
/// "approximate" label, so the exact honey hole is never revealed.
struct SharedSpotDetailView: View {
    let spot: CommunityService.SharedSpot
    let friendName: String
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let coord = spot.coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(latitudeDelta: spot.isApproximate ? 0.12 : 0.02,
                                               longitudeDelta: spot.isApproximate ? 0.12 : 0.02)))) {
                        Annotation(spot.name, coordinate: coord) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2).foregroundStyle(DS.accent)
                                .background(Circle().fill(.white))
                        }
                        if spot.isApproximate {
                            MapCircle(center: coord, radius: 4500)
                                .foregroundStyle(DS.accent.opacity(0.12))
                                .stroke(DS.accent.opacity(0.5), lineWidth: 1)
                        }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        if spot.isApproximate {
                            Label("Approximate area", systemImage: "location.circle")
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .glassEffect(.regular, in: Capsule())
                                .padding(10)
                        }
                    }
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s2)
                }

                DetailHeader(over: "Shared by \(friendName)", title: spot.name, subtitle: spot.type)
                    .padding(.top, DS.Space.s4)

                if spot.coordinate != nil {
                    Button {
                        copySpot()
                    } label: {
                        Label(copied ? "Saved to my spots" : "Save to my spots",
                              systemImage: copied ? "checkmark" : "square.and.arrow.down")
                    }
                    .buttonStyle(.dsPrimary)
                    .disabled(copied)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s5)
                    if spot.isApproximate {
                        SectionFootnote("Saves the approximate area. You can fine-tune the pin afterwards.")
                    }
                }

                if spot.isApproximate || !spot.notes.isEmpty {
                    CrewSection(title: "Notes") {
                        VStack(alignment: .leading, spacing: DS.Space.s2) {
                            if !spot.notes.isEmpty {
                                Text(spot.notes).font(.body).foregroundStyle(.dsText)
                            }
                            if spot.isApproximate {
                                Label("Shared as an approximate area. \(friendName) kept the exact location private.",
                                      systemImage: "eye.slash")
                                    .font(.subheadline).foregroundStyle(.dsText2)
                            }
                        }
                        .padding(.horizontal, DS.gutter)
                    }
                }

                if let coord = spot.coordinate {
                    DriveToButton(coordinate: coord, name: spot.name)
                        .padding(.horizontal, DS.gutter)
                        .padding(.top, DS.Space.s5)
                }
            }
            .padding(.bottom, DS.Space.s6)
            .pageWidth()
        }
        .dsScreenBackground()
        .detailScrollEdge()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private func copySpot() {
        guard let coord = spot.coordinate else { return }
        // Already saved on a previous visit? The disable flag resets with the
        // sheet, so re-check against the actual spot list.
        if let existing = try? appState.spotRepository.fetchAll(),
           existing.contains(where: {
               abs($0.latitude - coord.latitude) < 0.0005 &&
               abs($0.longitude - coord.longitude) < 0.0005
           }) {
            copied = true
            ToastCenter.shared.show("Already in your spots", style: .info)
            return
        }
        var newSpot = Spot(
            name: spot.isApproximate ? "\(spot.name) (approx)" : spot.name,
            latitude: coord.latitude,
            longitude: coord.longitude,
            notes: spot.notes.isEmpty ? "Shared by \(friendName)" : spot.notes,
            spotType: Spot.SpotType(rawValue: spot.type) ?? .general
        )
        try? appState.spotRepository.save(&newSpot)
        copied = true
        Haptics.success()
    }
}

// MARK: - Community catch detail

/// A single community catch, pushed from a friend's profile, a trip or a
/// leaderboard row. Resolves species artwork by name where possible.
struct CommunityCatchDetailView: View {
    let row: CommunityService.LeaderRow
    @Environment(AppState.self) private var appState
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }
    @State private var species: Species?
    @State private var photo: UIImage?
    @State private var showingFullscreen = false

    var body: some View {
        CrewCloudGate { page }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s2)
                DetailHeader(over: row.date.formatted(date: .abbreviated, time: .omitted),
                             title: row.species,
                             subtitle: "Caught by \(row.anglerName)")
                    .padding(.top, DS.Space.s4)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    if let w = row.weightKg {
                        let p = Units.weightParts(kg: w, imperial: imperial)
                        StatTile("Weight", systemImage: "scalemass", value: p.0, unit: p.1, width: nil)
                    }
                    if let l = row.lengthCm {
                        let p = Units.lengthParts(cm: l, imperial: imperial)
                        StatTile("Length", systemImage: "ruler", value: p.0, unit: p.1, width: nil)
                    }
                }
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s5)

                if let coord = row.coordinate {
                    CrewSection(title: "Where", detail: row.region.isEmpty ? nil : row.region) {
                        CommunityCatchMap(coordinate: coord)
                            .frame(height: 170)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                            .overlay(alignment: .bottomLeading) {
                                Label("Approximate area", systemImage: "location.circle")
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .glassEffect(.regular, in: Capsule())
                                    .padding(10)
                            }
                            .padding(.horizontal, DS.gutter)
                        DriveToButton(coordinate: coord, name: row.species)
                            .padding(.horizontal, DS.gutter)
                            .padding(.top, DS.Space.s3)
                    }
                } else if !row.region.isEmpty {
                    SectionFootnote(row.region)
                        .padding(.top, DS.Space.s3)
                }
            }
            .padding(.bottom, DS.Space.s6)
            .pageWidth()
        }
        .detailTint(species?.artTint)
        .navigationTitle("Catch")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingFullscreen) {
            if let photo { FullscreenImageViewer(image: photo) }
        }
        .task {
            if let path = row.localPhotoPath {
                photo = PhotoManager.load(path)
            } else if row.hasRemotePhoto {
                photo = await CommunityService.shared.catchPhoto(recordName: row.id)
            }
            species = (try? appState.speciesRepository.fetchByCommonName(row.species)) ?? nil
        }
    }

    @ViewBuilder private var hero: some View {
        if let photo {
            // Fit the whole photo (no crop); tap to view fullscreen and zoom.
            Button { showingFullscreen = true } label: {
                Image(uiImage: photo)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            }
            .buttonStyle(.dim)
            .accessibilityLabel("View photo full screen")
        } else if let species {
            ThumbView(species: species, size: 160)
        } else {
            ThumbView(systemImage: "fish.fill", tint: DS.accent, size: 160)
        }
    }
}

// MARK: - Community map + photo thumbnail helpers

/// A non-interactive mini map centred on a (deliberately obfuscated) catch
/// location, with a soft radius circle to signal it's an approximate area.
private struct CommunityCatchMap: View {
    let coordinate: CLLocationCoordinate2D
    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))) {
            Annotation("", coordinate: coordinate) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2).foregroundStyle(DS.accent)
                    .background(Circle().fill(.white))
            }
            MapCircle(center: coordinate, radius: 3500)
                .foregroundStyle(DS.accent.opacity(0.12))
                .stroke(DS.accent.opacity(0.5), lineWidth: 1)
        }
        .disabled(true)
    }
}

/// A square thumbnail for a community catch: the angler's photo if they shared
/// one, otherwise the species artwork. Loads remote photos lazily and cached.
struct CommunityCatchThumb: View {
    let row: CommunityService.LeaderRow
    var size: CGFloat = 44
    @Environment(AppState.self) private var appState
    @Environment(\.displayScale) private var displayScale
    @State private var photo: UIImage?
    @State private var species: Species?

    var body: some View {
        Group {
            if let photo {
                ThumbView(image: photo, tint: DS.accent, size: size)
            } else if let species {
                ThumbView(species: species, size: size)
            } else {
                ThumbView(systemImage: "fish.fill", tint: DS.accent, size: size)
            }
        }
        .accessibilityHidden(true)
        .task(id: row.id) {
            if let path = row.localPhotoPath {
                let px = size * displayScale
                let scale = displayScale
                photo = await Task.detached { PhotoManager.thumbnail(path, maxPixel: px, scale: scale) }.value
            } else if row.hasRemotePhoto, CrewCloud.shared.isAvailable {
                photo = await CommunityService.shared.catchPhoto(recordName: row.id)
            }
            if photo == nil {
                species = (try? appState.speciesRepository.fetchByCommonName(row.species)) ?? nil
            }
        }
    }
}

// MARK: - Add-friend confirmation (from an invite link)

/// Shown when someone taps a `currents://friend/<CODE>` link: previews the
/// angler's profile and asks before sending a request, rather than silently
/// adding a stranger.
struct AddFriendConfirmView: View {
    let code: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var svc = CommunityService.shared

    @State private var profile: CommunityService.Profile?
    @State private var loading = true
    @State private var added = false
    @State private var sending = false
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }

    private var isFriend: Bool { svc.friends.contains(code.uppercased()) }

    var body: some View {
        CrewCloudGate(closeButton: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if svc.joined { confirmBody } else { joinGate }
                }
                .padding(.bottom, DS.Space.s6)
                .pageWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .dsScreenBackground()
            .detailScrollEdge()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isFriend || added ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    /// Set up a community profile before revealing the angler's profile.
    private var joinGate: some View {
        VStack(spacing: DS.Space.s3) {
            CrewGateArt()
                .padding(.top, DS.Space.s4)
                .padding(.bottom, DS.Space.s3)
            Text("Add a friend")
                .font(.title.bold())
                .foregroundStyle(.dsText)
            Text("Someone shared their angler code with you. Pick the name they'll see, then send a request.")
                .font(.body)
                .foregroundStyle(.dsText2)
                .multilineTextAlignment(.center)
            // svc.joined flips, confirmBody appears and its .task loads the
            // shared angler's profile.
            CrewJoinForm(buttonTitle: "Join and continue")
                .padding(.top, DS.Space.s3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.gutter)
    }

    @ViewBuilder private var confirmBody: some View {
        Group {
            if loading {
                FishLoader(message: "Looking up angler")
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Space.s6)
            } else if let p = profile {
                CrewAvatar(image: p.avatar, name: p.name, size: 88)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s4)
                DetailHeader(over: "Angler code \(p.id)", title: p.name,
                             subtitle: p.bio.isEmpty ? nil : p.bio)
                    .padding(.top, DS.Space.s4)
                CrewMetaLine(items: [("water.waves", p.homeWater), ("globe", p.region)])
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s3)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    StatTile("Catches", systemImage: "fish.fill", value: "\(p.totalCatches)", width: nil)
                    StatTile("Species", systemImage: "square.grid.2x2", value: "\(p.speciesCount)", width: nil)
                    if p.bestWeightKg > 0 {
                        let w = Units.weightParts(kg: p.bestWeightKg, imperial: imperial)
                        StatTile("Heaviest", systemImage: "scalemass", value: w.0, unit: w.1, width: nil)
                    }
                    if p.bestLengthCm > 0 {
                        let l = Units.lengthParts(cm: p.bestLengthCm, imperial: imperial)
                        StatTile("Longest", systemImage: "ruler", value: l.0, unit: l.1, width: nil)
                    }
                }
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s5)

                Group {
                    if isFriend {
                        Label("You're friends", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.dsScoreGood)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    } else if added {
                        Label("Friend request sent", systemImage: "paperplane.fill")
                            .font(.headline)
                            .foregroundStyle(.dsScoreGood)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    } else {
                        Button {
                            sending = true
                            Task {
                                let ok = await svc.sendFriendRequest(to: code)
                                sending = false
                                added = ok
                                ToastCenter.shared.show(ok ? "Friend request sent" : "Couldn't send the request",
                                                        style: ok ? .success : .error)
                            }
                        } label: {
                            if sending { ProgressView() } else { Label("Send friend request", systemImage: "person.badge.plus") }
                        }
                        .buttonStyle(.dsPrimary)
                        .disabled(sending)
                    }
                }
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s5)
                SectionFootnote("They'll see your request on their Crew tab.")
            } else {
                ContentUnavailableView(
                    "Angler not found",
                    systemImage: "person.slash",
                    description: Text("Code \(code) doesn't match anyone yet. Ask them to join the community first.")
                )
                .padding(.top, DS.Space.s6)
            }
        }
        .task {
            guard svc.joined else { loading = false; return }
            profile = await svc.fetchProfile(code: code)
            loading = false
        }
    }
}
