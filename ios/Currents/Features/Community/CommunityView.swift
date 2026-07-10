import SwiftUI
import PhotosUI
import MapKit

/// Community hub: your angler profile, a friends/regional/global leaderboard,
/// and a friend system with in-depth profiles and per-friend spot privacy.
struct CommunityView: View {
    @Environment(AppState.self) private var appState
    @StateObject private var svc = CommunityService.shared

    @State private var name = ""
    @State private var showingEdit = false

    private var region: String { svc.myRegion }

    var body: some View {
        Group {
            if svc.joined { joinedBody } else { joinBody }
        }
        .navigationTitle("Community")
        .sheet(isPresented: $showingEdit) {
            ProfileEditView(stats: computeStats())
        }
        .task { await syncCatches() }
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
             caughtAt: $0.catchRecord.caughtAt)
        }
        await svc.syncAllCatches(details)
    }

    // MARK: Join gate

    private var joinBody: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 44)).foregroundStyle(CurrentsTheme.accent)
                    Text("Fish with friends").font(.title3.bold())
                    Text("A friends, regional, and global leaderboard, in-depth angler profiles, and spots you can share privately — one friend at a time. Powered by iCloud; no account or password needed.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            Section("Your angler name") { TextField("Name", text: $name) }
            Section {
                Button {
                    Task { await svc.join(name: name, region: region); await svc.updateProfile(name: svc.myName, bio: svc.myBio, homeWater: svc.myHomeWater, region: region, avatar: nil, stats: computeStats()) }
                } label: {
                    Label("Join the Community", systemImage: "person.3.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
            } footer: {
                Text("Your spots stay private. Only your best catches (species, size, broad region) appear on the leaderboard — never coordinates.")
            }
        }
    }

    // MARK: Joined

    private var joinedBody: some View {
        List {
            Section {
                Button { showingEdit = true } label: { MyProfileHeader(stats: computeStats()) }
                    .buttonStyle(.plain)
            }
            TripInvitesSection()
            LeaderboardSection(region: region)
            Section("Group Trips") {
                NavigationLink {
                    GroupTripView(tripId: nil, tripName: "Group Trip")
                } label: {
                    Label("Start or Join a Trip", systemImage: "person.3.fill")
                }
            }
            FriendsSection()
            Section {
                Button("Leave Community", role: .destructive) { svc.leave() }
            }
        }
    }

    // MARK: Stats from local data

    private func computeStats() -> CommunityService.MyStats {
        let catches = (try? appState.catchRepository.fetchAll(limit: 100000)) ?? []
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

// MARK: - Leaderboard

private struct LeaderboardSection: View {
    let region: String
    @StateObject private var svc = CommunityService.shared
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }

    @State private var scope: CommunityService.Scope = .friends
    @State private var metric: CommunityService.Metric = .count
    @State private var rows: [CommunityService.LeaderRow] = []
    @State private var myStanding: (rank: Int, row: CommunityService.LeaderRow)?
    @State private var loading = false

    var body: some View {
        Section("Leaderboard") {
            Picker("Scope", selection: $scope) {
                Text("Friends").tag(CommunityService.Scope.friends)
                Text("Region").tag(CommunityService.Scope.region)
                Text("Global").tag(CommunityService.Scope.global)
            }.pickerStyle(.segmented)
            Picker("By", selection: $metric) {
                Text("Most Fish").tag(CommunityService.Metric.count)
                Text("Heaviest").tag(CommunityService.Metric.weight)
                Text("Longest").tag(CommunityService.Metric.length)
            }.pickerStyle(.segmented)

            if loading {
                HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
            } else if rows.isEmpty {
                Text("No entries yet — log a catch to appear here.")
                    .font(.caption).foregroundStyle(.secondary)
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
        }
        .task { await reload() }
        .onChange(of: scope) { _, _ in Task { await reload() } }
        .onChange(of: metric) { _, _ in Task { await reload() } }
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
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(isSelf ? "You" : row.anglerName).font(.subheadline.bold())
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

    private func reload() async {
        loading = true
        let result = await svc.board(scope: scope, metric: metric, region: region)
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

    var body: some View {
        Section("Friends") {
            HStack {
                Text("Your code")
                Spacer()
                Text(svc.friendCode).font(.body.monospaced().bold()).foregroundStyle(CurrentsTheme.accent)
                ShareLink(item: svc.friendInviteMessage()) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            HStack {
                TextField("Add friend by 6-char code", text: $addCode)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                Button("Add") { Task { _ = await svc.addFriend(code: addCode); addCode = ""; await reload() } }
                    .disabled(addCode.trimmingCharacters(in: .whitespaces).count != 6)
            }
            if friends.isEmpty {
                Text("Add friends by code to compare catches and share spots privately.")
                    .font(.caption).foregroundStyle(.secondary)
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
                    Button("Remove", role: .destructive) { svc.removeFriend(f.id); Task { await reload() } }
                }
            }
        }
        .task { await reload() }
    }

    private func privacyNickname(_ f: CommunityService.Profile) -> String {
        let nick = svc.privacy(for: f.id).nickname
        return nick.isEmpty ? f.name : "\(nick) (\(f.name))"
    }

    private func reload() async {
        var result: [CommunityService.Profile] = []
        for code in svc.friends {
            if let p = await svc.fetchProfile(code: code) { result.append(p) }
        }
        friends = result
    }
}

// MARK: - Trip invites (accept a friend's group-trip invite)

private struct TripInvitesSection: View {
    @StateObject private var svc = CommunityService.shared
    @State private var invites: [CommunityService.TripInvite] = []
    @State private var opened: OpenedGroup?

    struct OpenedGroup: Identifiable { let id: String }

    var body: some View {
        Group {
            if !invites.isEmpty {
                Section("Trip Invites") {
                    ForEach(invites) { inv in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: "person.3.fill")
                                    .foregroundStyle(CurrentsTheme.accent)
                                    .frame(width: 34, height: 34)
                                    .background(CurrentsTheme.accent.opacity(0.15), in: Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(inv.tripName).font(.subheadline.bold())
                                    Text("Invited by \(inv.fromName)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            HStack(spacing: 10) {
                                Button {
                                    Task { await svc.acceptInvite(inv); opened = OpenedGroup(id: inv.groupCode); await load() }
                                } label: {
                                    Label("Join Trip", systemImage: "checkmark").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
                                Button(role: .destructive) {
                                    Task { await svc.declineInvite(inv); await load() }
                                } label: {
                                    Label("Decline", systemImage: "xmark").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .task { await load() }
        .sheet(item: $opened) { g in
            NavigationStack {
                GroupTripView(tripId: nil, tripName: "Group Trip", initialCode: g.id)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { opened = nil } }
                    }
            }
        }
    }

    private func load() async { invites = await svc.refreshTripInvites() }
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
    @State private var sharedSpots: [CommunityService.SharedSpot] = []
    @State private var catches: [CommunityService.LeaderRow] = []
    @State private var catchAccess = false
    @State private var copiedSpots: Set<String> = []
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
                Section { HStack { ProgressView(); Text("Loading profile…").foregroundStyle(.secondary) } }
            }

            // Their catches — friends-only, and only if they've shared them.
            Section("Catches") {
                if !catchAccess {
                    Label("This angler hasn't shared their catch history with you.",
                          systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.secondary)
                } else if catches.isEmpty {
                    Text("No catches shared yet.").font(.caption).foregroundStyle(.secondary)
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
                Toggle("Share my catches with them", isOn: $privacy.shareCatches)
                Toggle("Share my spots with them", isOn: $privacy.shareSpots)
                if privacy.shareSpots {
                    Toggle("Include exact spot locations", isOn: $privacy.shareExactLocations)
                }
            } header: {
                Text("What you share with \(profile?.name ?? "this friend")")
            } footer: {
                Text("Spots are private by default. Turn this on to share your saved spots with just this friend — exact GPS stays off unless you allow it. Your catch history is friends-only, per friend.")
            }
            .onChange(of: privacy) { _, new in
                svc.setPrivacy(new, for: code)
                Task {
                    let spots = (try? appState.spotRepository.fetchAll()) ?? []
                    await svc.republishSharedSpots(spots: spots)
                }
            }
        }
        .navigationTitle(profile?.name ?? "Angler")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            privacy = svc.privacy(for: code)
            profile = await svc.fetchProfile(code: code)
            sharedSpots = await svc.sharedSpots(fromFriend: code)
            catchAccess = await svc.hasCatchAccess(to: code)
            if catchAccess { catches = await svc.anglerCatches(code: code) }
        }
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
        HStack {
            Image(systemName: "fish.fill").foregroundStyle(CurrentsTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.species).font(.subheadline.bold())
                Text(c.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(c.weightKg.map { Units.weight(kg: $0, imperial: imperial) }
                 ?? c.lengthCm.map { Units.length(cm: $0, imperial: imperial) } ?? "")
                .font(.caption.bold()).foregroundStyle(CurrentsTheme.accent)
        }
    }

    @ViewBuilder private func sharedSpotRow(_ s: CommunityService.SharedSpot) -> some View {
        HStack {
            Image(systemName: "mappin.circle.fill").foregroundStyle(CurrentsTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).font(.subheadline.bold())
                Text(s.coordinate == nil ? "\(s.type) · approximate area" : s.type)
                    .font(.caption2).foregroundStyle(.secondary)
                if !s.notes.isEmpty {
                    Text(s.notes).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                }
            }
            Spacer()
            if s.coordinate != nil {
                if copiedSpots.contains(s.id) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button {
                        copySpot(s)
                    } label: {
                        Image(systemName: "square.and.arrow.down").foregroundStyle(CurrentsTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func copySpot(_ s: CommunityService.SharedSpot) {
        guard let coord = s.coordinate else { return }
        var spot = Spot(
            name: s.name,
            latitude: coord.latitude,
            longitude: coord.longitude,
            notes: s.notes.isEmpty ? "Shared by \(profile?.name ?? "a friend")" : s.notes,
            spotType: Spot.SpotType(rawValue: s.type) ?? .general
        )
        try? appState.spotRepository.save(&spot)
        copiedSpots.insert(s.id)
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

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Group {
                    if let species {
                        SpeciesArtworkView(species: species, caught: true, size: 150)
                    } else {
                        Image(systemName: "fish.fill")
                            .font(.system(size: 84)).foregroundStyle(CurrentsTheme.accent.opacity(0.5))
                    }
                }
                .frame(height: 160)

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

                if !row.region.isEmpty {
                    Label(row.region, systemImage: "globe").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Catch")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let all = (try? appState.speciesRepository.fetchAll()) ?? []
            species = all.first { $0.commonName.localizedCaseInsensitiveCompare(row.species) == .orderedSame }
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

// MARK: - Add-friend confirmation (from an invite link)

/// Shown when someone taps a `currents://friend/<CODE>` link — previews the
/// angler's profile and lets you confirm before adding, rather than silently
/// adding a stranger.
struct AddFriendConfirmView: View {
    let code: String
    @Environment(\.dismiss) private var dismiss
    private var svc: CommunityService { .shared }

    @State private var profile: CommunityService.Profile?
    @State private var loading = true
    @State private var added = false
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }

    private var isFriend: Bool { svc.friends.contains(code.uppercased()) || added }

    var body: some View {
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
                        Label("Added to your friends", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            Task { _ = await svc.addFriend(code: code); added = true }
                        } label: {
                            Label("Add Friend", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
                    }
                } footer: {
                    Text("They'll appear in your Friends list and on the friends leaderboard. Your spots stay private unless you choose to share them, per friend.")
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
        .navigationTitle("Add Friend")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isFriend ? "Done" : "Close") { dismiss() }
            }
        }
        .task {
            profile = await svc.fetchProfile(code: code)
            loading = false
        }
    }
}
