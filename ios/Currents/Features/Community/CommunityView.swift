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
            AnglerAvatar(image: loadAvatar(), size: 64)
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

    private func loadAvatar() -> UIImage? {
        guard let p = UserDefaults.standard.string(forKey: "communityAvatarPath") else { return nil }
        return UIImage(contentsOfFile: p)
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
    @State private var metric: CommunityService.Metric = .weight
    @State private var rows: [CommunityService.LeaderRow] = []
    @State private var loading = false

    var body: some View {
        Section("Leaderboard") {
            Picker("Scope", selection: $scope) {
                Text("Friends").tag(CommunityService.Scope.friends)
                Text("Region").tag(CommunityService.Scope.region)
                Text("Global").tag(CommunityService.Scope.global)
            }.pickerStyle(.segmented)
            Picker("By", selection: $metric) {
                Text("Heaviest").tag(CommunityService.Metric.weight)
                Text("Longest").tag(CommunityService.Metric.length)
            }.pickerStyle(.segmented)

            if loading {
                HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
            } else if rows.isEmpty {
                Text("No entries yet — log a measured catch to appear here.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(i < 3 ? .white : .secondary)
                            .frame(width: 26, height: 26)
                            .background(i < 3 ? CurrentsTheme.accent : Color.secondary.opacity(0.15), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.anglerName).font(.subheadline.bold())
                            Text("\(row.species) · \(row.region)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(metric == .weight
                             ? (row.weightKg.map { Units.weight(kg: $0, imperial: imperial) } ?? "—")
                             : (row.lengthCm.map { Units.length(cm: $0, imperial: imperial) } ?? "—"))
                            .font(.subheadline.bold()).foregroundStyle(CurrentsTheme.accent)
                    }
                }
            }
        }
        .task { await reload() }
        .onChange(of: scope) { _, _ in Task { await reload() } }
        .onChange(of: metric) { _, _ in Task { await reload() } }
    }

    private func reload() async {
        loading = true
        rows = await svc.leaderboard(scope: scope, metric: metric, region: region)
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
                ShareLink(item: "Add me on Currents — my angler code is \(svc.friendCode) 🎣") {
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
                if let p = UserDefaults.standard.string(forKey: "communityAvatarPath") { avatar = UIImage(contentsOfFile: p) }
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
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }

    var body: some View {
        List {
            if let p = profile {
                Section {
                    VStack(spacing: 8) {
                        AnglerAvatar(image: p.avatar, size: 84)
                        Text(p.name).font(.title3.bold())
                        if !p.bio.isEmpty { Text(p.bio).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                        if !p.homeWater.isEmpty {
                            Label(p.homeWater, systemImage: "water.waves").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Angler since \(p.memberSince.formatted(.dateTime.month().year()))")
                            .font(.caption2).foregroundStyle(.tertiary)
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
            } else {
                Section { HStack { ProgressView(); Text("Loading profile…").foregroundStyle(.secondary) } }
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
                Text("Spots are private by default. Turn this on to share your saved spots with just this friend — exact GPS stays off unless you allow it.")
            }
            .onChange(of: privacy) { _, new in
                svc.setPrivacy(new, for: code)
                Task {
                    let spots = (try? appState.spotRepository.fetchAll()) ?? []
                    await svc.republishSharedSpots(spots: spots)
                }
            }

            if !sharedSpots.isEmpty {
                Section("Spots they've shared with you") {
                    ForEach(sharedSpots) { s in
                        HStack {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(CurrentsTheme.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name).font(.subheadline.bold())
                                Text(s.coordinate == nil ? "\(s.type) · approximate area" : s.type)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if s.coordinate != nil { Image(systemName: "location.fill").font(.caption).foregroundStyle(CurrentsTheme.accent) }
                        }
                    }
                }
            }
        }
        .navigationTitle(profile?.name ?? "Angler")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            privacy = svc.privacy(for: code)
            profile = await svc.fetchProfile(code: code)
            sharedSpots = await svc.sharedSpots(fromFriend: code)
        }
    }
}
