import SwiftUI

/// The leaderboard page (pushed from the Crew tab). Scope toggles between
/// your friends and each of your crews; Most fish is a podium with ranked
/// rows, Heaviest and Longest are a photo-first 2-up gallery of catches.
struct LeaderboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    /// The local log, read once per visit on the database queue; metric
    /// and scope switches re-rank it without reading it again.
    @State private var localCatches: [CatchDetail]?

    var body: some View {
        // Without iCloud the Crew unavailable state shows and no load starts.
        CrewCloudGate { page }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHeader(title: "Leaderboard")
                Picker("Rank by", selection: $metric.haptic().animation(reduceMotion ? nil : DS.Motion.softSpring)) {
                    Text("Most fish").tag(CommunityService.Metric.count)
                    Text("Heaviest").tag(CommunityService.Metric.weight)
                    Text("Longest").tag(CommunityService.Metric.length)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s5)

                scopeChips
                    .padding(.top, DS.Space.s3)
                Text(scopeFooter)
                    .font(.footnote)
                    .foregroundStyle(Color.dsText2)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s2)

                Group {
                    if loading && rows.isEmpty {
                        FishLoader(message: "Reeling in the leaderboard…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, DS.Space.s8)
                    } else if rows.isEmpty {
                        emptyState
                    } else if metric == .count {
                        countBoard
                    } else {
                        catchGallery
                    }
                }
                .padding(.top, DS.Space.s4)
                .id(metric)
                .transition(.opacity)
            }
            .padding(.bottom, DS.Space.s6)
            .pageWidth()
        }
        .detailTint(nil)
        .eventPageTitle("Leaderboard")
        .safeAreaInset(edge: .bottom) {
            if let pinned = pinnedStanding {
                pinnedRow(pinned)
                    .padding(.horizontal, DS.gutter)
                    .padding(.bottom, DS.Space.s2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task { await reload() }
        .onChange(of: metric) { _, _ in Task { await reload() } }
        .onChange(of: scope) { _, _ in Task { await reload() } }
        .onChange(of: svc.revision) { _, _ in Task { await reload() } }
    }

    // MARK: Scope

    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                Chip("Friends", systemImage: "person.2.fill", isSelected: scope == "friends") {
                    withAnimation(DS.Motion.press) { scope = "friends" }
                }
                ForEach(svc.myCrews) { crew in
                    Chip(crew.name, isSelected: scope == crew.code) {
                        withAnimation(DS.Motion.press) { scope = crew.code }
                    }
                }
            }
            .padding(.horizontal, DS.gutter)
            .padding(.vertical, 2)
        }
        .scrollBounceBehavior(.basedOnSize, axes: [.horizontal])
    }

    private var scopeFooter: String {
        scope == "friends" ? "You and your friends."
        : "\(svc.crew(withCode: scope)?.name ?? "The crew")'s members."
    }

    private var emptyState: some View {
        ContentUnavailableView("No entries yet", systemImage: "trophy",
            description: Text(scope == "friends"
                ? "Add friends and log catches to fill the board."
                : "When the crew logs measured catches, the board fills up."))
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Space.s4)
    }

    // MARK: Most fish: podium and ranked rows

    private var countBoard: some View {
        VStack(spacing: 0) {
            EventPodium(entries: rows.prefix(3).map { row in
                EventPodiumEntry(id: row.friendCode,
                                 name: row.friendCode == svc.friendCode ? "You" : firstName(row.anglerName),
                                 value: "\(row.catchCount ?? 0)", unit: "fish",
                                 images: [avatars[row.friendCode]],
                                 isMe: false)
            }) { e in
                FriendProfileView(code: e.id)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()).dropFirst(3), id: \.element.id) { i, row in
                    let isSelf = row.friendCode == svc.friendCode
                    NavigationLink {
                        FriendProfileView(code: row.friendCode)
                    } label: {
                        EventRankRow(rank: i + 1,
                                     name: isSelf ? "You" : row.anglerName,
                                     value: value(row),
                                     images: [avatars[row.friendCode]],
                                     isMe: isSelf)
                    }
                    .buttonStyle(.dim)
                }
            }
            .padding(.top, DS.Space.s3)
        }
        .animation(reduceMotion ? nil : DS.Motion.softSpring, value: rows.map(\.id))
    }

    private func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    // MARK: Heaviest and longest: catch gallery

    /// Same 2-up photo-first cells as the Logbook, with the rank and the
    /// angler's name on the card.
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
                    .buttonStyle(.dim)
                } else {
                    LeaderCatchGalleryCell(row: row, rank: i + 1,
                                           value: value(row), isSelf: isSelf)
                }
            }
        }
        .padding(.horizontal, DS.gutter)
    }

    private func value(_ row: CommunityService.LeaderRow) -> String {
        switch metric {
        case .count: return "\(row.catchCount ?? 0) fish"
        case .weight: return row.weightKg.map { Units.weight(kg: $0, imperial: imperial) } ?? "Not weighed"
        case .length: return row.lengthCm.map { Units.length(cm: $0, imperial: imperial) } ?? "Not measured"
        }
    }

    // MARK: Pinned you

    /// Where you stand, pinned above the tab bar: your place in the list when
    /// you're on it, otherwise the standing the service worked out for you.
    private var pinnedStanding: (rank: Int, row: CommunityService.LeaderRow, onBoard: Bool)? {
        guard !rows.isEmpty else { return nil }
        if let i = rows.firstIndex(where: { $0.friendCode == svc.friendCode }) {
            return (i + 1, rows[i], true)
        }
        if let mine = myStanding { return (mine.rank, mine.row, false) }
        return nil
    }

    private func pinnedRow(_ mine: (rank: Int, row: CommunityService.LeaderRow, onBoard: Bool)) -> some View {
        HStack(spacing: DS.Space.s3) {
            Text("\(mine.rank)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.dsText2)
                .frame(minWidth: 22)
                .contentTransition(.numericText())
            AnglerAvatar(image: svc.myAvatar, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("You").font(.body.weight(.medium))
                Text(mine.rank == 1 ? "On top"
                     : mine.onBoard ? "\(eventOrdinal(mine.rank)) of \(rows.count)"
                     : eventOrdinal(mine.rank))
                    .font(.subheadline)
                    .foregroundStyle(Color.dsText2)
            }
            Spacer()
            Text(value(mine.row))
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
        }
        .foregroundStyle(Color.dsText)
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s3)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your place: \(eventOrdinal(mine.rank)), \(value(mine.row))")
    }

    // MARK: Data

    /// My own catches from the local database, so I always appear regardless
    /// of CloudKit sync state.
    private func myLocalRows() async -> [CommunityService.LeaderRow] {
        let local: [CatchDetail]
        if let cached = localCatches {
            local = cached
        } else {
            local = (try? await appState.catchRepository.fetchAllInBackground(limit: 100000)) ?? []
            localCatches = local
        }
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
        let myRows = await myLocalRows()
        let result = await svc.board(metric: metric, myRows: myRows, among: among)
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

/// A leaderboard catch as a gallery card: photo (or species art on its art
/// colour), rank top-left, value, species and angler under it.
private struct LeaderCatchGalleryCell: View {
    let row: CommunityService.LeaderRow
    let rank: Int
    let value: String
    let isSelf: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var scheme
    @State private var photo: UIImage?
    @State private var species: Species?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else if let species {
                        ZStack {
                            species.artTint.opacity(DS.thumbTintOpacity(scheme))
                            SpeciesArtworkView(species: species, caught: true, size: 72)
                        }
                    } else {
                        ZStack {
                            Color.dsFill
                            Image(systemName: "fish")
                                .font(.title)
                                .foregroundStyle(Color.dsText3)
                        }
                    }
                }
                .overlay(alignment: .topLeading) {
                    Text("\(rank)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(rank == 2 ? Color.dsText : rank <= 3 ? Color.black : Color.white)
                        .frame(minWidth: 28, minHeight: 28)
                        .background(rank == 1 ? Color.dsScoreFair
                                    : rank == 2 ? Color.dsFill2 // ui-lint: allow, silver medal
                                    : rank == 3 ? Color.dsScoreLow
                                    : Color.black.opacity(0.5),
                                    in: Circle())
                        .padding(DS.Space.s2)
                        .accessibilityHidden(true)
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
                .overlay {
                    if isSelf {
                        RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous)
                            .strokeBorder(DS.accent, lineWidth: 2)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.dsText)
                Text(row.species)
                    .font(.subheadline)
                    .foregroundStyle(Color.dsText)
                    .lineLimit(1)
                Text(isSelf ? "You" : row.anglerName)
                    .font(.footnote)
                    .foregroundStyle(Color.dsText2)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(eventOrdinal(rank)), \(value), \(row.species), \(isSelf ? "you" : row.anglerName)")
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
