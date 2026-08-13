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
                                if let team = g.teamName {
                                    Text("🏆 \(team)").font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.yellow.opacity(0.18), in: Capsule())
                                }
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
                .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
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
                                        .labelStyle(.prominentButton)
                                        .font(.caption.bold())
                                }
                                .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
                                .disabled(busy)
                            } else {
                                // Already a live session — just share it.
                                Button { Task { await startTrip(from: t) } } label: {
                                    Label("Share", systemImage: "person.2.badge.plus")
                                        .labelStyle(.prominentButton)
                                        .font(.caption.bold())
                                }
                                .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
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
                .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
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
        guard let trip = await svc.joinGroupTrip(code: code) else {
            ToastCenter.shared.show("Couldn't join — check the code (the trip may have ended or been deleted)", style: .error)
            return
        }
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
    @State private var showingInvite = false
    @State private var confirmingEndForAll = false
    @State private var confirmingLeave = false
    /// The trip's record is confirmed GONE from the server (deleted, not just
    /// unreachable) — show the dead-end screen instead of a join form.
    @State private var tripMissing = false

    private let autoJoin: Bool
    private var service: CommunityService { .shared }

    /// A tournament team session lives inside a crew — its roster is managed
    /// from the tournament screen (join a team / admin assign), so friend
    /// invites and share links make no sense here and are hidden.
    private var isTournamentTeam: Bool {
        trip?.tournamentCode != nil || trip?.teamName != nil
            || service.myGroups.first(where: { $0.code == code })?.teamName != nil
    }

    private func leave(code: String) {
        Task {
            await leaveGroupAndCleanup(code: code, tripId: tripId, appState: appState)
            self.code = nil
            trip = nil; members = []; feed = []
            tripMissing = false
        }
    }

    /// Dead-end state for a deleted session: say so plainly, stop any GPS
    /// session still ticking against it, and offer one-tap cleanup.
    private func tripMissingView(_ code: String) -> some View {
        VStack(spacing: 14) {
            ContentUnavailableView {
                Label("This trip no longer exists", systemImage: "flag.slash")
            } description: {
                Text("The session was deleted — usually because its tournament was removed. Catches you logged are still in your log.")
            }
            Button {
                Haptics.tap()
                // End a local GPS session still linked to the dead trip.
                if let localId = tripId ?? service.tripId(forGroupCode: code),
                   appState.tripTracker.activeTrip?.id == localId {
                    _ = appState.tripTracker.end()
                }
                leave(code: code)
            } label: {
                Label("Remove from my trips", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
        }
        .padding(.top, 40)
    }

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
                } else if tripMissing, let code {
                    tripMissingView(code)
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
        // Lifecycle + invites live in the toolbar so the screen itself is all
        // trip: who's here, who's winning, what's being caught.
        .toolbar {
            if let code, !confirming, svc.joined {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !isTournamentTeam {
                            Button { showingInvite = true } label: {
                                Label("Invite friends", systemImage: "person.badge.plus")
                            }
                            ShareLink(item: service.inviteMessage(forGroup: code, tripName: trip?.name ?? tripName)) {
                                Label("Share invite link", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                        }
                        if trip?.isHost == true, !(trip?.isEnded ?? false) {
                            Button(role: .destructive) {
                                confirmingEndForAll = true
                            } label: {
                                Label("End trip for everyone", systemImage: "flag.slash")
                            }
                        }
                        Button(role: .destructive) {
                            if trip?.isEnded == true {
                                // Removing a finished trip from your list is
                                // harmless housekeeping — no ceremony needed.
                                leave(code: code)
                            } else {
                                confirmingLeave = true
                            }
                        } label: {
                            Label(trip?.isEnded == true ? "Remove from my trips" : "Leave trip",
                                  systemImage: "person.fill.xmark")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("End the trip for everyone?", isPresented: $confirmingEndForAll,
                            titleVisibility: .visible) {
            Button("End trip", role: .destructive) {
                guard let code else { return }
                Haptics.warning()
                Task {
                    await service.endGroupTrip(code: code)
                    ToastCenter.shared.show("Trip ended for everyone", style: .info, haptic: false)
                    await refresh()
                }
            }
        } message: {
            Text("Every member's live feed closes. Catches already logged stay on the trip.")
        }
        .confirmationDialog("Leave this trip?", isPresented: $confirmingLeave,
                            titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                guard let code else { return }
                Haptics.warning()
                leave(code: code)
            }
        } message: {
            Text("You can re-join with the trip code while it's still live.")
        }
        // No pull-to-refresh: it would swallow the sheet's pull-down-to-collapse
        // gesture. The feed auto-polls every 15s.
        .sheet(isPresented: $showingLog, onDismiss: {
            Task { await refresh() }
        }) {
            // The override tags the catch to this trip directly — no linked GPS
            // session required, so members who joined mid-trip can log too.
            LogCatchView(groupCodeOverride: code)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingInvite) {
            NavigationStack {
                ScrollView {
                    if let code { invitePanel(code).padding() }
                }
                .navigationTitle("Invite")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingInvite = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
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
                } else if await service.groupTripExists(code: c) == .missing {
                    // Opened a link/row for a session that's been deleted —
                    // dead-end screen, never the join form for a dead code.
                    tripMissing = true
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
            .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
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
            .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
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
                        } else {
                            ToastCenter.shared.show("Couldn't join — check the code (the trip may have ended or been deleted)", style: .error)
                        }
                        busy = false
                    }
                } label: {
                    Label("Join Trip", systemImage: "person.fill.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
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
                    if await service.joinGroupTrip(code: code) != nil {
                        ToastCenter.shared.show("Joined the trip", style: .success)
                        ensureLinkedTrip(code: code, name: trip?.name ?? "Group Trip")
                        confirming = false
                    } else {
                        ToastCenter.shared.show("Couldn't join the trip — it may have ended or been deleted", style: .error)
                    }
                    busy = false
                    await refresh()
                }
            } label: {
                HStack {
                    if busy { ProgressView().tint(.white) }
                    Label("Join Trip", systemImage: "person.fill.badge.plus")
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
            .disabled(busy)
        }
        .glassCard()
    }

    // MARK: - Member colours

    /// A stable colour per angler, so everything of theirs — feed rows,
    /// standings bars, avatar rings — reads as theirs at a glance.
    private func color(_ code: String) -> Color {
        let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .red, .indigo]
        var h = 5381
        for u in code.unicodeScalars { h = (h &* 33) &+ Int(u.value) }
        return palette[abs(h) % palette.count]
    }

    // MARK: - Active group

    @ViewBuilder private func activeGroup(_ code: String) -> some View {
        let ended = trip?.isEnded ?? false
        let amMember = members.contains { $0.id == service.friendCode }

        tripHero(code, ended: ended)

        if !ended {
            if amMember {
                Button {
                    Haptics.tap()
                    showingLog = true
                } label: {
                    Label("Log a Catch to the Trip", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).labelStyle(.prominentButton)
                .tint(CurrentsTheme.accent)
            } else {
                joinBanner(code)
            }
        }

        standingsCard(ended: ended)
        feedCard
        // The gear checklist lives in the planned-trip editor only — a live
        // session isn't the place to be packing.
        if amMember { sessionStrip(code, ended: ended) }
    }

    // MARK: - Hero

    private func tripHero(_ code: String, ended: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if ended {
                    Label("Ended", systemImage: "flag.checkered")
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.gray.opacity(0.2), in: Capsule())
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        PulseDot()
                        Text("LIVE").font(.caption.weight(.heavy)).foregroundStyle(.red)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.red.opacity(0.12), in: Capsule())
                }
                Spacer()
                if let start = trip?.createdAt {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        Label(elapsedLabel(from: start, to: trip?.endedAt), systemImage: "clock")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(trip?.name ?? tripName).font(.title2.bold())

            HStack(spacing: 6) {
                Text("Hosted by \(trip?.hostName ?? "…")")
                    .font(.caption).foregroundStyle(.secondary)
                if let crewCode = trip?.crewCode, let crew = svc.crew(withCode: crewCode) {
                    Text("\(crew.emoji) \(crew.name)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(CurrentsTheme.accent.opacity(0.15), in: Capsule())
                }
                // A tournament team session says so — otherwise it's
                // indistinguishable from a casual shared trip.
                if let team = trip?.teamName {
                    Text("🏆 Team \(team)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.16), in: Capsule())
                        .foregroundStyle(.primary)
                }
            }

            facepile

            if isTournamentTeam {
                // Teammates come from the crew via the tournament screen —
                // no invites, no code to pass around.
                Text("Crewmates join from the tournament page")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Trip code").font(.caption2).foregroundStyle(.secondary)
                        CopyableCode(code: code, font: .system(.subheadline, design: .monospaced).bold())
                    }
                    Spacer()
                    Button {
                        showingInvite = true
                    } label: {
                        Label("Invite", systemImage: "person.badge.plus").font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// Everyone on the trip: colour-ringed avatars with live catch-count
    /// badges, so "who's here and who's scoring" reads in one glance.
    private var facepile: some View {
        let counts = Dictionary(grouping: feed, by: \.friendCode).mapValues(\.count)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(members) { m in
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            AnglerAvatar(image: memberAvatars[m.id], size: 42)
                                .overlay(Circle().strokeBorder(color(m.id), lineWidth: 2.5))
                            if let n = counts[m.id], n > 0 {
                                Text("\(n)")
                                    .font(.system(size: 10, weight: .heavy)).monospacedDigit()
                                    .foregroundStyle(.white)
                                    .frame(width: 17, height: 17)
                                    .background(color(m.id), in: Circle())
                                    .offset(x: 5, y: -3)
                            }
                        }
                        Text(m.id == service.friendCode ? "You" : m.name)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .foregroundStyle(m.id == service.friendCode ? CurrentsTheme.accent : .secondary)
                    }
                    .frame(width: 52)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// A crewmate viewing a live trip they haven't joined — one tap in.
    private func joinBanner(_ code: String) -> some View {
        VStack(spacing: 10) {
            Text("You're watching this trip").font(.subheadline.bold())
            Text("Join to log your catches onto the board with everyone else's.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task {
                    busy = true
                    if await service.joinGroupTrip(code: code) != nil {
                        ensureLinkedTrip(code: code, name: trip?.name ?? tripName)
                        Haptics.success()
                        ToastCenter.shared.show("You're in — tight lines!", style: .success)
                    } else {
                        ToastCenter.shared.show("Couldn't join the trip — it may have ended or been deleted", style: .error)
                    }
                    busy = false
                    await refresh()
                }
            } label: {
                HStack {
                    if busy { ProgressView().tint(.white) }
                    Label("Join this trip", systemImage: "person.fill.badge.plus")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
            .disabled(busy)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Standings (podium)

    private func standingsCard(ended: Bool) -> some View {
        let stats = standings()
        let biggest = feed.compactMap { c -> (Double, String, String)? in
            guard let w = c.weightKg else { return nil }
            return (w, c.species, c.anglerName)
        }.max(by: { $0.0 < $1.0 })

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(ended ? "Final results" : "Standings",
                      systemImage: ended ? "flag.checkered" : "trophy.fill")
                    .font(.headline)
                Spacer()
                Text("\(feed.count) fish · \(Set(feed.map(\.species)).count) species")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if stats.allSatisfy({ $0.count == 0 }) {
                Text("No fish on the board yet — first catch takes the lead.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                podium(Array(stats.prefix(3)))
                ForEach(Array(stats.dropFirst(3).enumerated()), id: \.element.code) { i, s in
                    standingRow(rank: i + 4, s)
                }
            }

            if let biggest {
                Label("Biggest: \(biggest.1) · \(Units.weight(kg: biggest.0)) — \(biggest.2)",
                      systemImage: "crown.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// 2nd · 1st · 3rd, bars scaled to catch counts and tinted per member.
    private func podium(_ top: [MemberStat]) -> some View {
        var slots: [(stat: MemberStat, place: Int)] = []
        if top.count > 1 { slots.append((top[1], 2)) }
        if !top.isEmpty { slots.append((top[0], 1)) }
        if top.count > 2 { slots.append((top[2], 3)) }
        let maxCount = max(top.first?.count ?? 1, 1)

        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(slots, id: \.stat.code) { entry in
                let s = entry.stat
                VStack(spacing: 6) {
                    AnglerAvatar(image: memberAvatars[s.code], size: entry.place == 1 ? 46 : 38)
                        .overlay(Circle().strokeBorder(color(s.code), lineWidth: 2.5))
                    Text(s.code == service.friendCode ? "You" : s.name)
                        .font(.caption2.bold())
                        .lineLimit(1).minimumScaleFactor(0.7)
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(color(s.code).opacity(entry.place == 1 ? 1 : 0.75).gradient)
                            .frame(height: 40 + 44 * CGFloat(s.count) / CGFloat(maxCount))
                        VStack(spacing: 0) {
                            Text(entry.place == 1 ? "🥇" : entry.place == 2 ? "🥈" : "🥉")
                                .font(.system(size: 13))
                            Text("\(s.count)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.white)
                        }
                        .padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func standingRow(rank: Int, _ s: MemberStat) -> some View {
        NavigationLink { FriendProfileView(code: s.code) } label: {
            HStack(spacing: 10) {
                Text("\(rank)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                AnglerAvatar(image: memberAvatars[s.code], size: 28)
                    .overlay(Circle().strokeBorder(color(s.code), lineWidth: 2))
                Text(s.code == service.friendCode ? "You" : s.name)
                    .font(.subheadline).foregroundStyle(.primary)
                Spacer()
                Text("\(s.count)")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(color(s.code))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Live feed (per-member coloured timeline)

    private var feedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Live feed", systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)
                .padding(.bottom, 10)
            if feed.isEmpty {
                Text("Catches land here the moment anyone logs one.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else {
                ForEach(Array(feed.enumerated()), id: \.element.id) { i, c in
                    feedRow(c, isLast: i == feed.count - 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func feedRow(_ c: CommunityService.GroupCatch, isLast: Bool) -> some View {
        NavigationLink { CommunityCatchDetailView(row: leaderRow(from: c)) } label: {
            HStack(alignment: .top, spacing: 10) {
                // The member's colour runs down the spine, so scanning "who's
                // been catching" needs no reading at all.
                VStack(spacing: 0) {
                    Circle().fill(color(c.friendCode)).frame(width: 10, height: 10)
                        .padding(.top, 17)
                    if !isLast {
                        Rectangle()
                            .fill(color(c.friendCode).opacity(0.25))
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 10)
                CommunityCatchThumb(row: leaderRow(from: c), size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.species).font(.subheadline.bold()).foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(c.friendCode == service.friendCode ? "You" : c.anglerName)
                            .font(.caption2.bold())
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(color(c.friendCode).opacity(0.18), in: Capsule())
                            .foregroundStyle(color(c.friendCode))
                        Text(c.date, style: .relative)
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Text(sizeLabel(c))
                    .font(.subheadline.bold())
                    .foregroundStyle(CurrentsTheme.accent)
            }
            .padding(.bottom, isLast ? 0 : 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Invite (sheet content)

    @ViewBuilder private func invitePanel(_ code: String) -> some View {
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
    }

    // MARK: - Your GPS session (compact)

    @ViewBuilder private func sessionStrip(_ code: String, ended: Bool) -> some View {
        let tracker = appState.tripTracker
        let linkedId = service.tripId(forGroupCode: code)
        let isThisActive = tracker.isTracking && tracker.activeTrip?.id == linkedId && linkedId != nil

        VStack(alignment: .leading, spacing: 10) {
            Label("Your GPS session", systemImage: "figure.fishing").font(.headline)

            if ended {
                Label("This trip has ended", systemImage: "flag.checkered")
                    .font(.subheadline.bold()).foregroundStyle(.secondary)
                if isThisActive {
                    Button(role: .destructive) {
                        Haptics.warning()
                        _ = appState.tripTracker.end()
                    } label: {
                        Label("End my session", systemImage: "stop.circle").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                } else if let linkedId, let lt = (try? appState.tripRepository.fetch(linkedId)) ?? nil {
                    // The shared trip is over, but YOUR session — track, stats,
                    // catches — is still worth opening.
                    NavigationLink {
                        SessionDetailView(trip: lt)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "map")
                                .foregroundStyle(CurrentsTheme.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("View your session").font(.subheadline.bold())
                                Text("Your GPS track, stats and catches")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else if isThisActive, tracker.isDayActive {
                if tracker.manualPaused {
                    Label("GPS paused", systemImage: "pause.circle.fill").font(.caption).foregroundStyle(.orange)
                } else {
                    Label("Tracking live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.bold()).foregroundStyle(.green)
                }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let start = tracker.activeTrip?.currentDayStart ?? tracker.activeTrip?.startDate ?? .now
                    HStack(spacing: 10) {
                        sessionStat(SessionFormat.duration(tracker.manualPaused ? 0 : Date.now.timeIntervalSince(start)), "Elapsed", "clock")
                        sessionStat(SessionFormat.distance(trackDistance(tracker)), "Distance", "point.topleft.down.to.point.bottomright.curvepath")
                        sessionStat("\(myCatchCount())", "Your fish", "fish.fill")
                    }
                }
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
                Label("Day ended — trip still open", systemImage: "pause.circle").font(.caption).foregroundStyle(.secondary)
                Button {
                    Haptics.success()
                    tracker.startNextDay()
                } label: {
                    Label("Start next day", systemImage: "sun.max.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
                Button(role: .destructive) {
                    Haptics.warning()
                    _ = appState.tripTracker.end()
                } label: {
                    Label("End trip", systemImage: "stop.circle").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            } else if tracker.isTracking {
                Text("Another session is active. End it and start this trip's session to record your GPS track here.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let linkedId, let lt = (try? appState.tripRepository.fetch(linkedId)) ?? nil {
                if lt.isCompleted {
                    Label("Your session has ended. Catches you log still count for the trip.",
                          systemImage: "flag.checkered")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Optional: start a GPS session to record your track alongside the trip.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        Haptics.success()
                        _ = appState.tripTracker.startPlanned(lt)
                    } label: {
                        Label("Start GPS session", systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func elapsedLabel(from start: Date, to end: Date?) -> String {
        let seconds = (end ?? .now).timeIntervalSince(start)
        let h = Int(seconds) / 3600, m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
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

    private func refresh() async {
        guard let code else { return }
        async let freshTrip = service.groupTrip(code: code)
        async let freshMembers = service.groupMembers(code: code)
        async let freshFeed = service.groupCatches(code: code)
        trip = await freshTrip
        members = await freshMembers
        feed = await freshFeed
        // A nil trip can mean "deleted" (a Mate removed the tournament and its
        // sessions) or just "offline" — probe before declaring it gone, and
        // never fall back to the raw join screen for a dead code.
        if trip == nil {
            tripMissing = await service.groupTripExists(code: code) == .missing
        } else {
            tripMissing = false
        }
        // The shared trip ended remotely (tournament closed, host ended it):
        // stop the linked local GPS session too, instead of leaving it
        // silently running until the angler notices.
        if let t = trip, t.isEnded,
           let localId = tripId ?? service.tripId(forGroupCode: code),
           appState.tripTracker.activeTrip?.id == localId {
            _ = appState.tripTracker.end()
            ToastCenter.shared.show("Session ended — the shared trip is over", style: .info)
        }
        await loadFriendProfiles()
        await loadMemberAvatars()
    }

    /// Member avatars: cache-first, then ONE batched fetch for whoever's
    /// missing (this used to be a sequential network call per member).
    private func loadMemberAvatars() async {
        if memberAvatars[service.friendCode] == nil, let a = service.myAvatar {
            memberAvatars[service.friendCode] = a
        }
        for m in members where memberAvatars[m.id] == nil {
            if let a = service.cachedProfiles(for: [m.id]).first?.avatar { memberAvatars[m.id] = a }
        }
        let missing = members.map(\.id).filter { memberAvatars[$0] == nil && $0 != service.friendCode }
        guard !missing.isEmpty else { return }
        for (c, p) in await service.profiles(for: missing) where p.avatar != nil {
            memberAvatars[c] = p.avatar
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

/// The pulsing red dot in the LIVE badge.
private struct PulseDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 8, height: 8)
            .scaleEffect(on ? 1.0 : 0.6)
            .opacity(on ? 1 : 0.55)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
