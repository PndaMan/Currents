import SwiftUI
import PhotosUI
import MapKit
import Network

/// The Crew tab root: what is happening now, group trips, your crews, friends
/// and the merged catch feed from every crew. Crew, friend and request pages
/// push on this tab's stack.
struct CommunityView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var svc = CommunityService.shared
    @ObservedObject private var cloud = CrewCloud.shared
    @ObservedObject private var connection = CrewConnection.shared

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
    /// When the network load last ran. Coming back from a pushed page or
    /// another tab within 30 seconds skips it; the poll keeps things fresh.
    @State private var lastLoad: Date?
    /// Coalesces a burst of revision bumps into one reload.
    @State private var reloadGen = 0

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
            await refreshStats()
            guard canSync else { return }
            // This task restarts on every pop back and tab switch; a full
            // reload each time is what made the tab feel slow.
            if let lastLoad, Date().timeIntervalSince(lastLoad) < 30 {
                // Fresh enough: go straight to the poll below.
            } else {
                // Visible content first: cached friends and feed, then the network.
                friendProfiles = CrewFriendsLoader.cached()
                await loadMergedFeed()
                await loadNotifications()
                friendProfiles = await CrewFriendsLoader.load()
                await loadLive()
                // Only a load that ran to the end counts; one cut short by
                // leaving the tab runs again on return.
                if !Task.isCancelled { lastLoad = Date() }
                // Maintenance in the background: publish history, heal grants and
                // spot shares, and rebuild membership from the server once per
                // launch (a reinstall used to show zero crews or trips while the
                // server still counted and pushed to this angler).
                Task {
                    await syncCatches()
                    await svc.reconcileMemberships()
                }
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
            // A burst of pushes bumps the revision several times; reload
            // once. Local stats don't depend on it, so they're not re-read.
            reloadGen &+= 1
            let gen = reloadGen
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard gen == reloadGen else { return }
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
        case .leaderboard(let code): CrewLeaderboardView(code: code)
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
                let ok = await svc.updateProfile(name: svc.myName, bio: svc.myBio, homeWater: svc.myHomeWater,
                                                 region: region, avatar: nil, stats: stats)
                if ok {
                    ToastCenter.shared.show("You're in. Add a friend or start a crew", style: .success, haptic: false)
                } else {
                    ToastCenter.shared.show("You're in. Couldn't update your Crew profile", style: .error, haptic: false)
                }
            }
            .padding(.top, DS.Space.s3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.gutter)
    }

    // MARK: Joined

    /// Luma's home order: what needs you, what is on now, your plans, your
    /// groups, your people, then the feed. Each section keeps its title and
    /// shows an inline empty state rather than disappearing, so a new angler
    /// sees every way in.
    @ViewBuilder private var joinedContent: some View {
        if connection.isOffline {
            EventNotice("Offline. Crews, trips and the feed update when you're back online.",
                        systemImage: "wifi.slash") { EmptyView() }
                .padding(.top, DS.Space.s2)
        }
        inboxRow
        happeningNow
        groupTrips
        crewsSection
        friendsSection
        feedSection
    }

    /// "2" after a section title, or nothing when there are none.
    private func countDetail(_ n: Int) -> String? { n > 0 ? "\(n)" : nil }

    // MARK: Inbox

    @ViewBuilder private var inboxRow: some View {
        if notificationCount > 0 {
            NavigationLink(value: CrewRoute.requests) {
                ArtRow(title: notificationCount == 1 ? "1 waiting for you" : "\(notificationCount) waiting for you",
                       subtitle: inboxSummary, chevron: true) {
                    ThumbView(systemImage: "bell.fill", tint: DS.accent)
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
                    liveTournamentRow(item)
                }
                ForEach(liveTrips) { item in
                    liveTripRow(item)
                }
            }
        }
    }

    private func liveTournamentRow(_ item: LiveTournament) -> some View {
        NavigationLink {
            TournamentView(tournament: item.tournament, crew: item.crew)
        } label: {
            CrewEventRow(isLive: true,
                         over: item.rank.map { "\(item.crew.name), you're \(CrewText.ordinal($0))" } ?? item.crew.name,
                         title: item.tournament.name,
                         endsAt: item.tournament.endsAt) {
                ThumbView(systemImage: "trophy.fill", tint: .dsScoreFair)
            }
        }
        .buttonStyle(.dsRow)
    }

    private func liveTripRow(_ item: LiveTrip) -> some View {
        NavigationLink(value: CrewRoute.trip(code: item.trip.id, name: item.trip.name)) {
            CrewEventRow(isLive: true, over: item.crew.name, title: item.trip.name,
                         subtitle: item.trip.hostCode == svc.friendCode
                            ? "You're hosting" : "Hosted by \(item.trip.hostName)") {
                ThumbView(systemImage: "dot.radiowaves.left.and.right", tint: .dsScoreGood)
            }
        }
        .buttonStyle(.dsRow)
    }

    // MARK: Group trips

    /// Trips still running first, ended ones after them.
    private var sortedGroups: [CommunityService.GroupRef] {
        svc.myGroups.filter { $0.endedAt == nil } + svc.myGroups.filter { $0.endedAt != nil }
    }

    private var groupTrips: some View {
        CrewSection(title: "Group trips", detail: countDetail(svc.myGroups.count)) {
            ForEach(sortedGroups) { g in
                groupRow(g)
            }
            NavigationLink(value: CrewRoute.tripSetup(crewCode: nil)) {
                ArtRow(title: "Plan a group trip", subtitle: "Start now or pick a day, then invite friends",
                       chevron: true) {
                    ThumbView(systemImage: "calendar.badge.plus", tint: DS.accent)
                }
            }
            .buttonStyle(.dsRow)
        }
    }

    private func groupRow(_ g: CommunityService.GroupRef) -> some View {
        let ended = g.endedAt != nil
        let host = g.isHost ? "You're hosting" : "Hosted by \(g.hostName)"
        return NavigationLink(value: CrewRoute.trip(code: g.code, name: g.name)) {
            CrewEventRow(over: ended ? "Ended" : host,
                         title: g.name,
                         subtitle: g.teamName.map { "Tournament team \($0)" } ?? "Trip code \(g.code)") {
                ThumbView(systemImage: g.teamName != nil ? "trophy.fill" : "person.3.fill",
                          tint: ended ? .dsText2 : .dsScoreLow)
            }
        }
        .buttonStyle(.dsRow)
        .contextMenu {
            Button(role: .destructive) { confirmRemoveTrip = g } label: {
                Label("Remove trip", systemImage: "trash")
            }
        }
    }

    // MARK: Crews

    private var crewsSection: some View {
        CrewSection(title: "Your crews", detail: countDetail(svc.myCrews.count), link: .crews) {
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
        CrewSection(title: "Friends", detail: countDetail(svc.friends.count), link: .friends) {
            if svc.friends.isEmpty {
                InlineEmpty(systemImage: "person.2",
                            text: "No friends yet. Add one with their angler code to see their catches.",
                            actionTitle: "Add a friend") { sheet = .addFriend }
                    .padding(.bottom, DS.Space.s2)
            } else {
                friendStrip
            }
            Button { GameCenter.shared.openLeaderboards() } label: {
                ArtRow(title: "Game Center leaderboards",
                       subtitle: GameCenter.shared.isAuthenticated ? "Friends and global rankings"
                           : "Sign in to Game Center to see rankings",
                       chevron: true) {
                    ThumbView(systemImage: "gamecontroller.fill", tint: CrewTint.people)
                }
            }
            .buttonStyle(.dsRow)
        }
    }

    /// Faces you can tap, with Add first, like the people strip in Messages.
    private var friendStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.Space.s2) {
                Button { sheet = .addFriend } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "person.badge.plus")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(.dsText)
                            .frame(width: 56, height: 56)
                            .background(Color.dsTonal, in: Circle())
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

    /// Reads the whole log on the database queue; the synchronous read
    /// stalled the tab's first frames for anglers with long logs.
    private func refreshStats() async {
        myCatches = (try? await appState.catchRepository.fetchAllInBackground(limit: 100000)) ?? []
        cachedStats = computeStatsFrom(myCatches)
    }
    private var stats: CommunityService.MyStats { cachedStats ?? computeStatsFrom(myCatches) }

    private func loadNotifications() async {
        guard canSync else { return }
        pendingRequests = await svc.refreshFriendRequests()
        pendingInvites = await svc.refreshTripInvites()
    }

    /// Each crew's tournament (with standings, for the rank pill) and live
    /// trips. Crews are few, so one crew at a time keeps this simple.
    private func loadLive() async {
        // Screenshot mode reads the demo tournament and live trip seeded by
        // ScreenshotSupport, so "Happening now" photographs populated.
        guard canSync else { return }
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
        // refreshStats has just read the whole log; reuse it.
        let details = myCatches.map {
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

/// Your own angler page, in Luma's profile structure: photo, name and code,
/// title, bio and facts, a line of counts, the three actions, then your
/// badges and the way out of Crew.
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
                AnglerProfileHeader(
                    avatar: svc.myAvatar, name: svc.myName,
                    handle: "Angler code \(svc.friendCode)",
                    title: svc.myTitle.isEmpty ? nil : svc.myTitle,
                    bio: svc.myBio,
                    facts: AnglerProfileHeader.facts(homeWater: svc.myHomeWater, region: svc.myRegion,
                                                     favourite: stats.favoriteSpecies, since: svc.memberSince))
                AnglerStatsLine(AnglerStatsLine.items(
                    catches: stats.totalCatches, species: stats.speciesCount,
                    bestWeightKg: stats.bestWeightKg, bestLengthCm: stats.bestLengthCm, imperial: imperial))
                    .padding(.top, DS.Space.s4)
                actions
                    .padding(.top, DS.Space.s5)
                CrewSection(title: "Badges") {
                    AchievementsCard(catches: catches)
                        .padding(.horizontal, DS.gutter)
                }
                DangerButton(title: "Leave Crew", systemImage: "rectangle.portrait.and.arrow.right") {
                    confirmLeave = true
                }
                .padding(.top, DS.Space.s8)
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        // Anglers have no colour of their own, so the page stays plain.
        .detailTint(nil)
        .eventPageTitle(svc.myName)
        .sheet(isPresented: $showingEdit) { ProfileEditView(stats: stats) }
        .confirmationDialog("Leave Crew?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                Haptics.warning()
                svc.leave()
                ToastCenter.shared.show("Left Crew", style: .info, haptic: false)
                dismiss()
            }
        } message: {
            Text("Nothing new is shared and notifications stop. What you've already shared stays until you delete it.")
        }
    }

    private var actions: some View {
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
    }
}
// MARK: - Profile parts

/// The top of an angler's page in Today's hero shape: their code (or your
/// nickname for them) over the name, the bio as the one line, the round
/// photo on the right. Under it the title they wear as a badge, and their
/// facts with coloured icons.
private struct AnglerProfileHeader: View {
    let avatar: UIImage?
    let name: String
    /// The nickname you gave them, over the name.
    var over: String? = nil
    var handle: String? = nil
    var title: String? = nil
    var bio: String = ""
    var facts: [(String, String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHero(label: heroLabel, value: name, callout: bio.isEmpty ? nil : bio) {
                CrewAvatar(image: avatar, name: name, size: 92)
                    .zoomableOnTap(avatar)
            }
            .accessibilityAddTraits(.isHeader)
            .padding(.top, DS.Space.s2)
            if let title {
                TitleFlairChip(title: title)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s5)
            }
            if facts.contains(where: { !$0.1.isEmpty }) {
                AnglerFactsLine(facts: facts)
                    .padding(.top, DS.Space.s4)
            }
        }
    }

    /// "Nickname, angler code ABC123" or just the code line.
    private var heroLabel: String {
        let code = handle ?? "Angler"
        guard let over, !over.isEmpty else { return code }
        return "\(over), \(code.prefix(1).lowercased())\(code.dropFirst())"
    }

    /// Home water, region, favourite species and joining month, as icon
    /// facts. Empty ones drop out.
    static func facts(homeWater: String, region: String, favourite: String, since: Date?) -> [(String, String)] {
        [("water.waves", homeWater),
         ("mappin.and.ellipse", region),
         ("fish.fill", favourite.isEmpty ? "" : "Mostly \(favourite)"),
         ("calendar", since.map { "Since \($0.formatted(.dateTime.month(.wide).year()))" } ?? "")]
    }
}

/// An angler's facts as a scrolling row of filled chips, each icon in its
/// own colour: water cyan, region orange, fish blue, calendar red.
private struct AnglerFactsLine: View {
    let facts: [(String, String)]

    private var shown: [(String, String)] { facts.filter { !$0.1.isEmpty } }

    private func tint(_ symbol: String) -> Color {
        switch symbol {
        case "water.waves": return CrewTint.water
        case "mappin.and.ellipse": return CrewTint.region
        case "fish.fill": return CrewTint.fish
        case "calendar": return CrewTint.calendar
        default: return DS.accent
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                ForEach(shown.indices, id: \.self) { i in
                    chip(shown[i].0, shown[i].1)
                }
            }
            .padding(.horizontal, DS.gutter)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .accessibilityElement(children: .combine)
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint(symbol))
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.dsText)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(minHeight: 34)
        .background(tint(symbol).opacity(0.14), in: Capsule())
    }
}

/// An angler's counts as Logbook stat tiles in a scrolling strip: catches,
/// species, and their heaviest and longest once there is one.
private struct AnglerStatsLine: View {
    struct Item: Identifiable {
        let label: String
        let systemImage: String
        let tint: Color
        let value: String
        var unit: String? = nil
        var id: String { label }
    }

    let items: [Item]
    init(_ items: [Item]) { self.items = items }

    var body: some View {
        StatStrip {
            ForEach(items) { item in
                StatTile(item.label, systemImage: item.systemImage, tint: item.tint,
                         value: item.value, unit: item.unit, width: 128)
            }
        }
    }

    /// Catches and species always; heaviest and longest once there is one.
    static func items(catches: Int, species: Int, bestWeightKg: Double, bestLengthCm: Double,
                      imperial: Bool) -> [Item] {
        var out = [Item(label: "Catches", systemImage: "fish.fill", tint: CrewTint.fish, value: "\(catches)"),
                   Item(label: "Species", systemImage: "leaf.fill", tint: CrewTint.species, value: "\(species)")]
        if bestWeightKg > 0 {
            let p = Units.weightParts(kg: bestWeightKg, imperial: imperial)
            out.append(Item(label: "Heaviest", systemImage: "scalemass.fill", tint: CrewTint.weight,
                            value: p.0, unit: p.1))
        }
        if bestLengthCm > 0 {
            let p = Units.lengthParts(cm: bestLengthCm, imperial: imperial)
            out.append(Item(label: "Longest", systemImage: "ruler.fill", tint: CrewTint.length,
                            value: p.0, unit: p.1))
        }
        return out
    }
}

// MARK: - Connection

/// Whether the phone has a connection, for the Crew pages' offline notices.
/// It starts assuming online, so nothing flashes "Offline" before the first
/// answer arrives.
@MainActor
final class CrewConnection: ObservableObject {
    static let shared = CrewConnection()
    @Published private(set) var isOffline = false
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let offline = path.status != .satisfied
            Task { @MainActor in
                if CrewConnection.shared.isOffline != offline { CrewConnection.shared.isOffline = offline }
            }
        }
        monitor.start(queue: DispatchQueue(label: "CrewConnection"))
    }
}

/// The title worn under an angler's name: the unlocking achievement's symbol
/// in its rarity colour beside the title. Tapping it opens that achievement.
struct TitleFlairChip: View {
    let title: String
    @State private var showingBadge = false

    private var flair: TitleFlair? { TitleFlair.resolve(title) }
    private var tint: Color { flair?.rarity.color ?? .dsText2 }

    var body: some View {
        Button {
            guard flair != nil else { return }
            showingBadge = true
        } label: {
            if let flair {
                TitleBadge(flair: flair, subtitle: flair.unlockLine) {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.dsText3)
                }
            } else {
                Label {
                    Text(title)
                        .foregroundStyle(.dsText)
                } icon: {
                    Image(systemName: "rosette")
                        .foregroundStyle(tint)
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .buttonStyle(.dim)
        .accessibilityHint("Shows the badge that unlocked this title")
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

/// A labelled field for 6-character friend, crew and trip codes, in the same
/// shape as CrewTextField. Uppercases and caps at 6 characters. The label is
/// `label`, or the placeholder when there is none.
struct CodeField: View {
    @Binding var text: String
    var placeholder = "Code"
    var label: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label ?? placeholder)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.dsText2)
            TextField("6 letters and numbers", text: $text)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(.dsText)
                .padding(.horizontal, DS.Space.s4)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                .accessibilityLabel(label ?? placeholder)
                .onChange(of: text) { _, v in
                    let up = String(v.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.prefix(6))
                    if up != text { text = up }
                }
        }
    }
}

/// A friend, crew or trip code shown as text. Tap or long-press to copy it,
/// with a brief "Copied" confirmation.
struct CopyableCode: View {
    let code: String
    var font: Font = .body.bold().monospacedDigit()
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
    @State private var avatarChanged = false
    @State private var saving = false
    /// Set once the saved profile has been copied into the fields.
    @State private var loaded = false
    /// 1 name, 2 bio, 3 home water, 4 region.
    @FocusState private var focused: Int?

    @ObservedObject private var cloud = CrewCloud.shared
    private var flair: TitleFlair? { TitleFlair.resolve(title) }

    /// True once anything differs from the saved profile, so a swipe can't
    /// throw the edits away.
    private var hasChanges: Bool {
        guard loaded else { return false }
        return avatarChanged || name != svc.myName || bio != svc.myBio
            || homeWater != svc.myHomeWater || region != svc.myRegion || title != svc.myTitle
    }

    var body: some View {
        NavigationStack {
            CrewCloudGate {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s5) {
                        avatarPicker
                        CrewTextField(label: "Angler name", placeholder: "Your name", text: $name,
                                      focus: $focused, focusID: 1)
                            .textContentType(.name)
                            .submitLabel(.next)
                            .onSubmit { focused = 2 }
                        CrewTextField(label: "Bio", placeholder: "What you fish for and where", text: $bio,
                                      multiline: true, focus: $focused, focusID: 2)
                        CrewTextField(label: "Home water", placeholder: "Theewaterskloof Dam", text: $homeWater,
                                      focus: $focused, focusID: 3)
                            .submitLabel(.next)
                            .onSubmit { focused = 4 }
                        CrewTextField(label: "Region", placeholder: "Western Cape", text: $region,
                                      focus: $focused, focusID: 4)
                            .submitLabel(.done)
                            .onSubmit { focused = nil }
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
                    Button { save() } label: {
                        if saving { ProgressView() } else { Text("Save") }
                    }
                    .bold()
                    .accessibilityLabel("Save")
                    .disabled(saving || !cloud.isAvailable || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task {
                name = svc.myName; bio = svc.myBio; homeWater = svc.myHomeWater; region = svc.myRegion
                title = svc.myTitle
                avatar = svc.myAvatar
                loaded = true
                // Titles you can wear are achievements you've actually earned.
                let all = (try? await appState.catchRepository.fetchAllInBackground(limit: 2000)) ?? []
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
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        avatar = UIImage(data: data)
                        avatarChanged = true
                    }
                }
            }
        }
        .interactiveDismissDisabled(hasChanges || saving)
        .dsSheet([.large])
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
                if let flair {
                    TitleBadge(flair: flair, subtitle: "\(earnedFlairs.count) unlocked", medallionSize: 48) {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.dsText3)
                    }
                } else {
                    noTitleLabel
                }
            }
            .buttonStyle(.dim)
            .disabled(earnedFlairs.isEmpty)
            .accessibilityHint("Choose the title shown under your name")
        }
    }

    private var noTitleLabel: some View {
        HStack(spacing: DS.Space.s3) {
            ThumbView(systemImage: "rosette", tint: .dsScoreFair, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("No title")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.dsText)
                Text(earnedFlairs.isEmpty ? "Earn badges to unlock titles"
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

    /// The profile is saved on this phone first. Only a published copy
    /// counts as updated; otherwise the sheet stays open to try again.
    private func save() {
        focused = nil
        saving = true
        Task {
            let ok = await svc.updateProfile(name: name, bio: bio, homeWater: homeWater, region: region,
                                             avatar: avatar, stats: stats, title: title)
            avatarChanged = false
            // Refresh shared spots to reflect any privacy changes.
            let spots = (try? appState.spotRepository.fetchAll()) ?? []
            await svc.republishSharedSpots(spots: spots)
            saving = false
            if ok {
                ToastCenter.shared.show("Profile updated", style: .success)
                dismiss()
            } else {
                ToastCenter.shared.show("Saved on this phone. Couldn't update your Crew profile", style: .error)
            }
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

    /// Titles not yet unlocked, rarest last, so the shelf shows what's still
    /// to earn. The secret one stays secret.
    private var locked: [TitleFlair] {
        let earned = Set(flairs.map(\.id))
        return TitleFlair.all
            .filter { !earned.contains($0.id) && $0.achievement != "Bass Daddy" }
            .sorted { $0.rarity.rawValue < $1.rarity.rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    noTitleRow
                    if !flairs.isEmpty {
                        SectionTitle("Unlocked", detail: "\(flairs.count)")
                            .padding(.top, DS.Space.s6)
                        badges(flairs, locked: false)
                    }
                    if !locked.isEmpty {
                        SectionTitle("Still to earn", detail: "\(locked.count)")
                            .padding(.top, DS.Space.s6)
                        badges(locked, locked: true)
                    }
                }
                .padding(.top, DS.Space.s2)
                .padding(.bottom, DS.Space.s8)
                .pageWidth()
            }
            .dsScreenBackground()
            .detailScrollEdge()
            .navigationTitle("Title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { SheetDoneButton() }
            }
        }
        .dsSheet([.medium, .large])
    }

    private var noTitleRow: some View {
        CardGroup {
            Button {
                selection = ""
                dismiss()
            } label: {
                CardRow("No title", subtitle: "Show only your name", systemImage: "xmark", tint: .red) {
                    if selected == nil { checkmark }
                }
            }
            .buttonStyle(.dsCardRow)
            .buttonHaptic(.selection)
            .accessibilityAddTraits(selected == nil ? .isSelected : [])
        }
    }

    private func badges(_ list: [TitleFlair], locked: Bool) -> some View {
        VStack(spacing: 10) {
            ForEach(list) { flair in
                if locked {
                    TitleBadge(flair: flair, subtitle: "Earn \(flair.achievement)", medallionSize: 48, locked: true)
                } else {
                    Button {
                        selection = flair.name
                        dismiss()
                    } label: {
                        TitleBadge(flair: flair, subtitle: flair.unlockLine, medallionSize: 48) {
                            if selected?.id == flair.id { checkmark }
                        }
                    }
                    .buttonStyle(.dim)
                    .buttonHaptic(.selection)
                    .accessibilityAddTraits(selected?.id == flair.id ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, DS.gutter)
    }

    private var checkmark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.title3)
            .symbolRenderingMode(.hierarchical)
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
    /// The last refresh couldn't reach iCloud while online, so the catches
    /// on screen may be old.
    @State private var catchesRefreshFailed = false
    @State private var profileLoading = true
    /// The code has no published profile (not the same as a failed fetch).
    @State private var profileMissing = false
    @State private var selectedSpot: CommunityService.SharedSpot?
    @State private var showingSettings = false
    @State private var confirmRemove = false
    @State private var requestSent = false
    @State private var sendingRequest = false
    /// A sharing menu changed while the sheet was open; said once on close.
    @State private var sharingChanged = false
    @State private var showAllCatches = false
    /// Own catches with full local detail, for the real achievements card when
    /// the profile being viewed is yours.
    @State private var ownDetails: [CatchDetail] = []
    @AppStorage("units") private var units = "metric"
    @ObservedObject private var connection = CrewConnection.shared
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
                header
                statsBlock
                actions
                offlineNotice
                refreshNotice
                catchesSection
                if !sharedSpots.isEmpty { spotsSection }
                achievementsSection
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
        // Anglers have no colour of their own, so the page stays plain.
        .detailTint(nil)
        .eventPageTitle(displayName)
        .sheet(isPresented: $showingSettings) { friendSettingsSheet }
        .sheet(item: $selectedSpot) { s in
            NavigationStack { SharedSpotDetailView(spot: s, friendName: profile?.name ?? "a friend") }
                .dsSheet([.medium, .large])
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
            ownDetails = (try? await appState.catchRepository.fetchAllInBackground(limit: 2000)) ?? []
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
        async let freshProfile = svc.lookupProfile(code: code)
        async let freshSpots = svc.sharedSpots(fromFriend: code)
        async let freshAccess = svc.hasCatchAccess(to: code)
        // The grant and catch calls fall back to saved answers without
        // saying so; a failed profile lookup in the same pass is the sign
        // that iCloud couldn't be reached.
        var refreshFailed = false
        let lookup = await freshProfile
        switch lookup {
        case .found(let fresh):
            profile = fresh
            profileMissing = false
        case .notFound:
            profileMissing = true
        case .failed:
            refreshFailed = true
        case .ownCode:
            break
        }
        profileLoading = false
        sharedSpots = await freshSpots
        catchAccess = await freshAccess
        if catchAccess { catches = await svc.anglerCatches(code: code) }
        catchesRefreshFailed = refreshFailed
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

    private var header: some View {
        AnglerProfileHeader(
            avatar: isSelf ? (svc.myAvatar ?? profile?.avatar) : profile?.avatar,
            name: displayName,
            over: privacy.nickname.isEmpty ? nil : privacy.nickname,
            handle: "Angler code \(code)",
            title: flairTitle,
            bio: profile?.bio ?? "",
            facts: AnglerProfileHeader.facts(homeWater: profile?.homeWater ?? "",
                                             region: profile?.region ?? "",
                                             favourite: profile?.favoriteSpecies ?? "",
                                             since: profile?.memberSince))
    }

    /// Their counts on one line, or the loading and failed states while the
    /// profile record is missing.
    @ViewBuilder private var statsBlock: some View {
        if let p = profile {
            AnglerStatsLine(AnglerStatsLine.items(
                catches: p.totalCatches, species: p.speciesCount,
                bestWeightKg: p.bestWeightKg, bestLengthCm: p.bestLengthCm, imperial: imperial))
                .padding(.top, DS.Space.s4)
        } else if profileLoading {
            FishLoader(message: "Loading profile")
                .frame(height: 90)
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Space.s5)
        } else if profileMissing && !connection.isOffline {
            InlineEmpty(systemImage: "person.slash",
                        text: "No Crew profile uses this angler code.")
                .padding(.top, DS.Space.s5)
        } else {
            InlineEmpty(systemImage: "wifi.slash",
                        text: connection.isOffline
                            ? "Offline. This profile loads when you're back online."
                            : "Couldn't load this profile. Check your connection and come back.")
                .padding(.top, DS.Space.s5)
        }
    }

    /// Shown only when the page has something saved to fall back on; with
    /// nothing saved, the stats line above says it instead.
    @ViewBuilder private var offlineNotice: some View {
        if connection.isOffline && profile != nil && !isSelf {
            EventNotice("Offline. Showing what was saved last time.", systemImage: "wifi.slash") {
                EmptyView()
            }
            .padding(.top, DS.Space.s5)
        }
    }

    /// Online but the refresh failed: the catches below are the saved ones.
    @ViewBuilder private var refreshNotice: some View {
        if catchesRefreshFailed && !connection.isOffline && !isSelf {
            EventNotice("Couldn't refresh catches", systemImage: "exclamationmark.icloud") {
                Button("Try again") {
                    catchesRefreshFailed = false
                    Task { await load() }
                }
            }
            .padding(.top, DS.Space.s5)
        }
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
                    addFriendButton
                }
                Button {
                    UIPasteboard.general.string = code
                    ToastCenter.shared.show("Angler code copied", style: .success)
                } label: {
                    Label("Copy code", systemImage: "doc.on.doc")
                }
                .buttonStyle(ActionTileStyle())
                if isFriend { moreMenu }
            }
            .padding(.top, DS.Space.s5)
        }
    }

    private var addFriendButton: some View {
        Button {
            sendingRequest = true
            Task {
                let result = await svc.sendFriendRequestResult(to: code)
                sendingRequest = false
                switch result {
                case .found:
                    requestSent = true
                    ToastCenter.shared.show("Friend request sent", style: .success)
                case .notFound:
                    ToastCenter.shared.show("No angler matches that code", style: .error)
                case .ownCode:
                    ToastCenter.shared.show("That's your own angler code", style: .error)
                case .failed:
                    ToastCenter.shared.show(connection.isOffline ? "You're offline. Send it when you're back online"
                                                                 : "Can't reach Crew right now. Try again",
                                            style: .error)
                }
            }
        } label: {
            if sendingRequest {
                Label {
                    Text("Sending")
                } icon: {
                    ProgressView()
                }
            } else {
                Label(requestSent ? "Request sent" : "Add friend",
                      systemImage: requestSent ? "checkmark" : "person.badge.plus")
            }
        }
        .buttonStyle(ActionTileStyle(.primary))
        .disabled(requestSent || sendingRequest)
    }

    private var moreMenu: some View {
        Menu {
            Button { showingSettings = true } label: {
                Label("Nickname and sharing", systemImage: "pencil")
            }
            Button { GameCenter.shared.addFriend() } label: {
                Label("Add on Game Center", systemImage: "gamecontroller")
            }
            Button(role: .destructive) { confirmRemove = true } label: {
                Label("Remove friend", systemImage: "person.badge.minus")
            }
        } label: {
            ActionTileLabel("More", systemImage: "ellipsis")
        }
        .buttonStyle(.dim)
    }

    /// Your own medals when it is you; otherwise the badges their public
    /// numbers and shared catches earn.
    @ViewBuilder private var achievementsSection: some View {
        if let p = profile {
            CrewSection(title: "Badges") {
                Group {
                    if isSelf {
                        AchievementsCard(catches: ownDetails)
                    } else {
                        FriendBadgesCard(badges: BadgeDefinition.computeFriend(
                            totalCatches: p.totalCatches, speciesCount: p.speciesCount,
                            bestWeightKg: p.bestWeightKg, bestLengthCm: p.bestLengthCm,
                            rows: catches))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.gutter)
            }
        }
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
                    let kind = (Spot.SpotType(rawValue: s.type) ?? .general).label
                    ArtRow(title: s.name,
                           subtitle: s.isApproximate ? "\(kind), approximate area" : kind,
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
                VStack(alignment: .leading, spacing: 0) {
                    PageHero(label: "Sharing with", value: displayName, callout: sharingSummary) {
                        CrewAvatar(image: profile?.avatar, name: displayName, size: 64)
                    }
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, DS.Space.s2)
                    CardSection("Nickname") { nicknameRow }
                        .padding(.top, DS.Space.s6)
                    if isFriend { shareSection }
                }
                .padding(.bottom, DS.Space.s8)
                .pageWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .dsScreenBackground()
            .detailScrollEdge()
            .navigationTitle("Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { SheetDoneButton() }
            }
            .onChange(of: override) { _, o in
                // The initial .task assignment lands here too; only react to
                // changes the user actually made.
                guard overrideLoaded else { return }
                svc.setOverride(o, for: code)
                sharingChanged = true
                let spots = (try? appState.spotRepository.fetchAll()) ?? []
                Task { await svc.applyPrivacy(for: code, spots: spots) }
            }
            .onDisappear {
                svc.setNickname(privacy.nickname, for: code)
                if sharingChanged {
                    sharingChanged = false
                    ToastCenter.shared.show("Sharing updated", style: .success, haptic: false)
                }
            }
        }
        .dsSheet([.medium, .large])
    }

    private var nicknameRow: some View {
        CardRow("Nickname", systemImage: "person.text.rectangle.fill", tint: DS.accent,
                combinesChildren: false) {
            TextField("Only you see it", text: $privacy.nickname)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.dsText)
                .submitLabel(.done)
                .onSubmit { svc.setNickname(privacy.nickname, for: code) }
                .accessibilityLabel("Nickname")
        }
    }

    private var shareSection: some View {
        CardSection("What you share", note: "Default follows your privacy settings.") {
            overrideRow("Catches", systemImage: "fish.fill", tint: CrewTint.fish,
                        globalOn: svc.shareCatchesWithFriends, value: $override.shareCatches)
            overrideRow("Spots", systemImage: "mappin.and.ellipse", tint: CrewTint.spot,
                        globalOn: svc.shareSpotsWithFriends, value: $override.shareSpots)
            overrideRow("Exact locations", systemImage: "scope", tint: CrewTint.exact,
                        globalOn: svc.shareSpotExactLocations, value: $override.shareExactLocations)
        }
        .padding(.top, DS.Space.s6)
    }

    /// What the friend gets, in one line for the hero.
    private var sharingSummary: String {
        guard isFriend else { return "Only you see the nickname." }
        let catches = override.shareCatches ?? svc.shareCatchesWithFriends
        let spots = override.shareSpots ?? svc.shareSpotsWithFriends
        switch (catches, spots) {
        case (true, true): return "Catches and spots shared"
        case (true, false): return "Catches shared, spots hidden"
        case (false, true): return "Spots shared, catches hidden"
        case (false, false): return "Nothing shared"
        }
    }

    /// A three-way per-friend override: Default (follow the global setting),
    /// Share or Hide, as a menu on the right of a coloured icon row.
    private func overrideRow(_ title: String, systemImage: String, tint: Color, globalOn: Bool,
                             value: Binding<Bool?>) -> some View {
        CardRow(title, subtitle: overrideSubtitle(value.wrappedValue, globalOn: globalOn),
                systemImage: systemImage, tint: tint, combinesChildren: false) {
            Picker(title, selection: Binding(
                get: { value.wrappedValue == nil ? 0 : (value.wrappedValue! ? 1 : 2) },
                set: { value.wrappedValue = $0 == 0 ? nil : ($0 == 1) }
            ).haptic()) {
                Text("Default").tag(0)
                Text("Share").tag(1)
                Text("Hide").tag(2)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
    }

    private func overrideSubtitle(_ value: Bool?, globalOn: Bool) -> String {
        guard let value else { return globalOn ? "On by default" : "Off by default" }
        return value ? "Always shared with them" : "Hidden from them"
    }
}

/// A friend's achievements, computed from their public stats and published
/// catches, laid out like your own: the count, the earned medals rarest
/// first, and a button to every badge. Each medal opens the same explainer
/// your own badges use.
struct FriendBadgesCard: View {
    let badges: [BadgeDefinition]
    var topCount = 5
    @State private var selected: BadgeDefinition?
    @State private var showingAll = false

    /// Hidden badges only count once earned, so the tally has no spoiler.
    private var visible: [BadgeDefinition] { badges.filter { $0.earned || !$0.hidden } }
    private var earned: [BadgeDefinition] {
        visible.filter(\.earned).sorted { $0.rarity.rawValue > $1.rarity.rawValue }
    }
    private var locked: [BadgeDefinition] {
        visible.filter { !$0.earned }.sorted { $0.rarity.rawValue < $1.rarity.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s3) {
                ThumbView(systemImage: "trophy.fill", tint: CrewTint.trophy, size: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(earned.count) of \(visible.count)")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.dsText)
                    Text(earned.isEmpty ? "No badges yet" : "Badges earned")
                        .font(.footnote)
                        .foregroundStyle(.dsText2)
                }
            }
            .accessibilityElement(children: .combine)
            if !earned.isEmpty { medals }
            Button("Show all badges") { showingAll = true }
                .buttonStyle(.dsTonal)
        }
        .padding(DS.Space.s4)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .sheet(item: $selected) { badge in
            BadgeDetailView(badge: badge)
        }
        .sheet(isPresented: $showingAll) {
            FriendBadgesSheet(earned: earned, locked: locked)
        }
    }

    private var medals: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: DS.Space.s3)],
                  alignment: .leading, spacing: DS.Space.s3) {
            ForEach(earned.prefix(topCount)) { badge in
                Button { selected = badge } label: {
                    BadgeMedal(badge: badge, size: 46)
                }
                .buttonStyle(.dim)
                .accessibilityLabel(badge.accessibilityLabel)
            }
        }
    }
}

/// Every badge a friend's public data can earn: earned first, then locked,
/// on the same medal grid as your own achievements page.
private struct FriendBadgesSheet: View {
    let earned: [BadgeDefinition]
    let locked: [BadgeDefinition]
    @State private var selected: BadgeDefinition?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !earned.isEmpty {
                        SectionTitle("Earned", detail: "\(earned.count)")
                        BadgeMedalGrid(badges: earned) { selected = $0 }
                            .padding(.top, DS.Space.s2)
                    }
                    if !locked.isEmpty {
                        SectionTitle("Locked", detail: "\(locked.count)")
                            .padding(.top, earned.isEmpty ? 0 : DS.Space.s8)
                        BadgeMedalGrid(badges: locked) { selected = $0 }
                            .padding(.top, DS.Space.s2)
                    }
                }
                .padding(.top, DS.Space.s2)
                .padding(.bottom, DS.Space.s8)
                .pageWidth()
            }
            .detailTint(nil)
            .navigationTitle("Badges")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { SheetDoneButton() }
            }
        }
        .dsSheet([.medium, .large])
        .sheet(item: $selected) { badge in
            BadgeDetailView(badge: badge)
        }
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
    @State private var copied = false

    private var kind: String { (Spot.SpotType(rawValue: spot.type) ?? .general).label }

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
                                .background(Circle().fill(Color.dsBackground))
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

                PageHero(label: "Shared by \(friendName)", value: spot.name, callout: kind) {
                    ThumbView(systemImage: "mappin.and.ellipse", tint: CrewTint.spot, size: 72)
                }
                .accessibilityAddTraits(.isHeader)
                .padding(.top, DS.Space.s4)

                if spot.coordinate != nil {
                    Button {
                        copySpot()
                    } label: {
                        Label(copied ? "Saved to your spots" : "Save to your spots",
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

                CrewSection(title: "About this spot") { spotFacts }

                if !spot.notes.isEmpty {
                    CrewSection(title: "Notes") {
                        Text(spot.notes)
                            .font(.body)
                            .foregroundStyle(.dsText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.Space.s4)
                            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card,
                                                                           style: .continuous))
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
        .navigationTitle("Shared spot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { SheetDoneButton() } }
    }

    /// Who shared it and how precise the pin is, as
    /// coloured rows on one card.
    private var spotFacts: some View {
        CardGroup {
            CardRow("Shared by", systemImage: "person.fill", tint: CrewTint.people, value: friendName)
            if spot.isApproximate {
                CardRow("Approximate area", subtitle: "\(friendName) kept the exact pin private",
                        systemImage: "eye.slash.fill", tint: CrewTint.lock)
            } else {
                CardRow("Exact pin", subtitle: "Shared to the metre",
                        systemImage: "scope", tint: CrewTint.exact)
            }
        }
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
        // The name stays the friend's; an approximate pin says so in the
        // notes instead.
        let notes = spot.notes.isEmpty ? "Shared by \(friendName)" : spot.notes
        var newSpot = Spot(
            name: spot.name,
            latitude: coord.latitude,
            longitude: coord.longitude,
            notes: spot.isApproximate ? "Approximate area. \(notes)" : notes,
            spotType: Spot.SpotType(rawValue: spot.type) ?? .general
        )
        do {
            try appState.spotRepository.save(&newSpot)
            copied = true
            ToastCenter.shared.show("Spot saved to your spots", style: .success, icon: "bookmark.fill")
        } catch {
            ToastCenter.shared.show("Couldn't save the spot", style: .error)
        }
    }
}

// MARK: - Community catch detail

/// A single community catch, pushed from a friend's profile, a trip or a
/// leaderboard row: the read-only version of a catch page, built from the
/// same parts. Photo hero, title block, the stat grid, then the approximate
/// area and directions. Tinted with the species' art colour when the name
/// resolves to a known species.
struct CommunityCatchDetailView: View {
    let row: CommunityService.LeaderRow
    @Environment(AppState.self) private var appState
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }
    @State private var species: Species?
    @State private var photo: UIImage?
    @State private var photoLoaded = false
    @State private var showingFullscreen = false

    private var hasPhoto: Bool { row.localPhotoPath != nil || row.hasRemotePhoto }

    var body: some View {
        CrewCloudGate { page }
    }

    private var page: some View {
        ScrollView {
            content
                .padding(.bottom, DS.Space.s8)
                .pageWidth()
        }
        .detailTint(species?.artTint)
        .modifier(CatchHeroChrome(title: row.species, heroFactor: CatchHero.factor(hasPhoto: hasPhoto)))
        .fullScreenCover(isPresented: $showingFullscreen) {
            if let photo { FullscreenImageViewer(image: photo) }
        }
        .task {
            if let path = row.localPhotoPath {
                photo = PhotoManager.load(path)
            } else if row.hasRemotePhoto {
                photo = await CommunityService.shared.catchPhoto(recordName: row.id)
            }
            photoLoaded = true
            species = (try? appState.speciesRepository.fetchByCommonName(row.species)) ?? nil
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            CatchHero(photos: photo.map { [$0] } ?? [],
                      index: .constant(0),
                      species: species,
                      showsPhotos: hasPhoto,
                      isLoading: hasPhoto && !photoLoaded,
                      open: { showingFullscreen = true })
            DetailHeader(over: row.date.formatted(date: .long, time: .omitted),
                         title: row.species,
                         subtitle: "Caught by \(row.anglerName)")
                .padding(.top, DS.Space.s4)
            CatchFactsLine(facts: facts)
                .padding(.top, DS.Space.s3)
            if !stats.isEmpty {
                CatchStatGrid(stats: stats)
                    .padding(.top, DS.Space.s6)
            }
            whereSection
        }
    }

    private var facts: [CatchFact] {
        row.region.isEmpty ? [] : [CatchFact(systemImage: "mappin.and.ellipse", text: row.region)]
    }

    private var stats: [CatchStat] {
        var list: [CatchStat] = []
        if let w = row.weightKg {
            list.append(CatchStat("Weight", measured: Units.weight(kg: w, imperial: imperial)))
        }
        if let l = row.lengthCm {
            list.append(CatchStat("Length", measured: Units.length(cm: l, imperial: imperial)))
        }
        return list
    }

    @ViewBuilder private var whereSection: some View {
        if let coord = row.coordinate {
            SectionTitle("Where")
                .padding(.top, DS.Space.s8)
            CommunityCatchMap(coordinate: coord, tint: species?.artTint ?? DS.accent)
                .frame(height: CatchMapRender.height)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .accessibilityLabel("Map of the approximate area")
                .padding(.horizontal, DS.gutter)
            SectionFootnote("Approximate area. \(row.anglerName) shares a rough location, not the exact spot.")
            DirectionsButton(coordinate: coord, name: row.region.isEmpty ? row.species : row.region)
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s3)
        }
    }
}

// MARK: - Community map + photo thumbnail helpers

/// A non-interactive mini map centred on a (deliberately obfuscated) catch
/// location, with a soft radius circle to signal it's an approximate area.
private struct CommunityCatchMap: View {
    let coordinate: CLLocationCoordinate2D
    var tint: Color = DS.accent

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))) {
            MapCircle(center: coordinate, radius: 3500)
                .foregroundStyle(tint.opacity(0.18))
                .stroke(tint.opacity(0.7), lineWidth: 1.5)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
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
                ThumbView(systemImage: "fish.fill", tint: CrewTint.fish, size: size)
            }
        }
        .accessibilityHidden(true)
        .task(id: row.id) {
            let px = size * displayScale
            if let path = row.localPhotoPath {
                let scale = displayScale
                photo = await Task.detached { PhotoManager.thumbnail(path, maxPixel: px, scale: scale) }.value
            } else if row.hasRemotePhoto, CrewCloud.shared.isAvailable {
                // Same thumbnail size as a local photo, not the full image.
                photo = await CommunityService.shared.catchPhoto(recordName: row.id, maxPixel: px)
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
/// adding a stranger. A code nobody holds, your own code and a failed lookup
/// each get their own state, so an offline angler is never told the code
/// doesn't exist.
struct AddFriendConfirmView: View {
    let code: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var svc = CommunityService.shared
    @ObservedObject private var connection = CrewConnection.shared

    @State private var result: CommunityService.LookupResult<CommunityService.Profile> = .failed
    @State private var loading = true
    @State private var added = false
    @State private var sending = false
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }

    private var isFriend: Bool { svc.friends.contains(code.uppercased()) }
    private var shownCode: String { code.uppercased() }

    /// Nothing left to decide: Done. Joining, looking up or sending: Cancel.
    private var finished: Bool {
        guard svc.joined, !loading else { return false }
        if case .found = result { return isFriend || added }
        return true
    }

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
            .navigationTitle("Add a friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if finished {
                    ToolbarItem(placement: .confirmationAction) { SheetDoneButton() }
                }
                if !finished {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
        }
        .dsSheet([.large])
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
            } else {
                switch result {
                case .found(let p):
                    profileBody(p)
                case .notFound:
                    stateHero(value: "Angler not found",
                              callout: "Nobody uses that code yet. Ask them to set up their angler profile.",
                              systemImage: "person.slash.fill", tint: CrewTint.lock)
                case .ownCode:
                    stateHero(value: "That's your own angler code",
                              callout: "Share it with a friend so they can add you.",
                              systemImage: "person.crop.circle.fill", tint: DS.accent)
                case .failed:
                    VStack(alignment: .leading, spacing: DS.Space.s5) {
                        stateHero(value: "Can't reach Crew right now",
                                  callout: connection.isOffline
                                      ? "You're offline. Try again when you're back online."
                                      : "Check your connection and try again.",
                                  systemImage: "wifi.slash", tint: .blue)
                        Button("Try again") { Task { await lookUp() } }
                            .buttonStyle(.dsTonal)
                            .padding(.horizontal, DS.gutter)
                    }
                }
            }
        }
        .task { await lookUp() }
    }

    @ViewBuilder private func profileBody(_ p: CommunityService.Profile) -> some View {
        AnglerProfileHeader(
            avatar: p.avatar, name: p.name,
            handle: "Angler code \(p.id)",
            title: p.title.isEmpty ? nil : p.title,
            bio: p.bio,
            facts: AnglerProfileHeader.facts(homeWater: p.homeWater, region: p.region,
                                             favourite: p.favoriteSpecies, since: p.memberSince))
        AnglerStatsLine(AnglerStatsLine.items(
            catches: p.totalCatches, species: p.speciesCount,
            bestWeightKg: p.bestWeightKg, bestLengthCm: p.bestLengthCm, imperial: imperial))
            .padding(.top, DS.Space.s4)

        if isFriend {
            CardGroup {
                CardRow("You're friends", subtitle: "You already share catches",
                        systemImage: "checkmark", tint: .dsScoreGood)
            }
            .padding(.top, DS.Space.s5)
        } else if added {
            CardGroup {
                CardRow("Friend request sent", subtitle: "Waiting for them to accept",
                        systemImage: "paperplane.fill", tint: .blue)
            }
            .padding(.top, DS.Space.s5)
        } else {
            Button(action: send) {
                if sending { ProgressView() } else { Label("Send friend request", systemImage: "person.badge.plus") }
            }
            .buttonStyle(.dsPrimary)
            .disabled(sending)
            .accessibilityLabel("Send friend request")
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s5)
            SectionFootnote("They'll see your request on their Crew tab.")
        }
    }

    /// The hero for a code that can't be added, in Today's hero layout.
    private func stateHero(value: String, callout: String, systemImage: String, tint: Color) -> some View {
        PageHero(label: "Angler code \(shownCode)", value: value, callout: callout) {
            ThumbView(systemImage: systemImage, tint: tint, size: 72)
        }
        .accessibilityAddTraits(.isHeader)
        .padding(.top, DS.Space.s6)
    }

    private func lookUp() async {
        guard svc.joined else { loading = false; return }
        loading = true
        result = await svc.lookupProfile(code: code)
        loading = false
    }

    private func send() {
        sending = true
        Task {
            let outcome = await svc.sendFriendRequestResult(to: code)
            sending = false
            switch outcome {
            case .found:
                added = true
                ToastCenter.shared.show("Friend request sent", style: .success)
            case .notFound:
                result = .notFound
                ToastCenter.shared.show("No angler matches that code", style: .error)
            case .ownCode:
                result = .ownCode
            case .failed:
                ToastCenter.shared.show(connection.isOffline ? "You're offline. Send it when you're back online"
                                                             : "Can't reach Crew right now. Try again",
                                        style: .error)
            }
        }
    }
}
