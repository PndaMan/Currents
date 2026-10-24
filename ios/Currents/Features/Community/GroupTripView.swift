import SwiftUI
import CoreLocation
import UIKit

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

// MARK: - Setup: start (pick a trip) or join by code

/// Start a shared trip, based on a new or an existing/planned trip, or join
/// one by code. On join, a local trip is created and linked so your catches
/// sync to the group and you get your own session to track.
struct GroupTripSetupView: View {
    /// When launched from a Crew, trips created here are tied to that crew.
    var crewCode: String? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var svc: CommunityService { .shared }

    @State private var trips: [Trip] = []
    @State private var joinCode = ""
    @State private var busy = false
    @State private var openedCode: String?
    @State private var showingPlanner = false
    @State private var editingPlan: Trip?
    @State private var showingStartNow = false
    @FocusState private var joinFocused: Bool

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
            ScrollView { content(proxy) }
                .scrollDismissesKeyboard(.interactively)
                .detailTint(nil)
                .eventPageTitle("Group trip")
        }
        .sheet(isPresented: $showingPlanner) {
            // Planning only schedules the trip locally. You start it (going
            // live + sharing to the crew) from the list when it's time.
            PlanSessionSheet(onSaved: { _ in reloadTrips() })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingStartNow) {
            StartLiveTripSheet { name in Task { await beginLiveNew(name: name) } }
        }
        .sheet(item: $editingPlan, onDismiss: reloadTrips) { t in
            PlanSessionSheet(editingTrip: t)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .navigationDestination(item: openedBinding) { c in
            GroupTripView(tripId: svc.tripId(forGroupCode: c.id), tripName: currentName(c.id), initialCode: c.id)
        }
        .task { reloadTrips() }
    }

    private func content(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CommunityHero(label: crewCode.flatMap { svc.crew(withCode: $0)?.name } ?? "Fish together",
                          title: "Group trip",
                          line: "Everyone sees every catch, live.") {
                ThumbView(systemImage: "person.3.fill", tint: CrewTint.region, size: 92)
            }
            .padding(.top, DS.Space.s2)
            actions(proxy)
                .padding(.top, DS.Space.s5)
            if !startableTrips.isEmpty {
                CrewSection(title: "Your trips") {
                    VStack(spacing: 0) {
                        ForEach(startableTrips) { t in yourTripRow(t) }
                    }
                    SectionFootnote("Start one to take it live, or tap it to edit.")
                }
            }
            CrewSection(title: "Join a friend's trip") { joinForm }
                .id(Self.joinAnchor)
        }
        .padding(.bottom, DS.Space.s8)
        .pageWidth()
    }

    private func actions(_ proxy: ScrollViewProxy) -> some View {
        ActionTriple {
            Button { showingStartNow = true } label: {
                Label("Start now", systemImage: "dot.radiowaves.left.and.right")
            }
            .buttonStyle(ActionTileStyle(.primary))
            Button { showingPlanner = true } label: {
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
    }

    private var joinForm: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text("Enter the 6-character code from whoever started it.")
                .font(.body)
                .foregroundStyle(.dsText2)
                .fixedSize(horizontal: false, vertical: true)
            CodeField(text: $joinCode, placeholder: "Trip code")
                .focused($joinFocused)
            Button { Task { await joinTrip() } } label: {
                if busy { ProgressView() } else { Text("Join trip") }
            }
            .buttonStyle(.dsPrimary)
            .disabled(busy || joinCode.trimmingCharacters(in: .whitespaces).count != 6)
        }
        .padding(.horizontal, DS.gutter)
    }

    private func yourTripRow(_ t: Trip) -> some View {
        HStack(spacing: 0) {
            // Tap a planned trip to edit its name, date and checklist; tapping
            // an active session shares it.
            Button {
                if t.isPlanned { editingPlan = t } else { Task { await startTrip(from: t) } }
            } label: {
                ArtRow(over: t.plannedDate.map { "\($0.formatted(.dateTime.day().month(.abbreviated))), \(ForecastFormat.time($0))" },
                       title: t.name,
                       subtitle: t.isPlanned ? "Planned. Tap to edit." : "Active session") {
                    if t.plannedDate != nil {
                        ThumbView(systemImage: "calendar.badge.clock", tint: CrewTint.calendar, size: 56)
                    } else {
                        ThumbView(systemImage: "figure.fishing", tint: .dsScoreGood, size: 56)
                    }
                }
            }
            .buttonStyle(.dim)
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

    private var openedBinding: Binding<IdString?> {
        Binding(get: { openedCode.map { IdString(id: $0) } },
                set: { openedCode = $0?.id })
    }

    private func reloadTrips() {
        trips = (try? appState.tripRepository.fetchAll()) ?? []
    }

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

// MARK: - Start live trip

/// Name a new live trip, then start it. The same form as the crew sheets.
private struct StartLiveTripSheet: View {
    let start: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = SessionFormat.defaultName()

    var body: some View {
        NavigationStack {
            ScrollView { form }
                .scrollDismissesKeyboard(.interactively)
                .dsScreenBackground()
                .eventSheetTitle("Start live trip", close: "Cancel")
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: DS.Space.s5) {
            CommunityHero(label: "Live now", title: "Start a trip",
                          line: "GPS starts where you are and the crew follows along.") {
                ThumbView(systemImage: "dot.radiowaves.left.and.right", tint: .dsScoreGood, size: 72)
            }
            .padding(.horizontal, -DS.gutter)
            CrewTextField(label: "Trip name", placeholder: "Morning session", text: $name)
                .submitLabel(.go)
                .onSubmit(go)
            Button(action: go) { Text("Start live trip") }
                .buttonStyle(.dsPrimary)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s3)
        .padding(.bottom, DS.Space.s6)
        .pageWidth()
    }

    private func go() {
        dismiss()
        start(name)
    }
}

// MARK: - Group trip page

/// The shared trip as an event page: cover, title, three actions, then the
/// leaderboard, your GPS session, the live feed, invites and details.
/// Serverless (CloudKit public DB) and identical for host and joiner.
struct GroupTripView: View {
    let tripId: String?
    let tripName: String

    @State private var code: String?
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var svc = CommunityService.shared
    @State private var trip: CommunityService.GroupTrip?
    @State private var members: [CommunityService.GroupMember] = []
    @State private var feed: [CommunityService.GroupCatch] = []
    @State private var memberAvatars: [String: UIImage] = [:]
    /// The heaviest fish on the trip, for the cover and the page tint.
    @State private var coverSpecies: Species?
    /// The first refresh has finished, so empty lists mean empty.
    @State private var loaded = false
    /// The last refresh couldn't reach iCloud, so the page shows what it had.
    @State private var offline = false
    @State private var lastUpdated: Date?
    @State private var joinCode = ""
    @State private var inviteCode = ""
    @State private var busy = false
    @State private var confirming = false
    @State private var friendProfiles: [CommunityService.Profile] = []
    @State private var invited: Set<String> = []
    @State private var showingLog = false
    @State private var showingInvite = false
    @State private var confirmingEndForAll = false
    @State private var confirmingLeave = false
    /// The trip's record is confirmed GONE from the server (deleted, not just
    /// unreachable), so show the dead-end screen instead of a join form.
    @State private var tripMissing = false

    private let autoJoin: Bool
    private var service: CommunityService { .shared }

    init(tripId: String?, tripName: String, initialCode: String? = nil) {
        self.tripId = tripId
        self.tripName = tripName
        self.autoJoin = initialCode != nil
        _code = State(initialValue: initialCode)
    }

    /// A tournament team session lives inside a crew. Its roster is managed
    /// from the tournament screen (join a team / admin assign), so friend
    /// invites and share links make no sense here and are hidden.
    private var isTournamentTeam: Bool {
        trip?.tournamentCode != nil || trip?.teamName != nil
            || service.myGroups.first(where: { $0.code == code })?.teamName != nil
    }

    private var ended: Bool { trip?.isEnded ?? false }

    private var isHost: Bool { trip?.isHost == true }

    private var inMyGroups: Bool { service.myGroups.contains { $0.code == code } }

    /// On the trip's roster. Offline with nothing cached, the local list of
    /// my trips stands in for the roster.
    private var amMember: Bool {
        members.contains { $0.id == service.friendCode } || (members.isEmpty && inMyGroups)
    }

    private var canLeave: Bool { amMember || inMyGroups }

    /// Invites belong to live trips that aren't tournament teams.
    private var showsInvites: Bool { !isTournamentTeam && !ended }

    private var showsTrip: Bool {
        svc.joined && !tripMissing && code != nil
    }

    private func leave(code: String) {
        Task {
            await leaveGroupAndCleanup(code: code, tripId: tripId, appState: appState)
            self.code = nil
            trip = nil; members = []; feed = []
            tripMissing = false
        }
    }

    var body: some View {
        // Without iCloud the Crew unavailable state shows and no load starts.
        CrewCloudGate { page }
    }

    private var page: some View {
        scrollPage
            .confirmationDialog("End the trip for everyone?", isPresented: $confirmingEndForAll,
                                titleVisibility: .visible) {
                Button("End trip", role: .destructive, action: endForAll)
            } message: {
                Text("Every member's live feed closes. Catches already logged stay on the trip.")
            }
            .confirmationDialog("Leave this trip?", isPresented: $confirmingLeave,
                                titleVisibility: .visible) {
                Button("Leave trip", role: .destructive) {
                    // leaveGroupAndCleanup plays the warning once it lands.
                    if let code { leave(code: code) }
                }
            } message: {
                Text("You can rejoin with the trip code while it's still live.")
            }
            // No pull-to-refresh: it would swallow the sheet's pull-down-to-
            // collapse gesture. The feed auto-polls every 15s.
            .fullScreenCover(isPresented: $showingLog, onDismiss: { Task { await refresh() } }) {
                // The override tags the catch to this trip directly, with no
                // linked GPS session required, so members who joined mid-trip
                // can log too.
                LogCatchView(groupCodeOverride: code)
            }
            .sheet(isPresented: $showingInvite) { inviteSheet }
            .task { await load() }
    }

    private var scrollPage: some View {
        ScrollView { content }
            .scrollDismissesKeyboard(.interactively)
            .detailTint(showsTrip ? coverSpecies?.artTint : nil)
            .eventPageTitle(trip?.name ?? tripName)
            .toolbar {
                if let code, showsTrip, !confirming, showsInvites {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: service.inviteMessage(forGroup: code, tripName: trip?.name ?? tripName)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share invite link")
                    }
                }
            }
    }

    private var content: some View {
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

    private func endForAll() {
        guard let code else { return }
        Haptics.warning()
        Task {
            await service.endGroupTrip(code: code)
            ToastCenter.shared.show("Trip ended for everyone", style: .info, haptic: false)
            await refresh()
        }
    }

    private func load() async {
        if code == nil, let tripId { code = service.groupCode(forTripId: tripId) }
        // Show last-seen members + catches instantly, then refresh in the
        // background, so reopening a trip never flashes a blank page.
        if let c = code {
            members = service.cachedGroupMembers(c)
            feed = service.cachedGroupCatches(c)
            coverSpecies = eventCoverSpecies(feed, appState: appState)
        }
        if autoJoin, let c = code {
            trip = await service.groupTrip(code: c)
            members = await service.groupMembers(code: c)
            let alreadyIn = members.contains { $0.id == service.friendCode }
            if alreadyIn {
                ensureLinkedTrip(code: c, name: trip?.name ?? tripName)
                await refresh()
            } else if let t = trip, !t.isEnded {
                confirming = true
            } else if trip == nil, await service.groupTripExists(code: c) == .missing {
                // Opened a link/row for a session that's been deleted:
                // dead-end screen, never the join form for a dead code.
                tripMissing = true
            } else {
                // An ended trip, or no connection: show what there is.
                await refresh()
            }
        } else {
            if let c = code { ensureLinkedTrip(code: c, name: trip?.name ?? tripName) }
            await refresh()
        }
        await pollLoop()
    }

    // Light polling so members + catches stay in sync while the view is open.
    private func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            if code != nil, !confirming { await refresh() }
        }
    }

    // MARK: - Shared page parts

    private var cover: some View {
        EventCover(species: coverSpecies, systemImage: "person.3.sequence.fill", tint: DS.accent)
            .padding(.top, DS.Space.s2)
    }

    private var hostLine: String? {
        guard let trip else { return nil }
        let host = trip.hostCode == service.friendCode ? "Hosted by you" : "Hosted by \(trip.hostName)"
        if let crewCode = trip.crewCode, let crew = svc.crew(withCode: crewCode) {
            return "\(host) in \(crew.name)"
        }
        return host
    }

    /// Today's hero: status over the trip name, the host, and the anglers'
    /// faces on the right.
    private var tripHeader: some View {
        HStack(alignment: .center, spacing: DS.Space.s4) {
            VStack(alignment: .leading, spacing: 4) {
                tripStatus
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
                Text(trip?.name ?? tripName)
                    .font(.title.bold())
                    .foregroundStyle(.dsText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let hostLine {
                    Text(hostLine)
                        .font(.callout)
                        .foregroundStyle(.dsText2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            heroVisual
        }
        .padding(.horizontal, DS.gutter)
    }

    @ViewBuilder private var tripStatus: some View {
        if ended {
            Text(endedLine)
        } else {
            HStack(spacing: 6) {
                EventLiveTag()
                if let start = trip?.createdAt {
                    Text("Since \(eventTimeText(start))")
                }
            }
        }
    }

    @ViewBuilder private var heroVisual: some View {
        if members.isEmpty {
            ThumbView(systemImage: "person.3.fill", tint: CrewTint.region, size: 92)
        } else {
            EventAvatarStack(images: members.prefix(3).map { memberAvatars[$0.id] }, size: 52)
        }
    }

    /// Anglers, fish, species and time on the water as Today's stat tiles.
    private var tripStats: some View {
        let speciesCount = Set(feed.map(\.species)).count
        return StatStrip {
            StatTile("Anglers", systemImage: "person.2.fill", tint: CrewTint.people,
                     value: "\(members.count)", width: 120)
            StatTile("Fish", systemImage: "fish.fill", tint: CrewTint.fish,
                     value: "\(feed.count)", width: 120)
            StatTile("Species", systemImage: "leaf.fill", tint: CrewTint.species,
                     value: "\(speciesCount)", width: 120)
            if let trip {
                StatTile(trip.endedAt == nil ? "Fishing for" : "Fished for", systemImage: "timer",
                         tint: CrewTint.region, value: elapsedLabel(from: trip.createdAt, to: trip.endedAt),
                         width: 132)
            }
        }
    }

    private var endedLine: String {
        "Ended \((trip?.endedAt ?? .now).formatted(date: .abbreviated, time: .omitted))"
    }

    // MARK: - Gone

    /// Dead-end state for a deleted session: say so plainly, stop any GPS
    /// session still ticking against it, and offer one-tap cleanup.
    private func tripMissingView(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CommunityHero(label: "No longer available", title: trip?.name ?? tripName) {
                ThumbView(systemImage: "flag.slash.fill", tint: .dsScoreSlow, size: 72)
            }
            .padding(.top, DS.Space.s4)
            InlineEmpty(systemImage: "flag.slash",
                        text: "This trip was deleted, usually with its tournament. Your catches are still in your logbook.")
                .padding(.top, DS.Space.s5)
            DangerButton(title: "Remove from my trips", systemImage: "trash") {
                // End a local GPS session still linked to the dead trip.
                if let localId = tripId ?? service.tripId(forGroupCode: code),
                   appState.tripTracker.activeTrip?.id == localId {
                    _ = appState.tripTracker.end()
                }
                leave(code: code)
            }
            .padding(.top, DS.Space.s8)
        }
    }

    // MARK: - Join gate (opened a trip link without a community profile yet)

    /// When someone taps a trip link before setting up Community, walk them
    /// through the same one-field onboarding (just a name) before they join,
    /// so their catches carry a name and they show up in the standings.
    private var joinGate: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            CommunityHero(label: "Trip invite", title: trip?.name ?? tripName,
                          line: "Pick a name to join. No account needed.")
                .padding(.top, DS.Space.s4)
            CrewJoinForm(buttonTitle: "Join and continue") { await afterProfileJoin() }
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s6)
        }
    }

    /// Profile made: carry on into the trip's own join confirmation.
    private func afterProfileJoin() async {
        guard let c = code else { return }
        trip = await service.groupTrip(code: c)
        members = await service.groupMembers(code: c)
        if members.contains(where: { $0.id == service.friendCode }) {
            ensureLinkedTrip(code: c, name: trip?.name ?? tripName)
            await refresh()
        } else {
            confirming = trip.map { !$0.isEnded } ?? false
        }
    }

    // MARK: - Setup (no group yet, e.g. from a live session with no group)

    private var setup: some View {
        VStack(alignment: .leading, spacing: 0) {
            CommunityHero(label: "Group trip", title: tripName,
                          line: "Everyone you invite sees every catch, live.") {
                ThumbView(systemImage: "person.3.fill", tint: CrewTint.region, size: 92)
            }
            .padding(.top, DS.Space.s2)
            Button { Task { await startShared() } } label: {
                if busy { ProgressView() } else { Text("Start a shared trip") }
            }
            .buttonStyle(.dsPrimary)
            .disabled(busy)
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s6)
            CrewSection(title: "Join a friend's trip") { setupJoinForm }
        }
    }

    private var setupJoinForm: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text("Enter the 6-character code from whoever started it.")
                .font(.body)
                .foregroundStyle(.dsText2)
                .fixedSize(horizontal: false, vertical: true)
            CodeField(text: $joinCode, placeholder: "Trip code")
            Button { Task { await joinByCode() } } label: { Text("Join trip") }
                .buttonStyle(.dsTonal)
                .disabled(joinCode.trimmingCharacters(in: .whitespaces).count != 6 || busy)
        }
        .padding(.horizontal, DS.gutter)
    }

    private func startShared() async {
        busy = true
        if let new = await service.createGroupTrip(name: tripName, tripId: tripId ?? UUID().uuidString) {
            ToastCenter.shared.show("Group trip created", style: .success)
            code = new
            await refresh()
        } else {
            ToastCenter.shared.show("Couldn't start the shared trip", style: .error)
        }
        busy = false
    }

    private func joinByCode() async {
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

    // MARK: - Join confirmation (from an invite link)

    private func confirmJoin(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            CommunityHero(label: isTournamentTeam ? "Tournament team" : "Trip invite",
                          title: trip?.name ?? tripName, line: hostLine)
                .padding(.top, DS.Space.s4)
            if !members.isEmpty {
                CrewSection(title: "Going", detail: "\(members.count)") { goingStrip }
            }
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Button { Task { await confirmJoinTapped(code) } } label: {
                    if busy { ProgressView() } else { Text(isTournamentTeam ? "Join team" : "Join trip") }
                }
                .buttonStyle(.dsPrimary)
                .disabled(busy)
                Text("Your spots and exact locations stay private.")
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
            }
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s6)
        }
    }

    private var goingStrip: some View {
        HStack(spacing: DS.Space.s3) {
            HStack(spacing: -10) {
                ForEach(members.prefix(5)) { m in
                    AnglerAvatar(image: memberAvatars[m.id], size: 32)
                        .overlay(Circle().strokeBorder(Color.dsBackground, lineWidth: 2))
                }
            }
            Text(members.count == 1 ? "1 angler already in" : "\(members.count) anglers already in")
                .font(.subheadline)
                .foregroundStyle(.dsText2)
        }
        .padding(.horizontal, DS.gutter)
        .accessibilityElement(children: .combine)
    }

    private func confirmJoinTapped(_ code: String) async {
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

    // MARK: - Active group

    @ViewBuilder private func activeGroup(_ code: String) -> some View {
        cover
        tripHeader
            .padding(.top, DS.Space.s4)
        tripActions(code)
        if offline {
            EventNotice(eventOfflineText("Catches", since: lastUpdated), systemImage: "wifi.slash") {
                Button("Try again") { Task { await refresh() } }
            }
            .padding(.top, DS.Space.s4)
        }
        tripStats
            .padding(.top, DS.Space.s5)
        standingsSection
        // The gear checklist lives in the planned-trip editor only. A live
        // session isn't the place to be packing.
        if amMember { sessionSection(code) }
        feedSection
        if showsInvites { inviteSection(code) }
        detailsSection
        if canLeave {
            DangerButton(title: ended ? "Remove from my trips" : "Leave trip",
                         systemImage: "person.fill.xmark") {
                // Removing a finished trip from your list is harmless
                // housekeeping, so no confirmation.
                if ended { leave(code: code) } else { confirmingLeave = true }
            }
            .padding(.top, DS.Space.s8)
        }
    }

    private func joinFromPage(_ code: String) async {
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

    // MARK: - Actions

    @ViewBuilder private func tripActions(_ code: String) -> some View {
        if ended {
            if let track = myLinkedTrip(code) {
                ActionTriple {
                    // The shared trip is over, but YOUR session (track, stats,
                    // catches) is still worth opening.
                    NavigationLink { SessionDetailView(trip: track) } label: {
                        ActionTileLabel("Your track", systemImage: "map", kind: .primary)
                    }
                    .buttonStyle(.dim)
                    if hasMoreItems { moreMenu(code) }
                }
                .padding(.top, DS.Space.s5)
            }
        } else {
            ActionTriple {
                firstTile(code)
                secondTile
                if hasMoreItems { moreMenu(code) }
            }
            .padding(.top, DS.Space.s5)
        }
    }

    @ViewBuilder private func firstTile(_ code: String) -> some View {
        if amMember {
            Button { showingLog = true } label: { Label("Log catch", systemImage: "plus") }
                .buttonStyle(ActionTileStyle(.primary))
        } else {
            Button { Task { await joinFromPage(code) } } label: {
                Label(isTournamentTeam ? "Join team" : "Join trip", systemImage: "person.badge.plus")
            }
            .buttonStyle(ActionTileStyle(.primary))
            .disabled(busy)
        }
    }

    /// Invite on a shared trip. On a tournament team, whose roster lives on
    /// the tournament page, the GPS control for members instead.
    @ViewBuilder private var secondTile: some View {
        if showsInvites {
            Button { showingInvite = true } label: {
                Label("Invite", systemImage: "person.badge.plus")
            }
            .buttonStyle(ActionTileStyle(.tonal))
        } else if amMember, let code {
            gpsTile(sessionState(code))
        }
    }

    @ViewBuilder private func gpsTile(_ state: SessionState) -> some View {
        let tracker = appState.tripTracker
        switch state {
        case .tracking:
            Button {
                if tracker.manualPaused { tracker.resumeTracking() } else { tracker.pauseTracking() }
            } label: {
                Label(tracker.manualPaused ? "Resume GPS" : "Pause GPS",
                      systemImage: tracker.manualPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(ActionTileStyle(.tonal))
            .buttonHaptic(.toggle)
        case .dayEnded:
            Button {
                Haptics.success()
                tracker.startNextDay()
            } label: {
                Label("Next day", systemImage: "sun.max.fill")
            }
            .buttonStyle(ActionTileStyle(.tonal))
        case .notStarted(let lt):
            Button {
                Haptics.success()
                _ = tracker.startPlanned(lt)
            } label: {
                Label("Start GPS", systemImage: "location.fill")
            }
            .buttonStyle(ActionTileStyle(.tonal))
        default:
            EmptyView()
        }
    }

    private var hasMoreItems: Bool {
        (showsInvites) || (isHost && !ended) || canLeave
    }

    private func moreMenu(_ code: String) -> some View {
        Menu {
            if showsInvites {
                ShareLink(item: service.inviteMessage(forGroup: code, tripName: trip?.name ?? tripName)) {
                    Label("Share invite link", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = code
                    ToastCenter.shared.show("Trip code copied", style: .info, icon: "doc.on.doc")
                } label: {
                    Label("Copy trip code", systemImage: "doc.on.doc")
                }
                if (isHost && !ended) || canLeave { Divider() }
            }
            if isHost && !ended {
                Button(role: .destructive) {
                    confirmingEndForAll = true
                } label: {
                    Label("End trip for everyone", systemImage: "flag.slash")
                }
            }
            if canLeave {
                Button(role: .destructive) {
                    if ended { leave(code: code) } else { confirmingLeave = true }
                } label: {
                    Label(ended ? "Remove from my trips" : "Leave trip", systemImage: "person.fill.xmark")
                }
            }
        } label: {
            ActionTileLabel("More", systemImage: "ellipsis")
        }
        .buttonStyle(.dim)
        .accessibilityLabel("More")
    }

    // MARK: - Standings

    private var standingsSection: some View {
        let stats = standings()
        return CrewSection(title: ended ? "Final results" : "Leaderboard",
                           detail: feed.isEmpty ? nil : "\(feed.count) fish") {
            if !loaded && stats.isEmpty {
                EventSkeletonRows(count: 3, thumbSize: 36, label: "Loading the leaderboard")
            } else {
                standingsRows(stats)
            }
        }
    }

    @ViewBuilder private func standingsRows(_ stats: [MemberStat]) -> some View {
        if !stats.contains(where: { $0.count > 0 }) {
            InlineEmpty(text: ended ? "Nobody landed a fish on this trip." : "No fish yet. The first catch takes the lead.",
                        systemImage: "trophy")
                .padding(.bottom, stats.isEmpty ? 0 : DS.Space.s2)
        }
        VStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.code) { i, s in
                standingRow(s, rank: i + 1)
            }
        }
        .animation(reduceMotion ? nil : DS.Motion.softSpring, value: stats.map(\.code))
        if !feed.isEmpty {
            SectionFootnote("\(Set(feed.map(\.species)).count) species on the trip so far.")
        }
    }

    @ViewBuilder private func standingRow(_ s: MemberStat, rank: Int) -> some View {
        let isMe = s.code == service.friendCode
        let row = EventRankRow(rank: rank,
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

    // MARK: - Live feed

    private var feedSection: some View {
        CrewSection(title: ended ? "Catches" : "Live feed") {
            if feed.isEmpty {
                if loaded {
                    InlineEmpty(text: ended ? "No catches were logged on this trip."
                                            : "Catches land here the moment anyone logs one.")
                } else {
                    EventSkeletonRows(count: 2, thumbSize: 64, label: "Loading catches")
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(feed) { c in feedRow(c) }
                }
                .animation(reduceMotion ? nil : DS.Motion.softSpring, value: feed.map(\.id))
            }
        }
    }

    private func feedRow(_ c: CommunityService.GroupCatch) -> some View {
        let row = leaderRow(from: c)
        let who = c.friendCode == service.friendCode ? "You" : c.anglerName
        return NavigationLink { CommunityCatchDetailView(row: row) } label: {
            ArtRow(over: "\(who), \(ForecastFormat.time(c.date))",
                   title: feedTitle(c)) {
                CommunityCatchThumb(row: row, size: 64)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
            } trailing: {
                Text(c.date, style: .relative)
                    .font(.footnote)
                    .foregroundStyle(.dsText3)
            }
        }
        .buttonStyle(.dim)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func feedTitle(_ c: CommunityService.GroupCatch) -> String {
        if let w = c.weightKg { return "\(c.species), \(Units.weight(kg: w))" }
        if let l = c.lengthCm { return "\(c.species), \(Units.length(cm: l))" }
        return c.species
    }

    // MARK: - Invite and details

    private func inviteSection(_ code: String) -> some View {
        CrewSection(title: "Invite") {
            VStack(spacing: 0) {
                Button { showingInvite = true } label: {
                    ArtRow(title: "Invite friends", subtitle: "Send an invite in one tap", chevron: true) {
                        ThumbView(systemImage: "person.badge.plus", tint: .dsScoreGood, size: 44)
                    }
                }
                .buttonStyle(.dim)
                ArtRow(title: "Trip code", subtitle: "Tap the code to copy it") {
                    ThumbView(systemImage: "number", tint: CrewTint.region, size: 44)
                } trailing: {
                    CopyableCode(code: code, font: .system(.headline, design: .monospaced))
                }
            }
        }
    }

    private var detailsSection: some View {
        CrewSection(title: "Details") {
            detailCard
            if isTournamentTeam {
                SectionFootnote("Crewmates join this team from the tournament page.")
            }
        }
    }

    private struct DetailItem {
        let title: String
        let value: String
        let systemImage: String
        let tint: Color
    }

    private var detailItems: [DetailItem] {
        var rows: [DetailItem] = []
        if let trip {
            rows.append(.init(title: "Host", value: trip.hostCode == service.friendCode ? "You" : trip.hostName,
                              systemImage: "person.fill", tint: CrewTint.people))
            rows.append(.init(title: "Started", value: "\(trip.createdAt.formatted(.dateTime.day().month(.abbreviated))), \(ForecastFormat.time(trip.createdAt))",
                              systemImage: "play.fill", tint: .dsScoreGood))
            if let endedAt = trip.endedAt {
                rows.append(.init(title: "Ended", value: "\(endedAt.formatted(.dateTime.day().month(.abbreviated))), \(ForecastFormat.time(endedAt))",
                                  systemImage: "flag.checkered", tint: CrewTint.calendar))
            }
            if let crewCode = trip.crewCode, let crew = svc.crew(withCode: crewCode) {
                rows.append(.init(title: "Crew", value: crew.name, systemImage: "person.3.fill", tint: CrewTint.region))
            }
            if let team = trip.teamName {
                rows.append(.init(title: "Tournament team", value: team, systemImage: "trophy.fill",
                                  tint: CrewTint.trophy))
            }
        }
        return rows
    }

    @ViewBuilder private var detailCard: some View {
        let items = detailItems
        if !items.isEmpty {
            GroupedCard {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    if i > 0 { CardDivider() }
                    IconRow(item.title, systemImage: item.systemImage, tint: item.tint) {
                        Text(item.value)
                            .foregroundStyle(.dsText2)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - Invite sheet

    @ViewBuilder private var inviteSheet: some View {
        if let code {
            NavigationStack {
                ScrollView { invitePanel(code) }
                    .scrollDismissesKeyboard(.interactively)
                    .dsScreenBackground()
                    .eventSheetTitle("Invite friends")
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func invitePanel(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            inviteCodeField(code)
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s3)
            CrewSection(title: "Friends") { friendRows(code) }
            CrewSection(title: "Invite by angler code") { inviteByCodeForm(code) }
        }
        .padding(.bottom, DS.Space.s6)
        .pageWidth()
    }

    private func inviteCodeField(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            EventFormField("Trip code") {
                CopyableCode(code: code, font: .system(.largeTitle, design: .monospaced).bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.s4)
            }
            ShareLink(item: service.inviteMessage(forGroup: code, tripName: trip?.name ?? tripName)) {
                Label("Share link", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.dsTonal)
            Text("Tap the code to copy it. Anyone with it can join while the trip is live.")
                .font(.footnote)
                .foregroundStyle(.dsText2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func friendRows(_ code: String) -> some View {
        let memberCodes = Set(members.map(\.id))
        let invitable = friendProfiles.filter { !memberCodes.contains($0.id) }
        if friendProfiles.isEmpty {
            InlineEmpty(text: "Add friends on the Crew tab to invite them in one tap.", systemImage: "person.2")
        } else if invitable.isEmpty {
            InlineEmpty(text: "All your friends are on this trip.", systemImage: "checkmark.circle")
        } else {
            VStack(spacing: 0) {
                ForEach(invitable) { f in friendRow(f, code: code) }
            }
        }
    }

    private func friendRow(_ f: CommunityService.Profile, code: String) -> some View {
        ArtRow(title: f.name, subtitle: f.homeWater.isEmpty ? nil : f.homeWater) {
            AnglerAvatar(image: f.avatar, size: 44)
        } trailing: {
            if invited.contains(f.id) {
                Label("Invited", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.dsText2)
                    .transition(.opacity)
            } else {
                Button("Invite") { invite(f, code: code) }
                    .buttonStyle(TonalButtonStyle(fullWidth: false))
                    .accessibilityLabel("Invite \(f.name)")
            }
        }
    }

    private func invite(_ f: CommunityService.Profile, code: String) {
        withAnimation(DS.Motion.spring) { _ = invited.insert(f.id) }
        Task {
            await service.inviteFriend(f.id, toGroup: code, tripName: trip?.name ?? tripName)
            ToastCenter.shared.show("Invite sent to \(f.name)", style: .success)
        }
    }

    private func inviteByCodeForm(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            CodeField(text: $inviteCode, placeholder: "Angler code")
            Button {
                let c = inviteCode.uppercased().trimmingCharacters(in: .whitespaces)
                inviteCode = ""
                Task {
                    await service.inviteFriend(c, toGroup: code, tripName: trip?.name ?? tripName)
                    ToastCenter.shared.show("Invite sent", style: .success)
                }
            } label: {
                Text("Send invite")
            }
            .buttonStyle(.dsPrimary)
            .disabled(inviteCode.trimmingCharacters(in: .whitespaces).count != 6)
            Text("Their angler code is on their profile in the Crew tab.")
                .font(.footnote)
                .foregroundStyle(.dsText2)
        }
        .padding(.horizontal, DS.gutter)
    }

    // MARK: - Your GPS session

    /// Where my own GPS session stands against this trip.
    private enum SessionState {
        case nothing
        /// The shared trip ended while my session still runs.
        case endedStillTracking
        case tracking
        case dayEnded
        /// A different session is running.
        case otherRunning
        case completed
        case notStarted(Trip)

        var isNothing: Bool {
            if case .nothing = self { return true }
            return false
        }
    }

    private func sessionState(_ code: String) -> SessionState {
        let tracker = appState.tripTracker
        let linkedId = service.tripId(forGroupCode: code)
        let isThisActive = linkedId != nil && tracker.isTracking && tracker.activeTrip?.id == linkedId
        if ended { return isThisActive ? .endedStillTracking : .nothing }
        if isThisActive { return tracker.isDayActive ? .tracking : .dayEnded }
        if tracker.isTracking { return .otherRunning }
        guard let lt = myLinkedTrip(code) else { return .nothing }
        return lt.isCompleted ? .completed : .notStarted(lt)
    }

    private func myLinkedTrip(_ code: String) -> Trip? {
        guard let id = service.tripId(forGroupCode: code) else { return nil }
        return (try? appState.tripRepository.fetch(id)) ?? nil
    }

    @ViewBuilder private func sessionSection(_ code: String) -> some View {
        let state = sessionState(code)
        if !state.isNothing {
            CrewSection(title: "Your GPS session") { sessionBody(state) }
        }
    }

    @ViewBuilder private func sessionBody(_ state: SessionState) -> some View {
        switch state {
        case .endedStillTracking:
            InlineEmpty(text: "The trip has ended. Your GPS session is still running.",
                        systemImage: "flag.checkered")
            endSessionButton("End my session")
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s3)
        case .tracking:
            trackingStats
            trackingControls
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s3)
        case .dayEnded:
            InlineEmpty(text: "Day ended. The trip is still open.", systemImage: "moon.zzz")
            VStack(spacing: DS.Space.s2) {
                Button {
                    Haptics.success()
                    appState.tripTracker.startNextDay()
                } label: {
                    Label("Start next day", systemImage: "sun.max.fill")
                }
                .buttonStyle(.dsPrimary)
                endSessionButton("End trip")
            }
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s3)
        case .otherRunning:
            InlineEmpty(text: "Another session is running. End it to track this trip.",
                        systemImage: "location.slash")
        case .completed:
            InlineEmpty(text: "Your session ended. New catches still count.",
                        systemImage: "flag.checkered")
        case .notStarted(let lt):
            Button {
                Haptics.success()
                _ = appState.tripTracker.startPlanned(lt)
            } label: {
                Label("Start GPS session", systemImage: "location.fill")
            }
            .buttonStyle(.dsTonal)
            .padding(.horizontal, DS.gutter)
            SectionFootnote("Optional. Records your track alongside the trip.")
        case .nothing:
            EmptyView()
        }
    }

    private func endSessionButton(_ title: String) -> some View {
        Button(role: .destructive) {
            Haptics.warning()
            _ = appState.tripTracker.end()
        } label: {
            Label(title, systemImage: "stop.circle")
                .foregroundStyle(.dsScoreSlow)
        }
        .buttonStyle(.dsTonal)
    }

    private var trackingStats: some View {
        let tracker = appState.tripTracker
        return TimelineView(.periodic(from: .now, by: 1)) { _ in
            let start = tracker.activeTrip?.currentDayStart ?? tracker.activeTrip?.startDate ?? .now
            let elapsed = tracker.manualPaused ? 0 : Date.now.timeIntervalSince(start)
            KeyValueList(rows: [
                .init(label: tracker.manualPaused ? "GPS paused" : "Tracking live",
                      value: SessionFormat.duration(elapsed), emphasized: true),
                .init(label: "Distance", value: SessionFormat.distance(trackDistance(tracker))),
                .init(label: "Your fish", value: "\(myCatchCount())"),
            ])
        }
    }

    private var trackingControls: some View {
        let tracker = appState.tripTracker
        return HStack(spacing: DS.Space.s2) {
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
                    .foregroundStyle(.dsText)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.dsTonal, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
            }
            .buttonStyle(.dim)
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
        // A nil trip can mean "deleted" (a Mate removed the tournament and its
        // sessions) or just "offline". Probe before declaring it gone, and
        // never fall back to the raw join screen for a dead code.
        var probe = CommunityService.RecordProbe.exists
        if t == nil { probe = await service.groupTripExists(code: code) }
        // New catches drop into the feed and the leaderboard re-sorts.
        withAnimation(reduceMotion ? nil : DS.Motion.softSpring) {
            // Offline keeps the trip it last saw, so the page stays whole.
            if let t { trip = t } else if probe == .missing { trip = nil }
            members = m
            feed = f
            offline = probe == .unreachable
        }
        tripMissing = probe == .missing
        if !offline { lastUpdated = .now }
        loaded = true
        coverSpecies = eventCoverSpecies(feed, appState: appState)
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
