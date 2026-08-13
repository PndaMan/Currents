import SwiftUI

/// The leaderboard, promoted to its own screen (toolbar trophy on Community).
/// Scope toggles between your friends and each of your crews; Most Fish is an
/// avatar podium + grid, Heaviest/Longest are the same photo-first 2-up
/// gallery as the Catches tab.
struct LeaderboardView: View {
    @Environment(AppState.self) private var appState
    @StateObject private var svc = CommunityService.shared
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

    var body: some View {
        ScrollView {
            VStack(spacing: CurrentsTheme.paddingM) {
                scopeChips
                Picker("By", selection: $metric) {
                    Text("Most Fish").tag(CommunityService.Metric.count)
                    Text("Heaviest").tag(CommunityService.Metric.weight)
                    Text("Longest").tag(CommunityService.Metric.length)
                }
                .pickerStyle(.segmented)

                if loading && rows.isEmpty {
                    FishLoader(message: "Reeling in the leaderboard…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                } else if rows.isEmpty {
                    emptyState
                } else if metric == .count {
                    podium
                    if rows.count > 3 { runnersGrid }
                } else {
                    catchGallery
                }

                if let mine = myStanding,
                   !rows.contains(where: { $0.friendCode == svc.friendCode }) {
                    myStandingFooter(mine)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .onChange(of: metric) { _, _ in Task { await reload() } }
        .onChange(of: scope) { _, _ in Task { await reload() } }
        .onChange(of: svc.revision) { _, _ in Task { await reload() } }
        .sensoryFeedback(.selection, trigger: metric)
    }

    // MARK: Scope

    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "Friends", isSelected: scope == "friends",
                           systemImage: "person.2.fill") {
                    withAnimation(.easeInOut(duration: 0.15)) { scope = "friends" }
                }
                ForEach(svc.myCrews) { crew in
                    FilterChip(title: "\(crew.emoji) \(crew.name)",
                               isSelected: scope == crew.code) {
                        withAnimation(.easeInOut(duration: 0.15)) { scope = crew.code }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollBounceBehavior(.basedOnSize, axes: [.vertical, .horizontal])
    }

    private var scopeFooter: String {
        scope == "friends" ? "Among you and your friends only."
        : "Among \(svc.crew(withCode: scope)?.name ?? "the crew")'s members."
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ContentUnavailableView("No entries yet", systemImage: "trophy",
                description: Text(scope == "friends"
                    ? "Add friends and log catches to fill the board."
                    : "When the crew logs measured catches, the board fills up."))
            if scope == "friends" {
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
            }
        }
        .padding(.top, 20)
    }

    // MARK: Most Fish — podium + avatar grid

    /// Top three as a proper podium: champion centred and biggest, gold ring
    /// and crown; silver and bronze flanking.
    private var podium: some View {
        let top = Array(rows.prefix(3))
        return HStack(alignment: .bottom, spacing: 18) {
            if top.count > 1 { podiumSpot(top[1], rank: 2, size: 64) }
            if !top.isEmpty { podiumSpot(top[0], rank: 1, size: 92) }
            if top.count > 2 { podiumSpot(top[2], rank: 3, size: 64) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func podiumSpot(_ row: CommunityService.LeaderRow, rank: Int, size: CGFloat) -> some View {
        let ring: Color = rank == 1 ? .yellow : rank == 2 ? Color(white: 0.75) : .orange
        let isSelf = row.friendCode == svc.friendCode
        return NavigationLink {
            FriendProfileView(code: row.friendCode)
        } label: {
            VStack(spacing: 5) {
                if rank == 1 {
                    Text("👑").font(.title3)
                        .shadow(color: .yellow.opacity(0.6), radius: 6)
                }
                ZStack(alignment: .bottom) {
                    // Ring drawn ON the avatar's edge (not a larger circle
                    // behind it) so the photo fills flush to the ring with no
                    // background gap showing through.
                    AnglerAvatar(image: avatars[row.friendCode], size: size)
                        .overlay(Circle().strokeBorder(ring, lineWidth: rank == 1 ? 3.5 : 2.5))
                        .shadow(color: ring.opacity(0.45), radius: rank == 1 ? 10 : 5)
                    Text(rank == 1 ? "🥇" : rank == 2 ? "🥈" : "🥉")
                        .font(.system(size: rank == 1 ? 22 : 17))
                        .offset(y: 10)
                }
                .padding(.bottom, 6)
                Text(isSelf ? "You" : row.anglerName)
                    .font(rank == 1 ? .subheadline.bold() : .caption.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(row.catchCount ?? 0) fish")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(CurrentsTheme.accent)
            }
            .frame(maxWidth: size + 40)
        }
        .buttonStyle(.plain)
    }

    /// Everyone from 4th place as tappable avatar cards — the board reads as
    /// faces, not a table.
    private var runnersGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
            ForEach(Array(rows.dropFirst(3).enumerated()), id: \.element.id) { i, row in
                let isSelf = row.friendCode == svc.friendCode
                NavigationLink {
                    FriendProfileView(code: row.friendCode)
                } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .topLeading) {
                            AnglerAvatar(image: avatars[row.friendCode], size: 54)
                            Text("\(i + 4)")
                                .font(.system(size: 10, weight: .heavy).monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.secondary.opacity(0.85), in: Circle())
                                .offset(x: -6, y: -4)
                        }
                        Text(isSelf ? "You" : row.anglerName)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(row.catchCount ?? 0) fish")
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(CurrentsTheme.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(isSelf ? CurrentsTheme.accent.opacity(0.10)
                                       : Color.clear)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Heaviest / Longest — catch gallery

    /// Same 2-up photo-first cells as the Catches tab, with the rank medal
    /// and the angler's name on the card.
    private var catchGallery: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)],
                  spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                let isSelf = row.friendCode == svc.friendCode
                let canOpen = isSelf || (catchAccess[row.friendCode] ?? false)
                if canOpen {
                    NavigationLink {
                        CommunityCatchDetailView(row: row)
                    } label: {
                        LeaderCatchGalleryCell(row: row, rank: i + 1,
                                               value: value(row), isSelf: isSelf)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    LeaderCatchGalleryCell(row: row, rank: i + 1,
                                           value: value(row), isSelf: isSelf)
                }
            }
        }
    }

    private func value(_ row: CommunityService.LeaderRow) -> String {
        switch metric {
        case .count: return "\(row.catchCount ?? 0) fish"
        case .weight: return row.weightKg.map { Units.weight(kg: $0, imperial: imperial) } ?? "—"
        case .length: return row.lengthCm.map { Units.length(cm: $0, imperial: imperial) } ?? "—"
        }
    }

    private func myStandingFooter(_ mine: (rank: Int, row: CommunityService.LeaderRow)) -> some View {
        HStack(spacing: 10) {
            Text("#\(mine.rank)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.secondary)
            AnglerAvatar(image: svc.myAvatar, size: 30)
            Text("You").font(.subheadline.bold())
            Spacer()
            Text(value(mine.row))
                .font(.subheadline.bold())
                .foregroundStyle(CurrentsTheme.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(CurrentsTheme.accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Data

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
        rows = result.rows
        myStanding = result.mine
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

/// A leaderboard catch as a gallery card: photo (or species art), rank medal
/// top-left, value + species + angler on the bottom scrim.
private struct LeaderCatchGalleryCell: View {
    let row: CommunityService.LeaderRow
    let rank: Int
    let value: String
    let isSelf: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.displayScale) private var displayScale
    @State private var photo: UIImage?
    @State private var species: Species?

    var body: some View {
        Color.clear
            .frame(height: 190)
            .overlay {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    ZStack {
                        CurrentsTheme.accent.opacity(0.10)
                        if let species {
                            SpeciesArtworkView(species: species, caught: true, size: 64)
                        } else {
                            Image(systemName: "fish.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(CurrentsTheme.accent.opacity(0.5))
                        }
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                Text(rank == 1 ? "🥇" : rank == 2 ? "🥈" : rank == 3 ? "🥉" : "#\(rank)")
                    .font(rank <= 3 ? .title3 : .caption.bold())
                    .foregroundStyle(.white)
                    .padding(rank <= 3 ? 4 : 7)
                    .background(rank <= 3 ? AnyShapeStyle(.clear)
                                          : AnyShapeStyle(.black.opacity(0.45)),
                                in: Circle())
                    .padding(6)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(value)
                        .font(.footnote.bold())
                    Text("\(row.species) · \(isSelf ? "You" : row.anglerName)")
                        .font(.system(size: 10))
                        .opacity(0.85)
                        .lineLimit(1)
                }
                .foregroundStyle(photo == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if photo != nil {
                        LinearGradient(colors: [.clear, .black.opacity(0.72)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if isSelf {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(CurrentsTheme.accent.opacity(0.7), lineWidth: 1.5)
                }
            }
            .task(id: row.id) {
                if let path = row.localPhotoPath {
                    let px = 240 * displayScale
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
