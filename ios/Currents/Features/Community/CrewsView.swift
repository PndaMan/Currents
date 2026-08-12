import SwiftUI
import PhotosUI

// MARK: - Community section: my Crews

/// A "Crew" is a persistent circle of friends with a shared, ongoing catch
/// feed — the way you keep up with what your friends are catching. Catches you
/// log flow in automatically (per-crew toggle), members can react and caption,
/// and a crew can optionally start a live trip when you fish together.
struct CrewsSection: View {
    @StateObject private var svc = CommunityService.shared

    var body: some View {
        Section("Crews") {
            if svc.myCrews.isEmpty {
                Text("Start a crew to share catches with your friends — everyone's catches land in one feed.")
                    .font(.caption).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(svc.myCrews) { crew in
                NavigationLink {
                    CrewDetailView(code: crew.code)
                } label: {
                    HStack(spacing: 12) {
                        CrewIconView(code: crew.code, emoji: crew.emoji, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(crew.name).font(.subheadline.bold())
                            Text(crew.createdByCode == svc.friendCode
                                 ? "You started this · \(crew.code)"
                                 : "Started by \(crew.createdByName) · \(crew.code)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            NavigationLink {
                CrewSetupView()
            } label: {
                Label("New crew", systemImage: "plus.circle.fill")
                    .foregroundStyle(CurrentsTheme.accent)
            }
        }
    }
}

/// A crew's round icon: its icon photo when one is set (disk-cached, refreshed
/// lazily), otherwise its emoji on a tinted circle.
private struct CrewIconView: View {
    let code: String
    let emoji: String
    var size: CGFloat = 34
    @State private var icon: UIImage?

    var body: some View {
        Group {
            if let icon {
                Image(uiImage: icon).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(CurrentsTheme.accent.opacity(0.15))
                    Text(emoji).font(.system(size: size * 0.5))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task {
            icon = CommunityDiskCache.loadImage(key: "crewicon-\(code)")
            if icon == nil {
                icon = await CommunityService.shared.crewArt(code: code).icon
            }
        }
    }
}

// MARK: - Create or join a crew

struct CrewSetupView: View {
    @Environment(\.dismiss) private var dismiss
    private var svc: CommunityService { .shared }

    @State private var name = ""
    @State private var emoji = "🎣"
    @State private var joinCode = ""
    @State private var busy = false

    private let emojis = ["🎣", "🐟", "🐠", "🦈", "🌊", "⚓️", "🛥️", "🏆"]

    var body: some View {
        Form {
            Section {
                TextField("Crew name (e.g. The Usual Suspects)", text: $name)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(emojis, id: \.self) { e in
                            Button { Haptics.tap(); emoji = e } label: {
                                Text(e)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(emoji == e ? CurrentsTheme.accent.opacity(0.2) : Color(.secondarySystemBackground),
                                                in: Circle())
                                    .overlay(Circle().stroke(emoji == e ? CurrentsTheme.accent : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Button {
                    Task {
                        busy = true
                        let crew = await svc.createCrew(name: name.trimmingCharacters(in: .whitespaces), emoji: emoji)
                        busy = false
                        if crew != nil {
                            Haptics.success()
                            ToastCenter.shared.show("Crew created 🎣")
                            dismiss()
                        } else {
                            ToastCenter.shared.show("Couldn't create the crew", style: .error)
                        }
                    }
                } label: {
                    Label("Create crew", systemImage: "person.3.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
                .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Start a crew")
            } footer: {
                Text("Invite friends afterwards. Everyone's catches show up in the crew's feed automatically — you can turn that off per crew.")
            }

            Section {
                CodeField(text: $joinCode, placeholder: "CREW CODE")
                Button {
                    Task {
                        busy = true
                        let crew = await svc.joinCrew(code: joinCode)
                        busy = false
                        if crew != nil {
                            Haptics.success()
                            ToastCenter.shared.show("Joined the crew 🎣")
                            dismiss()
                        } else {
                            ToastCenter.shared.show("Couldn't find that crew", style: .error)
                        }
                    }
                } label: {
                    Label("Join by code", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(busy || joinCode.trimmingCharacters(in: .whitespaces).count != 6)
            } header: {
                Text("Join a crew")
            } footer: {
                Text("Enter the 6-character code a friend shared with you.")
            }
        }
        .navigationTitle("New Crew")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Crew detail (feed-first)

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
    @State private var iconImage: UIImage?
    @State private var liveTrips: [CommunityService.GroupTrip] = []
    @State private var tournament: CommunityService.Tournament?
    @State private var standings: [CommunityService.TeamStanding] = []
    @State private var showingSettings = false
    @State private var showingTournamentSetup = false

    private let pageSize = 30

    var body: some View {
        List {
            headerSection
            membersSection
            if let crew { tournamentsSection(crew) }
            sessionsSection
            feedSection
        }
        .navigationTitle(crew?.name ?? "Crew")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Crew settings")
            }
        }
        .sheet(isPresented: $showingSettings) {
            if let crew {
                CrewSettingsView(crew: crew, members: members,
                                 onChange: { Task { await refresh() } },
                                 onLeave: { dismiss() })
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
            iconImage = CommunityDiskCache.loadImage(key: "crewicon-\(code)")
            if !feed.isEmpty || !members.isEmpty { isLoading = false }
            await refresh()
            await pollLoop()
        }
    }

    /// Every 20s: re-fetch only the first feed page (merged into what's
    /// loaded) plus the live-session/tournament state.
    private func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            mergeFirstPage(await svc.crewFeedPage(code: code))
            liveTrips = await svc.liveCrewTrips(crewCode: code)
            tournament = await svc.activeTournament(crewCode: code)
            if let t = tournament, !t.isEnded {
                standings = await svc.teamStandings(tournament: t)
            }
        }
    }

    private func refresh() async {
        // Everything independent goes out in parallel — the crew page used to
        // stack seven round trips end to end.
        async let freshCrew = svc.fetchCrew(code: code)
        async let freshMembers = svc.crewMembers(code: code)
        async let art = svc.crewArt(code: code)
        async let firstPage = svc.crewFeedPage(code: code)
        async let trips = svc.liveCrewTrips(crewCode: code)
        async let tourney = svc.activeTournament(crewCode: code)

        if let fresh = await freshCrew { crew = fresh }
        members = await freshMembers
        let a = await art
        banner = a.banner
        iconImage = a.icon
        let page = await firstPage
        mergeFirstPage(page)
        canLoadMore = page.count == pageSize
        liveTrips = await trips
        tournament = await tourney
        if let t = tournament {
            standings = await svc.teamStandings(tournament: t)
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
        // Instant: whatever's already cached.
        for m in members where memberAvatars[m.id] == nil {
            if let a = svc.cachedProfiles(for: [m.id]).first?.avatar { memberAvatars[m.id] = a }
        }
        // Fresh: batch-fetch any we still don't have.
        let missing = members.map(\.id).filter { memberAvatars[$0] == nil }
        guard !missing.isEmpty else { return }
        let profiles = await svc.profiles(for: missing)
        for (c, p) in profiles where p.avatar != nil { memberAvatars[c] = p.avatar }
    }

    // MARK: Header (banner + identity)

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let banner {
                        Image(uiImage: banner).resizable().scaledToFill()
                    } else {
                        LinearGradient(colors: [CurrentsTheme.accent.opacity(0.55),
                                                CurrentsTheme.accent.opacity(0.25)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .zoomableOnTap(banner)

                HStack(spacing: 12) {
                    crewIcon(size: 56)
                        .zoomableOnTap(iconImage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(crew?.name ?? "Crew").font(.title2.bold())
                        Text("\(members.count) member\(members.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.leading, 12)
                .padding(.top, -32)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
        .listRowSeparator(.hidden)
    }

    private func crewIcon(size: CGFloat) -> some View {
        Group {
            if let iconImage {
                Image(uiImage: iconImage).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(CurrentsTheme.accent.opacity(0.18))
                    Text(crew?.emoji ?? "🎣").font(.system(size: size * 0.5))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.background, lineWidth: 3))
    }

    // MARK: Members strip

    private var membersSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(members) { m in memberChip(m) }
                }
                .padding(.vertical, 4)
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func memberChip(_ m: CommunityService.GroupMember) -> some View {
        let role = crew.map { svc.role(of: m.id, in: $0) } ?? .member
        return NavigationLink {
            FriendProfileView(code: m.id)
        } label: {
            VStack(spacing: 4) {
                AnglerAvatar(image: memberAvatars[m.id], size: 44)
                    .overlay(alignment: .bottomTrailing) { roleBadge(role) }
                Text(m.id == svc.friendCode ? "You" : m.name)
                    .font(.caption2).lineLimit(1).frame(maxWidth: 64)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func roleBadge(_ role: CrewRole) -> some View {
        if role != .member {
            Image(systemName: role.icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Self.roleColor(role), in: Circle())
                .overlay(Circle().stroke(.background, lineWidth: 1.5))
        }
    }

    static func roleColor(_ role: CrewRole) -> Color {
        switch role {
        case .captain: .yellow
        case .mate:    .orange
        case .admin:   .blue
        case .member:  .clear
        }
    }

    // MARK: Tournament hero

    /// The crew's dedicated tournament area: the active tournament front and
    /// centre, a create action for admins, and the full history behind one
    /// link — fifty past tournaments never pile up on this screen.
    private func tournamentsSection(_ crew: CommunityService.Crew) -> some View {
        Section("Tournaments") {
            if let tournament {
                tournamentHero(tournament, crew: crew)
            }
            if tournament == nil || tournament?.isEnded == true {
                if svc.myRole(in: crew).canRunTournaments {
                    newTournamentRow
                } else if tournament == nil {
                    Text("No tournament running — a crew admin can start one.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            NavigationLink {
                TournamentHistoryView(crew: crew)
            } label: {
                Label("All tournaments", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline)
            }
        }
    }

    private var newTournamentRow: some View {
        Button {
            Haptics.tap()
            showingTournamentSetup = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
                    .frame(width: 34, height: 34)
                    .background(Color.yellow.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Start a tournament").font(.subheadline.bold())
                    Text("Teams are live sessions — every catch scores points.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func tournamentHero(_ t: CommunityService.Tournament,
                                crew: CommunityService.Crew) -> some View {
            NavigationLink {
                TournamentView(tournament: t, crew: crew)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                        Text(t.name).font(.headline)
                        Spacer()
                        Text(t.isEnded ? "ENDED" : "LIVE")
                            .font(.system(size: 10, weight: .heavy))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(t.isEnded ? Color.secondary.opacity(0.25) : Color.red,
                                        in: Capsule())
                            .foregroundStyle(t.isEnded ? Color.secondary : Color.white)
                    }
                    if t.isEnded, let winner = t.winnerTeam {
                        Text("🏆 \(winner) won").font(.subheadline.bold())
                    } else if let ends = t.endsAt {
                        TimelineView(.periodic(from: .now, by: 60)) { ctx in
                            Label(crewCountdownLabel(to: ends, now: ctx.date), systemImage: "clock")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(standings.prefix(2)) { s in
                        HStack {
                            Text(s.teamName).font(.caption.bold())
                            Spacer()
                            Text("\(s.points) pts")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(CurrentsTheme.accent)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
    }

    // MARK: Live sessions

    private var sessionsSection: some View {
        Section("Live sessions") {
            if liveTrips.isEmpty {
                Text("No live sessions right now — start one when you're fishing together.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(liveTrips) { trip in liveTripRow(trip) }
            // Tournaments have their own section now — this strip is purely
            // for casual live sessions.
            NavigationLink {
                GroupTripSetupView(crewCode: code)
            } label: {
                Label("Start live session", systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func liveTripRow(_ trip: CommunityService.GroupTrip) -> some View {
        let amIn = svc.myGroups.contains { $0.code == trip.id }
        return NavigationLink {
            GroupTripView(tripId: svc.tripId(forGroupCode: trip.id),
                          tripName: trip.name, initialCode: trip.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.red, in: Circle())
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(trip.name) is live").font(.subheadline.bold())
                    Text(trip.hostCode == svc.friendCode ? "You're hosting · tap to open"
                         : amIn ? "You're in · tap to open"
                         : "Hosted by \(trip.hostName) · tap to join")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if !amIn {
                    Text("JOIN")
                        .font(.system(size: 10, weight: .heavy))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.red, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: Feed (paginated)

    @ViewBuilder
    private var feedSection: some View {
        Section("Catches") {
            if feed.isEmpty {
                if isLoading {
                    FishLoader(message: "Loading the feed…")
                        .frame(height: 90).frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else {
                    ContentUnavailableView(
                        "No catches yet",
                        systemImage: "fish",
                        description: Text("When you or a crewmate log a catch, it shows up here."))
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(feed) { post in
                    CrewPostCard(post: post, crewCode: code, crew: crew) { await refresh() }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .onAppear { loadMoreIfNeeded(after: post) }
                }
                if loadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
        }
    }
}

/// "Ends in 3h 12m" / "Overtime" once past due.
private func crewCountdownLabel(to end: Date, now: Date) -> String {
    let s = end.timeIntervalSince(now)
    guard s > 0 else { return "Overtime" }
    let h = Int(s) / 3600, m = (Int(s) % 3600) / 60
    return h > 0 ? "Ends in \(h)h \(m)m" : "Ends in \(m)m"
}

// MARK: - Crew settings (identity, posting, members, invite, leave)

struct CrewSettingsView: View {
    let crew: CommunityService.Crew
    let members: [CommunityService.GroupMember]
    let onChange: () -> Void
    var onLeave: () -> Void = {}

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
    @State private var confirmLeave = false
    @State private var showingIconPicker = false
    @State private var showingBannerPicker = false
    @State private var showingEmojiRow = false

    private let emojis = ["🎣", "🐟", "🐠", "🦈", "🌊", "⚓️", "🛥️", "🏆"]

    init(crew: CommunityService.Crew, members: [CommunityService.GroupMember],
         onChange: @escaping () -> Void, onLeave: @escaping () -> Void = {}) {
        self.crew = crew
        self.members = members
        self.onChange = onChange
        self.onLeave = onLeave
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
                postingSection
                membersSection
                rolesGuideSection
                inviteSection
                dangerSection
            }
            .navigationTitle("Crew Settings")
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
    }

    // MARK: Identity

    /// What the banner/avatar currently look like, folding in pending picks
    /// and removals so the header is always a live preview of what Save does.
    private var currentBanner: UIImage? {
        newBanner ?? (removeBanner || !hasBanner ? nil
                      : CommunityDiskCache.loadImage(key: "crewbanner-\(crew.code)"))
    }
    private var currentIcon: UIImage? {
        newIcon ?? (removeIcon || !hasIcon ? nil
                    : CommunityDiskCache.loadImage(key: "crewicon-\(crew.code)"))
    }

    /// One visual header instead of six stacked rows: the banner IS the
    /// banner control, the avatar IS the icon control (photo or emoji), and
    /// the name sits beneath — edit what you're looking at.
    private var identitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    bannerCanvas
                    avatarCircle
                        .padding(.leading, 14)
                        .offset(y: 32)
                }
                .padding(.bottom, 34)

                TextField("Crew name", text: $name)
                    .font(.headline)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color(.tertiarySystemFill),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                if showingEmojiRow { emojiRow }

                Button {
                    save()
                } label: {
                    HStack {
                        if saving { ProgressView().tint(.white) }
                        Label("Save changes", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
                .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        } header: {
            Text("Identity")
        } footer: {
            Text("Tap the banner or the avatar to change them. Only the captain and mates can change the crew's name and look.")
        }
    }

    private var bannerCanvas: some View {
        ZStack(alignment: .topTrailing) {
            // A real Button, not onTapGesture — in a Form row a bare tap
            // gesture becomes the whole row's primary action.
            Button {
                showingBannerPicker = true
            } label: {
                Group {
                    if let banner = currentBanner {
                        Image(uiImage: banner).resizable().scaledToFill()
                    } else {
                        LinearGradient(colors: [CurrentsTheme.accent.opacity(0.45),
                                                CurrentsTheme.accent.opacity(0.12)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                            .overlay {
                                Label("Add a banner", systemImage: "photo.badge.plus")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

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
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(8)
        }
    }

    private var avatarCircle: some View {
        Menu {
            Button {
                showingIconPicker = true
            } label: {
                Label(currentIcon == nil ? "Choose a photo" : "Change photo", systemImage: "photo")
            }
            Button {
                withAnimation(.snappy(duration: 0.2)) { showingEmojiRow.toggle() }
            } label: {
                Label("Pick an emoji", systemImage: "face.smiling")
            }
            if currentIcon != nil {
                Button(role: .destructive) {
                    removeIcon = true
                    newIcon = nil
                    iconItem = nil
                } label: {
                    Label("Remove photo (use emoji)", systemImage: "trash")
                }
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let icon = currentIcon {
                        Image(uiImage: icon).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Circle().fill(CurrentsTheme.accent.opacity(0.18))
                            Text(emoji).font(.system(size: 30))
                        }
                    }
                }
                .frame(width: 66, height: 66)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))

                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(CurrentsTheme.accent, in: Circle())
            }
        }
    }

    private var emojiRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(emojis, id: \.self) { e in
                    Button { Haptics.tap(); emoji = e } label: {
                        Text(e)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(emoji == e ? CurrentsTheme.accent.opacity(0.2)
                                                   : Color(.secondarySystemBackground),
                                        in: Circle())
                            .overlay(Circle().stroke(emoji == e ? CurrentsTheme.accent : .clear,
                                                     lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
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

    // MARK: Posting

    private var postingSection: some View {
        Section("Posting") {
            Toggle(isOn: Binding(
                get: { svc.crew(withCode: currentCrew.code)?.autoPost ?? currentCrew.autoPost },
                set: { on in
                    svc.setAutoPost(on, forCrew: currentCrew.code)
                    currentCrew.autoPost = on
                    Haptics.tap()
                    ToastCenter.shared.show(on ? "Auto-posting to this crew" : "Auto-post off for this crew",
                                            style: .info, haptic: false)
                }
            )) {
                Label("Post my catches here", systemImage: "arrow.up.circle.fill")
            }
            .tint(CurrentsTheme.accent)
        }
    }

    // MARK: Members

    /// What YOU are in this crew and what that lets you do — the role system
    /// was invisible until a second member joined.
    private var yourRoleSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: myRole.icon)
                    .font(.headline)
                    .foregroundStyle(myRole == .member ? Color.secondary : CrewDetailView.roleColor(myRole))
                    .frame(width: 38, height: 38)
                    .background((myRole == .member ? Color.secondary : CrewDetailView.roleColor(myRole)).opacity(0.15),
                                in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("You're \(myRole == .admin ? "an" : myRole == .member ? "a" : "the") \(myRole.label)")
                        .font(.subheadline.bold())
                    Text(Self.roleSummary(myRole))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    static func roleSummary(_ role: CrewRole) -> String {
        switch role {
        case .captain: "Full control: identity, roles, members, posts and tournaments — and you can hand the crew over."
        case .mate:    "Everything but the wheel: edit the crew's look, manage roles, moderate posts and members, run tournaments."
        case .admin:   "Keeper of the peace: delete any post, remove members, run tournaments."
        case .member:  "Post catches, react, join sessions and tournaments."
        }
    }

    /// The whole ladder, so everyone knows what each badge means.
    private var rolesGuideSection: some View {
        Section {
            DisclosureGroup {
                ForEach([CrewRole.captain, .mate, .admin, .member], id: \.self) { role in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: role.icon)
                            .font(.caption)
                            .foregroundStyle(role == .member ? Color.secondary : CrewDetailView.roleColor(role))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(role.label).font(.caption.bold())
                            Text(Self.roleSummary(role)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } label: {
                Label("How roles work", systemImage: "person.badge.shield.checkmark")
                    .font(.subheadline)
            }
        } footer: {
            Text("The Captain and Mates set roles from a member's ⋯ menu. Admins and up can remove members and delete posts.")
        }
    }

    private var membersSection: some View {
        Section("Members · \(members.count)") {
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
            Text("\(m.name) can re-join with the crew code.")
        }
        .confirmationDialog(
            "Hand over the crew?",
            isPresented: Binding(get: { confirmingTransfer != nil },
                                 set: { if !$0 { confirmingTransfer = nil } }),
            titleVisibility: .visible,
            presenting: confirmingTransfer
        ) { m in
            Button("Make \(m.name) Captain", role: .destructive) {
                Task {
                    if let updated = await svc.transferCaptaincy(to: m.id, name: m.name, in: currentCrew) {
                        currentCrew = updated
                        Haptics.success()
                        ToastCenter.shared.show("\(m.name) is Captain now — you stay aboard as a Mate",
                                                style: .success)
                        onChange()
                    } else {
                        ToastCenter.shared.show("Couldn't transfer the crew", style: .error)
                    }
                }
            }
        } message: { m in
            Text("\(m.name) becomes the Captain with full control. You stay aboard as a Mate.")
        }
    }

    @ViewBuilder private func memberRow(_ m: CommunityService.GroupMember) -> some View {
        let role = svc.role(of: m.id, in: currentCrew)
        let isSelf = m.id == svc.friendCode
        let isCaptain = m.id == currentCrew.createdByCode
        HStack(spacing: 12) {
            AnglerAvatar(image: svc.cachedProfiles(for: [m.id]).first?.avatar, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(isSelf ? "You" : m.name).font(.subheadline.bold())
                Text(role.label).font(.caption2)
                    .foregroundStyle(role == .member ? Color.secondary : CrewDetailView.roleColor(role))
            }
            Spacer()
            if !isSelf, !isCaptain, myRole.canModerate {
                Menu {
                    if myRole.canManage {
                        if myRole == .captain {
                            Button { confirmingTransfer = m } label: {
                                Label("Make Captain", systemImage: CrewRole.captain.icon)
                            }
                        }
                        if myRole == .captain, role != .mate {
                            Button { apply(.mate, to: m) } label: {
                                Label("Make Mate", systemImage: CrewRole.mate.icon)
                            }
                        }
                        if role != .admin {
                            Button { apply(.admin, to: m) } label: {
                                Label("Make Admin", systemImage: CrewRole.admin.icon)
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
                    Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func apply(_ role: CrewRole, to m: CommunityService.GroupMember) {
        Task {
            if let updated = await svc.setRole(role, for: m.id, in: currentCrew) {
                currentCrew = updated
                Haptics.success()
                ToastCenter.shared.show(role == .member ? "\(m.name) is a member again"
                                                        : "\(m.name) is now \(role.label)",
                                        style: .success)
                onChange()
            } else {
                ToastCenter.shared.show("Couldn't change that role", style: .error)
            }
        }
    }

    // MARK: Invite

    private var inviteSection: some View {
        Section("Invite") {
            HStack {
                Text("Crew code")
                Spacer()
                CopyableCode(code: currentCrew.code)
            }
            ShareLink(item: svc.crewInviteMessage(code: currentCrew.code, name: currentCrew.name)) {
                Label("Share invite", systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: Danger

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                confirmLeave = true
            } label: {
                Label("Leave crew", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .confirmationDialog("Leave this crew?", isPresented: $confirmLeave,
                                titleVisibility: .visible) {
                Button("Leave", role: .destructive) {
                    Task {
                        await svc.leaveCrew(code: currentCrew.code)
                        Haptics.warning()
                        ToastCenter.shared.show("Left the crew", style: .info, haptic: false)
                        dismiss()
                        onLeave()
                    }
                }
            } message: {
                Text("You'll stop seeing this crew's feed. You can re-join with the code.")
            }
        }
    }
}

// MARK: - Feed post card

/// A crew catch as a social card: the photo IS the card, species and size on
/// a scrim, and a plain always-visible emoji row for reactions — no menus.
/// Species-by-name lookup for feed cards — a CrewPost only carries the name,
/// and 1,500 species are too many to re-scan per card, so the index builds
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

struct CrewPostCard: View {
    let post: CommunityService.CrewPost
    let crewCode: String
    /// The crew this post lives in, when known — needed for moderation
    /// (delete-others'-posts) checks and the delete call itself.
    var crew: CommunityService.Crew? = nil
    let reload: () async -> Void

    private var svc: CommunityService { .shared }
    @Environment(AppState.self) private var appState
    @State private var photo: UIImage?
    @State private var editingCaption = false
    @State private var captionDraft = ""
    @State private var confirmingDelete = false
    /// Optimistic reactions, shown the instant you tap and replaced by the
    /// server's truth on the next reload.
    @State private var localReactions: [CommunityService.CrewReaction]?

    private var isMine: Bool { post.authorCode == svc.friendCode }
    private var canModerate: Bool { crew.map { svc.myRole(in: $0).canModerate } ?? false }
    private var reactions: [CommunityService.CrewReaction] { localReactions ?? post.reactions }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if post.hasPhoto { photoHero } else { textHero }
            if !post.caption.isEmpty {
                Text(post.caption).font(.subheadline)
            } else if isMine {
                Button("Add a caption…") { startEditingCaption() }
                    .font(.caption).foregroundStyle(CurrentsTheme.accent)
                    .buttonStyle(.plain)
            }
            reactionRow
        }
        .padding(.vertical, 4)
        .task(id: post.id) {
            if post.hasPhoto, photo == nil {
                photo = await svc.crewPostImage(recordName: post.id)
            }
        }
        .onChange(of: post.reactions) { _, _ in localReactions = nil }
        .alert("Caption", isPresented: $editingCaption) {
            TextField("Say something…", text: $captionDraft)
            Button("Save") {
                let text = captionDraft
                Task { await svc.setCrewCaption(text, postId: post.id); await reload() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this post?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    if let crew, await svc.deleteCrewPost(post, in: crew) {
                        Haptics.warning()
                        ToastCenter.shared.show("Post deleted", style: .info, haptic: false)
                        await reload()
                    } else {
                        ToastCenter.shared.show("Couldn't delete the post", style: .error)
                    }
                }
            }
        } message: {
            Text("The post disappears from the crew's feed for everyone.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AnglerAvatar(image: svc.cachedProfiles(for: [post.authorCode]).first?.avatar, size: 36)
                .zoomableOnTap(svc.cachedProfiles(for: [post.authorCode]).first?.avatar)
            VStack(alignment: .leading, spacing: 1) {
                Text(isMine ? "You" : post.authorName).font(.subheadline.bold())
                Text(post.caughtAt.formatted(.relative(presentation: .named)))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                if isMine {
                    Button { startEditingCaption() } label: {
                        Label(post.caption.isEmpty ? "Add caption" : "Edit caption",
                              systemImage: "pencil")
                    }
                }
                ShareLink(item: "🎣 \(isMine ? svc.myName : post.authorName) caught a \(post.species)!") {
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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
        }
    }

    /// Full-bleed photo with the species and size on a bottom scrim, trip tag
    /// floating top-right — the catch is the hero, not a row of metadata.
    /// Tap it to go fullscreen and zoom.
    private var photoHero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.gray.opacity(0.15)).overlay(ProgressView())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.78)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 110)

            VStack(alignment: .leading, spacing: 2) {
                Text(post.species).font(.title3.bold()).foregroundStyle(.white)
                if let size = sizeText {
                    Text(size).font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(12)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if !post.tripName.isEmpty {
                Label(post.tripName, systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(8)
            }
        }
        .zoomableOnTap(photo)
    }

    /// Photo-less posts still get a proper hero, not a bare text line — the
    /// species' own artwork where we have it, never the generic fish glyph.
    private var textHero: some View {
        HStack(spacing: 10) {
            Group {
                if let sp = SpeciesArtLookup.species(named: post.species, appState: appState) {
                    SpeciesArtworkView(species: sp, caught: true, size: 34)
                        .frame(width: 40, height: 40)
                } else {
                    Image(systemName: "fish.fill")
                        .foregroundStyle(CurrentsTheme.accent)
                        .frame(width: 40, height: 40)
                }
            }
            .background(CurrentsTheme.accent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(post.species).font(.headline)
                if let size = sizeText {
                    Text(size).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !post.tripName.isEmpty {
                Label(post.tripName, systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption2.bold()).foregroundStyle(CurrentsTheme.accent)
            }
        }
    }

    private var sizeText: String? {
        let parts = [post.weightKg.map { Units.weight(kg: $0) },
                     post.lengthCm.map { Units.length(cm: $0) }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// All five emojis, always visible, tap to toggle. Counts appear beside an
    /// emoji once someone's used it; yours gets the tinted capsule. No menus,
    /// no "React" labels.
    private var reactionRow: some View {
        let grouped = Dictionary(grouping: reactions, by: \.emoji)
        let mine = reactions.first { $0.reactorCode == svc.friendCode }?.emoji
        return HStack(spacing: 6) {
            ForEach(CommunityService.crewReactionEmojis, id: \.self) { emoji in
                let count = grouped[emoji]?.count ?? 0
                let selected = mine == emoji
                Button { toggle(emoji) } label: {
                    HStack(spacing: 4) {
                        Text(emoji).font(.system(size: 16))
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(selected ? CurrentsTheme.accent : .secondary)
                        }
                    }
                    .padding(.horizontal, count > 0 ? 10 : 8)
                    .padding(.vertical, 6)
                    .background(selected ? AnyShapeStyle(CurrentsTheme.accent.opacity(0.18))
                                         : AnyShapeStyle(.gray.opacity(0.12)),
                                in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(selected ? CurrentsTheme.accent.opacity(0.6) : .clear,
                                               lineWidth: 1)
                    }
                    .opacity(count > 0 || selected ? 1 : 0.65)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func toggle(_ emoji: String) {
        Haptics.tap()
        // Optimistic: the tap shows immediately; the reload swaps in truth.
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
        localReactions = rs
        Task {
            await svc.toggleCrewReaction(emoji: emoji, postId: post.id,
                                         crewCode: crewCode, postAuthorCode: post.authorCode)
            await reload()
            localReactions = nil
        }
    }

    private func startEditingCaption() {
        captionDraft = post.caption
        editingCaption = true
    }
}

// MARK: - Join a crew from an invite link

/// Presented when the app opens a `currents://crew/<CODE>` deep link. Confirms
/// the crew, then joins with one tap (setting up a Community profile first if
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
        Group {
            if svc.joined { confirmBody } else { joinGate }
        }
        .navigationTitle(svc.joined ? "Join Crew" : "Join Community")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
        }
        .task {
            crew = await svc.fetchCrew(code: code)
            members = await svc.crewMembers(code: code).count
            loading = false
        }
    }

    private var joinGate: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Text(crew?.emoji ?? "🎣").font(.system(size: 44))
                    Text("Join “\(crew?.name ?? "a crew")”").font(.title3.bold())
                    Text("Set up your free Currents profile — no account or password, just a name — to join this crew and share catches.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            Section("Your angler name") {
                TextField("Name", text: $joinName).textContentType(.givenName)
            }
            Section {
                Button {
                    joining = true
                    Task {
                        await svc.join(name: joinName, region: svc.myRegion)
                        Haptics.success()
                        joining = false
                    }
                } label: {
                    HStack {
                        if joining { ProgressView().tint(.white) }
                        Label("Join & Continue", systemImage: "arrow.right.circle.fill").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
                .disabled(joining || joinName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var confirmBody: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Text(crew?.emoji ?? "🎣").font(.system(size: 52))
                    Text(crew?.name ?? "Crew").font(.title2.bold())
                    if loading {
                        ProgressView()
                    } else {
                        Text("\(members) member\(members == 1 ? "" : "s") · started by \(crew?.createdByName ?? "an angler")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section {
                if joined || alreadyIn {
                    Label("You're in this crew", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        joining = true
                        Task {
                            let ok = await svc.joinCrew(code: code) != nil
                            joining = false
                            if ok {
                                joined = true
                                Haptics.success()
                                ToastCenter.shared.show("Joined the crew 🎣")
                            } else {
                                ToastCenter.shared.show("Couldn't join that crew", style: .error)
                            }
                        }
                    } label: {
                        HStack {
                            if joining { ProgressView().tint(.white) }
                            Label("Join crew", systemImage: "person.3.fill").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
                    .disabled(joining || crew == nil)
                }
            } footer: {
                Text("Open the crew from Community once you've joined.")
            }
        }
    }
}
