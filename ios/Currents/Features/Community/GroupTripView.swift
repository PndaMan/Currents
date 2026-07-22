import SwiftUI
import CoreLocation
import UIKit

// MARK: - Community section: my group trips

/// Lists the group trips you host or have joined (persisted locally, so they
/// show up reliably for BOTH host and joiner), plus an entry to start or join.
struct GroupTripsSection: View {
    @StateObject private var svc = CommunityService.shared
    @Environment(AppState.self) private var appState

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
                            HStack(spacing: 6) {
                                Text(g.name).font(.subheadline.bold())
                                if g.endedAt != nil {
                                    Text("Ended").font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.2), in: Capsule())
                                }
                            }
                            Text(g.isHost ? "You're hosting · \(g.code)" : "Hosted by \(g.hostName) · \(g.code)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button("Remove", role: .destructive) {
                        Task { await leaveGroupAndCleanup(code: g.code, tripId: nil, appState: appState) }
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

/// Leave a group trip and, if the local session it was linked to never got past
/// the planned stage (never started, so nothing was tracked or logged), delete
/// that planned session too — leaving a group you only planned shouldn't leave
/// an orphaned plan behind.
@MainActor
func leaveGroupAndCleanup(code: String, tripId: String?, appState: AppState) async {
    let svc = CommunityService.shared
    // Resolve the linked trip BEFORE leaving (leaving forgets the mapping).
    let linked = tripId ?? svc.tripId(forGroupCode: code)
    await svc.leaveGroupTrip(code: code, tripId: linked)
    if let linked,
       let trip = (try? appState.tripRepository.fetch(linked)) ?? nil,
       trip.isPlanned {
        try? appState.tripRepository.delete(trip)
    }
    Haptics.warning()
    ToastCenter.shared.show("Left the trip", style: .info, haptic: false)
}

// MARK: - Setup: start (pick a trip) or join by code

/// Start a shared trip — based on a new or an existing/planned trip — or join
/// one by code. On join, a local trip is created and linked so your catches
/// sync to the group and you get your own session to track.
struct GroupTripSetupView: View {
    /// When launched from a Crew, trips created here are tied to that crew.
    var crewCode: String? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    private var svc: CommunityService { .shared }

    @State private var trips: [Trip] = []
    @State private var joinCode = ""
    @State private var busy = false
    @State private var openedCode: String?
    @State private var showingPlanner = false
    @State private var editingPlan: Trip?
    @State private var showingStartNow = false
    @State private var newTripName = ""

    // Trips you can turn into a group: planned or currently-active (not
    // finished) that don't already have a group. A trip with a group is opened
    // from the group trips list, not shared again.
    private var startableTrips: [Trip] {
        trips.filter { $0.endDate == nil && svc.groupCode(forTripId: $0.id) == nil }
    }

    var body: some View {
        Form {
            Section {
                Button {
                    newTripName = SessionFormat.defaultName()
                    showingStartNow = true
                } label: {
                    Label("Start now", systemImage: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
                .disabled(busy)

                Button {
                    showingPlanner = true
                } label: {
                    Label("Plan for later", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(busy)
            } header: {
                Text("Start a new shared trip")
            } footer: {
                Text("“Start now” begins a GPS-tracked session at your current location and shares it live with the crew. “Plan for later” schedules a trip (name, date, gear checklist) you can start from here when it's time.")
            }

            if !startableTrips.isEmpty {
                Section {
                    ForEach(startableTrips) { t in
                        HStack(spacing: 10) {
                            // Tap a planned trip to edit its name, date and
                            // checklist; tapping an active session shares it.
                            Button {
                                if t.isPlanned { editingPlan = t } else { Task { await startTrip(from: t) } }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: t.plannedDate != nil ? "calendar.badge.clock" : "figure.fishing")
                                        .foregroundStyle(CurrentsTheme.accent)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(t.name).font(.subheadline.bold()).foregroundStyle(.primary)
                                        Text(t.plannedDate != nil ? "Planned · tap to edit" : "Active session")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if t.isPlanned {
                                // Begin the planned session live now (+ share to crew).
                                Button { Task { await beginLive(planned: t) } } label: {
                                    Label("Start", systemImage: "play.fill")
                                        .labelStyle(.titleAndIcon)
                                        .font(.caption.bold())
                                }
                                .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
                                .disabled(busy)
                            } else {
                                // Already a live session — just share it.
                                Button { Task { await startTrip(from: t) } } label: {
                                    Label("Share", systemImage: "person.2.badge.plus")
                                        .labelStyle(.titleAndIcon)
                                        .font(.caption.bold())
                                }
                                .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
                                .disabled(busy)
                            }
                        }
                    }
                } header: {
                    Text("Your trips")
                } footer: {
                    Text("Start a trip you've already planned to take it live and share it with the crew (tap it first to edit its checklist), or share a session you're already running.")
                }
            }

            Section {
                CodeField(text: $joinCode, placeholder: "TRIP CODE")
                Button { Task { await joinTrip() } } label: {
                    Label("Join Trip", systemImage: "person.fill.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
                .disabled(busy || joinCode.trimmingCharacters(in: .whitespaces).count != 6)
            } header: {
                Text("Join a friend's trip")
            } footer: {
                Text("Enter the code they shared. You can also join instantly by tapping their invite in Notifications.")
            }
        }
        .navigationTitle("Group Trip")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPlanner) {
            // Planning only schedules the trip locally — you start it (going
            // live + sharing to the crew) from the list below when it's time.
            PlanSessionSheet(onSaved: { _ in trips = (try? appState.tripRepository.fetchAll()) ?? [] })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Start live trip", isPresented: $showingStartNow) {
            TextField("Trip name", text: $newTripName)
            Button("Start") { Task { await beginLiveNew(name: newTripName) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Begins a GPS-tracked session now and shares it live with the crew.")
        }
        .sheet(item: $editingPlan, onDismiss: { trips = (try? appState.tripRepository.fetchAll()) ?? [] }) { t in
            PlanSessionSheet(editingTrip: t)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .navigationDestination(item: Binding(get: { openedCode.map { IdString(id: $0) } },
                                             set: { openedCode = $0?.id })) { c in
            GroupTripView(tripId: svc.tripId(forGroupCode: c.id), tripName: currentName(c.id), initialCode: c.id)
        }
        .task { trips = (try? appState.tripRepository.fetchAll()) ?? [] }
    }

    private struct IdString: Identifiable, Hashable { let id: String }

    private func currentName(_ code: String) -> String {
        svc.myGroups.first(where: { $0.code == code })?.name ?? "Group Trip"
    }

    private func startTrip(from trip: Trip) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        // If this local trip already has a group, open it instead of making a
        // second one (avoids duplicate groups from a double-tap or re-entry).
        if let existing = svc.groupCode(forTripId: trip.id) {
            openedCode = existing
            return
        }
        if let code = await svc.createGroupTrip(name: trip.name, tripId: trip.id, crewCode: crewCode) {
            ToastCenter.shared.show(crewCode != nil ? "Live trip started" : "Group trip created", style: .success)
            openedCode = code
        }
    }

    private func startTrip(fromId id: String) async {
        trips = (try? appState.tripRepository.fetchAll()) ?? []
        guard let t = trips.first(where: { $0.id == id }) else { return }
        await startTrip(from: t)
    }

    /// Start a brand-new live session now and share it with the crew.
    private func beginLiveNew(name: String) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        let n = name.trimmingCharacters(in: .whitespaces).isEmpty ? SessionFormat.defaultName() : name
        let trip = appState.tripTracker.start(name: n, spotId: nil)
        await shareStartedTrip(trip)
    }

    /// Take a planned trip live now (begin its GPS session) and share it.
    private func beginLive(planned: Trip) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        let trip = appState.tripTracker.activeTrip?.id == planned.id
            ? planned
            : appState.tripTracker.startPlanned(planned)
        await shareStartedTrip(trip)
    }

    /// Create (or reopen) the shared crew group for a now-live local trip.
    private func shareStartedTrip(_ trip: Trip) async {
        if let existing = svc.groupCode(forTripId: trip.id) {
            openedCode = existing
            return
        }
        if let code = await svc.createGroupTrip(name: trip.name, tripId: trip.id, crewCode: crewCode) {
            ToastCenter.shared.show(crewCode != nil ? "Live trip started" : "Group trip created", style: .success)
            openedCode = code
        }
    }

    private func joinTrip() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        let code = joinCode.uppercased().trimmingCharacters(in: .whitespaces)
        guard let trip = await svc.joinGroupTrip(code: code) else { return }
        ToastCenter.shared.show("Joined the trip", style: .success)
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
    @StateObject private var svc = CommunityService.shared
    @State private var joinName = ""
    @State private var trip: CommunityService.GroupTrip?
    @State private var members: [CommunityService.GroupMember] = []
    @State private var feed: [CommunityService.GroupCatch] = []
    @State private var memberAvatars: [String: UIImage] = [:]
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
                if !svc.joined {
                    joinGate
                } else if confirming, let code {
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
        // No pull-to-refresh: it would swallow the sheet's pull-down-to-collapse
        // gesture. The feed auto-polls every 15s and has a manual Refresh button.
        .sheet(isPresented: $showingLog, onDismiss: {
            Task { await publishLatestToGroup(); await refresh() }
        }) {
            LogCatchView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            if code == nil, let tripId { code = service.groupCode(forTripId: tripId) }
            // Show last-seen members + catches instantly, then refresh in the
            // background — reopening a trip no longer flashes a blank page.
            if let c = code {
                members = service.cachedGroupMembers(c)
                feed = service.cachedGroupCatches(c)
            }
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

    // MARK: - Join gate (opened a trip link without a community profile yet)

    /// When someone taps a trip link before setting up Community, walk them
    /// through the same one-field onboarding (just a name) before they join —
    /// so their catches carry a name and they show up in the standings.
    private var joinGate: some View {
        VStack(spacing: CurrentsTheme.paddingM) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 44)).foregroundStyle(CurrentsTheme.accent)
                .padding(.top, 12)
            Text("Join to fish together").font(.title2.bold())
            Text("You've been invited to “\(trip?.name ?? tripName)”. Set up your free Currents profile — no account or password, just a name — to join the trip.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("Your angler name").font(.headline)
                TextField("Name", text: $joinName).textContentType(.givenName)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task {
                    busy = true
                    await svc.join(name: joinName, region: svc.myRegion)
                    Haptics.success()
                    // Now proceed into the group's join confirmation.
                    if let c = code {
                        trip = await service.groupTrip(code: c)
                        confirming = trip != nil
                    }
                    busy = false
                }
            } label: {
                HStack {
                    if busy { ProgressView().tint(.white) }
                    Label("Join & Continue", systemImage: "arrow.right.circle.fill").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
            .disabled(joinName.trimmingCharacters(in: .whitespaces).isEmpty || busy)
        }
        .glassCard()
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
                        ToastCenter.shared.show("Group trip created", style: .success)
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

            VStack(alignment: .leading, spacing: 10) {
                Text("Join a friend's trip").font(.headline)
                CodeField(text: $joinCode, placeholder: "TRIP CODE")
                Button {
                    Task {
                        busy = true
                        if let t = await service.joinGroupTrip(code: joinCode, tripId: tripId) {
                            ToastCenter.shared.show("Joined the trip", style: .success)
                            code = t.id
                            await refresh()
                        }
                        busy = false
                    }
                } label: {
                    Label("Join Trip", systemImage: "person.fill.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
                .disabled(joinCode.trimmingCharacters(in: .whitespaces).count != 6 || busy)
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
                    ToastCenter.shared.show("Joined the trip", style: .success)
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

        // Your gear checklist for this trip (editable any time).
        if let linkedId = service.tripId(forGroupCode: code) {
            TripChecklistCard(tripId: linkedId)
        }

        // Invite: pick friends (primary), share link / add-by-code (secondary).
        VStack(alignment: .leading, spacing: 12) {
            let memberCodes = Set(members.map(\.id))
            let invitable = friendProfiles.filter { !memberCodes.contains($0.id) }

            Text("Invite friends").font(.headline)
            if friendProfiles.isEmpty {
                ContentUnavailableView("No friends yet", systemImage: "person.2",
                    description: Text("Add friends in Community to invite them with one tap — or share the code below."))
            } else if invitable.isEmpty {
                ContentUnavailableView("Everyone's in", systemImage: "checkmark.circle",
                    description: Text("All your friends are already in this trip."))
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
                                    ToastCenter.shared.show("Invite sent to \(f.name)", style: .success)
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
                    CopyableCode(code: code, font: .system(.title3, design: .monospaced).bold())
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
                VStack(spacing: 8) {
                    CodeField(text: $joinCode, placeholder: "ANGLER CODE")
                    Button {
                        let c = joinCode.uppercased().trimmingCharacters(in: .whitespaces)
                        joinCode = ""
                        Task {
                            await service.inviteFriend(c, toGroup: code, tripName: trip?.name ?? tripName)
                            ToastCenter.shared.show("Invite sent", style: .success)
                        }
                    } label: {
                        Label("Send Invite", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(CurrentsTheme.accent)
                    .disabled(joinCode.trimmingCharacters(in: .whitespaces).count != 6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()

        // Group totals
        groupTotalsCard

        // Standings — anglers ranked by catches, with each one's stats.
        VStack(alignment: .leading, spacing: 10) {
            Label("Standings", systemImage: "trophy.fill").font(.headline)
            let stats = standings()
            ForEach(Array(stats.enumerated()), id: \.element.code) { i, s in
                NavigationLink {
                    FriendProfileView(code: s.code)
                } label: {
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(i < 3 ? .white : .secondary)
                            .frame(width: 24, height: 24)
                            .background(i < 3 ? CurrentsTheme.accent : Color.secondary.opacity(0.15), in: Circle())
                        AnglerAvatar(image: memberAvatars[s.code], size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(s.name).font(.subheadline.bold()).foregroundStyle(.primary)
                                if s.code == trip?.hostCode {
                                    Text("Host").font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(CurrentsTheme.accent.opacity(0.2), in: Capsule())
                                }
                                if s.code == service.friendCode {
                                    Text("YOU").font(.system(size: 9, weight: .heavy))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(CurrentsTheme.accent, in: Capsule())
                                        .foregroundStyle(.white)
                                }
                            }
                            Text(s.subtitle).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(s.count)").font(.headline.monospacedDigit()).foregroundStyle(CurrentsTheme.accent)
                            + Text(s.count == 1 ? " fish" : " fish").font(.caption2).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()

        // Live catch feed
        VStack(alignment: .leading, spacing: 10) {
            Label("Group catches", systemImage: "fish.fill").font(.headline)
            if feed.isEmpty {
                ContentUnavailableView("No catches yet", systemImage: "fish",
                    description: Text("Be the first to put a fish on the board!"))
            } else {
                ForEach(feed) { c in
                    NavigationLink { CommunityCatchDetailView(row: leaderRow(from: c)) } label: {
                        HStack(spacing: 10) {
                            CommunityCatchThumb(row: leaderRow(from: c), size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.species).font(.subheadline.bold()).foregroundStyle(.primary)
                                Text("\(c.anglerName) · \(c.date.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(sizeLabel(c)).font(.subheadline.bold()).foregroundStyle(CurrentsTheme.accent)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
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

        // Host-only: end the whole trip for everyone (doesn't touch anyone's
        // personal GPS session). Members can only end their own session.
        if trip?.isHost == true, !(trip?.isEnded ?? false) {
            Button(role: .destructive) {
                Haptics.warning()
                Task { await service.endGroupTrip(code: code); ToastCenter.shared.show("Trip ended", style: .info, haptic: false); await refresh() }
            } label: {
                Label("End trip for everyone", systemImage: "flag.slash").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }

        Button(role: .destructive) {
            Task {
                await leaveGroupAndCleanup(code: code, tripId: tripId, appState: appState)
                self.code = nil
                trip = nil; members = []; feed = []
            }
        } label: {
            Label(trip?.isEnded == true ? "Remove from my trips" : "Leave group", systemImage: "person.fill.xmark").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Your session card (start / pause GPS / log)

    @ViewBuilder private func yourSessionCard(_ code: String) -> some View {
        let tracker = appState.tripTracker
        let linkedId = service.tripId(forGroupCode: code)
        let isThisActive = tracker.isTracking && tracker.activeTrip?.id == linkedId && linkedId != nil

        let ended = trip?.isEnded ?? false

        VStack(alignment: .leading, spacing: 10) {
            Label("Your session", systemImage: "figure.fishing").font(.headline)

            if ended {
                // Host ended the shared trip. Standings + catches stay visible as
                // history; you can still wrap up your own session if it's running.
                Label("This trip has ended", systemImage: "flag.checkered")
                    .font(.subheadline.bold()).foregroundStyle(.secondary)
                if isThisActive {
                    Button(role: .destructive) {
                        Haptics.warning()
                        _ = appState.tripTracker.end()
                    } label: {
                        Label("End my session", systemImage: "stop.circle").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
            } else if isThisActive, tracker.isDayActive {
                if tracker.manualPaused {
                    Label("GPS paused", systemImage: "pause.circle.fill").font(.caption).foregroundStyle(.orange)
                } else {
                    Label("Fishing — tracking live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.bold()).foregroundStyle(.green)
                }
                // Live session stats.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let start = tracker.activeTrip?.currentDayStart ?? tracker.activeTrip?.startDate ?? .now
                    HStack(spacing: 10) {
                        sessionStat(SessionFormat.duration(tracker.manualPaused ? 0 : Date.now.timeIntervalSince(start)), "Elapsed", "clock")
                        sessionStat(SessionFormat.distance(trackDistance(tracker)), "Distance", "point.topleft.down.to.point.bottomright.curvepath")
                        sessionStat("\(myCatchCount())", "Your fish", "fish.fill")
                    }
                }
                // Logging is only available WHILE fishing, so catches can't be
                // added before the trip starts or after it ends — and they're
                // always tagged to the group.
                Button { Haptics.tap(); showingLog = true } label: {
                    Label("Log a Catch", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
                HStack(spacing: 10) {
                    Button {
                        Haptics.selection()
                        if tracker.manualPaused { tracker.resumeTracking() } else { tracker.pauseTracking() }
                    } label: {
                        Label(tracker.manualPaused ? "Resume" : "Pause",
                              systemImage: tracker.manualPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                    Menu {
                        Button {
                            Haptics.warning()
                            tracker.endDay()
                        } label: { Label("End for the day", systemImage: "moon.zzz.fill") }
                        Button(role: .destructive) {
                            Haptics.warning()
                            _ = appState.tripTracker.end()
                        } label: { Label("End my session", systemImage: "stop.circle") }
                    } label: {
                        Label("Finish", systemImage: "flag.checkered").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
            } else if isThisActive {
                // Day ended but the trip is still open — pick back up tomorrow
                // or finish the whole trip. No logging between days.
                Label("Day ended — trip still open", systemImage: "pause.circle").font(.caption).foregroundStyle(.secondary)
                Button {
                    Haptics.success()
                    tracker.startNextDay()
                } label: {
                    Label("Start next day", systemImage: "sun.max.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
                Button(role: .destructive) {
                    Haptics.warning()
                    _ = appState.tripTracker.end()
                } label: {
                    Label("End trip", systemImage: "stop.circle").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            } else if tracker.isTracking {
                Text("Another session is active. End it and start this trip's session to log catches here.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let linkedId, let lt = (try? appState.tripRepository.fetch(linkedId)) ?? nil {
                if lt.isCompleted {
                    // Ending a session is final — no restarting it, no logging.
                    Label("Your session has ended. You can still see the group's catches.",
                          systemImage: "flag.checkered")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Start your session to record your GPS track and log catches toward the group.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        Haptics.success()
                        _ = appState.tripTracker.startPlanned(lt)
                    } label: {
                        Label("Start Fishing", systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Group stats

    private var groupTotalsCard: some View {
        let biggest = feed.compactMap { c -> (Double, String, String)? in
            guard let w = c.weightKg else { return nil }
            return (w, c.species, c.anglerName)
        }.max(by: { $0.0 < $1.0 })
        let speciesCount = Set(feed.map(\.species)).count
        let activeAnglers = Set(feed.map(\.friendCode)).count
        return VStack(alignment: .leading, spacing: 10) {
            Label("Group totals", systemImage: "chart.bar.fill").font(.headline)
            HStack(spacing: 10) {
                sessionStat("\(feed.count)", "Catches", "fish.fill")
                sessionStat("\(speciesCount)", "Species", "square.grid.2x2")
                sessionStat("\(activeAnglers)/\(members.count)", "Scored", "person.2.fill")
            }
            if let biggest {
                Label("Biggest: \(biggest.1) · \(Units.weight(kg: biggest.0)) by \(biggest.2)",
                      systemImage: "trophy.fill")
                    .font(.caption).foregroundStyle(CurrentsTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private struct MemberStat {
        let code: String
        let name: String
        var count: Int
        var bestKg: Double?
        var bestCm: Double?
        var species: Set<String>
        var subtitle: String {
            var parts: [String] = ["\(species.count) \(species.count == 1 ? "species" : "species")"]
            if let bestKg { parts.append("PB \(Units.weight(kg: bestKg))") }
            else if let bestCm { parts.append("PB \(Units.length(cm: bestCm))") }
            return parts.joined(separator: " · ")
        }
    }

    /// Per-member standings from the group's catches (members with none included).
    private func standings() -> [MemberStat] {
        var byCode: [String: MemberStat] = [:]
        for m in members {
            byCode[m.id] = MemberStat(code: m.id, name: m.name, count: 0, bestKg: nil, bestCm: nil, species: [])
        }
        for c in feed {
            var s = byCode[c.friendCode] ?? MemberStat(code: c.friendCode, name: c.anglerName, count: 0, bestKg: nil, bestCm: nil, species: [])
            s.count += 1
            s.species.insert(c.species)
            if let w = c.weightKg { s.bestKg = max(s.bestKg ?? 0, w) }
            if let l = c.lengthCm { s.bestCm = max(s.bestCm ?? 0, l) }
            byCode[c.friendCode] = s
        }
        return byCode.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return ($0.bestKg ?? 0) > ($1.bestKg ?? 0)
        }
    }

    private func myCatchCount() -> Int {
        feed.filter { $0.friendCode == service.friendCode }.count
    }

    private func trackDistance(_ tracker: TripTracker) -> Double {
        let pts = tracker.track
        guard pts.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<pts.count {
            total += CLLocation(latitude: pts[i].lat, longitude: pts[i].lon)
                .distance(from: CLLocation(latitude: pts[i-1].lat, longitude: pts[i-1].lon))
        }
        return total
    }

    /// Build a LeaderRow from a group catch so it opens in the full catch detail
    /// (photo, map, stats) and reuses the community thumbnail.
    private func leaderRow(from c: CommunityService.GroupCatch) -> CommunityService.LeaderRow {
        CommunityService.LeaderRow(
            id: c.id, anglerName: c.anglerName, friendCode: c.friendCode,
            species: c.species, weightKg: c.weightKg, lengthCm: c.lengthCm,
            catchCount: nil, region: "", date: c.date, hasRemotePhoto: true)
    }

    private func sessionStat(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundStyle(CurrentsTheme.accent)
            Text(value).font(.subheadline.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(CurrentsTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
        await loadMemberAvatars()
    }

    /// Fetch each member's profile picture once (cached), so standings + the
    /// member list show real avatars instead of initials.
    private func loadMemberAvatars() async {
        for m in members where memberAvatars[m.id] == nil {
            if m.id == service.friendCode {
                if let a = service.myAvatar { memberAvatars[m.id] = a }
            } else if let p = await service.fetchProfile(code: m.id), let a = p.avatar {
                memberAvatars[m.id] = a
            }
        }
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
