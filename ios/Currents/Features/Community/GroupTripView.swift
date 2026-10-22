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
        Section {
            ForEach(svc.myGroups) { g in
                NavigationLink {
                    GroupTripView(tripId: CommunityService.shared.tripId(forGroupCode: g.code),
                                  tripName: g.name, initialCode: g.code)
                } label: {
                    ArtRow(over: g.endedAt != nil ? "Ended" : (g.teamName.map { "Tournament team \($0)" } ?? "Group trip"),
                           title: g.name,
                           subtitle: g.isHost ? "You're hosting, code \(g.code)" : "Hosted by \(g.hostName), code \(g.code)") {
                        ThumbView(systemImage: g.teamName != nil ? "trophy.fill" : "person.3.fill",
                                  tint: g.endedAt != nil ? Color.gray : (g.teamName != nil ? Color.dsScoreFair : Color.dsScoreGood),
                                  size: 56)
                    }
                }
                .buttonStyle(.dsRow)
                .dsListRow()
                .swipeActions {
                    Button("Remove", role: .destructive) {
                        Task { await leaveGroupAndCleanup(code: g.code, tripId: nil, appState: appState) }
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        Task { await leaveGroupAndCleanup(code: g.code, tripId: nil, appState: appState) }
                    } label: { Label("Remove from my trips", systemImage: "trash") }
                }
            }
            NavigationLink {
                GroupTripSetupView()
            } label: {
                ArtRow(title: "Start or join a trip", subtitle: "Fish together and see every catch live") {
                    ThumbView(systemImage: "plus", tint: DS.accent, size: 56)
                }
            }
            .buttonStyle(.dsRow)
            .dsListRow()
        } header: {
            SectionTitle("Group trips")
                .padding(.top, DS.Space.s4)
                .textCase(nil)
        }
    }
}

/// Leave a group trip and, if the local session it was linked to never got past
/// the planned stage (never started, so nothing was tracked or logged), delete
/// that planned session too. Leaving a group you only planned shouldn't leave
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

// MARK: - Shared bits

/// A rounded text field on the tonal fill, for names.
private struct GroupTripTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.body)
            .padding(.horizontal, DS.Space.s4)
            .frame(minHeight: 50)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
    }
}

/// A big centred icon over a title block, for the gate and setup states.
private struct GroupTripIntro: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            ThumbView(systemImage: systemImage, tint: DS.accent, size: 72)
                .padding(.horizontal, DS.gutter)
            DetailHeader(title: title, subtitle: message)
        }
    }
}

// MARK: - Setup: start (pick a trip) or join by code

/// Start a shared trip, based on a new or an existing/planned trip, or join
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
    @FocusState private var joinFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let joinAnchor = "join"

    // Trips you can turn into a group: planned or currently-active (not
    // finished) that don't already have a group. A trip with a group is opened
    // from the group trips list, not shared again.
    private var startableTrips: [Trip] {
        trips.filter { $0.endDate == nil && svc.groupCode(forTripId: $0.id) == nil }
    }

    var body: some View {
        // Without iCloud the Crew unavailable state shows and no load starts.
        CrewCloudGate { page }
    }

    private var page: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHeader(over: crewCode.flatMap { svc.crew(withCode: $0)?.name },
                             title: "Group trip",
                             subtitle: "Fish together. Everyone sees every catch, live.")

                ActionTriple {
                    Button {
                        newTripName = SessionFormat.defaultName()
                        showingStartNow = true
                    } label: {
                        Label("Start now", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(ActionTileStyle(.primary))
                    Button {
                        showingPlanner = true
                    } label: {
                        Label("Plan", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(ActionTileStyle(.tonal))
                    Button {
                        withAnimation(reduceMotion ? nil : DS.Motion.softSpring) {
                            proxy.scrollTo(Self.joinAnchor, anchor: .top)
                        }
                        joinFocused = true
                    } label: {
                        Label("Join", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(ActionTileStyle(.tonal))
                }
                .disabled(busy)
                .padding(.top, DS.Space.s5)

                if !startableTrips.isEmpty {
                    EventSection("Your trips") {
                        VStack(spacing: 0) {
                            ForEach(startableTrips) { t in yourTripRow(t) }
                        }
                        EventFootnote("Start one to take it live, or tap it to edit.")
                    }
                }

                EventSection("Join a friend's trip") {
                    VStack(spacing: DS.Space.s3) {
                        CodeField(text: $joinCode, placeholder: "Trip code")
                            .focused($joinFocused)
                        Button { Task { await joinTrip() } } label: {
                            HStack(spacing: DS.Space.s2) {
                                if busy { ProgressView() }
                                Text("Join trip")
                            }
                        }
                        .buttonStyle(.dsPrimary)
                        .disabled(busy || joinCode.trimmingCharacters(in: .whitespaces).count != 6)
                    }
                    .padding(.horizontal, DS.gutter)
                    EventFootnote("Use the code they shared, or tap their invite.")
                }
                .id(Self.joinAnchor)
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .dsScreenBackground()
        .eventPageTitle("Group trip")
        .sheet(isPresented: $showingPlanner) {
            // Planning only schedules the trip locally. You start it (going
            // live + sharing to the crew) from the list when it's time.
            PlanSessionSheet(onSaved: { _ in trips = (try? appState.tripRepository.fetchAll()) ?? [] })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Start live trip", isPresented: $showingStartNow) {
            TextField("Trip name", text: $newTripName)
            Button("Start") { Task { await beginLiveNew(name: newTripName) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Starts a GPS session where you are and shares it live.")
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
    }

    private func yourTripRow(_ t: Trip) -> some View {
        HStack(spacing: 0) {
            // Tap a planned trip to edit its name, date and checklist; tapping
            // an active session shares it.
            Button {
                if t.isPlanned { editingPlan = t } else { Task { await startTrip(from: t) } }
            } label: {
                ArtRow(over: t.plannedDate.map { $0.formatted(date: .abbreviated, time: .shortened) },
                       title: t.name,
                       subtitle: t.isPlanned ? "Planned. Tap to edit." : "Active session") {
                    ThumbView(systemImage: t.plannedDate != nil ? "calendar.badge.clock" : "figure.fishing",
                              tint: t.isPlanned ? Color.dsScoreLow : Color.dsScoreGood, size: 56)
                }
            }
            .buttonStyle(.dsRow)
            Group {
                if t.isPlanned {
                    // Begin the planned session live now (+ share to crew).
                    Button { Task { await beginLive(planned: t) } } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                } else {
                    // Already a live session, so just share it.
                    Button { Task { await startTrip(from: t) } } label: {
                        Label("Share", systemImage: "person.2.badge.plus")
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: false))
            .disabled(busy)
            .padding(.trailing, DS.gutter)
        }
    }

    private struct IdString: Identifiable, Hashable { let id: String }

    private func currentName(_ code: String) -> String {
        svc.myGroups.first(where: { $0.code == code })?.name ?? "Group trip"
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
            ToastCenter.shared.show("Couldn't join. Check the code; the trip may have ended or been deleted.", style: .error)
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

/// The shared trip as an event page: who's winning, a live catch feed, friend
/// invites, your own session controls (start / pause GPS / log), and leave.
/// Serverless (CloudKit public DB) and identical for host and joiner.
struct GroupTripView: View {
    let tripId: String?
    let tripName: String

    @State private var code: String?
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    /// unreachable), so show the dead-end screen instead of a join form.
    @State private var tripMissing = false

    private let autoJoin: Bool
    private var service: CommunityService { .shared }

    /// A tournament team session lives inside a crew. Its roster is managed
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

    init(tripId: String?, tripName: String, initialCode: String? = nil) {
        self.tripId = tripId
        self.tripName = tripName
        self.autoJoin = initialCode != nil
        _code = State(initialValue: initialCode)
    }

    private var pageTint: Color? {
        guard svc.joined, !tripMissing, !confirming, code != nil, let trip else { return nil }
        return trip.isEnded ? nil : .dsScoreGood
    }

    var body: some View {
        // Without iCloud the Crew unavailable state shows and no load starts.
        CrewCloudGate { page }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(pageTint)
        .eventPageTitle(trip?.name ?? tripName)
        .toolbar {
            if let code, !confirming, svc.joined, !isTournamentTeam, !tripMissing {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: service.inviteMessage(forGroup: code, tripName: trip?.name ?? tripName)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share invite link")
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
            Button("Leave trip", role: .destructive) {
                guard let code else { return }
                // leaveGroupAndCleanup plays the warning once it lands.
                leave(code: code)
            }
        } message: {
            Text("You can rejoin with the trip code while it's still live.")
        }
        // No pull-to-refresh: it would swallow the sheet's pull-down-to-collapse
        // gesture. The feed auto-polls every 15s.
        .fullScreenCover(isPresented: $showingLog, onDismiss: {
            Task { await refresh() }
        }) {
            // The override tags the catch to this trip directly, with no linked
            // GPS session required, so members who joined mid-trip can log too.
            LogCatchView(groupCodeOverride: code)
        }
        .sheet(isPresented: $showingInvite) {
            NavigationStack {
                ScrollView {
                    if let code { invitePanel(code).pageWidth() }
                }
                .dsScreenBackground()
                .eventSheetTitle("Invite friends")
            }
            .tint(DS.accent)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            if code == nil, let tripId { code = service.groupCode(forTripId: tripId) }
            // Show last-seen members + catches instantly, then refresh in the
            // background, so reopening a trip never flashes a blank page.
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
                    // Opened a link/row for a session that's been deleted:
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

    // MARK: - Gone

    /// Dead-end state for a deleted session: say so plainly, stop any GPS
    /// session still ticking against it, and offer one-tap cleanup.
    private func tripMissingView(_ code: String) -> some View {
        VStack(spacing: DS.Space.s4) {
            ContentUnavailableView {
                Label("This trip no longer exists", systemImage: "flag.slash")
            } description: {
                Text("It was deleted, usually with its tournament. Your catches are still in your logbook.")
            }
            Button {
                // End a local GPS session still linked to the dead trip.
                if let localId = tripId ?? service.tripId(forGroupCode: code),
                   appState.tripTracker.activeTrip?.id == localId {
                    _ = appState.tripTracker.end()
                }
                leave(code: code)
            } label: {
                Label("Remove from my trips", systemImage: "trash")
            }
            .buttonStyle(.dsPrimary)
            .padding(.horizontal, DS.gutter)
        }
        .padding(.top, DS.Space.s8)
    }

    // MARK: - Join gate (opened a trip link without a community profile yet)

    /// When someone taps a trip link before setting up Community, walk them
    /// through the same one-field onboarding (just a name) before they join,
    /// so their catches carry a name and they show up in the standings.
    private var joinGate: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupTripIntro(systemImage: "person.crop.circle.badge.plus",
                           title: "Join to fish together",
                           message: "You're invited to \(trip?.name ?? tripName). Pick a name to join. No account needed.")
            EventSection("Your angler name") {
                VStack(spacing: DS.Space.s3) {
                    GroupTripTextField(placeholder: "Name", text: $joinName)
                        .textContentType(.givenName)
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
                        HStack(spacing: DS.Space.s2) {
                            if busy { ProgressView() }
                            Text("Join and continue")
                        }
                    }
                    .buttonStyle(.dsPrimary)
                    .disabled(joinName.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
                .padding(.horizontal, DS.gutter)
            }
        }
    }

    // MARK: - Setup (no group yet, e.g. from a live session with no group)

    private var setup: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupTripIntro(systemImage: "person.3.sequence.fill",
                           title: "Fish together",
                           message: "Share \(tripName) and everyone you invite sees every catch, live.")
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
                HStack(spacing: DS.Space.s2) {
                    if busy { ProgressView() }
                    Text("Start a shared trip")
                }
            }
            .buttonStyle(.dsPrimary)
            .disabled(busy)
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s6)

            EventSection("Join a friend's trip") {
                VStack(spacing: DS.Space.s3) {
                    CodeField(text: $joinCode, placeholder: "Trip code")
                    Button {
                        Task {
                            busy = true
                            if let t = await service.joinGroupTrip(code: joinCode, tripId: tripId) {
                                ToastCenter.shared.show("Joined the trip", style: .success)
                                code = t.id
                                await refresh()
                            } else {
                                ToastCenter.shared.show("Couldn't join. Check the code; the trip may have ended or been deleted.", style: .error)
                            }
                            busy = false
                        }
                    } label: {
                        Text("Join trip")
                    }
                    .buttonStyle(.dsTonal)
                    .disabled(joinCode.trimmingCharacters(in: .whitespaces).count != 6 || busy)
                }
                .padding(.horizontal, DS.gutter)
            }
        }
    }

    // MARK: - Join confirmation (from an invite link)

    @ViewBuilder private func confirmJoin(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            EventCover(species: coverSpecies, systemImage: "person.3.sequence.fill", tint: .dsScoreGood)
                .padding(.top, DS.Space.s2)
                .padding(.bottom, DS.Space.s5)
            EventHeader(title: trip?.name ?? "Group trip",
                        subtitle: trip.map { "Hosted by \($0.hostName)" }) {
                if trip?.isEnded == true { Text("Ended") } else { EventLiveTag() }
                Text("Trip invite")
            }
            if !members.isEmpty {
                HStack(spacing: DS.Space.s3) {
                    HStack(spacing: -10) {
                        ForEach(members.prefix(5)) { m in
                            AnglerAvatar(image: memberAvatars[m.id], size: 32)
                                .overlay(Circle().strokeBorder(Color.dsBackground, lineWidth: 2))
                        }
                    }
                    Text("\(members.count) \(members.count == 1 ? "angler" : "anglers") already in")
                        .font(.subheadline)
                        .foregroundStyle(Color.dsText2)
                }
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s4)
            }
            Button {
                Task {
                    busy = true
                    if await service.joinGroupTrip(code: code) != nil {
                        ToastCenter.shared.show("Joined the trip", style: .success)
                        ensureLinkedTrip(code: code, name: trip?.name ?? "Group trip")
                        confirming = false
                    } else {
                        ToastCenter.shared.show("Couldn't join the trip. It may have ended or been deleted.", style: .error)
                    }
                    busy = false
                    await refresh()
                }
            } label: {
                HStack(spacing: DS.Space.s2) {
                    if busy { ProgressView() }
                    Label("Join trip", systemImage: "person.fill.badge.plus")
                }
            }
            .buttonStyle(.dsPrimary)
            .disabled(busy)
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s6)
            EventFootnote("Your spots and exact locations stay private.")
        }
    }

    /// The invite's cover: the heaviest fish already on the trip, when this
    /// device has seen the feed.
    private var coverSpecies: Species? {
        let best = feed.max { ($0.weightKg ?? 0) < ($1.weightKg ?? 0) }
        guard let name = best?.species else { return nil }
        return (try? appState.speciesRepository.fetchByCommonName(name)) ?? nil
    }

    // MARK: - Active group

    @ViewBuilder private func activeGroup(_ code: String) -> some View {
        let ended = trip?.isEnded ?? false
        let amMember = members.contains { $0.id == service.friendCode }

        tripHeader(code, ended: ended)

        if !ended && !amMember {
            EventNotice("You're watching this trip", systemImage: "eye") {
                Button {
                    Task { await joinFromBanner(code) }
                } label: {
                    HStack(spacing: DS.Space.s1) {
                        if busy { ProgressView() }
                        Text("Join trip")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                .disabled(busy)
            }
            .padding(.top, DS.Space.s4)
        }

        tripActions(code, ended: ended, amMember: amMember)
            .padding(.top, DS.Space.s5)

        standingsSection(ended: ended)
        // The gear checklist lives in the planned-trip editor only. A live
        // session isn't the place to be packing.
        if amMember { sessionSection(code, ended: ended) }
        feedSection
        tripDetailsSection(code, ended: ended)
    }

    private func joinFromBanner(_ code: String) async {
        busy = true
        if await service.joinGroupTrip(code: code) != nil {
            ensureLinkedTrip(code: code, name: trip?.name ?? tripName)
            Haptics.success()
            ToastCenter.shared.show("You're in. Tight lines.", style: .success, haptic: false)
        } else {
            ToastCenter.shared.show("Couldn't join the trip. It may have ended or been deleted.", style: .error)
        }
        busy = false
        await refresh()
    }

    // MARK: - Header

    private func tripHeader(_ code: String, ended: Bool) -> some View {
        var subtitle: [String] = []
        if let host = trip?.hostName {
            subtitle.append(trip?.hostCode == service.friendCode ? "Hosted by you." : "Hosted by \(host).")
        }
        if let crewCode = trip?.crewCode, let crew = svc.crew(withCode: crewCode) {
            subtitle.append("Crew \(crew.name).")
        }
        // A tournament team session says so, otherwise it's indistinguishable
        // from a casual shared trip.
        if let team = trip?.teamName {
            subtitle.append("Tournament team \(team).")
        }
        return EventHeader(title: trip?.name ?? tripName, subtitle: subtitle.joined(separator: " ")) {
            if ended {
                Text(endedLabel)
            } else if let start = trip?.createdAt {
                EventLiveTag()
                Text("since \(start.formatted(date: .omitted, time: .shortened))")
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text(elapsedLabel(from: start, to: nil))
                        .monospacedDigit()
                        .foregroundStyle(Color.dsText3)
                }
            } else {
                EventLiveTag()
            }
        }
    }

    private var endedLabel: String {
        guard let start = trip?.createdAt else { return "Ended" }
        return "Ended. Fished for \(elapsedLabel(from: start, to: trip?.endedAt))"
    }

    // MARK: - Actions

    @ViewBuilder private func tripActions(_ code: String, ended: Bool, amMember: Bool) -> some View {
        ActionTriple {
            if !ended {
                Button {
                    showingLog = true
                } label: { Label("Log catch", systemImage: "plus") }
                    .buttonStyle(ActionTileStyle(amMember ? .primary : .tonal))
                    .disabled(!amMember)
            }
            if !isTournamentTeam && !ended {
                Button { showingInvite = true } label: {
                    Label("Invite", systemImage: "person.badge.plus")
                }
                .buttonStyle(ActionTileStyle(.tonal))
            }
            Menu {
                if !isTournamentTeam {
                    Button { showingInvite = true } label: {
                        Label("Invite friends", systemImage: "person.badge.plus")
                    }
                    ShareLink(item: service.inviteMessage(forGroup: code, tripName: trip?.name ?? tripName)) {
                        Label("Share invite link", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = code
                        ToastCenter.shared.show("Trip code copied", style: .info, icon: "doc.on.doc")
                    } label: {
                        Label("Copy trip code", systemImage: "doc.on.doc")
                    }
                    Divider()
                }
                if trip?.isHost == true, !ended {
                    Button(role: .destructive) {
                        confirmingEndForAll = true
                    } label: {
                        Label("End trip for everyone", systemImage: "flag.slash")
                    }
                }
                leaveButton(code, ended: ended)
            } label: {
                ActionTileLabel("More", systemImage: "ellipsis")
            }
            .accessibilityLabel("More")
        }
    }

    private func leaveButton(_ code: String, ended: Bool) -> some View {
        Button(role: .destructive) {
            if ended {
                // Removing a finished trip from your list is harmless
                // housekeeping, so no confirmation.
                leave(code: code)
            } else {
                confirmingLeave = true
            }
        } label: {
            Label(ended ? "Remove from my trips" : "Leave trip", systemImage: "person.fill.xmark")
        }
    }

    // MARK: - Standings

    private func standingsSection(ended: Bool) -> some View {
        let stats = standings()
        let hasFish = !stats.allSatisfy { $0.count == 0 }
        return EventSection(ended ? "Final results" : "Leaderboard",
                            detail: feed.isEmpty ? nil : "\(feed.count) fish") {
            if stats.isEmpty || !hasFish {
                EventInlineEmpty(text: "No fish yet. The first catch takes the lead.", systemImage: "trophy")
                    .padding(.bottom, stats.isEmpty ? 0 : DS.Space.s2)
            }
            VStack(spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.element.code) { i, s in
                    let isMe = s.code == service.friendCode
                    let row = EventRankRow(rank: i + 1,
                                           name: isMe ? "You" : s.name,
                                           subtitle: s.subtitle,
                                           value: "\(s.count) fish",
                                           images: [memberAvatars[s.code]],
                                           isMe: isMe)
                    if isMe {
                        row
                    } else {
                        NavigationLink { FriendProfileView(code: s.code) } label: { row }
                            .buttonStyle(.dim)
                    }
                }
            }
            .animation(reduceMotion ? nil : DS.Motion.softSpring, value: stats.map(\.code))
            if !feed.isEmpty {
                EventFootnote("\(Set(feed.map(\.species)).count) species on the trip so far.")
            }
        }
    }

    // MARK: - Live feed

    private var feedSection: some View {
        EventSection("Live feed") {
            if feed.isEmpty {
                EventInlineEmpty(text: "Catches land here the moment anyone logs one.")
            } else {
                VStack(spacing: 0) {
                    ForEach(feed) { c in
                        let row = leaderRow(from: c)
                        NavigationLink { CommunityCatchDetailView(row: row) } label: {
                            ArtRow(over: "\(c.friendCode == service.friendCode ? "You" : c.anglerName), \(c.date.formatted(date: .omitted, time: .shortened))",
                                   title: feedTitle(c)) {
                                CommunityCatchThumb(row: row, size: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
                            } trailing: {
                                Text(c.date, style: .relative)
                                    .font(.footnote)
                                    .foregroundStyle(Color.dsText3)
                            }
                        }
                        .buttonStyle(.dsRow)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : DS.Motion.softSpring, value: feed.map(\.id))
            }
        }
    }

    private func feedTitle(_ c: CommunityService.GroupCatch) -> String {
        if let w = c.weightKg { return "\(c.species), \(Units.weight(kg: w))" }
        if let l = c.lengthCm { return "\(c.species), \(Units.length(cm: l))" }
        return c.species
    }

    // MARK: - Trip details

    @ViewBuilder private func tripDetailsSection(_ code: String, ended: Bool) -> some View {
        EventSection("Trip") {
            if isTournamentTeam {
                EventInlineEmpty(text: "Crewmates join this team from the tournament page.", systemImage: "trophy")
            } else {
                VStack(spacing: 0) {
                    if !ended {
                        Button { showingInvite = true } label: {
                            ArtRow(title: "Invite friends", chevron: true) {
                                ThumbView(systemImage: "person.badge.plus", tint: DS.accent, size: 44)
                            }
                        }
                        .buttonStyle(.dsRow)
                    }
                    ArtRow(title: "Trip code", subtitle: "Tap the code to copy it") {
                        ThumbView(systemImage: "number", tint: .dsScoreGood, size: 44)
                    } trailing: {
                        CopyableCode(code: code, font: .system(.headline, design: .monospaced))
                    }
                }
            }
            EventDangerButton(title: ended ? "Remove from my trips" : "Leave trip",
                              systemImage: "person.fill.xmark") {
                if ended { leave(code: code) } else { confirmingLeave = true }
            }
        }
    }

    // MARK: - Invite (sheet content)

    @ViewBuilder private func invitePanel(_ code: String) -> some View {
        let memberCodes = Set(members.map(\.id))
        let invitable = friendProfiles.filter { !memberCodes.contains($0.id) }

        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: DS.Space.s3) {
                Text("Trip code")
                    .font(.subheadline)
                    .foregroundStyle(Color.dsText2)
                CopyableCode(code: code, font: .system(.largeTitle, design: .monospaced).bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Tap the code to copy it")
                    .font(.footnote)
                    .foregroundStyle(Color.dsText3)
                ShareLink(item: service.inviteMessage(forGroup: code, tripName: trip?.name ?? tripName)) {
                    Label("Share link", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.dsTonal)
                .padding(.top, DS.Space.s1)
            }
            .frame(maxWidth: .infinity)
            .padding(DS.Space.s5)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s2)

            SectionTitle("Friends")
                .padding(.top, DS.Space.s6)
            if friendProfiles.isEmpty {
                EventInlineEmpty(text: "Add friends on the Crew tab to invite them in one tap.",
                                 systemImage: "person.2")
            } else if invitable.isEmpty {
                EventInlineEmpty(text: "All your friends are on this trip.", systemImage: "checkmark.circle")
            } else {
                ForEach(invitable) { f in
                    ArtRow(title: f.name, subtitle: f.homeWater.isEmpty ? nil : f.homeWater) {
                        AnglerAvatar(image: f.avatar, size: 44)
                    } trailing: {
                        if invited.contains(f.id) {
                            Label("Invited", systemImage: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.dsScoreGood)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Button("Invite") {
                                withAnimation(DS.Motion.spring) { _ = invited.insert(f.id) }
                                Task {
                                    await service.inviteFriend(f.id, toGroup: code,
                                                               tripName: trip?.name ?? tripName)
                                    ToastCenter.shared.show("Invite sent to \(f.name)", style: .success)
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                            .accessibilityLabel("Invite \(f.name)")
                        }
                    }
                }
            }

            Button {
                withAnimation(DS.Motion.softSpring) { showAddByCode.toggle() }
            } label: {
                ArtRow(title: "Invite by angler code") {
                    ThumbView(systemImage: "number", tint: DS.accent, size: 44)
                } trailing: {
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.dsText3)
                        .rotationEffect(.degrees(showAddByCode ? 180 : 0))
                }
            }
            .buttonStyle(.dsRow)
            .padding(.top, DS.Space.s4)
            if showAddByCode {
                VStack(spacing: DS.Space.s3) {
                    CodeField(text: $joinCode, placeholder: "Angler code")
                    Button {
                        let c = joinCode.uppercased().trimmingCharacters(in: .whitespaces)
                        joinCode = ""
                        Task {
                            await service.inviteFriend(c, toGroup: code, tripName: trip?.name ?? tripName)
                            ToastCenter.shared.show("Invite sent", style: .success)
                        }
                    } label: {
                        Label("Send invite", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.dsPrimary)
                    .disabled(joinCode.trimmingCharacters(in: .whitespaces).count != 6)
                }
                .padding(.horizontal, DS.gutter)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.bottom, DS.Space.s6)
    }

    // MARK: - Your GPS session

    @ViewBuilder private func sessionSection(_ code: String, ended: Bool) -> some View {
        let tracker = appState.tripTracker
        let linkedId = service.tripId(forGroupCode: code)
        let isThisActive = tracker.isTracking && tracker.activeTrip?.id == linkedId && linkedId != nil

        EventSection("Your GPS session") {
            if ended {
                if isThisActive {
                    EventKeyValueList(rows: [.init(label: "Trip", value: "Ended")])
                    Button(role: .destructive) {
                        Haptics.warning()
                        _ = appState.tripTracker.end()
                    } label: {
                        Label("End my session", systemImage: "stop.circle")
                            .foregroundStyle(Color.dsScoreSlow)
                    }
                    .buttonStyle(.dsTonal)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s3)
                } else if let linkedId, let lt = (try? appState.tripRepository.fetch(linkedId)) ?? nil {
                    // The shared trip is over, but YOUR session (track, stats,
                    // catches) is still worth opening.
                    NavigationLink {
                        SessionDetailView(trip: lt)
                    } label: {
                        ArtRow(title: "View your session", subtitle: "Your GPS track, stats and catches", chevron: true) {
                            ThumbView(systemImage: "map", tint: DS.accent, size: 48)
                        }
                    }
                    .buttonStyle(.dsRow)
                } else {
                    EventInlineEmpty(text: "This trip has ended.", systemImage: "flag.checkered")
                }
            } else if isThisActive, tracker.isDayActive {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let start = tracker.activeTrip?.currentDayStart ?? tracker.activeTrip?.startDate ?? .now
                    EventKeyValueList(rows: [
                        .init(label: tracker.manualPaused ? "GPS paused" : "Tracking live",
                              value: SessionFormat.duration(tracker.manualPaused ? 0 : Date.now.timeIntervalSince(start)),
                              emphasized: true),
                        .init(label: "Distance", value: SessionFormat.distance(trackDistance(tracker))),
                        .init(label: "Your fish", value: "\(myCatchCount())"),
                    ])
                }
                HStack(spacing: DS.Space.s2) {
                    Button {
                        if tracker.manualPaused { tracker.resumeTracking() } else { tracker.pauseTracking() }
                    } label: {
                        Label(tracker.manualPaused ? "Resume" : "Pause",
                              systemImage: tracker.manualPaused ? "play.fill" : "pause.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.dsTonal)
                    .buttonHaptic(.toggle)
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
                        Label("Finish", systemImage: "flag.checkered")
                            .font(.headline)
                            .foregroundStyle(Color.dsText)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color.dsTonal, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                    }
                }
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s3)
            } else if isThisActive {
                EventInlineEmpty(text: "Day ended. The trip is still open.", systemImage: "moon.zzz")
                VStack(spacing: DS.Space.s2) {
                    Button {
                        Haptics.success()
                        tracker.startNextDay()
                    } label: {
                        Label("Start next day", systemImage: "sun.max.fill")
                    }
                    .buttonStyle(.dsPrimary)
                    Button(role: .destructive) {
                        Haptics.warning()
                        _ = appState.tripTracker.end()
                    } label: {
                        Label("End trip", systemImage: "stop.circle")
                            .foregroundStyle(Color.dsScoreSlow)
                    }
                    .buttonStyle(.dsTonal)
                }
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s3)
            } else if tracker.isTracking {
                EventInlineEmpty(text: "Another session is running. End it to track this trip.",
                                 systemImage: "location.slash")
            } else if let linkedId, let lt = (try? appState.tripRepository.fetch(linkedId)) ?? nil {
                if lt.isCompleted {
                    EventInlineEmpty(text: "Your session ended. New catches still count.",
                                     systemImage: "flag.checkered")
                } else {
                    Button {
                        Haptics.success()
                        _ = appState.tripTracker.startPlanned(lt)
                    } label: {
                        Label("Start GPS session", systemImage: "location.fill")
                    }
                    .buttonStyle(.dsTonal)
                    .padding(.horizontal, DS.gutter)
                    EventFootnote("Optional. Records your track alongside the trip.")
                }
            }
        }
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
        var bestSpecies: String?
        var species: Set<String>
        var subtitle: String {
            guard let bestSpecies else { return "No fish yet" }
            if let bestKg { return "Biggest \(bestSpecies.lowercased()), \(Units.weight(kg: bestKg))" }
            if let bestCm { return "Biggest \(bestSpecies.lowercased()), \(Units.length(cm: bestCm))" }
            return "\(species.count) species"
        }
    }

    /// Per-member standings from the group's catches (members with none included).
    private func standings() -> [MemberStat] {
        var byCode: [String: MemberStat] = [:]
        for m in members {
            byCode[m.id] = MemberStat(code: m.id, name: m.name, count: 0, bestKg: nil, bestCm: nil, bestSpecies: nil, species: [])
        }
        for c in feed {
            var s = byCode[c.friendCode] ?? MemberStat(code: c.friendCode, name: c.anglerName, count: 0, bestKg: nil, bestCm: nil, bestSpecies: nil, species: [])
            s.count += 1
            s.species.insert(c.species)
            if let w = c.weightKg, w > (s.bestKg ?? 0) {
                s.bestKg = w
                s.bestSpecies = c.species
            }
            if let l = c.lengthCm, l > (s.bestCm ?? 0) {
                s.bestCm = l
                if s.bestKg == nil { s.bestSpecies = c.species }
            }
            if s.bestSpecies == nil { s.bestSpecies = c.species }
            byCode[c.friendCode] = s
        }
        return byCode.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if ($0.bestKg ?? 0) != ($1.bestKg ?? 0) { return ($0.bestKg ?? 0) > ($1.bestKg ?? 0) }
            return $0.code < $1.code
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
        let (t, m, f) = await (freshTrip, freshMembers, freshFeed)
        // New catches drop into the feed and the leaderboard re-sorts.
        withAnimation(reduceMotion ? nil : DS.Motion.softSpring) {
            trip = t
            members = m
            feed = f
        }
        // A nil trip can mean "deleted" (a Mate removed the tournament and its
        // sessions) or just "offline". Probe before declaring it gone, and
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
            ToastCenter.shared.show("Session ended. The shared trip is over.", style: .info)
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
}
