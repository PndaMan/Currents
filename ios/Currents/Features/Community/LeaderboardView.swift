import SwiftUI

/// The leaderboard page (pushed from the Crew tab). Scope toggles between
/// your friends and each of your crews; the metric ranks by most fish,
/// heaviest or longest. Every board is one ranked list: the top three carry
/// a medal, your own row is highlighted, and while it is off screen your
/// place is pinned to the bottom of the page.
struct LeaderboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var svc = CommunityService.shared
    @ObservedObject private var connection = CrewConnection.shared
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }

    /// "friends" or a crew code.
    @State private var scope = "friends"
    @State private var metric: CommunityService.Metric = .count
    @State private var rows: [CommunityService.LeaderRow] = []
    @State private var myStanding: (rank: Int, row: CommunityService.LeaderRow)?
    @State private var catchAccess: [String: Bool] = [:]
    @State private var avatars: [String: UIImage] = [:]
    @State private var loading = false
    /// Whether your own row is on screen; the pinned row shows when it isn't.
    @State private var myRowVisible = false
    @State private var showingAddFriend = false

    var body: some View {
        // Without iCloud the Crew unavailable state shows and no load starts.
        CrewCloudGate { page }
    }

    private var page: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    board
                        .padding(.top, DS.Space.s4)
                }
                .padding(.bottom, DS.Space.s6)
                .pageWidth()
            }
            .detailTint(nil)
            .eventPageTitle("Leaderboard")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                pinnedRow(proxy)
            }
            .refreshable { await reload() }
        }
        .sheet(isPresented: $showingAddFriend, onDismiss: { Task { await reload() } }) {
            CrewAddFriendSheet()
        }
        .task { await reload() }
        .onChange(of: metric) { _, _ in boardChanged() }
        .onChange(of: scope) { _, _ in boardChanged() }
        .onChange(of: svc.revision) { _, _ in Task { await reload() } }
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        DetailHeader(title: "Leaderboard", subtitle: scopeLine)
        metricPicker
            .padding(.top, DS.Space.s5)
        if !svc.myCrews.isEmpty {
            scopeChips
                .padding(.top, DS.Space.s3)
        }
        if connection.isOffline {
            EventNotice(offlineText, systemImage: "wifi.slash") {
                Button("Try again") { Task { await reload() } }
            }
            .padding(.top, DS.Space.s4)
        }
    }

    private var metricPicker: some View {
        Picker("Rank by", selection: $metric.haptic().animation(reduceMotion ? nil : DS.Motion.softSpring)) {
            Text("Most fish").tag(CommunityService.Metric.count)
            Text("Heaviest").tag(CommunityService.Metric.weight)
            Text("Longest").tag(CommunityService.Metric.length)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DS.gutter)
    }

    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                Chip("Friends", systemImage: "person.2.fill", isSelected: scope == "friends") {
                    scope = "friends"
                }
                ForEach(svc.myCrews) { crew in
                    Chip(crew.name, isSelected: scope == crew.code) {
                        scope = crew.code
                    }
                }
            }
            .padding(.horizontal, DS.gutter)
            .padding(.vertical, 2)
        }
        .scrollBounceBehavior(.basedOnSize, axes: [.horizontal])
    }

    private var scopeLine: String {
        scope == "friends" ? "You and your friends"
            : "Members of \(svc.crew(withCode: scope)?.name ?? "the crew")"
    }

    private var offlineText: String {
        rows.isEmpty ? "Offline. The board loads when you're back online."
                     : "Offline. Showing the last saved board."
    }

    // MARK: Board

    @ViewBuilder private var board: some View {
        Group {
            if loading && rows.isEmpty {
                FishLoader(message: "Loading the leaderboard")
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
            } else if rows.isEmpty {
                emptyState
            } else {
                rankedList
            }
        }
        // A new board is a new list, so row visibility starts fresh.
        .id(boardKey)
        .transition(.opacity)
    }

    private var boardKey: String {
        switch metric {
        case .count: "count-\(scope)"
        case .weight: "weight-\(scope)"
        case .length: "length-\(scope)"
        }
    }

    private var emptyState: some View {
        InlineEmpty(systemImage: "trophy", text: emptyText,
                    actionTitle: scope == "friends" ? "Add a friend" : nil,
                    action: scope == "friends" ? { showingAddFriend = true } : nil)
    }

    private var emptyText: String {
        let who = scope == "friends" ? "you or your friends" : "the crew"
        switch metric {
        case .count: return "Nothing on the board yet. When \(who) log catches, they rank here."
        case .weight: return "No weighed catches yet. Add a weight when \(who) log a catch to rank here."
        case .length: return "No measured catches yet. Add a length when \(who) log a catch to rank here."
        }
    }

    private var rankedList: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                link(for: row, rank: i + 1)
                    .id(row.id)
                    .onScrollVisibilityChange(threshold: 0.6) { visible in
                        guard row.id == myFirstRowID else { return }
                        withAnimation(reduceMotion ? nil : DS.Motion.softSpring) { myRowVisible = visible }
                    }
            }
        }
        .animation(reduceMotion ? nil : DS.Motion.softSpring, value: rows.map(\.id))
    }

    /// Most fish opens the angler; a catch opens the catch when they share
    /// their catches with you, otherwise the angler.
    @ViewBuilder private func link(for row: CommunityService.LeaderRow, rank: Int) -> some View {
        let isSelf = row.friendCode == svc.friendCode
        let opensCatch = metric != .count && (isSelf || catchAccess[row.friendCode] == true)
        if opensCatch {
            NavigationLink { CommunityCatchDetailView(row: row) } label: { rankRow(row, rank: rank) }
                .buttonStyle(.dsRow)
        } else {
            NavigationLink { FriendProfileView(code: row.friendCode) } label: { rankRow(row, rank: rank) }
                .buttonStyle(.dsRow)
        }
    }

    private func rankRow(_ row: CommunityService.LeaderRow, rank: Int, chevron: Bool = true) -> some View {
        let isSelf = row.friendCode == svc.friendCode
        return LeaderRankRow(rank: rank,
                             name: isSelf ? "You" : row.anglerName,
                             avatarName: isSelf ? svc.myName : row.anglerName,
                             subtitle: subtitle(row),
                             value: value(row),
                             detail: detail(row),
                             avatar: avatars[row.friendCode],
                             isSelf: isSelf,
                             chevron: chevron)
    }

    private func subtitle(_ row: CommunityService.LeaderRow) -> String? {
        switch metric {
        case .count: return row.region.isEmpty ? nil : row.region
        case .weight, .length: return row.species
        }
    }

    private func value(_ row: CommunityService.LeaderRow) -> String {
        switch metric {
        case .count:
            let n = row.catchCount ?? 0
            return n == 1 ? "1 fish" : "\(n) fish"
        case .weight: return row.weightKg.map { Units.weight(kg: $0, imperial: imperial) } ?? "Not weighed"
        case .length: return row.lengthCm.map { Units.length(cm: $0, imperial: imperial) } ?? "Not measured"
        }
    }

    /// The date under a catch's value, as Strava dates a segment effort.
    private func detail(_ row: CommunityService.LeaderRow) -> String? {
        metric == .count ? nil : row.date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    // MARK: Pinned you

    /// Your first row on this board (your best catch on a catch board).
    private var myFirstRowID: String? {
        rows.first { $0.friendCode == svc.friendCode }?.id
    }

    /// Where you stand: your place in the list when you're on it, otherwise
    /// the standing the service worked out beyond the board's cut.
    private var pinnedStanding: (rank: Int, row: CommunityService.LeaderRow, onBoard: Bool)? {
        guard !rows.isEmpty else { return nil }
        if let i = rows.firstIndex(where: { $0.friendCode == svc.friendCode }) {
            return (i + 1, rows[i], true)
        }
        if let mine = myStanding { return (mine.rank, mine.row, false) }
        return nil
    }

    /// Your row, pinned above the tab bar while it is off screen. Tapping it
    /// scrolls to your place when that place is on the board.
    @ViewBuilder private func pinnedRow(_ proxy: ScrollViewProxy) -> some View {
        if let mine = pinnedStanding, !(mine.onBoard && myRowVisible) {
            Button {
                guard mine.onBoard, let id = myFirstRowID else { return }
                withAnimation(reduceMotion ? nil : DS.Motion.softSpring) {
                    proxy.scrollTo(id, anchor: .center)
                }
            } label: {
                rankRow(mine.row, rank: mine.rank, chevron: false)
            }
            .buttonStyle(.dsRow)
            .allowsHitTesting(mine.onBoard)
            .accessibilityHint(mine.onBoard ? "Scrolls to your place" : "")
            .background(Color.dsBackground)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Data

    private func boardChanged() {
        myRowVisible = false
        Task { await reload() }
    }

    /// My own catches from the local database, so I always appear regardless
    /// of CloudKit sync state.
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
        if rows.isEmpty { loading = true }
        var among: Set<String>? = nil
        if scope != "friends" {
            // Crew scope: the board is exactly that crew's roster.
            var members = svc.cachedCrewMembers(scope).map(\.id)
            if members.isEmpty {
                members = await svc.crewMembers(code: scope).map(\.id)
            }
            among = Set(members)
        }
        let result = await svc.board(metric: metric, myRows: myLocalRows(), among: among)
        withAnimation(reduceMotion ? nil : DS.Motion.softSpring) {
            rows = result.rows
            myStanding = result.mine
        }
        let codes = Set(result.rows.map(\.friendCode))
        // Faces: cache-first, then one batched refresh.
        for p in svc.cachedProfiles(for: Array(codes)) where p.avatar != nil {
            avatars[p.id] = p.avatar
        }
        if let a = svc.myAvatar { avatars[svc.friendCode] = a }
        let othersToCheck = codes.filter { $0 != svc.friendCode }
        catchAccess = await svc.catchAccess(for: Array(othersToCheck))
        for (code, p) in await svc.profiles(for: Array(othersToCheck)) where p.avatar != nil {
            avatars[code] = p.avatar
        }
        loading = false
    }
}

// MARK: - Rank row

/// One place on a board, in the Luma row metrics: rank, the angler's avatar,
/// name and a secondary line, the value on the right with an optional date
/// under it. The top three get a medal disc behind the number; your own row
/// is tinted with the accent.
private struct LeaderRankRow: View {
    let rank: Int
    let name: String
    let avatarName: String
    let subtitle: String?
    let value: String
    let detail: String?
    let avatar: UIImage?
    let isSelf: Bool
    var chevron = true

    @ScaledMetric(relativeTo: .headline) private var rankWidth: CGFloat = 30

    var body: some View {
        ArtRow(title: name, subtitle: subtitle, chevron: chevron) {
            HStack(spacing: DS.Space.s3) {
                LeaderRankMark(rank: rank)
                    .frame(width: rankWidth)
                CrewAvatar(image: avatar, name: avatarName, size: 48)
            }
        } trailing: {
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .contentTransition(.numericText())
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                }
            }
            .multilineTextAlignment(.trailing)
        }
        .background(isSelf ? DS.accent.opacity(0.12) : Color.clear)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [eventOrdinal(rank), name, value]
        if let subtitle { parts.append(subtitle) }
        if let detail { parts.append(detail) }
        return parts.joined(separator: ", ")
    }
}

/// The rank number; first, second and third sit on a gold, silver and bronze
/// disc (the podium's plinth colours), the rest are plain.
private struct LeaderRankMark: View {
    let rank: Int
    @ScaledMetric(relativeTo: .subheadline) private var disc: CGFloat = 28

    var body: some View {
        if let fill = medal {
            Text("\(rank)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.dsText)
                .frame(width: disc, height: disc)
                .background(fill, in: Circle())
        } else {
            Text("\(rank)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.dsText2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
    }

    private var medal: Color? {
        switch rank {
        case 1: return Color.dsScoreFair.opacity(0.32)
        case 2: return Color.dsFill2
        case 3: return Color.dsScoreLow.opacity(0.28)
        default: return nil
        }
    }
}
