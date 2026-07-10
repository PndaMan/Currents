import SwiftUI

/// Serverless multiplayer hub: a friends/regional/global leaderboard and a
/// friend-code system, all on CloudKit's public database. Opt-in.
struct CommunityView: View {
    @StateObject private var svc = CommunityService.shared
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }

    @State private var name = ""
    @State private var scope: CommunityService.Scope = .friends
    @State private var metric: CommunityService.Metric = .weight
    @State private var rows: [CommunityService.LeaderRow] = []
    @State private var friends: [CommunityService.Profile] = []
    @State private var addCode = ""
    @State private var loading = false

    private var region: String {
        UserDefaults.standard.string(forKey: "communityRegion")
            ?? Locale.current.region?.identifier ?? "Global"
    }

    var body: some View {
        Group {
            if svc.joined { joinedBody } else { joinBody }
        }
        .navigationTitle("Community")
    }

    // MARK: Join

    private var joinBody: some View {
        Form {
            Section {
                Text("Compare your catches on a friends, regional, or global leaderboard — and add friends by code. Powered by iCloud, no account needed.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Your angler name") {
                TextField("e.g. \(svc.displayName)", text: $name)
            }
            Section {
                Button {
                    Task { await svc.join(name: name, region: region); await reload() }
                } label: {
                    Label("Join the Community", systemImage: "person.3.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
            } footer: {
                Text("Only your best catches (species, size, and broad region) are shared — never your exact spots. You can leave any time.")
            }
        }
    }

    // MARK: Joined

    private var joinedBody: some View {
        List {
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
                    Text("No entries yet — be the first to log a measured catch!")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        leaderRow(rank: i + 1, row)
                    }
                }
            }

            Section("Your friend code") {
                HStack {
                    Text(svc.friendCode).font(.title3.monospaced().bold()).foregroundStyle(CurrentsTheme.accent)
                    Spacer()
                    ShareLink(item: "Add me on Currents — my angler code is \(svc.friendCode) 🎣") {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                HStack {
                    TextField("Add friend by code", text: $addCode)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button("Add") {
                        Task { _ = await svc.addFriend(code: addCode); addCode = ""; await reload() }
                    }.disabled(addCode.count != 6)
                }
                ForEach(friends) { f in
                    HStack {
                        Image(systemName: "person.fill").foregroundStyle(CurrentsTheme.accent)
                        VStack(alignment: .leading) {
                            Text(f.name).font(.subheadline.bold())
                            Text("\(f.speciesCount) species · code \(f.id)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { svc.removeFriend(f.id); Task { await reload() } }
                    }
                }
            }

            Section {
                Button("Leave Community", role: .destructive) { svc.leave() }
            }
        }
        .task { await reload() }
        .onChange(of: scope) { _, _ in Task { await reloadBoard() } }
        .onChange(of: metric) { _, _ in Task { await reloadBoard() } }
    }

    private func leaderRow(rank: Int, _ row: CommunityService.LeaderRow) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)").font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(rank <= 3 ? .white : .secondary)
                .frame(width: 26, height: 26)
                .background(rank <= 3 ? CurrentsTheme.accent : Color.secondary.opacity(0.15), in: Circle())
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

    private func reload() async {
        friends = await svc.fetchFriendProfiles()
        await reloadBoard()
    }

    private func reloadBoard() async {
        loading = true
        rows = await svc.leaderboard(scope: scope, metric: metric, region: region)
        loading = false
    }
}
