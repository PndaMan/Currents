import SwiftUI
import PhotosUI
import MapKit

/// Community hub: your angler profile, a friends-only leaderboard, and a friend
/// system with in-depth profiles and per-friend spot privacy.
struct CommunityView: View {
    @Environment(AppState.self) private var appState
    @StateObject private var svc = CommunityService.shared

    @State private var name = ""
    @State private var showingEdit = false
    @State private var showingInbox = false
    @State private var pendingRequests: [CommunityService.FriendRequest] = []
    @State private var pendingInvites: [CommunityService.TripInvite] = []
    /// Cached angler stats so a full catch-table scan doesn't run on every
    /// SwiftUI body re-render — refreshed on appear and when catches change.
    @State private var cachedStats: CommunityService.MyStats?
    /// Local catches, used to compute achievements shown on the profile.
    @State private var myCatches: [CatchDetail] = []

    private var region: String { svc.myRegion }
    private var notificationCount: Int { pendingRequests.count + pendingInvites.count }

    var body: some View {
        Group {
            if svc.joined { joinedBody } else { joinBody }
        }
        .navigationTitle("Community")
        .toolbar {
            if svc.joined {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingInbox = true } label: {
                        NotificationBell(count: notificationCount)
                    }
                    .accessibilityLabel("Notifications")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            ProfileEditView(stats: stats)
        }
        .sheet(isPresented: $showingInbox, onDismiss: { Task { await loadNotifications() } }) {
            NotificationInboxView()
        }
        .task { refreshStats(); await syncCatches(); await loadNotifications() }
        .onChange(of: svc.revision) { _, _ in refreshStats() }
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
                }.buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
            } footer: {
                Text("The Community is optional. Until you join, everything stays on your device. When you join, your best catches (species, size, broad region), your angler profile, and spots you explicitly share sync through Apple's CloudKit so friends can see them. Coordinates are never shared unless you turn on location sharing — and even then they're offset by your honey-hole radius.")
            }
        }
    }

    // MARK: Joined

    private var joinedBody: some View {
        List {
            Section {
                Button { showingEdit = true } label: { MyProfileHeader(stats: stats) }
                    .buttonStyle(.plain)
            }
            Section {
                AchievementsCard(catches: myCatches)
            }
            LeaderboardSection()
            GroupTripsSection()
            FriendsSection()
            Section {
                Button("Leave Community", role: .destructive) {
                    Haptics.warning()
                    svc.leave()
                    ToastCenter.shared.show("Left the Community", style: .info, haptic: false)
                }
            }
        }
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

// MARK: - My profile header

private struct MyProfileHeader: View {
    let stats: CommunityService.MyStats
    private var svc: CommunityService { .shared }

    var body: some View {
        HStack(spacing: 14) {
            AnglerAvatar(image: svc.myAvatar, size: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(svc.myName).font(.headline)
                if !svc.myBio.isEmpty {
                    Text(svc.myBio).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Text("\(stats.totalCatches) catches · \(stats.speciesCount) species")
                    .font(.caption2).foregroundStyle(CurrentsTheme.accent)
            }
            Spacer()
            Image(systemName: "square.and.pencil").foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
                ContentUnavailableView("No entries yet", systemImage: "trophy",
                    description: Text("Add friends and log catches to fill the board."))
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
        .sensoryFeedback(.selection, trigger: metric)
    }

    /// Rows are only tappable for friends (and yourself) — individual catches
    /// and profiles are friends-only; global just shows the ranking.
    @ViewBuilder private func leaderRow(_ i: Int, _ row: CommunityService.LeaderRow) -> some View {
        let isSelf = row.friendCode == svc.friendCode
        let isFriend = svc.isFriend(row.friendCode)
        if metric == .count, isFriend {
            NavigationLink { FriendProfileView(code: row.friendCode) } label: { rowBody(i, row) }
        } else if metric != .count, isFriend || isSelf {
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
        loading = true
        let result = await svc.board(metric: metric, myRows: myLocalRows())
        rows = result.rows
        myStanding = result.mine
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
                .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
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

        // 2) Background: refresh from iCloud (all friends concurrently) and
        //    quietly swap in the fresh data.
        let tasks = codes.map { code in Task { await svc.fetchProfile(code: code) } }
        var result: [CommunityService.Profile] = []
        for t in tasks {
            if let p = await t.value { result.append(p) }
        }
        if !result.isEmpty {
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
    @State private var sharedSpots: [CommunityService.SharedSpot] = []
    @State private var catches: [CommunityService.LeaderRow] = []
    @State private var catchAccess = false
    @State private var selectedSpot: CommunityService.SharedSpot?
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }

    var body: some View {
        List {
            if let p = profile {
                Section {
                    VStack(spacing: 8) {
                        AnglerAvatar(image: p.avatar, size: 88)
                        Text(p.name).font(.title2.bold())
                        if !p.bio.isEmpty { Text(p.bio).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                        if !p.homeWater.isEmpty {
                            Label(p.homeWater, systemImage: "water.waves").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Angler since \(p.memberSince.formatted(.dateTime.month().year()))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)

                Section {
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
                    if !p.favoriteSpecies.isEmpty {
                        Label("Favourite: \(p.favoriteSpecies)", systemImage: "star.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    FishLoader(message: "Loading profile…")
                        .padding(.vertical, 8).listRowBackground(Color.clear)
                }
            }

            // Their catches — friends-only, and only if they've shared them.
            Section("Catches") {
                if !catchAccess {
                    Label("This angler hasn't shared their catch history with you.",
                          systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.secondary)
                } else if catches.isEmpty {
                    ContentUnavailableView("No catches shared", systemImage: "fish",
                        description: Text("This angler hasn't shared any catches yet."))
                } else {
                    ForEach(catches) { c in
                        NavigationLink { CommunityCatchDetailView(row: c) } label: { catchRow(c) }
                    }
                }
            }

            if !sharedSpots.isEmpty {
                Section("Spots they've shared with you") {
                    ForEach(sharedSpots) { s in sharedSpotRow(s) }
                }
            }

            Section {
                TextField("Nickname (optional)", text: $privacy.nickname)
            } header: {
                Text("Nickname")
            }
            .onChange(of: privacy.nickname) { _, name in
                svc.setNickname(name, for: code)
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
                .onChange(of: override) { _, o in
                    svc.setOverride(o, for: code)
                    ToastCenter.shared.show("Sharing updated", style: .info, haptic: false)
                    let spots = (try? appState.spotRepository.fetchAll()) ?? []
                    Task { await svc.applyPrivacy(for: code, spots: spots) }
                }
            }
        }
        .navigationTitle(profile?.name ?? "Angler")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: override)
        .sheet(item: $selectedSpot) { s in
            NavigationStack { SharedSpotDetailView(spot: s, friendName: profile?.name ?? "a friend") }
        }
        .task {
            privacy = svc.privacy(for: code)
            override = svc.override(for: code)
            // Show the cached profile instantly, then refresh from iCloud.
            if profile == nil { profile = svc.cachedProfiles(for: [code]).first }
            if let fresh = await svc.fetchProfile(code: code) { profile = fresh }
            sharedSpots = await svc.sharedSpots(fromFriend: code)
            catchAccess = await svc.hasCatchAccess(to: code)
            if catchAccess { catches = await svc.anglerCatches(code: code) }
        }
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
                .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
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
                        .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
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
