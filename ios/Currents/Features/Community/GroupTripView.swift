import SwiftUI

// MARK: - Community section: my group trips

/// Lists the group trips you host or have joined (persisted locally, so they
/// show up reliably for BOTH host and joiner), plus an entry to start or join.
struct GroupTripsSection: View {
    @StateObject private var svc = CommunityService.shared

    var body: some View {
        Section("Group Trips") {
            ForEach(svc.myGroups) { g in
                NavigationLink {
                    GroupTripView(tripId: CommunityService.shared.tripId(forGroupCode: g.code),
                                  tripName: g.name, initialCode: g.code)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.3.fill")
                            .foregroundStyle(CurrentsTheme.accent)
                            .frame(width: 34, height: 34)
                            .background(CurrentsTheme.accent.opacity(0.15), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(g.name).font(.subheadline.bold())
                            Text(g.isHost ? "You're hosting · \(g.code)" : "Hosted by \(g.hostName) · \(g.code)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            NavigationLink {
                GroupTripSetupView()
            } label: {
                Label("Start or join a trip", systemImage: "plus.circle.fill")
                    .foregroundStyle(CurrentsTheme.accent)
            }
        }
    }
}

// MARK: - Setup: start (pick a trip) or join by code

/// Start a shared trip — based on a new or an existing/planned trip — or join
/// one by code. On join, a local trip is created and linked so your catches
/// sync to the group and you get your own session to track.
struct GroupTripSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    private var svc: CommunityService { .shared }

    @State private var trips: [Trip] = []
    @State private var baseTripId: String?          // nil = create a new trip
    @State private var newName = "Group Trip"
    @State private var joinCode = ""
    @State private var busy = false
    @State private var openedCode: String?

    var body: some View {
        Form {
            Section {
                Picker("Base on", selection: $baseTripId) {
                    Text("New trip").tag(nil as String?)
                    ForEach(trips) { t in
                        Text(tripLabel(t)).tag(t.id as String?)
                    }
                }
                if baseTripId == nil {
                    TextField("Trip name", text: $newName)
                }
                Button {
                    Task { await startTrip() }
                } label: {
                    HStack {
                        if busy { ProgressView() }
                        Label("Start & Invite", systemImage: "person.3.fill").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
                .disabled(busy || (baseTripId == nil && newName.trimmingCharacters(in: .whitespaces).isEmpty))
            } header: {
                Text("Start a shared trip")
            } footer: {
                Text("Pick one of your trips (incl. planned ones) or start a fresh one. Then invite friends — they'll see the same trip, members, and every catch as it's logged.")
            }

            Section {
                HStack {
                    TextField("6-letter code", text: $joinCode)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button("Join") { Task { await joinTrip() } }
                        .buttonStyle(.bordered)
                        .disabled(busy || joinCode.trimmingCharacters(in: .whitespaces).count != 6)
                }
            } header: {
                Text("Join a friend's trip")
            } footer: {
                Text("Enter the code they shared. You can also join instantly by tapping their invite in Notifications.")
            }
        }
        .navigationTitle("Group Trip")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: Binding(get: { openedCode.map { IdString(id: $0) } },
                                             set: { openedCode = $0?.id })) { c in
            GroupTripView(tripId: svc.tripId(forGroupCode: c.id), tripName: currentName(c.id), initialCode: c.id)
        }
        .task { trips = (try? appState.tripRepository.fetchAll()) ?? [] }
    }

    private struct IdString: Identifiable { let id: String }

    private func currentName(_ code: String) -> String {
        svc.myGroups.first(where: { $0.code == code })?.name ?? "Group Trip"
    }

    private func tripLabel(_ t: Trip) -> String {
        if t.plannedDate != nil { return "\(t.name) (planned)" }
        if t.endDate == nil { return "\(t.name) (active)" }
        return t.name
    }

    private func startTrip() async {
        busy = true; defer { busy = false }
        let tripId: String
        let name: String
        if let baseTripId, let t = trips.first(where: { $0.id == baseTripId }) {
            tripId = t.id; name = t.name
        } else {
            var t = Trip(name: newName.trimmingCharacters(in: .whitespaces), startDate: .now)
            try? appState.tripRepository.save(&t)
            tripId = t.id; name = t.name
        }
        if let code = await svc.createGroupTrip(name: name, tripId: tripId) {
            openedCode = code
        }
    }

    private func joinTrip() async {
        busy = true; defer { busy = false }
        let code = joinCode.uppercased().trimmingCharacters(in: .whitespaces)
        guard let trip = await svc.joinGroupTrip(code: code) else { return }
        // Give the joiner a local trip so their catches sync + they can track.
        if svc.tripId(forGroupCode: code) == nil {
            var t = Trip(name: trip.name, startDate: .now)
            try? appState.tripRepository.save(&t)
            svc.setGroupCode(code, forTripId: t.id)
        }
        openedCode = code
    }
}

// MARK: - Group trip detail

/// The shared trip hub: members, a live catch feed, friend invites, your own
/// session controls (start / pause GPS / log), and leave. Serverless (CloudKit
/// public DB) and identical for host and joiner.
struct GroupTripView: View {
    let tripId: String?
    let tripName: String

    @State private var code: String?
    @Environment(AppState.self) private var appState
    @State private var trip: CommunityService.GroupTrip?
    @State private var members: [CommunityService.GroupMember] = []
    @State private var feed: [CommunityService.GroupCatch] = []
    @State private var joinCode = ""
    @State private var busy = false
    @State private var confirming = false
    @State private var friendProfiles: [CommunityService.Profile] = []
    @State private var invited: Set<String> = []
    @State private var showAddByCode = false
    @State private var showingLog = false

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
        .navigationTitle(trip?.name ?? tripName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .fullScreenCover(isPresented: $showingLog, onDismiss: {
            Task { await publishLatestToGroup(); await refresh() }
        }) { LogCatchView() }
        .task {
            if code == nil, let tripId { code = service.groupCode(forTripId: tripId) }
            if autoJoin, let c = code {
                trip = await service.groupTrip(code: c)
                members = await service.groupMembers(code: c)
                let alreadyIn = members.contains { $0.id == service.friendCode }
                if alreadyIn {
                    ensureLinkedTrip(code: c, name: trip?.name ?? tripName)
                    await refresh()
                } else if trip != nil {
                    confirming = true
                }
            } else {
                if let c = code { ensureLinkedTrip(code: c, name: trip?.name ?? tripName) }
                await refresh()
            }
            await pollLoop()
        }
    }

    // Light polling so members + catches stay in sync while the view is open.
    private func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if code != nil, !confirming { await refresh() }
        }
    }

    // MARK: - Setup (no group yet — e.g. from a live session with no group)

    private var setup: some View {
        VStack(spacing: CurrentsTheme.paddingM) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 44)).foregroundStyle(CurrentsTheme.accent)
                .padding(.top, 12)
            Text("Fish together").font(.title2.bold())
            Text("Start a shared trip for “\(tripName)” and invite friends. Everyone sees the same members and every catch, live.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

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
                    _ = await service.joinGroupTrip(code: code)
                    ensureLinkedTrip(code: code, name: trip?.name ?? "Group Trip")
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
        // Header + your session controls.
        yourSessionCard(code)

        // Invite: pick friends (primary), share link / add-by-code (secondary).
        VStack(alignment: .leading, spacing: 12) {
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
            Button { showAddByCode.toggle() } label: {
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
            Button { Task { await refresh() } } label: {
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

    // MARK: - Your session card (start / pause GPS / log)

    @ViewBuilder private func yourSessionCard(_ code: String) -> some View {
        let tracker = appState.tripTracker
        let linkedId = service.tripId(forGroupCode: code)
        let isThisActive = tracker.isTracking && tracker.activeTrip?.id == linkedId && linkedId != nil

        VStack(alignment: .leading, spacing: 10) {
            Label("Your session", systemImage: "figure.fishing").font(.headline)

            if isThisActive {
                if tracker.manualPaused {
                    Label("GPS paused", systemImage: "pause.circle.fill").font(.caption).foregroundStyle(.orange)
                } else {
                    Label("Tracking live", systemImage: "dot.radiowaves.left.and.right").font(.caption).foregroundStyle(.green)
                }
                HStack(spacing: 10) {
                    Button {
                        if tracker.manualPaused { tracker.resumeTracking() } else { tracker.pauseTracking() }
                    } label: {
                        Label(tracker.manualPaused ? "Resume GPS" : "Pause GPS",
                              systemImage: tracker.manualPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
            } else if tracker.isTracking {
                Text("Another session is active. End it to track this trip, or just log catches below.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if linkedId != nil {
                Button {
                    if let linkedId, let lt = (try? appState.tripRepository.fetch(linkedId)) ?? nil {
                        _ = appState.tripTracker.startPlanned(lt)
                    }
                } label: {
                    Label("Start & track my session", systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).tint(CurrentsTheme.accent)
            }

            Button { showingLog = true } label: {
                Label("Log a Catch", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Helpers

    private func ensureLinkedTrip(code: String, name: String) {
        guard service.tripId(forGroupCode: code) == nil else { return }
        var t = Trip(name: name, startDate: .now)
        try? appState.tripRepository.save(&t)
        service.setGroupCode(code, forTripId: t.id)
    }

    /// After logging a catch from the group view, make sure it reaches the group
    /// feed even if no linked session was actively tracking.
    private func publishLatestToGroup() async {
        guard let code else { return }
        let recent = (try? appState.catchRepository.fetchAll(limit: 10)) ?? []
        guard let latest = recent.max(by: { $0.catchRecord.createdAt < $1.catchRecord.createdAt }),
              latest.catchRecord.createdAt.timeIntervalSinceNow > -180,
              latest.catchRecord.weightKg != nil || latest.catchRecord.lengthCm != nil else { return }
        await service.publishGroupCatch(
            species: latest.species?.commonName ?? "Fish",
            weightKg: latest.catchRecord.weightKg,
            lengthCm: latest.catchRecord.lengthCm,
            catchId: latest.catchRecord.id,
            groupCode: code)
    }

    private func refresh() async {
        guard let code else { return }
        trip = await service.groupTrip(code: code)
        members = await service.groupMembers(code: code)
        feed = await service.groupCatches(code: code)
        await loadFriendProfiles()
    }

    private func loadFriendProfiles() async {
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
