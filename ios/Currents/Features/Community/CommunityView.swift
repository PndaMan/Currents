import SwiftUI
import PhotosUI
import MapKit

/// Community hub: your angler profile, a friends-only leaderboard, and a friend
/// system with in-depth profiles and per-friend spot privacy.
struct CommunityView: View {
    @Environment(AppState.self) private var appState
    @StateObject private var svc = CommunityService.shared

    enum CommunityTab: String, CaseIterable, Identifiable {
        case feed, crews, friends
        var id: String { rawValue }
        var title: String {
            switch self {
            case .feed:    "Feed"
            case .crews:   "Crews"
            case .friends: "Friends"
            }
        }
        var icon: String {
            switch self {
            case .feed:    "square.stack.fill"
            case .crews:   "person.3.fill"
            case .friends: "trophy.fill"
            }
        }
        /// Where this inner tab sits in the smart-swipe continuum.
        var swipePage: SwipePage {
            switch self {
            case .feed:    .communityFeed
            case .crews:   .communityCrews
            case .friends: .communityFriends
            }
        }
    }

    @AppStorage("communityTab") private var tab: CommunityTab = .feed
    @State private var name = ""
    @State private var showingSettings = false
    @State private var showingProfile = false
    @State private var pushedCrew: CrewRoute?
    @State private var showingInbox = false
    @State private var pendingRequests: [CommunityService.FriendRequest] = []
    @State private var pendingInvites: [CommunityService.TripInvite] = []
    /// Cached angler stats so a full catch-table scan doesn't run on every
    /// SwiftUI body re-render — refreshed on appear and when catches change.
    @State private var cachedStats: CommunityService.MyStats?
    /// Local catches, used to compute achievements shown on the profile.
    @State private var myCatches: [CatchDetail] = []
    /// The merged cross-crew feed shown on the Feed tab.
    @State private var mergedFeed: [CommunityService.CrewPost] = []
    @State private var feedLoading = false
    /// Per-crew "older pages exist" flags + the in-flight guard for the
    /// feed's infinite scroll.
    @State private var feedHasMore: [String: Bool] = [:]
    @State private var feedLoadingMore = false

    private var region: String { svc.myRegion }
    private var notificationCount: Int { pendingRequests.count + pendingInvites.count }

    var body: some View {
        Group {
            if svc.joined { joinedBody } else { joinBody }
        }
        // Rightmost stretch of the swipe continuum: Seasons ← Feed·Crews·Friends.
        // Before joining there are no inner tabs, so the whole screen sits at
        // the Feed position (left edge swipes back to Fish).
        .smartSwipe(svc.joined ? tab.swipePage : .communityFeed)
        .onChange(of: appState.swipePage) { _, page in applySwipe(page) }
        .onAppear { applySwipe(appState.swipePage) }
        .navigationTitle("Community")
        .toolbar {
            if svc.joined {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingProfile = true } label: {
                        AnglerAvatar(image: svc.myAvatar, size: 32)
                    }
                    .accessibilityLabel("My profile")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingInbox, onDismiss: { Task { await loadNotifications() } }) {
            NotificationInboxView()
        }
        .navigationDestination(isPresented: $showingProfile) {
            MyProfileView(stats: stats, catches: myCatches)
        }
        .task(id: svc.joined) {
            refreshStats()
            // Visible content FIRST — the feed used to wait behind the whole
            // catch-upload/grant-healing pass before it even started loading.
            await loadMergedFeed()
            await loadNotifications()
            // Maintenance in the background: publish history, heal grants and
            // spot shares, and rebuild membership from the server once per
            // launch (a reinstall used to show zero crews/trips while the
            // server still counted — and pushed to — this angler).
            Task {
                await syncCatches()
                await svc.reconcileMemberships()
            }
            // Light poll while Community is open — fills the gaps CloudKit
            // subscriptions can't cover (there's no pull-to-refresh anymore).
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                guard !Task.isCancelled, svc.joined else { continue }
                await loadMergedFeed()
                await loadNotifications()
            }
        }
        .onChange(of: svc.revision) { _, _ in refreshStats() }
        // A crew push tap lands directly in that crew.
        .navigationDestination(item: $pushedCrew) { route in
            CrewDetailView(code: route.id)
        }
        .onChange(of: appState.openCrewCode) { _, code in
            if let code { pushedCrew = CrewRoute(id: code); appState.openCrewCode = nil }
        }
        .onAppear {
            if let code = appState.openCrewCode {
                pushedCrew = CrewRoute(id: code); appState.openCrewCode = nil
            }
        }
    }

    private struct CrewRoute: Identifiable, Hashable { let id: String }

    /// A cross-tab swipe landed on Community: pick the inner tab the swipe
    /// asked for (Feed when arriving from Fish, Friends never — it's interior).
    private func applySwipe(_ page: SwipePage?) {
        switch page {
        case .communityFeed:    tab = .feed
        case .communityCrews:   tab = .crews
        case .communityFriends: tab = .friends
        default: return
        }
        appState.swipePage = nil
    }

    private func refreshStats() {
        myCatches = (try? appState.catchRepository.fetchAll(limit: 100000)) ?? []
        cachedStats = computeStatsFrom(myCatches)
    }
    private var stats: CommunityService.MyStats { cachedStats ?? computeStats() }

    private func loadNotifications() async {
        guard svc.joined else { return }
        pendingRequests = await svc.refreshFriendRequests()
        pendingInvites = await svc.refreshTripInvites()
    }

    private var inboxSummary: String {
        var parts: [String] = []
        if !pendingRequests.isEmpty { parts.append("\(pendingRequests.count) friend \(pendingRequests.count == 1 ? "request" : "requests")") }
        if !pendingInvites.isEmpty { parts.append("\(pendingInvites.count) trip \(pendingInvites.count == 1 ? "invite" : "invites")") }
        return parts.joined(separator: " · ")
    }

    /// Publish the full local catch history so the leaderboards reflect
    /// everything, not just catches logged after joining. Throttled service-side.
    private func syncCatches() async {
        guard svc.joined else { return }
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
        // And spot shares: creating/editing/deleting a spot doesn't republish
        // on its own, so heal the shared set on every Community visit.
        let spots = (try? appState.spotRepository.fetchAll()) ?? []
        await svc.republishSharedSpots(spots: spots)
    }

    // MARK: Join gate

    private var joinBody: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 44)).foregroundStyle(CurrentsTheme.accent)
                    Text("Fish with friends").font(.title3.bold())
                    Text("A friends leaderboard, in-depth angler profiles, and spots you can share privately — one friend at a time. Powered by iCloud; no account or password needed.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            Section("Your angler name") { TextField("Name", text: $name) }
            Section {
                Button {
                    Task {
                        await svc.join(name: name, region: region)
                        await svc.updateProfile(name: svc.myName, bio: svc.myBio, homeWater: svc.myHomeWater, region: region, avatar: nil, stats: stats)
                        ToastCenter.shared.show("Welcome to the Community", style: .success)
                    }
                } label: {
                    Label("Join the Community", systemImage: "person.3.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
                // Without this you silently became "Angler XXXXXX".
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text("The Community is optional. Until you join, everything stays on your device. When you join, your best catches (species, size, broad region), your angler profile, and spots you explicitly share sync through Apple's CloudKit so friends can see them. Coordinates are never shared unless you turn on location sharing — and even then they're offset by your honey-hole radius.")
            }
        }
    }

    // MARK: Joined

    private var joinedBody: some View {
        List {
            // Pills are the first element inside the list so they scroll with
            // the content (the FishTab pattern) instead of colliding with the
            // large title.
            Section {
                SegmentedPills(options: CommunityTab.allCases, selection: $tab,
                               title: { $0.title }, icon: { $0.icon })
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)

            switch tab {
            case .feed:
                feedSections
            case .crews:
                CrewsSection()
                // Live/group trips stay reachable from the Crews tab.
                GroupTripsSection()
            case .friends:
                LeaderboardSection()
                FriendsSection()
            }
        }
        .task(id: tab) {
            if tab == .feed { await loadMergedFeed() }
        }
        // No pull-to-refresh anywhere in Community — changes arrive on their
        // own: pushes bump the revision (below) and a light poll fills the
        // gaps CloudKit subscriptions can't cover.
        .onChange(of: svc.revision) { _, _ in
            Task {
                refreshStats()
                await loadMergedFeed()
                await loadNotifications()
            }
        }
        .sensoryFeedback(.selection, trigger: tab)
    }

    // MARK: Feed tab

    @ViewBuilder private var feedSections: some View {
        if notificationCount > 0 {
            Section {
                Button { showingInbox = true } label: {
                    HStack(spacing: 12) {
                        NotificationBell(count: notificationCount)
                        Text(inboxSummary).font(.subheadline.bold())
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }

        Section {
            if mergedFeed.isEmpty && feedLoading {
                FishLoader(message: "Reeling in the feed…")
                    .frame(height: 90).frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if mergedFeed.isEmpty {
                VStack(spacing: 10) {
                    ContentUnavailableView(
                        svc.myCrews.isEmpty ? "No crew yet" : "Nothing in the feed yet",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text(svc.myCrews.isEmpty
                            ? "Join or start a crew and everyone's catches land in one feed."
                            : "When you or a crewmate log a catch, it shows up here."))
                    Button {
                        withAnimation(.snappy) { tab = .crews }
                    } label: {
                        Label("Find your crew", systemImage: "person.3.fill")
                    }
                    .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else {
                // Each post is its own card. Rows are lazy — the List only
                // builds what's on screen, so a long feed stays smooth.
                ForEach(mergedFeed) { post in
                    VStack(alignment: .leading, spacing: 8) {
                        crewTag(for: post)
                        CrewPostCard(post: post, crewCode: post.crewCode,
                                     crew: svc.crew(withCode: post.crewCode)) {
                            await loadMergedFeed()
                        }
                    }
                    .padding(12)
                    .background(.ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.secondary.opacity(0.10), lineWidth: 1))
                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .onAppear {
                        // Infinite scroll: nearing the bottom pulls the next
                        // 30-post page from every crew that still has more.
                        if post.id == mergedFeed.suffix(5).first?.id {
                            Task { await loadMoreFeed() }
                        }
                    }
                }
                if feedLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if !feedHasMore.values.contains(true), mergedFeed.count > 20 {
                    Text("You're all caught up 🎣")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
    }

    /// Tiny chip naming the crew a post came from — tap to open the crew.
    private func crewTag(for post: CommunityService.CrewPost) -> some View {
        let crew = svc.crew(withCode: post.crewCode)
        return Button {
            pushedCrew = CrewRoute(id: post.crewCode)
        } label: {
            HStack(spacing: 4) {
                Text(crew?.emoji ?? "🎣").font(.caption)
                Text(crew?.name ?? post.crewCode).font(.caption2.bold())
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(CurrentsTheme.accent.opacity(0.12), in: Capsule())
            .foregroundStyle(CurrentsTheme.accent)
        }
        .buttonStyle(.plain)
    }

    /// One page from every crew, fetched concurrently and merged newest-first.
    private func loadMergedFeed() async {
        guard svc.joined else { return }
        let crews = svc.myCrews
        guard !crews.isEmpty else { mergedFeed = []; return }
        // Instant: last-seen pages from disk, so the feed is on screen before
        // the network round trips come back.
        if mergedFeed.isEmpty {
            let cached = crews.flatMap { CommunityDiskCache.loadFeed($0.code) }
            if !cached.isEmpty { mergedFeed = cached.sorted { $0.caughtAt > $1.caughtAt } }
        }
        // Screenshot mode: the seeded disk feed IS the feed — a network
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
    /// merge, and keep going until each crew's history runs dry — so a crew
    /// with 1,000 posts is reachable, but only ever 30-at-a-time per crew.
    private func loadMoreFeed() async {
        guard !feedLoadingMore, feedHasMore.values.contains(true) else { return }
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

/// Your own profile page: avatar, bio, stats and achievements — plus the
/// leave-community escape hatch, moved out of the main Community flow.
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
        List {
            Section {
                VStack(spacing: 8) {
                    AnglerAvatar(image: svc.myAvatar, size: 96)
                        .zoomableOnTap(svc.myAvatar)
                    Text(svc.myName).font(.title2.bold())
                    if !svc.myBio.isEmpty {
                        Text(svc.myBio).font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if !svc.myRegion.isEmpty {
                        Label(svc.myRegion, systemImage: "globe")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button { showingEdit = true } label: {
                        Label("Edit Profile", systemImage: "square.and.pencil")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .listRowBackground(Color.clear)

            Section {
                HStack(spacing: 10) {
                    statTile("\(stats.totalCatches)", "Catches", "fish.fill")
                    statTile("\(stats.speciesCount)", "Species", "square.grid.2x2")
                    if stats.bestWeightKg > 0 {
                        statTile(Units.weight(kg: stats.bestWeightKg, imperial: imperial), "Heaviest", "scalemass")
                    }
                    if stats.bestLengthCm > 0 {
                        statTile(Units.length(cm: stats.bestLengthCm, imperial: imperial), "Longest", "ruler")
                    }
                }
                if !stats.favoriteSpecies.isEmpty {
                    Label("Favourite: \(stats.favoriteSpecies)", systemImage: "star.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.clear)

            Section {
                AchievementsCard(catches: catches)
            }

            Section {
                Button("Leave Community", role: .destructive) { confirmLeave = true }
                    .confirmationDialog("Leave the Community?", isPresented: $confirmLeave,
                                        titleVisibility: .visible) {
                        Button("Leave", role: .destructive) {
                            Haptics.warning()
                            svc.leave()
                            ToastCenter.shared.show("Left the Community", style: .info, haptic: false)
                            dismiss()
                        }
                    } message: {
                        Text("Notifications stop and nothing new is shared. What you've already published stays visible to friends until you delete those catches; rejoining picks everything back up.")
                    }
            }
        }
        .navigationTitle("My Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEdit) { ProfileEditView(stats: stats) }
    }

    private func statTile(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.caption).foregroundStyle(CurrentsTheme.accent)
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(CurrentsTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct AnglerAvatar: View {
    let image: UIImage?
    var size: CGFloat = 56
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(CurrentsTheme.accent.opacity(0.2))
                    Image(systemName: "figure.fishing").foregroundStyle(CurrentsTheme.accent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(CurrentsTheme.accent.opacity(0.4), lineWidth: 1.5))
    }
}

// MARK: - Reusable: code field + accept/decline

/// A clean, centred, monospaced input for 6-character friend / trip codes —
/// auto-uppercases and caps at 6 characters.
struct CodeField: View {
    @Binding var text: String
    var placeholder = "CODE"
    var body: some View {
        TextField(placeholder, text: $text)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .font(.system(.title3, design: .monospaced).weight(.bold))
            .tracking(6)
            .multilineTextAlignment(.center)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CurrentsTheme.accent.opacity(0.35), lineWidth: 1))
            .onChange(of: text) { _, v in
                let up = String(v.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.prefix(6))
                if up != text { text = up }
            }
    }
}

/// A friend / trip code shown as monospaced accent text. Tap or long-press to
/// copy it to the clipboard, with a brief "Copied" confirmation.
struct CopyableCode: View {
    let code: String
    var font: Font = .body.monospaced().bold()
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = code
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { copied = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation { copied = false }
            }
        } label: {
            Text(copied ? "Copied!" : code).font(font)
                .foregroundStyle(copied ? .green : CurrentsTheme.accent)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                UIPasteboard.general.string = code
            } label: { Label("Copy code", systemImage: "doc.on.doc") }
        }
        .accessibilityLabel("Copy code \(code)")
    }
}

/// Green "Accept" + red "Decline" — high contrast in any theme (the accent
/// colour can be orange/low-contrast, so these use semantic colours).
struct AcceptDeclineButtons: View {
    var acceptTitle = "Accept"
    var declineTitle = "Decline"
    var acceptIcon = "checkmark"
    let onAccept: () -> Void
    let onDecline: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Button(action: onAccept) {
                Label(acceptTitle, systemImage: acceptIcon).font(.subheadline.bold())
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(Color.green, in: Capsule()).foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Button(action: onDecline) {
                Label(declineTitle, systemImage: "xmark").font(.subheadline.bold())
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(Color.red.opacity(0.16), in: Capsule()).foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Leaderboard

private struct LeaderboardSection: View {
    @Environment(AppState.self) private var appState
    @StateObject private var svc = CommunityService.shared
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }

    @State private var metric: CommunityService.Metric = .count
    @State private var rows: [CommunityService.LeaderRow] = []
    @State private var myStanding: (rank: Int, row: CommunityService.LeaderRow)?
    /// friendCode → may I open their individual catches (their grant to me).
    @State private var catchAccess: [String: Bool] = [:]
    @State private var loading = false

    var body: some View {
        Section {
            Picker("By", selection: $metric) {
                Text("Most Fish").tag(CommunityService.Metric.count)
                Text("Heaviest").tag(CommunityService.Metric.weight)
                Text("Longest").tag(CommunityService.Metric.length)
            }.pickerStyle(.segmented)

            if loading && rows.isEmpty {
                FishLoader(message: "Reeling in the leaderboard…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
            } else if rows.isEmpty {
                VStack(spacing: 10) {
                    ContentUnavailableView("No entries yet", systemImage: "trophy",
                        description: Text("Add friends and log catches to fill the board."))
                    // The demo angler existed in the service all along ("so
                    // there's always something to see") but no UI mentioned it.
                    Button {
                        Task {
                            _ = await svc.sendFriendRequest(to: CommunityService.demoCode)
                            svc.bumpRevision()
                            await reload()
                        }
                    } label: {
                        Label("Add Marlin, the demo angler", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    leaderRow(i, row)
                }
                // Always show where you stand, even outside the visible top.
                if let mine = myStanding,
                   !rows.contains(where: { $0.friendCode == svc.friendCode }) {
                    Divider()
                    rowBody(mine.rank - 1, mine.row)
                }
            }
        } header: {
            Text("Leaderboard")
        } footer: {
            Text("Among you and your friends only.")
        }
        .task { await reload() }
        .onChange(of: metric) { _, _ in Task { await reload() } }
        // Reload when friends/catches change (accepting a request, removing a
        // friend, logging a catch) — the board otherwise froze at first render.
        .onChange(of: svc.revision) { _, _ in Task { await reload() } }
        .sensoryFeedback(.selection, trigger: metric)
    }

    /// Rows are only tappable for friends (and yourself) — individual catches
    /// and profiles are friends-only; global just shows the ranking.
    @ViewBuilder private func leaderRow(_ i: Int, _ row: CommunityService.LeaderRow) -> some View {
        let isSelf = row.friendCode == svc.friendCode
        let isFriend = svc.isFriend(row.friendCode)
        if metric == .count, isFriend {
            NavigationLink { FriendProfileView(code: row.friendCode) } label: { rowBody(i, row) }
        } else if metric != .count, isSelf || (isFriend && (catchAccess[row.friendCode] ?? false)) {
            NavigationLink { CommunityCatchDetailView(row: row) } label: { rowBody(i, row) }
        } else {
            rowBody(i, row)
        }
    }

    private func rowBody(_ i: Int, _ row: CommunityService.LeaderRow) -> some View {
        let isSelf = row.friendCode == svc.friendCode
        return HStack(spacing: 10) {
            Text("\(i + 1)").font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(i < 3 ? .white : .secondary)
                .frame(width: 26, height: 26)
                .background(i < 3 ? CurrentsTheme.accent : Color.secondary.opacity(0.15), in: Circle())
            if metric != .count {
                CommunityCatchThumb(row: row, size: 38)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.anglerName).font(.subheadline.bold())
                    if isSelf {
                        Text("YOU").font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(CurrentsTheme.accent, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                Text(subtitle(row)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value(row)).font(.subheadline.bold()).foregroundStyle(CurrentsTheme.accent)
        }
        .listRowBackground(isSelf ? CurrentsTheme.accent.opacity(0.10) : nil)
    }

    private func subtitle(_ row: CommunityService.LeaderRow) -> String {
        if metric == .count { return row.region.isEmpty ? "angler" : row.region }
        return row.region.isEmpty ? row.species : "\(row.species) · \(row.region)"
    }

    private func value(_ row: CommunityService.LeaderRow) -> String {
        switch metric {
        case .count: return "\(row.catchCount ?? 0) fish"
        case .weight: return row.weightKg.map { Units.weight(kg: $0, imperial: imperial) } ?? "—"
        case .length: return row.lengthCm.map { Units.length(cm: $0, imperial: imperial) } ?? "—"
        }
    }

    /// My own catches, straight from the local database, so I always appear on
    /// the board (and see my full history) regardless of CloudKit sync state.
    private func myLocalRows() -> [CommunityService.LeaderRow] {
        let local = (try? appState.catchRepository.fetchAll(limit: 100000)) ?? []
        return local.map {
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
                localPhotoPath: $0.catchRecord.photoPath
            )
        }
    }

    private func reload() async {
        // Only show the loader when there's nothing on screen yet — refreshes
        // swap data in place instead of blanking the board.
        if rows.isEmpty { loading = true }
        let result = await svc.board(metric: metric, myRows: myLocalRows())
        rows = result.rows
        myStanding = result.mine
        // Per-friend catch access, so a friend who set "hide my catch history"
        // isn't still browsable through the Heaviest/Longest rows. One batched
        // round trip for every code (this used to be N sequential fetches).
        let codes = Set(result.rows.map(\.friendCode)).filter { $0 != svc.friendCode }
        catchAccess = await svc.catchAccess(for: Array(codes))
        loading = false
    }
}

// MARK: - Friends

private struct FriendsSection: View {
    @StateObject private var svc = CommunityService.shared
    @State private var friends: [CommunityService.Profile] = []
    @State private var addCode = ""
    @State private var requestSent = false
    // Starts true so the very first frame (before .task runs) shows the loader
    // rather than briefly flashing the "couldn't load" state.
    @State private var isLoading = true

    var body: some View {
        Section("Friends") {
            HStack {
                Text("Your code")
                Spacer()
                CopyableCode(code: svc.friendCode)
                ShareLink(item: svc.friendInviteMessage()) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            VStack(spacing: 10) {
                CodeField(text: $addCode, placeholder: "FRIEND CODE")
                    .onChange(of: addCode) { _, _ in requestSent = false }
                Button {
                    let code = addCode
                    addCode = ""
                    Task {
                        let ok = await svc.sendFriendRequest(to: code)
                        requestSent = ok
                        ToastCenter.shared.show(ok ? "Friend request sent" : "Couldn't find that code",
                                                style: ok ? .success : .error)
                        await reload()
                    }
                } label: {
                    Label("Send Request", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
                .disabled(addCode.trimmingCharacters(in: .whitespaces).count != 6)
            }
            .padding(.vertical, 4)
            if requestSent {
                Label("Friend request sent — they'll get it in Community.", systemImage: "paperplane.fill")
                    .font(.caption).foregroundStyle(.green)
            }
            if svc.friends.isEmpty {
                // You genuinely have no friends yet.
                ContentUnavailableView("No friends yet", systemImage: "person.2",
                    description: Text("Send a friend request by code to compare catches and share spots privately."))
                    .listRowBackground(Color.clear)
            } else if isLoading && friends.isEmpty {
                // You have friend codes but their profiles are still loading —
                // don't flash "No friends yet" while iCloud fetches them.
                FishLoader(message: "Loading friends…")
                    .frame(height: 88)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if friends.isEmpty {
                // Codes exist but nothing came back (offline / fetch failed).
                ContentUnavailableView("Couldn't load friends", systemImage: "wifi.slash",
                    description: Text("Check your connection and pull down to refresh."))
                    .listRowBackground(Color.clear)
            }
            ForEach(friends) { f in
                NavigationLink { FriendProfileView(code: f.id) } label: {
                    HStack(spacing: 12) {
                        AnglerAvatar(image: f.avatar, size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(privacyNickname(f)).font(.subheadline.bold())
                            Text("\(f.speciesCount) species · \(f.totalCatches) catches").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button("Remove", role: .destructive) {
                        Haptics.warning()
                        svc.removeFriend(f.id)
                        ToastCenter.shared.show("Friend removed", style: .info, haptic: false)
                        Task { await reload() }
                    }
                }
            }
        }
        .task { await reload() }
        .onChange(of: svc.revision) { _, _ in Task { await reload() } }
    }

    private func privacyNickname(_ f: CommunityService.Profile) -> String {
        let nick = svc.privacy(for: f.id).nickname
        return nick.isEmpty ? f.name : "\(nick) (\(f.name))"
    }

    private func reload() async {
        let codes = svc.friends
        guard !codes.isEmpty else {
            friends = []
            isLoading = false
            return
        }
        let order = Dictionary(codes.enumerated().map { ($0.element, $0.offset) },
                               uniquingKeysWith: { first, _ in first })
        func ordered(_ list: [CommunityService.Profile]) -> [CommunityService.Profile] {
            list.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        }

        // 1) Instant: show last-known cached profiles right away — no spinner on
        //    any launch after the first.
        let cached = svc.cachedProfiles(for: codes)
        if !cached.isEmpty {
            friends = ordered(cached)
            isLoading = false
        } else {
            isLoading = true
        }

        // 2) Background: refresh from iCloud — batched, concurrent, and TTL'd
        //    (fresh disk copies skip the network entirely) so opening Friends
        //    doesn't re-download every avatar every time.
        let fetched = await svc.profiles(for: codes, maxAge: 900)
        var result: [CommunityService.Profile] = []
        var resolved = 0
        for code in codes {
            if let p = fetched[code] {
                result.append(p)
                resolved += 1
            } else {
                // Keep a placeholder row: a friend whose profile can't be
                // fetched used to vanish from the list entirely — while still
                // counting against grants — with no way left to remove them.
                result.append(.init(id: code, name: "Angler \(code)", bio: "",
                                    region: "", homeWater: "", avatar: nil,
                                    memberSince: .now, totalCatches: 0,
                                    speciesCount: 0, bestWeightKg: 0,
                                    bestLengthCm: 0, favoriteSpecies: ""))
            }
        }
        // Fully offline (nothing resolved) with cached names on screen: keep
        // the cache rather than replacing every row with placeholders.
        if resolved > 0 || cached.isEmpty {
            friends = ordered(result)
        }
        isLoading = false
    }
}


// MARK: - Notification bell + inbox

/// A themed bell with an unread badge. The bell is centred in a fixed frame and
/// the badge sits in the top-trailing corner *inside* that frame, so nothing
/// extends beyond the bounds and the toolbar's glass button never clips it.
struct NotificationBell: View {
    let count: Int
    var body: some View {
        ZStack {
            Image(systemName: "bell.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(count > 0 ? CurrentsTheme.accent : .secondary)
        }
        .frame(width: 30, height: 30)
        .overlay(alignment: .topTrailing) {
            if count > 0 {
                Text("\(min(count, 9))\(count > 9 ? "+" : "")")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(minWidth: 15)
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(Color.red, in: Capsule())
                    .fixedSize()
            }
        }
    }
}

/// The notification inbox: pending friend requests and group-trip invites, each
/// with accept / decline actions. Loads its own data once (single source of
/// truth), so the count and the list never disagree and the empty state only
/// appears after loading — not as a flash before the data arrives.
struct NotificationInboxView: View {
    @Environment(\.dismiss) private var dismiss
    private var svc: CommunityService { .shared }

    @State private var requests: [CommunityService.FriendRequest] = []
    @State private var invites: [CommunityService.TripInvite] = []
    @State private var profiles: [String: CommunityService.Profile] = [:]
    @State private var loaded = false
    @State private var openedTrip: String?

    var body: some View {
        NavigationStack {
            List {
                if !loaded {
                    Section {
                        FishLoader(message: "Checking for updates…")
                            .frame(height: 88)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                } else if requests.isEmpty && invites.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "You're all caught up",
                            systemImage: "bell.slash",
                            description: Text("Friend requests and trip invites will show up here."))
                    }
                } else {
                    if !requests.isEmpty {
                        Section("Friend Requests") {
                            ForEach(requests) { req in requestRow(req) }
                        }
                    }
                    if !invites.isEmpty {
                        Section("Trip Invites") {
                            ForEach(invites) { inv in inviteRow(inv) }
                        }
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await load() }
            .sheet(item: Binding(get: { openedTrip.map { IdString(id: $0) } },
                                 set: { openedTrip = $0?.id })) { g in
                NavigationStack {
                    GroupTripView(tripId: nil, tripName: "Group Trip", initialCode: g.id)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { openedTrip = nil } } }
                }
            }
        }
    }

    private struct IdString: Identifiable { let id: String }

    @ViewBuilder private func requestRow(_ req: CommunityService.FriendRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink { FriendProfileView(code: req.fromCode) } label: {
                HStack(spacing: 10) {
                    AnglerAvatar(image: profiles[req.fromCode]?.avatar, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(req.fromName).font(.subheadline.bold())
                        Text("wants to be friends").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            AcceptDeclineButtons(
                onAccept: { Task { await svc.acceptFriendRequest(req); ToastCenter.shared.show("You're now friends 🎣", style: .success); await load() } },
                onDecline: { Task { Haptics.warning(); await svc.declineFriendRequest(req); ToastCenter.shared.show("Request declined", style: .info, haptic: false); await load() } })
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func inviteRow(_ inv: CommunityService.TripInvite) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "person.3.fill").foregroundStyle(CurrentsTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(CurrentsTheme.accent.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(inv.tripName).font(.subheadline.bold())
                    Text("Invited by \(inv.fromName)").font(.caption).foregroundStyle(.secondary)
                }
            }
            AcceptDeclineButtons(
                acceptTitle: "Join Trip",
                onAccept: { Task { await svc.acceptInvite(inv); ToastCenter.shared.show("Joined the trip", style: .success); openedTrip = inv.groupCode; await load() } },
                onDecline: { Task { Haptics.warning(); await svc.declineInvite(inv); ToastCenter.shared.show("Invite declined", style: .info, haptic: false); await load() } })
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        let reqs = await svc.refreshFriendRequests()
        let invs = await svc.refreshTripInvites()
        for req in reqs where profiles[req.fromCode] == nil {
            profiles[req.fromCode] = await svc.fetchProfile(code: req.fromCode)
        }
        requests = reqs
        invites = invs
        loaded = true
    }
}

// MARK: - Profile editor

struct ProfileEditView: View {
    let stats: CommunityService.MyStats
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    private var svc: CommunityService { .shared }

    @State private var name = ""
    @State private var bio = ""
    @State private var homeWater = ""
    @State private var region = ""
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatar: UIImage?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            ZStack(alignment: .bottomTrailing) {
                                AnglerAvatar(image: avatar, size: 90)
                                Image(systemName: "camera.circle.fill").font(.title2)
                                    .foregroundStyle(CurrentsTheme.accent).background(Circle().fill(.background))
                            }
                        }
                        Spacer()
                    }
                }
                Section("About you") {
                    TextField("Angler name", text: $name)
                    TextField("Bio", text: $bio, axis: .vertical).lineLimit(2...4)
                    TextField("Home water (e.g. Theewaterskloof Dam)", text: $homeWater)
                    TextField("Region", text: $region)
                }
                Section("Your stats (auto)") {
                    LabeledContent("Catches", value: "\(stats.totalCatches)")
                    LabeledContent("Species", value: "\(stats.speciesCount)")
                    if !stats.favoriteSpecies.isEmpty {
                        LabeledContent("Favourite", value: stats.favoriteSpecies)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.bold().disabled(saving)
                }
            }
            .task {
                name = svc.myName; bio = svc.myBio; homeWater = svc.myHomeWater; region = svc.myRegion
                avatar = svc.myAvatar
            }
            .onChange(of: avatarItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) { avatar = UIImage(data: data) }
                }
            }
        }
    }

    private func save() {
        saving = true
        Task {
            await svc.updateProfile(name: name, bio: bio, homeWater: homeWater, region: region, avatar: avatar, stats: stats)
            // Refresh shared spots to reflect any privacy changes.
            let spots = (try? appState.spotRepository.fetchAll()) ?? []
            await svc.republishSharedSpots(spots: spots)
            ToastCenter.shared.show("Profile updated", style: .success)
            dismiss()
        }
    }
}

// MARK: - Friend profile + per-friend privacy

struct FriendProfileView: View {
    let code: String
    @Environment(AppState.self) private var appState
    private var svc: CommunityService { .shared }

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
    @State private var selectedSpot: CommunityService.SharedSpot?
    @State private var showingSettings = false
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }

    /// Viewing yourself (from a crew roster, facepile or leaderboard): it's
    /// your own account, so everything shows — no grant checks against you.
    private var isSelf: Bool { code == svc.friendCode }

    var body: some View {
        ScrollView {
            VStack(spacing: CurrentsTheme.paddingM) {
                heroCard
                if let p = profile {
                    statsRow(p)
                    FriendBadgesCard(badges: BadgeDefinition.computeFriend(
                        totalCatches: p.totalCatches, speciesCount: p.speciesCount,
                        bestWeightKg: p.bestWeightKg, bestLengthCm: p.bestLengthCm,
                        rows: catches))
                }
                catchesCard
                if !sharedSpots.isEmpty { spotsCard }
            }
            .padding()
        }
        .navigationTitle(isSelf ? "You" : (profile?.name ?? "Angler"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Nickname + per-friend sharing live behind one control instead of
            // stretching the profile out. Meaningless on your own page.
            if !isSelf {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Nickname & sharing")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: override)
        .sheet(isPresented: $showingSettings) { friendSettingsSheet }
        .sheet(item: $selectedSpot) { s in
            NavigationStack { SharedSpotDetailView(spot: s, friendName: profile?.name ?? "a friend") }
        }
        .task {
            if profile == nil { profile = svc.cachedProfiles(for: [code]).first }
            if isSelf {
                // Owner sees everything: catches straight from the local log,
                // profile from the published record (or built locally).
                catchAccess = true
                catches = ownLocalRows()
                if let fresh = await svc.fetchProfile(code: code) { profile = fresh }
                if profile == nil { profile = ownFallbackProfile() }
                catchesLoading = false
                return
            }
            privacy = svc.privacy(for: code)
            override = svc.override(for: code)
            overrideLoaded = true
            // Instant: last-seen profile, grant answer and catches from disk —
            // the page fills immediately and quietly swaps in fresh data.
            catchAccess = svc.cachedCatchAccess(code)
            if catchAccess, catches.isEmpty { catches = svc.cachedAnglerCatches(code: code) }
            // Refresh: everything in parallel, not one round trip after another.
            async let freshProfile = svc.fetchProfile(code: code)
            async let freshSpots = svc.sharedSpots(fromFriend: code)
            async let freshAccess = svc.hasCatchAccess(to: code)
            if let fresh = await freshProfile { profile = fresh }
            sharedSpots = await freshSpots
            catchAccess = await freshAccess
            if catchAccess { catches = await svc.anglerCatches(code: code) }
            catchesLoading = false
        }
    }

    /// Your catches, straight from the local log — newest first, photos and
    /// species art included.
    private func ownLocalRows() -> [CommunityService.LeaderRow] {
        let all = (try? appState.catchRepository.fetchAll()) ?? []
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
              favoriteSpecies: "")
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(CurrentsTheme.accent.opacity(0.35), lineWidth: 3)
                    .frame(width: 104, height: 104)
                AnglerAvatar(image: profile?.avatar, size: 92)
            }
            .zoomableOnTap(profile?.avatar)
            VStack(spacing: 3) {
                Text(profile?.name ?? "Angler").font(.title2.bold())
                if !privacy.nickname.isEmpty {
                    Text("“\(privacy.nickname)”")
                        .font(.subheadline).foregroundStyle(CurrentsTheme.accent)
                }
                if let p = profile, !p.bio.isEmpty {
                    Text(p.bio).font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            if let p = profile {
                HStack(spacing: 8) {
                    if !p.homeWater.isEmpty { heroChip(p.homeWater, icon: "water.waves") }
                    if !p.region.isEmpty { heroChip(p.region, icon: "globe.americas.fill") }
                }
                if !p.favoriteSpecies.isEmpty { favouriteRow(p.favoriteSpecies) }
                Text("Angler since \(p.memberSince.formatted(.dateTime.month().year()))")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                FishLoader(message: "Loading profile…").frame(height: 70)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private func heroChip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private func favouriteRow(_ name: String) -> some View {
        HStack(spacing: 8) {
            if let sp = SpeciesArtLookup.species(named: name, appState: appState) {
                SpeciesArtworkView(species: sp, caught: true, size: 30)
            } else {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Favourite species").font(.caption2).foregroundStyle(.secondary)
                Text(name).font(.caption.bold())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(CurrentsTheme.accent.opacity(0.10), in: Capsule())
    }

    private func statsRow(_ p: CommunityService.Profile) -> some View {
        HStack(spacing: 10) {
            statTile("\(p.totalCatches)", "Catches", "fish.fill")
            statTile("\(p.speciesCount)", "Species", "square.grid.2x2")
            if p.bestWeightKg > 0 {
                statTile(Units.weight(kg: p.bestWeightKg, imperial: imperial), "Heaviest", "scalemass")
            }
            if p.bestLengthCm > 0 {
                statTile(Units.length(cm: p.bestLengthCm, imperial: imperial), "Longest", "ruler")
            }
        }
    }

    // MARK: Catches

    private var catchesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Catches", systemImage: "fish.fill").font(.headline)
                Spacer()
                if catchAccess, !catches.isEmpty {
                    Text("\(catches.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !catchAccess {
                Label("This angler hasn't shared their catch history with you.",
                      systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
            } else if catches.isEmpty && catchesLoading {
                FishLoader(message: "Reeling in their catches…")
                    .frame(height: 84).frame(maxWidth: .infinity)
            } else if catches.isEmpty {
                Text("No catches shared yet.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(catches) { c in
                        NavigationLink { CommunityCatchDetailView(row: c) } label: {
                            catchRow(c)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if c.id != catches.last?.id { Divider() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var spotsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Spots they've shared with you", systemImage: "mappin.and.ellipse")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(sharedSpots) { s in
                    sharedSpotRow(s).padding(.vertical, 6)
                    if s.id != sharedSpots.last?.id { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: Nickname + sharing sheet

    private var friendSettingsSheet: some View {
        NavigationStack {
            Form {
                Section("Nickname") {
                    TextField("Nickname (optional)", text: $privacy.nickname)
                        .onSubmit { svc.setNickname(privacy.nickname, for: code) }
                }
                if svc.isFriend(code) {
                    Section {
                        overrideRow("See my catch history",
                                    globalOn: svc.shareCatchesWithFriends,
                                    value: $override.shareCatches)
                        overrideRow("Share my spots",
                                    globalOn: svc.shareSpotsWithFriends,
                                    value: $override.shareSpots)
                        overrideRow("Share my exact spot locations",
                                    globalOn: svc.shareSpotExactLocations,
                                    value: $override.shareExactLocations)
                    } header: {
                        Text("What you share with \(profile?.name ?? "this friend")")
                    } footer: {
                        Text("“Default” follows your global Privacy settings. Override any of these to share more (or less) with just this friend — e.g. share your exact spots with a trusted friend while everyone else sees an approximate area. Your honey-hole radius stays global.")
                    }
                }
            }
            .navigationTitle(profile?.name ?? "Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingSettings = false }
                }
            }
            .onChange(of: override) { _, o in
                // The initial .task assignment lands here too — only react
                // to changes the user actually made.
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

    /// A tri-state per-friend override: Default (follow global) / Share / Hide.
    private func overrideRow(_ title: String, globalOn: Bool, value: Binding<Bool?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline)
            Picker("", selection: Binding(
                get: { value.wrappedValue == nil ? 0 : (value.wrappedValue! ? 1 : 2) },
                set: { value.wrappedValue = $0 == 0 ? nil : ($0 == 1) }
            )) {
                Text("Default (\(globalOn ? "On" : "Off"))").tag(0)
                Text("Share").tag(1)
                Text("Hide").tag(2)
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 2)
    }

    private func statTile(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.caption).foregroundStyle(CurrentsTheme.accent)
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(CurrentsTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func catchRow(_ c: CommunityService.LeaderRow) -> some View {
        HStack(spacing: 12) {
            CommunityCatchThumb(row: c, size: 46)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.species).font(.subheadline.bold())
                HStack(spacing: 4) {
                    Text(c.date.formatted(date: .abbreviated, time: .omitted))
                    if c.coordinate != nil {
                        Image(systemName: "mappin.and.ellipse")
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(c.weightKg.map { Units.weight(kg: $0, imperial: imperial) }
                 ?? c.lengthCm.map { Units.length(cm: $0, imperial: imperial) } ?? "")
                .font(.caption.bold()).foregroundStyle(CurrentsTheme.accent)
        }
    }

    @ViewBuilder private func sharedSpotRow(_ s: CommunityService.SharedSpot) -> some View {
        Button { selectedSpot = s } label: {
            HStack {
                Image(systemName: s.isApproximate ? "mappin.circle" : "mappin.circle.fill")
                    .foregroundStyle(CurrentsTheme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.name).font(.subheadline.bold()).foregroundStyle(.primary)
                    Text(s.isApproximate ? "\(s.type) · approximate area" : s.type)
                        .font(.caption2).foregroundStyle(.secondary)
                    if !s.notes.isEmpty {
                        Text(s.notes).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

}

/// A friend's achievements, computed from their public stats + published
/// catches: earned medals up front, the locked remainder counted, every
/// bubble opening the same explainer modal your own badges use.
struct FriendBadgesCard: View {
    let badges: [BadgeDefinition]
    @State private var selected: BadgeDefinition?

    private var earned: [BadgeDefinition] {
        badges.filter(\.earned).sorted { $0.rarity.rawValue > $1.rarity.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Achievements", systemImage: "trophy.fill").font(.headline)
                Spacer()
                Text("\(earned.count)/\(badges.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if earned.isEmpty {
                Text("No badges yet — their trophy shelf is waiting.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(earned) { badge in
                            Button { selected = badge } label: { bubble(badge) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .sheet(item: $selected) { badge in
            BadgeDetailView(badge: badge)
                .presentationDetents([.medium]).presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.selection, trigger: selected?.id)
    }

    private func bubble(_ badge: BadgeDefinition) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(badge.rarity.color.opacity(0.18)).frame(width: 46, height: 46)
                Circle().stroke(badge.rarity.color.opacity(0.8), lineWidth: 2).frame(width: 46, height: 46)
                Image(systemName: badge.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(badge.rarity.color)
                    .symbolRenderingMode(.hierarchical)
            }
            Text(badge.title)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1).frame(width: 48)
        }
    }
}

// MARK: - Shared spot detail (map + copy)

/// A friend's shared spot on a map. When the owner only shared an approximate
/// area, the pin sits on an obfuscated point with a radius circle and a clear
/// "approximate" label — the exact honey hole is never revealed.
struct SharedSpotDetailView: View {
    let spot: CommunityService.SharedSpot
    let friendName: String
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        List {
            if let coord = spot.coordinate {
                Section {
                    ZStack(alignment: .bottomLeading) {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: spot.isApproximate ? 0.12 : 0.02,
                                                   longitudeDelta: spot.isApproximate ? 0.12 : 0.02)))) {
                            Annotation(spot.name, coordinate: coord) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title2).foregroundStyle(CurrentsTheme.accent)
                                    .background(Circle().fill(.white))
                            }
                            if spot.isApproximate {
                                MapCircle(center: coord, radius: 4500)
                                    .foregroundStyle(CurrentsTheme.accent.opacity(0.12))
                                    .stroke(CurrentsTheme.accent.opacity(0.5), lineWidth: 1)
                            }
                        }
                        .frame(height: 240)
                        if spot.isApproximate {
                            Label("Approximate area", systemImage: "location.circle")
                                .font(.caption2).padding(6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(10)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                LabeledContent("Name", value: spot.name)
                LabeledContent("Type", value: spot.type)
                if spot.isApproximate {
                    Label("Shared as an approximate area — \(friendName) kept the exact GPS private.",
                          systemImage: "eye.slash")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !spot.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes").font(.caption).foregroundStyle(.secondary)
                        Text(spot.notes).font(.subheadline)
                    }
                }
            }

            if let coord = spot.coordinate {
                Section {
                    DriveToButton(coordinate: coord, name: spot.name)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if spot.coordinate != nil {
                Section {
                    Button {
                        copySpot()
                    } label: {
                        Label(copied ? "Saved to My Spots" : "Save to My Spots",
                              systemImage: copied ? "checkmark.circle.fill" : "square.and.arrow.down")
                    }
                    .disabled(copied)
                } footer: {
                    if spot.isApproximate {
                        Text("Saves the approximate area — you can fine-tune the pin afterwards.")
                    }
                }
            }
        }
        .navigationTitle(spot.name)
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
            ToastCenter.shared.show("Already in My Spots", style: .info)
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
    }
}

// MARK: - Community catch detail

/// A single community catch, tappable from a friend's profile or a friends
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
        ScrollView {
            VStack(spacing: 16) {
                Group {
                    if let photo {
                        // Fit the whole photo (no crop) and tap to view fullscreen
                        // + zoom, like the My Catches detail page.
                        Image(uiImage: photo)
                            .resizable().scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                            .onTapGesture { showingFullscreen = true }
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption2.bold()).foregroundStyle(.white)
                                    .padding(6).background(.black.opacity(0.4), in: Circle())
                                    .padding(8)
                            }
                    } else if let species {
                        SpeciesArtworkView(species: species, caught: true, size: 150)
                            .frame(height: 160)
                    } else {
                        Image(systemName: "fish.fill")
                            .font(.system(size: 84)).foregroundStyle(CurrentsTheme.accent.opacity(0.5))
                            .frame(height: 160)
                    }
                }

                VStack(spacing: 3) {
                    Text(row.species).font(.title2.bold())
                    Text("Caught by \(row.anglerName)").font(.subheadline).foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    if let w = row.weightKg {
                        tile(Units.weight(kg: w, imperial: imperial), "Weight", "scalemass")
                    }
                    if let l = row.lengthCm {
                        tile(Units.length(cm: l, imperial: imperial), "Length", "ruler")
                    }
                    tile(row.date.formatted(date: .abbreviated, time: .omitted), "Date", "calendar")
                }

                if let coord = row.coordinate {
                    CommunityCatchMap(coordinate: coord)
                        .frame(height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(alignment: .bottomLeading) {
                            Label("Approximate area", systemImage: "location.circle")
                                .font(.caption2).padding(6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(8)
                        }
                    DriveToButton(coordinate: coord, name: row.species)
                }

                if !row.region.isEmpty {
                    Label(row.region, systemImage: "globe").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
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

    private func tile(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.caption).foregroundStyle(CurrentsTheme.accent)
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(CurrentsTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
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
                    .font(.title2).foregroundStyle(CurrentsTheme.accent)
                    .background(Circle().fill(.white))
            }
            MapCircle(center: coordinate, radius: 3500)
                .foregroundStyle(CurrentsTheme.accent.opacity(0.12))
                .stroke(CurrentsTheme.accent.opacity(0.5), lineWidth: 1)
        }
        .disabled(true)
    }
}

/// A square thumbnail for a community catch: the angler's photo if they shared
/// one, otherwise the species artwork. Loads remote photos lazily + cached.
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
                Image(uiImage: photo).resizable().scaledToFill()
            } else if let species {
                SpeciesArtworkView(species: species, caught: true, size: size * 0.8)
            } else {
                ZStack {
                    CurrentsTheme.accent.opacity(0.12)
                    Image(systemName: "fish.fill").foregroundStyle(CurrentsTheme.accent.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .task {
            if let path = row.localPhotoPath {
                let px = size * displayScale
                let scale = displayScale
                photo = await Task.detached { PhotoManager.thumbnail(path, maxPixel: px, scale: scale) }.value
            } else if row.hasRemotePhoto {
                photo = await CommunityService.shared.catchPhoto(recordName: row.id)
            }
            if photo == nil {
                species = (try? appState.speciesRepository.fetchByCommonName(row.species)) ?? nil
            }
        }
    }
}

// MARK: - Add-friend confirmation (from an invite link)

/// Shown when someone taps a `currents://friend/<CODE>` link — previews the
/// angler's profile and lets you confirm before adding, rather than silently
/// adding a stranger.
struct AddFriendConfirmView: View {
    let code: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var svc = CommunityService.shared

    @State private var profile: CommunityService.Profile?
    @State private var loading = true
    @State private var added = false
    @State private var joinName = ""
    @State private var joining = false
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }

    private var isFriend: Bool { svc.friends.contains(code.uppercased()) }

    var body: some View {
        Group {
            if svc.joined { confirmBody } else { joinGate }
        }
        .navigationTitle(svc.joined ? "Add Friend" : "Join Community")
        .navigationBarTitleDisplayMode(.inline)
    }

    // Prompt to set up a community profile BEFORE revealing the angler's profile.
    private var joinGate: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 44)).foregroundStyle(CurrentsTheme.accent)
                    Text("Join to add \(code)").font(.title3.bold())
                    Text("Someone shared their angler code with you. Set up your free Currents profile to send them a friend request — no account or password, just a name.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            Section("Your angler name") {
                TextField("Name", text: $joinName)
                    .textContentType(.givenName)
            }
            Section {
                Button {
                    joining = true
                    Task {
                        await svc.join(name: joinName, region: svc.myRegion)
                        Haptics.success()
                        joining = false
                        // svc.joined flips → confirmBody appears and its .task
                        // loads the shared angler's profile.
                    }
                } label: {
                    HStack {
                        if joining { ProgressView().tint(.white) }
                        Label("Join & Continue", systemImage: "arrow.right.circle.fill").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
                .disabled(joinName.trimmingCharacters(in: .whitespaces).isEmpty || joining)
            }
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }

    private var confirmBody: some View {
        List {
            if loading {
                Section { HStack { ProgressView(); Text("Looking up angler…").foregroundStyle(.secondary) } }
            } else if let p = profile {
                Section {
                    VStack(spacing: 8) {
                        AnglerAvatar(image: p.avatar, size: 88)
                        Text(p.name).font(.title3.bold())
                        if !p.bio.isEmpty {
                            Text(p.bio).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        if !p.homeWater.isEmpty {
                            Label(p.homeWater, systemImage: "water.waves").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Angler code \(p.id)").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                Section("Personal bests") {
                    LabeledContent("Catches", value: "\(p.totalCatches)")
                    LabeledContent("Species", value: "\(p.speciesCount)")
                    if p.bestWeightKg > 0 { LabeledContent("Heaviest", value: Units.weight(kg: p.bestWeightKg, imperial: imperial)) }
                    if p.bestLengthCm > 0 { LabeledContent("Longest", value: Units.length(cm: p.bestLengthCm, imperial: imperial)) }
                    if !p.favoriteSpecies.isEmpty { LabeledContent("Favourite", value: p.favoriteSpecies) }
                }
                Section {
                    if isFriend {
                        Label("You're friends", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if added {
                        Label("Friend request sent", systemImage: "paperplane.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            Task {
                                _ = await svc.sendFriendRequest(to: code)
                                added = true
                                ToastCenter.shared.show("Friend request sent", style: .success)
                            }
                        } label: {
                            Label("Send Friend Request", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
                    }
                } footer: {
                    Text("They'll get your request in Community and can accept it. Your spots stay private unless you choose to share them, per friend.")
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "Angler not found",
                        systemImage: "person.slash",
                        description: Text("Code \(code) doesn't match anyone yet — ask them to join Community first.")
                    )
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isFriend || added ? "Done" : "Close") { dismiss() }
            }
        }
        .task {
            guard svc.joined else { loading = false; return }
            profile = await svc.fetchProfile(code: code)
            loading = false
        }
    }
}
