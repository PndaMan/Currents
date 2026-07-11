import SwiftUI

/// Shared "group trip" hub — invite friends by link, see who's in, and watch
/// everyone's catches roll in live. Serverless (CloudKit public DB); works from
/// an active session, a finished session, or a join link.
struct GroupTripView: View {
    /// Local trip to keep linked to the group (nil for a standalone join).
    let tripId: String?
    let tripName: String

    @State private var code: String?
    @State private var trip: CommunityService.GroupTrip?
    @State private var members: [CommunityService.GroupMember] = []
    @State private var feed: [CommunityService.GroupCatch] = []
    @State private var joinCode = ""
    @State private var busy = false
    @State private var confirming = false
    @State private var friendProfiles: [CommunityService.Profile] = []
    @State private var invited: Set<String> = []
    @State private var showAddByCode = false

    private let autoJoin: Bool
    private var service: CommunityService { .shared }

    init(tripId: String?, tripName: String, initialCode: String? = nil) {
        self.tripId = tripId
        self.tripName = tripName
        self.autoJoin = initialCode != nil
        _code = State(initialValue: initialCode)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: CurrentsTheme.paddingM) {
                if confirming, let code {
                    confirmJoin(code)
                } else if let code {
                    activeGroup(code)
                } else {
                    setup
                }
            }
            .padding()
        }
        .navigationTitle("Group Trip")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if code == nil, let tripId { code = service.groupCode(forTripId: tripId) }
            // Arrived via an invite link — show a confirm gate (with trip info)
            // unless already a member, rather than silently joining.
            if autoJoin, let c = code {
                trip = await service.groupTrip(code: c)
                members = await service.groupMembers(code: c)
                let alreadyIn = members.contains { $0.id == service.friendCode }
                if alreadyIn {
                    await refresh()
                } else if trip != nil {
                    confirming = true
                }
            } else {
                await refresh()
            }
        }
    }

    // MARK: - Setup (no group yet)

    private var setup: some View {
        VStack(spacing: CurrentsTheme.paddingM) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 44)).foregroundStyle(CurrentsTheme.accent)
                .padding(.top, 12)
            Text("Fish together")
                .font(.title2.bold())
            Text("Start a shared trip and invite friends by link. Everyone's catches show up here in real time — no account, no server.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    busy = true
                    if let new = await service.createGroupTrip(name: tripName, tripId: tripId ?? UUID().uuidString) {
                        code = new
                        await refresh()
                    }
                    busy = false
                }
            } label: {
                HStack {
                    if busy { ProgressView().tint(.white) }
                    Label("Start a shared trip", systemImage: "plus.circle.fill")
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
            .disabled(busy)

            VStack(alignment: .leading, spacing: 8) {
                Text("Join a friend's trip").font(.headline)
                HStack {
                    TextField("6-letter code", text: $joinCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Button("Join") {
                        Task {
                            busy = true
                            if let t = await service.joinGroupTrip(code: joinCode, tripId: tripId) {
                                code = t.id
                                await refresh()
                            }
                            busy = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(joinCode.trimmingCharacters(in: .whitespaces).count != 6 || busy)
                }
            }
            .glassCard()
        }
    }

    // MARK: - Join confirmation (from an invite link)

    @ViewBuilder private func confirmJoin(_ code: String) -> some View {
        VStack(spacing: CurrentsTheme.paddingM) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 44)).foregroundStyle(CurrentsTheme.accent)
                .padding(.top, 12)
            Text(trip?.name ?? "Group Trip").font(.title2.bold())
            if let host = trip?.hostName {
                Text("Hosted by \(host)").font(.subheadline).foregroundStyle(.secondary)
            }
            Label("\(members.count) \(members.count == 1 ? "angler" : "anglers") already in",
                  systemImage: "person.2.fill")
                .font(.caption).foregroundStyle(.secondary)
            Text("Join to share your catches live with the group and see everyone else's. Your saved spots and exact locations stay private.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    busy = true
                    _ = await service.joinGroupTrip(code: code, tripId: tripId)
                    confirming = false
                    busy = false
                    await refresh()
                }
            } label: {
                HStack {
                    if busy { ProgressView().tint(.white) }
                    Label("Join Trip", systemImage: "person.fill.badge.plus")
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
            .disabled(busy)
        }
        .glassCard()
    }

    // MARK: - Active group

    @ViewBuilder private func activeGroup(_ code: String) -> some View {
        // Invite: pick friends (primary), share link / add-by-code (secondary).
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(trip?.name ?? tripName).font(.title3.bold())
                Spacer()
                if trip?.isHost == true {
                    Text("Host").font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(CurrentsTheme.accent.opacity(0.2), in: Capsule())
                }
            }

            let memberCodes = Set(members.map(\.id))
            let invitable = friendProfiles.filter { !memberCodes.contains($0.id) }

            Text("Invite friends").font(.headline)
            if friendProfiles.isEmpty {
                Text("Add friends in Community to invite them with one tap — or share the code below.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if invitable.isEmpty {
                Text("All your friends are already in this trip 🎣")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(invitable) { f in
                    HStack(spacing: 10) {
                        AnglerAvatar(image: f.avatar, size: 34)
                        Text(f.name).font(.subheadline)
                        Spacer()
                        if invited.contains(f.id) {
                            Label("Invited", systemImage: "checkmark.circle.fill")
                                .font(.caption.bold()).foregroundStyle(.green)
                        } else {
                            Button {
                                invited.insert(f.id)
                                Task {
                                    await service.inviteFriend(f.id, toGroup: code,
                                                               tripName: trip?.name ?? tripName)
                                }
                            } label: {
                                Text("Invite").font(.caption.bold())
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(CurrentsTheme.accent, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Divider().padding(.vertical, 2)

            // Secondary: invite code + share link + add-by-code.
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Invite code").font(.caption2).foregroundStyle(.secondary)
                    Text(code).font(.system(.title3, design: .monospaced).bold())
                        .tracking(3).foregroundStyle(CurrentsTheme.accent)
                }
                Spacer()
                ShareLink(item: service.inviteMessage(forGroup: code, tripName: trip?.name ?? tripName)) {
                    Label("Share link", systemImage: "square.and.arrow.up").font(.caption.bold())
                }
            }
            Button {
                showAddByCode.toggle()
            } label: {
                Label("Invite by angler code", systemImage: "number").font(.caption)
            }
            .buttonStyle(.borderless)
            if showAddByCode {
                HStack {
                    TextField("Friend's 6-char code", text: $joinCode)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Button("Invite") {
                        let c = joinCode.uppercased().trimmingCharacters(in: .whitespaces)
                        joinCode = ""
                        Task { await service.inviteFriend(c, toGroup: code, tripName: trip?.name ?? tripName) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(joinCode.trimmingCharacters(in: .whitespaces).count != 6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()

        // Members
        VStack(alignment: .leading, spacing: 10) {
            Label("\(members.count) \(members.count == 1 ? "angler" : "anglers")", systemImage: "person.2.fill")
                .font(.headline)
            ForEach(members) { m in
                HStack(spacing: 10) {
                    initials(m.name)
                    Text(m.name).font(.subheadline)
                    if m.id == trip?.hostCode {
                        Text("Host").font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(CurrentsTheme.accent.opacity(0.2), in: Capsule())
                    }
                    Spacer()
                    if m.id == service.friendCode {
                        Text("You").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()

        // Live catch feed
        VStack(alignment: .leading, spacing: 10) {
            Label("Group catches", systemImage: "fish.fill").font(.headline)
            if feed.isEmpty {
                Text("No catches yet — first fish on the board!")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(feed) { c in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.species).font(.subheadline.bold())
                            Text("\(c.anglerName) · \(c.date.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(sizeLabel(c)).font(.subheadline.bold()).foregroundStyle(CurrentsTheme.accent)
                    }
                    .padding(.vertical, 2)
                }
            }
            Button {
                Task { await refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise").font(.caption)
            }
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()

        Button(role: .destructive) {
            Task {
                await service.leaveGroupTrip(code: code, tripId: tripId)
                self.code = nil
                trip = nil; members = []; feed = []
            }
        } label: {
            Label("Leave group", systemImage: "person.fill.xmark").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Helpers

    private func refresh() async {
        guard let code else { return }
        trip = await service.groupTrip(code: code)
        members = await service.groupMembers(code: code)
        feed = await service.groupCatches(code: code)
        await loadFriendProfiles()
    }

    private func loadFriendProfiles() async {
        // Always surface every friend so you can invite them directly — even if
        // their public profile can't be fetched right now (offline / not yet in
        // CloudKit), fall back to a minimal profile keyed by their code.
        var result: [CommunityService.Profile] = []
        for c in service.friends {
            if let p = await service.fetchProfile(code: c) {
                result.append(p)
            } else {
                result.append(CommunityService.Profile(
                    id: c, name: "Angler \(c)", bio: "", region: "", homeWater: "",
                    avatar: nil, memberSince: .now, totalCatches: 0, speciesCount: 0,
                    bestWeightKg: 0, bestLengthCm: 0, favoriteSpecies: ""))
            }
        }
        friendProfiles = result
    }

    private func initials(_ name: String) -> some View {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
        return Text(letters.isEmpty ? "🎣" : letters.uppercased())
            .font(.caption.bold()).foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(CurrentsTheme.accent.gradient, in: Circle())
    }

    private func sizeLabel(_ c: CommunityService.GroupCatch) -> String {
        if let w = c.weightKg { return Units.weight(kg: w) }
        if let l = c.lengthCm { return Units.length(cm: l) }
        return "—"
    }
}
