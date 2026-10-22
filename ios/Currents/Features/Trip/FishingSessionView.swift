import SwiftUI
import MapKit
import Charts

// The gear checklist lives on the plan (PlanSessionSheet, PlanDetailView)
// only. Live sessions and group trips do not carry one.

// MARK: - Sessions (list, start, plan)

/// Every session: the one running now, plans coming up, and past sessions.
/// Pushed from Profile and the `sessions` route; the Logbook's Sessions and
/// Plans segments show the same records inline.
struct SessionsView: View {
    @Environment(AppState.self) private var appState
    @State private var sessions: [Trip] = []
    @State private var planned: [Trip] = []
    @State private var catchCounts: [String: Int] = [:]
    @State private var loaded = false
    @State private var showingNew = false
    @State private var showingPlanner = false
    @State private var editingTrip: Trip?
    @State private var editingPlanned: Trip?
    @State private var tripToDelete: Trip?

    private var tracker: TripTracker { appState.tripTracker }
    private var pastSessions: [Trip] { sessions.filter { $0.isCompleted } }

    private var headerSubtitle: String {
        let count = pastSessions.count
        guard count > 0 else { return "Record your track and catches on the water." }
        let hours = Int((pastSessions.reduce(0) { $0 + $1.totalDurationSeconds } / 3600).rounded())
        return "\(count) \(count == 1 ? "session" : "sessions"), \(hours) h on the water"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHeader(title: "Sessions", subtitle: headerSubtitle)

                HStack(spacing: DS.Space.s2) {
                    Button { showingNew = true } label: {
                        Label("Start a session", systemImage: "play.fill")
                    }
                    .buttonStyle(ActionTileStyle(.primary))
                    .disabled(tracker.isTracking)

                    Button { showingPlanner = true } label: {
                        Label("Plan a session", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(ActionTileStyle(.tonal))
                }
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s5)

                if let active = tracker.activeTrip {
                    SectionTitle("Now")
                        .padding(.top, DS.Space.s8)
                    NavigationLink { ActiveSessionView() } label: {
                        ActiveSessionRow(trip: active)
                    }
                    .buttonStyle(.dsRow)
                }

                if !planned.isEmpty {
                    SectionTitle("Upcoming", detail: "\(planned.count)")
                        .padding(.top, DS.Space.s8)
                    ForEach(planned) { trip in
                        PlannedRow(trip: trip, canStart: !tracker.isTracking, onStart: {
                            start(trip)
                        }, onEdit: { editingPlanned = trip })
                        .contextMenu { rowMenu(trip) }
                    }
                }

                if !pastSessions.isEmpty {
                    SectionTitle("History", detail: "\(pastSessions.count)")
                        .padding(.top, DS.Space.s8)
                    ForEach(pastSessions) { trip in
                        NavigationLink {
                            SessionDetailView(trip: trip)
                        } label: {
                            SessionRow(trip: trip, catchCount: catchCounts[trip.id] ?? 0)
                        }
                        .buttonStyle(.dsRow)
                        .contextMenu { rowMenu(trip) }
                    }
                    SectionFoot("Long-press a session to edit or delete it.")
                }

                if loaded && pastSessions.isEmpty && planned.isEmpty && tracker.activeTrip == nil {
                    ContentUnavailableView("No sessions yet", systemImage: "figure.fishing",
                                           description: Text("Start a session when you get to the water. Your track, catches and bag limits are recorded as you fish."))
                        .padding(.top, DS.Space.s6)
                }
            }
            .padding(.bottom, DS.Space.s8)
        }
        .dsScreenBackground()
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingNew, onDismiss: reload) { NewSessionSheet() }
        .sheet(isPresented: $showingPlanner, onDismiss: reload) { PlanSessionSheet() }
        .sheet(item: $editingPlanned, onDismiss: reload) { PlanSessionSheet(editingTrip: $0) }
        .sheet(item: $editingTrip, onDismiss: reload) { EditSessionSheet(trip: $0) }
        .confirmationDialog(
            tripToDelete?.isPlanned == true ? "Delete this plan?" : "Delete this session?",
            isPresented: Binding(get: { tripToDelete != nil }, set: { if !$0 { tripToDelete = nil } }),
            titleVisibility: .visible,
            presenting: tripToDelete
        ) { trip in
            Button(trip.isPlanned ? "Delete plan" : "Delete session", role: .destructive) {
                Haptics.warning()
                try? appState.tripRepository.delete(trip); tripToDelete = nil; reload()
                ToastCenter.shared.show(trip.isPlanned ? "Plan deleted" : "Session deleted",
                                        style: .info, haptic: false, icon: "trash")
            }
            Button("Cancel", role: .cancel) { tripToDelete = nil }
        } message: { trip in
            Text(trip.isPlanned
                 ? "\(trip.name) and its checklist are removed."
                 : "Catches you logged are kept. Only the session and its track are removed.")
        }
        .task { reload() }
    }

    @ViewBuilder private func rowMenu(_ trip: Trip) -> some View {
        // Planned sessions open the full planner (checklist, location, outlook);
        // completed ones use the lightweight editor.
        if trip.isPlanned && !tracker.isTracking {
            Button { start(trip) } label: { Label("Start now", systemImage: "play.fill") }
        }
        Button {
            if trip.isPlanned { editingPlanned = trip } else { editingTrip = trip }
        } label: { Label(trip.isPlanned ? "Edit plan" : "Edit session", systemImage: "pencil") }
        Button(role: .destructive) { tripToDelete = trip } label: {
            Label(trip.isPlanned ? "Delete plan" : "Delete session", systemImage: "trash")
        }
    }

    private func start(_ trip: Trip) {
        _ = tracker.startPlanned(trip)
        reload()
        ToastCenter.shared.show("Session started", icon: "play.fill")
    }

    private func reload() {
        sessions = (try? appState.tripRepository.fetchAll()) ?? []
        planned = (try? appState.tripRepository.fetchPlanned()) ?? []
        for trip in sessions {
            catchCounts[trip.id] = (try? appState.tripRepository.catchCount(tripId: trip.id)) ?? 0
        }
        loaded = true
    }
}

/// A plan in a list: a date thumb, name and time, and a Start button. Tapping
/// the row opens the plan.
struct PlannedRow: View {
    let trip: Trip
    let canStart: Bool
    let onStart: () -> Void
    let onEdit: () -> Void

    private var date: Date { trip.plannedDate ?? trip.startDate }

    var body: some View {
        HStack(spacing: 0) {
            NavigationLink {
                PlanDetailView(tripId: trip.id)
            } label: {
                ArtRow(title: trip.name,
                       subtitle: "\(LogbookFormat.relativeDay(date)), \(LogbookFormat.time(date))") {
                    PlanDateThumb(date: date, size: 52)
                }
            }
            .buttonStyle(.dsRow)

            Button("Start", action: onStart)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.dsText)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(Color.dsTonal, in: Capsule())
                .buttonStyle(.dim)
                .disabled(!canStart)
                .opacity(canStart ? 1 : 0.4)
                .accessibilityLabel("Start \(trip.name)")
                .padding(.trailing, DS.gutter)
        }
    }
}

/// A calendar-page thumb: month over day number.
struct PlanDateThumb: View {
    let date: Date
    var size: CGFloat = 52

    var body: some View {
        ThumbView(tint: DS.accent, size: size) {
            VStack(spacing: 0) {
                Text(date.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DS.accent)
                Text(date.formatted(.dateTime.day()))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.dsText)
            }
        }
        .accessibilityHidden(true)
    }
}

struct EditSessionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var trip: Trip
    @State private var spots: [Spot] = []
    init(trip: Trip) { _trip = State(initialValue: trip) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Name", text: $trip.name)
                    if trip.isPlanned {
                        DatePicker("Planned for", selection: Binding(
                            get: { trip.plannedDate ?? .now },
                            set: { trip.plannedDate = $0; trip.startDate = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                    }
                    Picker("Spot", selection: $trip.spotId) {
                        Text("None").tag(nil as String?)
                        ForEach(spots) { Text($0.name).tag($0.id as String?) }
                    }
                }
                Section("Notes") {
                    TextField("Notes", text: Binding(
                        get: { trip.notes ?? "" },
                        set: { trip.notes = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle(trip.isPlanned ? "Edit plan" : "Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(trip.isPlanned ? "Save plan" : "Save session") { save() }.bold()
                }
            }
            .task { spots = (try? appState.spotRepository.fetchAll()) ?? [] }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        var t = trip
        try? appState.tripRepository.save(&t)
        if t.isPlanned { Task { await NotificationManager.shared.schedulePlannedSessionAlert(trip: t) } }
        ToastCenter.shared.show(t.isPlanned ? "Plan updated" : "Session updated")
        dismiss()
    }
}

/// The running session in a list, with a pulsing record dot.
struct ActiveSessionRow: View {
    let trip: Trip
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ArtRow(over: "Recording", title: trip.name,
               subtitle: "Started \(LogbookFormat.time(trip.startDate))",
               chevron: true) {
            ThumbView(tint: .dsScoreSlow, size: 52) {
                Image(systemName: "record.circle")
                    .font(.title2)
                    .foregroundStyle(Color.dsScoreSlow)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
            }
        }
    }
}

/// A past session in a list: drawn track, name, date, length and catches,
/// and which kind of shared trip it was.
struct SessionRow: View {
    let trip: Trip
    let catchCount: Int

    /// The shared-trip identity of this local session, if any, so the list
    /// says which session was a tournament team, a crew trip, or a plain
    /// shared trip instead of leaving them all indistinguishable.
    private var sharedRef: CommunityService.GroupRef? {
        guard let code = CommunityService.shared.groupCode(forTripId: trip.id) else { return nil }
        return CommunityService.shared.myGroups.first { $0.code == code }
    }

    private var subtitle: String {
        var parts = [LogbookFormat.relativeDay(trip.startDate),
                     LogbookFormat.duration(trip.totalDurationSeconds),
                     "\(catchCount) \(catchCount == 1 ? "catch" : "catches")"]
        if let ref = sharedRef {
            if let team = ref.teamName {
                parts.append("team \(team)")
            } else if ref.crewCode != nil {
                parts.append("crew trip")
            } else {
                parts.append("shared")
            }
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        ArtRow(title: trip.name, subtitle: subtitle, chevron: true) {
            TrackThumb(points: trip.allTrackPoints, size: 52)
        }
    }
}

// MARK: - New session

struct NewSessionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = SessionFormat.defaultName()
    @State private var spots: [Spot] = []
    @State private var spotId: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Spot", selection: $spotId) {
                        Text("None").tag(nil as String?)
                        ForEach(spots) { spot in Text(spot.name).tag(spot.id as String?) }
                    }
                } header: {
                    Text("Session")
                } footer: {
                    Text("Currents records your GPS track, catches and bag limits until you end the session. The spot is optional.")
                }
            }
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start session") {
                        _ = appState.tripTracker.start(name: name.isEmpty ? SessionFormat.defaultName() : name, spotId: spotId)
                        ToastCenter.shared.show("Session started", icon: "play.fill")
                        dismiss()
                    }.bold()
                }
            }
            .task { spots = (try? appState.spotRepository.fetchAll()) ?? [] }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Active session (live)

struct ActiveSessionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var catches: [CatchDetail] = []
    @State private var biteScore: Int?
    @State private var showingLog = false
    @State private var showingEndConfirm = false
    @State private var showingEndDayConfirm = false

    private var tracker: TripTracker { appState.tripTracker }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let trip = tracker.activeTrip {
                    DetailHeader(over: trip.isMultiDay
                                    ? (tracker.isDayActive ? "Day \(trip.decodedDays.count + 1)" : "\(trip.decodedDays.count) days, paused")
                                    : "Recording",
                                 title: trip.name,
                                 subtitle: "Started \(LogbookFormat.time(trip.startDate))")

                    if tracker.manualPaused {
                        pauseNote("Tracking is paused, so your position is not being recorded. Resume below.")
                    } else if tracker.autoPaused {
                        pauseNote("Paused because you stopped moving. Tracking resumes when you move.")
                    }

                    statsHeader(trip)
                        .padding(.horizontal, DS.gutter)
                        .padding(.top, DS.Space.s4)

                    sessionMap
                        .padding(.horizontal, DS.gutter)
                        .padding(.top, DS.Space.s3)

                    if let biteScore {
                        HStack(spacing: 14) {
                            ScoreRing(score: biteScore, size: 52)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bite now")
                                    .font(.headline)
                                    .foregroundStyle(.dsText)
                                Text("Worked out on your phone for where you are")
                                    .font(.footnote)
                                    .foregroundStyle(.dsText2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, DS.gutter)
                        .padding(.top, DS.Space.s4)
                        .accessibilityElement(children: .combine)
                    }

                    Button { Haptics.tap(); showingLog = true } label: {
                        Label("Log catch", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s5)

                    CatchLimitBar(catches: catches)

                    if !catches.isEmpty {
                        SectionTitle("Caught this session", detail: "\(catches.count)")
                            .padding(.top, DS.Space.s8)
                        ForEach(catches, id: \.catchRecord.id) { detail in
                            NavigationLink { CatchDetailView(detail: detail) } label: {
                                SessionCatchRow(detail: detail)
                            }
                            .buttonStyle(.dsRow)
                        }
                    }

                    sessionControls(trip)
                        .padding(.horizontal, DS.gutter)
                        .padding(.top, DS.Space.s8)
                } else {
                    ContentUnavailableView("No session running", systemImage: "figure.fishing",
                        description: Text("Start a session from the map or the Logbook to record your track and catches."))
                        .padding(.top, DS.Space.s8)
                }
            }
            .padding(.bottom, DS.Space.s8)
        }
        .dsScreenBackground()
        .navigationTitle(tracker.activeTrip?.name ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let trip = tracker.activeTrip {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        GroupTripView(tripId: trip.id, tripName: trip.name)
                    } label: {
                        Image(systemName: groupLinked(trip) ? "person.3.fill" : "person.badge.plus")
                    }
                    .accessibilityLabel(groupLinked(trip) ? "Group trip" : "Invite friends")
                }
            }
        }
        .fullScreenCover(isPresented: $showingLog, onDismiss: reload) {
            LogCatchView()
        }
        .confirmationDialog("End this day?", isPresented: $showingEndDayConfirm, titleVisibility: .visible) {
            Button("End day", role: .destructive) { Haptics.success(); tracker.endDay() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Saves today's stats and pauses tracking. The trip stays open, so start the next day when you are back out.")
        }
        .confirmationDialog("End the whole trip?", isPresented: $showingEndConfirm, titleVisibility: .visible) {
            Button("End trip", role: .destructive) { Haptics.warning(); _ = tracker.end(); dismiss() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Saves the track and catches and stops recording.")
        }
        .task { reload(); await refreshBite() }
    }

    private func pauseNote(_ text: String) -> some View {
        Label(text, systemImage: "pause.circle.fill")
            .font(.footnote)
            .foregroundStyle(Color.dsScoreLow)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s3)
    }

    /// One clear primary above (Log catch); here Pause or Resume, and a
    /// single Finish menu that offers End day or End trip. Between days a
    /// Start day button takes over.
    @ViewBuilder private func sessionControls(_ trip: Trip) -> some View {
        if tracker.isDayActive {
            HStack(spacing: DS.Space.s2) {
                Button {
                    Haptics.tap()
                    if tracker.manualPaused { tracker.resumeTracking() } else { tracker.pauseTracking() }
                } label: {
                    Label(tracker.manualPaused ? "Resume" : "Pause",
                          systemImage: tracker.manualPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(ActionTileStyle(.tonal))

                Menu {
                    if trip.isMultiDay || tracker.isDayActive {
                        Button { showingEndDayConfirm = true } label: {
                            Label("End day \(trip.dayCount)", systemImage: "moon.zzz.fill")
                        }
                    }
                    Button(role: .destructive) { showingEndConfirm = true } label: {
                        Label("End trip", systemImage: "stop.circle")
                    }
                } label: {
                    ActionTileLabel("Finish", systemImage: "flag.checkered", kind: .destructive)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Label("Trip paused between days", systemImage: "pause.circle")
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                HStack(spacing: DS.Space.s2) {
                    Button { Haptics.success(); tracker.startNextDay(); Task { await refreshBite() } } label: {
                        Label("Start day \(trip.decodedDays.count + 1)", systemImage: "sun.max.fill")
                    }
                    .buttonStyle(ActionTileStyle(.primary))
                    Button { showingEndConfirm = true } label: {
                        Label("End trip", systemImage: "stop.circle")
                    }
                    .buttonStyle(ActionTileStyle(.destructive))
                }
            }
        }
    }

    private func statsHeader(_ trip: Trip) -> some View {
        let priorDist = trip.decodedDays.reduce(0.0) { $0 + $1.distanceMeters }
        let priorDur = trip.decodedDays.reduce(0.0) { $0 + $1.durationSeconds }
        return TimelineView(.periodic(from: .now, by: 1)) { _ in
            let curDur = tracker.isDayActive ? Date.now.timeIntervalSince(trip.currentDayStart ?? trip.startDate) : 0
            HStack(spacing: 10) {
                StatTile(trip.isMultiDay ? "Total time" : "Time", systemImage: "clock", tint: .dsText2,
                         value: SessionFormat.duration(priorDur + curDur), width: nil)
                StatTile("Distance", systemImage: "point.topleft.down.to.point.bottomright.curvepath", tint: .dsText2,
                         value: SessionFormat.distance(priorDist + trackDistance()), width: nil)
                StatTile("Catches", systemImage: "fish.fill", tint: .dsText2,
                         value: "\(catches.count)", width: nil)
            }
        }
    }

    private func trackDistance() -> Double {
        let pts = tracker.track
        guard pts.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<pts.count {
            total += CLLocation(latitude: pts[i].lat, longitude: pts[i].lon)
                .distance(from: CLLocation(latitude: pts[i-1].lat, longitude: pts[i-1].lon))
        }
        return total
    }

    private var sessionMap: some View {
        // Prior days (persisted) + the live current day + catch pins.
        let prior = tracker.activeTrip?.decodedDays.flatMap(\.track) ?? []
        return SessionTrackMap(points: prior + tracker.track, showsUser: true, catches: catches)
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    private func reload() {
        guard let id = tracker.activeTrip?.id else { catches = []; return }
        catches = (try? appState.tripRepository.catches(tripId: id)) ?? []
        pushLiveUpdate()
    }

    private func groupLinked(_ trip: Trip) -> Bool {
        CommunityService.shared.groupCode(forTripId: trip.id) != nil
    }

    private func refreshBite() async {
        let coord = tracker.currentLocation?.coordinate
            ?? appState.locationManager.currentLocation?.coordinate
        guard let coord else { return }
        let w = await WeatherService.shared.current(for: coord)
        biteScore = ForecastEngine.forecast(
            coordinate: coord,
            currentPressureHpa: w?.pressureHpa, pressureChange6h: w?.pressureChange6h,
            waterTempC: w?.waterTempC, windSpeedKmh: w?.windSpeedKmh,
            windDirection: w?.windDirectionDeg, species: nil, isInSpawningZone: false
        ).score
        pushLiveUpdate()
    }

    /// Keep the Live Activity + widgets in sync with the live catch count and
    /// bite score.
    private func pushLiveUpdate() {
        guard tracker.isTracking else { return }
        LiveActivityManager.shared.update(
            catchCount: catches.count,
            biteScore: biteScore ?? 0,
            catchLimitText: CatchLimitBar.summary(for: catches)
        )
        WidgetSnapshotWriter.writeActiveSession(
            name: tracker.activeTrip?.name,
            start: tracker.activeTrip?.startDate,
            catches: catches.count
        )
    }
}

/// A catch inside a session: thumb, species, time and size.
struct SessionCatchRow: View {
    let detail: CatchDetail

    var body: some View {
        let r = detail.catchRecord
        let subtitle = [LogbookFormat.time(r.caughtAt), LogbookFormat.size(r), r.released ? "released" : nil]
            .compactMap { $0 }.joined(separator: ", ")
        ArtRow(title: detail.species?.commonName ?? "Unknown species", subtitle: subtitle, chevron: true) {
            CatchThumb(detail: detail, size: 52)
        }
    }
}

// MARK: - Session detail (past)

struct SessionDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State var trip: Trip
    @State private var catches: [CatchDetail] = []
    @State private var showingDeleteConfirm = false
    @State private var showingEdit = false
    @State private var suggestedSpots: [CoordItem] = []
    @State private var spotToAdd: CoordItem?
    @State private var recapImage: UIImage?
    @State private var showingShare = false
    @State private var generatingRecap = false
    @State private var replayToken = 0

    struct CoordItem: Identifiable {
        let id = UUID()
        let coord: CLLocationCoordinate2D
    }

    private var canReplay: Bool { trip.allTrackPoints.count > 2 }

    private var timeLine: String {
        if trip.isMultiDay {
            return "\(trip.dayCount) days, \(LogbookFormat.shortDay(trip.startDate)) to \(LogbookFormat.shortDay(trip.endDate ?? trip.startDate))"
        }
        guard let end = trip.endDate else { return "Started \(LogbookFormat.time(trip.startDate))" }
        return "\(LogbookFormat.time(trip.startDate)) to \(LogbookFormat.time(end))"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DetailHeader(over: LogbookFormat.longDay(trip.startDate),
                                 title: trip.name,
                                 subtitle: timeLine)

                    ActionTriple {
                        Button { shareRecap() } label: {
                            Label(generatingRecap ? "Preparing" : "Share recap", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(ActionTileStyle(.primary))
                        .disabled(generatingRecap)

                        Button {
                            withAnimation(DS.Motion.softSpring) { proxy.scrollTo("replay", anchor: .top) }
                            replayToken += 1
                        } label: {
                            Label("Replay", systemImage: "play.circle")
                        }
                        .buttonStyle(ActionTileStyle(.tonal))
                        .disabled(!canReplay)

                        Button { showingEdit = true } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .buttonStyle(ActionTileStyle(.tonal))
                    }
                    .padding(.top, DS.Space.s5)

                    SessionTrackMap(points: trip.allTrackPoints, showsUser: false, catches: catches)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                        .padding(.horizontal, DS.gutter)
                        .padding(.top, DS.Space.s6)
                    TrackLegend()
                        .padding(.horizontal, DS.gutter)
                        .padding(.top, DS.Space.s2)

                    HStack(spacing: 10) {
                        StatTile("Duration", systemImage: "clock", tint: .dsText2,
                                 value: SessionFormat.duration(trip.totalDurationSeconds), width: nil)
                        StatTile("Distance", systemImage: "point.topleft.down.to.point.bottomright.curvepath", tint: .dsText2,
                                 value: SessionFormat.distance(trip.totalTrackDistanceMeters), width: nil)
                        StatTile("Catches", systemImage: "fish.fill", tint: .dsText2,
                                 value: "\(catches.count)", width: nil)
                    }
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s4)

                    SessionBiteChart(trip: trip, catches: catches)

                    if canReplay {
                        TripScrubberCard(trip: trip, catches: catches, playToken: replayToken)
                            .id("replay")
                    }

                    if trip.isMultiDay { dayBreakdown }

                    SectionTitle("Caught this session", detail: catches.isEmpty ? nil : "\(catches.count)")
                        .padding(.top, DS.Space.s8)
                    if catches.isEmpty {
                        Text("No catches this time. The track and conditions are still saved.")
                            .font(.subheadline)
                            .foregroundStyle(.dsText2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.gutter)
                    } else {
                        ForEach(catches, id: \.catchRecord.id) { detail in
                            NavigationLink { CatchDetailView(detail: detail) } label: {
                                SessionCatchRow(detail: detail)
                            }
                            .buttonStyle(.dsRow)
                        }
                    }

                    TripOverviewHighlights(catches: catches)

                    CatchLimitBar(catches: catches)

                    if !suggestedSpots.isEmpty { suggestedSpotsSection }

                    SectionTitle("Fish with friends")
                        .padding(.top, DS.Space.s8)
                    NavigationLink {
                        GroupTripView(tripId: trip.id, tripName: trip.name)
                    } label: {
                        let linked = CommunityService.shared.groupCode(forTripId: trip.id) != nil
                        ArtRow(title: linked ? "Group trip" : "Invite friends",
                               subtitle: linked ? "See the team's catches and tracks" : "Share this session with your crew",
                               chevron: true) {
                            ThumbView(systemImage: "person.3.fill", tint: DS.accent, size: 52)
                        }
                    }
                    .buttonStyle(.dsRow)

                    if let notes = trip.notes, !notes.isEmpty {
                        SectionTitle("Notes")
                            .padding(.top, DS.Space.s8)
                        Text(notes)
                            .font(.body)
                            .foregroundStyle(.dsText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.gutter)
                    }

                    Button(role: .destructive) { showingDeleteConfirm = true } label: {
                        Label("Delete session", systemImage: "trash")
                            .foregroundStyle(Color.dsScoreSlow)
                    }
                    .buttonStyle(.dsTonal)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s8)
                }
                .padding(.bottom, DS.Space.s8)
            }
        }
        .dsScreenBackground()
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEdit, onDismiss: {
            trip = (try? appState.tripRepository.fetch(trip.id)) ?? trip
        }) {
            EditSessionSheet(trip: trip)
        }
        .confirmationDialog("Delete this session?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete session", role: .destructive) {
                Haptics.warning()
                try? appState.tripRepository.delete(trip)
                ToastCenter.shared.show("Session deleted", style: .info, haptic: false, icon: "trash")
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Catches you logged are kept. Only the session and its track are removed.")
        }
        .sheet(item: $spotToAdd, onDismiss: { load() }) { item in
            AddSpotSheet(prefillCoordinate: item.coord)
        }
        .sheet(isPresented: $showingShare) {
            if let recapImage {
                ImageShareSheet(image: recapImage, filename: "Currents-Trip",
                                caption: TripRecapCard.caption(for: trip, catches: catches))
            }
        }
        .task { load() }
    }

    private func shareRecap() {
        generatingRecap = true
        Task {
            let image = await TripRecapCard.render(trip: trip, catches: catches)
            generatingRecap = false
            recapImage = image
            if image != nil {
                showingShare = true
            } else {
                ToastCenter.shared.show("Could not build the recap", style: .error)
            }
        }
    }

    private func load() {
        catches = (try? appState.tripRepository.catches(tripId: trip.id)) ?? []
        let existing = (try? appState.spotRepository.fetchAll()) ?? []
        // Detected dwell spots not already close to a saved spot.
        let detected = SpotDetector.detectDwellSpots(in: trip.allTrackPoints)
        suggestedSpots = detected.filter { c in
            !existing.contains(where: {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                    .distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) < 80
            })
        }.map { CoordItem(coord: $0) }
    }

    @ViewBuilder private var suggestedSpotsSection: some View {
        SectionTitle("Spots you fished")
            .padding(.top, DS.Space.s8)
        SectionFoot("You stayed a while at these places. Save them for next time.")
        ForEach(Array(suggestedSpots.enumerated()), id: \.element.id) { index, item in
            HStack(spacing: 0) {
                ArtRow(title: "Stop \(index + 1)",
                       subtitle: String(format: "%.4f, %.4f", item.coord.latitude, item.coord.longitude)) {
                    ThumbView(systemImage: "mappin", tint: DS.accent, size: 44)
                }
                Button("Save spot") { spotToAdd = item }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.dsText)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .background(Color.dsTonal, in: Capsule())
                    .buttonStyle(.dim)
                    .padding(.trailing, DS.gutter)
            }
        }
    }

    /// Per-day summary for multi-day trips: date, hours, distance, catches.
    @ViewBuilder private var dayBreakdown: some View {
        SectionTitle("Days", detail: "\(trip.allDayLogs.count)")
            .padding(.top, DS.Space.s8)
        ForEach(trip.allDayLogs) { day in
            let dayCatches = catches.filter { $0.catchRecord.caughtAt >= day.start && $0.catchRecord.caughtAt <= day.end }.count
            ArtRow(title: "Day \(day.index + 1), \(LogbookFormat.shortDay(day.start))",
                   subtitle: "\(LogbookFormat.duration(day.durationSeconds)), \(SessionFormat.distance(day.distanceMeters)), \(dayCatches) \(dayCatches == 1 ? "catch" : "catches")") {
                TrackThumb(points: day.track, size: 44)
            }
        }
    }
}

/// Start, end and catch keys under a session map.
struct TrackLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            item(.dsScoreGood, "Start")
            item(.dsScoreSlow, "End")
            item(DS.accent, "Catch")
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .foregroundStyle(.dsText2)
        .accessibilityHidden(true)
    }

    private func item(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}

// MARK: - Bite during the session

/// The bite score by hour across the session, worked out on the phone for
/// where it started, with the catches marked at the hour they came in.
struct SessionBiteChart: View {
    let trip: Trip
    let catches: [CatchDetail]
    @State private var hours: [HourScore] = []

    struct HourScore: Identifiable {
        let hour: Int
        let score: Int
        var id: Int { hour }
    }

    private var catchHours: Set<Int> {
        Set(catches.map { Calendar.current.component(.hour, from: $0.catchRecord.caughtAt) })
    }

    var body: some View {
        Group {
            if hours.count > 1, let peak = hours.max(by: { $0.score < $1.score }) {
                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Bite score during the session")
                        .padding(.top, DS.Space.s8)
                    Chart {
                        ForEach(hours) { h in
                            BarMark(x: .value("Hour", h.hour), y: .value("Score", h.score), width: .ratio(0.7))
                                .foregroundStyle(DS.scoreColor(h.score))
                            if catchHours.contains(h.hour) {
                                PointMark(x: .value("Hour", h.hour), y: .value("Score", h.score + 8))
                                    .symbol {
                                        Image(systemName: "fish.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.dsText)
                                    }
                            }
                        }
                    }
                    .chartYScale(domain: 0...110)
                    .chartYAxis(.hidden)
                    .chartXAxis {
                        AxisMarks(values: hours.map(\.hour)) { value in
                            AxisValueLabel {
                                if let h = value.as(Int.self) { Text(Self.hourLabel(h)) }
                            }
                        }
                    }
                    .frame(height: 150)
                    .padding(.horizontal, DS.gutter)
                    .accessibilityLabel("Bite score by hour")
                    .accessibilityValue(hours.map { "\(Self.hourLabel($0.hour)) \($0.score)" }.joined(separator: ", "))
                    SectionFoot("Peaked at \(peak.score) around \(Self.hourLabel(peak.hour)). Fish marks the hours you caught.")
                }
            }
        }
        .task(id: trip.id) { compute() }
    }

    private func compute() {
        guard let first = trip.allTrackPoints.first ?? trip.allDayLogs.first?.track.first else { hours = []; return }
        let coord = CLLocationCoordinate2D(latitude: first.lat, longitude: first.lon)
        let cal = Calendar.current
        let start = trip.startDate
        let end = trip.endDate ?? trip.allTrackPoints.last?.t ?? start
        // Same calendar day only: the hourly forecast covers one day.
        let startHour = cal.component(.hour, from: start)
        let endHour = cal.isDate(end, inSameDayAs: start) ? cal.component(.hour, from: end) : 23
        guard endHour >= startHour else { hours = []; return }
        let f = ForecastEngine.forecast(date: start, coordinate: coord,
                                        currentPressureHpa: nil, pressureChange6h: nil,
                                        waterTempC: nil, windSpeedKmh: nil, windDirection: nil,
                                        species: nil, isInSpawningZone: false)
        hours = f.hourlyScores
            .filter { $0.hour >= startHour && $0.hour <= endHour }
            .map { HourScore(hour: $0.hour, score: $0.score) }
    }

    static func hourLabel(_ hour: Int) -> String {
        var c = DateComponents()
        c.hour = hour
        let date = Calendar.current.date(from: c) ?? .now
        return date.formatted(.dateTime.hour())
    }
}

// MARK: - Timeline scrubber

/// Drag along the session timeline to replay it: the playhead moves along the
/// route and surfaces the catch logged closest to that moment. Replay plays
/// it through from the start.
struct TripScrubberCard: View {
    let trip: Trip
    let catches: [CatchDetail]
    var playToken: Int = 0
    @State private var progress: Double = 1.0
    @State private var playTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var track: [Trip.TrackPoint] { trip.allTrackPoints }

    private var timeSpan: (start: Date, end: Date)? {
        guard let first = track.first?.t, let last = track.last?.t, last > first else { return nil }
        return (first, last)
    }

    private var currentTime: Date? {
        guard let span = timeSpan else { return nil }
        return span.start.addingTimeInterval(progress * span.end.timeIntervalSince(span.start))
    }

    /// Track point nearest the scrubbed time.
    private var currentPoint: Trip.TrackPoint? {
        guard let t = currentTime else { return track.last }
        return track.min { abs($0.t.timeIntervalSince(t)) < abs($1.t.timeIntervalSince(t)) }
    }

    private var currentCoord: CLLocationCoordinate2D? {
        currentPoint.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    /// The route walked so far, up to the playhead.
    private var walked: [CLLocationCoordinate2D] {
        guard let t = currentTime else { return [] }
        return track.filter { $0.t <= t }.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    /// Catch logged within 15 min of the scrubbed time (nearest wins).
    private var nearbyCatch: CatchDetail? {
        guard let t = currentTime else { return nil }
        return catches
            .filter { abs($0.catchRecord.caughtAt.timeIntervalSince(t)) < 900 }
            .min { abs($0.catchRecord.caughtAt.timeIntervalSince(t)) < abs($1.catchRecord.caughtAt.timeIntervalSince(t)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Replay", detail: currentTime.map { LogbookFormat.time($0) })
                .padding(.top, DS.Space.s8)

            Map(initialPosition: initialPosition) {
                MapPolyline(coordinates: track.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
                    .stroke(Color.white.opacity(0.35), lineWidth: 3)
                if walked.count > 1 {
                    MapPolyline(coordinates: walked)
                        .stroke(DS.accent, lineWidth: 4)
                }
                if let c = currentCoord {
                    Annotation("", coordinate: c) {
                        Circle().fill(DS.accent)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                    }
                }
            }
            .mapStyle(.hybrid)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .allowsHitTesting(false)
            .padding(.horizontal, DS.gutter)

            HStack(spacing: 12) {
                Button {
                    if playTask != nil { stop() } else { play() }
                } label: {
                    Image(systemName: playTask != nil ? "pause.fill" : "play.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.dsText)
                        .frame(width: 44, height: 44)
                        .background(Color.dsTonal, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.dim)
                .accessibilityLabel(playTask != nil ? "Pause replay" : "Play replay")

                Slider(value: Binding(get: { progress }, set: { stop(); progress = $0 }), in: 0...1)
                    .tint(DS.accent)
                    .accessibilityLabel("Replay time")
                    .accessibilityValue(currentTime.map { LogbookFormat.time($0) } ?? "")
            }
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s3)

            if let c = nearbyCatch {
                NavigationLink { CatchDetailView(detail: c) } label: {
                    ArtRow(over: "Caught \(LogbookFormat.time(c.catchRecord.caughtAt))",
                           title: c.species?.commonName ?? "Catch",
                           chevron: true) {
                        CatchThumb(detail: c, size: 44)
                    }
                }
                .buttonStyle(.dsRow)
            } else {
                Text("No catch around this time")
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s3)
            }
        }
        .onChange(of: playToken) { _, _ in play() }
        .onDisappear { stop() }
    }

    private var initialPosition: MapCameraPosition {
        let coords = track.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        guard let region = SessionTrackMap.fittingRegion(for: coords) else { return .automatic }
        return .region(region)
    }

    /// Plays the session through in about eight seconds. With Reduce Motion
    /// it steps in larger jumps instead of gliding.
    private func play() {
        stop()
        progress = 0
        let steps = reduceMotion ? 8 : 160
        let interval: UInt64 = reduceMotion ? 900_000_000 : 50_000_000
        playTask = Task { @MainActor in
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                progress = Double(i) / Double(steps)
            }
            playTask = nil
        }
    }

    private func stop() {
        playTask?.cancel()
        playTask = nil
    }
}

// MARK: - Trip overview highlights

/// Session highlights as plain rows: the standout catch, species, the most
/// productive spot and tackle, and how many were kept.
struct TripOverviewHighlights: View {
    let catches: [CatchDetail]
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }

    var body: some View {
        if !catches.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("Highlights")
                    .padding(.top, DS.Space.s8)
                KeyValueList(rows: rows)
            }
        }
    }

    private var rows: [(String, String)] {
        var rows: [(String, String)] = []
        if let best = largestCatch {
            let size: String? = {
                if let w = best.catchRecord.weightKg { return Units.weight(kg: w, imperial: imperial) }
                if let l = best.catchRecord.lengthCm { return Units.length(cm: l, imperial: imperial) }
                return nil
            }()
            let name = best.species?.commonName ?? "Catch"
            rows.append((best.catchRecord.weightKg != nil ? "Heaviest" : "Longest",
                         size.map { "\(name), \($0)" } ?? name))
        }
        if !speciesCounts.isEmpty {
            rows.append(("Species", speciesCounts.map { "\($0.name) \($0.count)" }.joined(separator: ", ")))
        }
        if let spot = bestSpot { rows.append(("Best spot", "\(spot.0), \(spot.1) fish")) }
        if let tackle = bestTackle { rows.append(("Best lure", "\(tackle.0), \(tackle.1) fish")) }
        let kept = catches.filter { !$0.catchRecord.released }.count
        rows.append(("Kept", "\(kept) of \(catches.count)"))
        return rows
    }

    private var largestCatch: CatchDetail? {
        // Rank by weight when any catch is weighed; otherwise by length. Mixing
        // the two magnitudes would let a long-but-light fish outrank a heavy one.
        if catches.contains(where: { $0.catchRecord.weightKg != nil }) {
            return catches.max { ($0.catchRecord.weightKg ?? 0) < ($1.catchRecord.weightKg ?? 0) }
        }
        guard catches.contains(where: { $0.catchRecord.lengthCm != nil }) else { return nil }
        return catches.max { ($0.catchRecord.lengthCm ?? 0) < ($1.catchRecord.lengthCm ?? 0) }
    }

    private var speciesCounts: [(name: String, count: Int)] {
        var acc: [String: Int] = [:]
        for c in catches { acc[c.species?.commonName ?? "Unknown", default: 0] += 1 }
        return acc.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    private var bestSpot: (String, Int)? {
        var acc: [String: Int] = [:]
        for c in catches { if let name = c.spot?.name { acc[name, default: 0] += 1 } }
        return acc.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }

    private var bestTackle: (String, Int)? {
        var acc: [String: Int] = [:]
        for c in catches {
            let label = c.gearLoadout?.lure ?? c.gearLoadout?.technique ?? c.gearLoadout?.name
            if let label, !label.isEmpty { acc[label, default: 0] += 1 }
        }
        return acc.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }
}

// MARK: - Catch-limit countdown

struct CatchLimitBar: View {
    let catches: [CatchDetail]

    var body: some View {
        let items = limitedSpecies()
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("Bag limits")
                    .padding(.top, DS.Space.s8)
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.name)
                                    .foregroundStyle(.dsText)
                                Spacer()
                                Text(item.remaining == 0 ? "Limit reached" : "\(item.kept) of \(item.limit) kept")
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                    .foregroundStyle(tint(item))
                            }
                            .font(.body)
                            ProgressView(value: Double(min(item.kept, item.limit)), total: Double(max(item.limit, 1)))
                                .tint(tint(item))
                        }
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                        if i < items.count - 1 {
                            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                        }
                    }
                }
                .padding(.horizontal, DS.gutter)
                SectionFoot("For information. Confirm current local rules before you keep a fish.")
            }
        }
    }

    private func tint(_ item: LimitItem) -> Color {
        item.remaining == 0 ? .dsScoreSlow : (item.remaining <= 1 ? .dsScoreLow : .dsText2)
    }

    struct LimitItem: Identifiable {
        let id: Int64
        let name: String
        let kept: Int
        let limit: Int
        var remaining: Int { max(0, limit - kept) }
    }

    private func limitedSpecies() -> [LimitItem] {
        Self.limitedSpecies(in: catches)
    }

    static func limitedSpecies(in catches: [CatchDetail]) -> [LimitItem] {
        var acc: [Int64: (name: String, kept: Int, limit: Int)] = [:]
        for c in catches {
            guard let sp = c.species, !c.catchRecord.released,
                  let reg = RegulationsService.shared.regulation(for: sp),
                  let limit = reg.bagLimit else { continue }
            var e = acc[sp.id] ?? (sp.commonName, 0, limit)
            e.kept += 1
            acc[sp.id] = e
        }
        return acc.map { LimitItem(id: $0.key, name: $0.value.name, kept: $0.value.kept, limit: $0.value.limit) }
            .sorted { $0.name < $1.name }
    }

    /// Short line for the Live Activity: the species nearest its bag limit,
    /// e.g. "Bass 2/4". Nil when no logged species has a limit.
    static func summary(for catches: [CatchDetail]) -> String? {
        let items = limitedSpecies(in: catches)
        guard let tightest = items.min(by: { $0.remaining < $1.remaining }) else { return nil }
        return "\(tightest.name) \(tightest.kept)/\(tightest.limit)"
    }
}

// MARK: - Track map

struct SessionTrackMap: View {
    let points: [Trip.TrackPoint]
    var showsUser: Bool
    /// Catches to drop as pins along the route.
    var catches: [CatchDetail] = []

    private var coords: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    /// Catches that carry a real coordinate (skip the 0,0 placeholders).
    private var catchPins: [CatchDetail] {
        catches.filter { abs($0.catchRecord.latitude) > 0.0001 || abs($0.catchRecord.longitude) > 0.0001 }
    }

    var body: some View {
        Map(initialPosition: initialPosition) {
            if coords.count > 1 {
                MapPolyline(coordinates: coords)
                    .stroke(DS.accent, lineWidth: 4)
            }
            if let start = coords.first {
                Marker("Start", systemImage: "flag.fill", coordinate: start).tint(Color.dsScoreGood)
            }
            if coords.count > 1, let end = coords.last {
                Marker("End", systemImage: "flag.checkered", coordinate: end).tint(Color.dsScoreSlow)
            }
            ForEach(catchPins, id: \.catchRecord.id) { detail in
                Marker(detail.species?.commonName ?? "Catch",
                       systemImage: "fish.fill",
                       coordinate: CLLocationCoordinate2D(latitude: detail.catchRecord.latitude,
                                                          longitude: detail.catchRecord.longitude))
                    .tint(DS.accent)
            }
            if showsUser { UserAnnotation() }
        }
        .mapStyle(.hybrid)
    }

    /// Frame the whole route by default (no manual zoom-out needed); pan/zoom
    /// stay fully interactive from there.
    private var initialPosition: MapCameraPosition {
        // Include catch pins in the framing so nothing sits off-screen.
        let all = coords + catchPins.map {
            CLLocationCoordinate2D(latitude: $0.catchRecord.latitude, longitude: $0.catchRecord.longitude)
        }
        guard let region = Self.fittingRegion(for: all) else {
            return .userLocation(fallback: .automatic)
        }
        return .region(region)
    }

    /// A region that contains every track point with a little breathing room.
    static func fittingRegion(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coords.first else { return nil }
        if coords.count == 1 {
            return MKCoordinateRegion(center: first,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        // 1.4× padding so start/end markers aren't flush against the edges.
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.004),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.004)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - Formatting

enum SessionFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
    static func distance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters)) m"
    }
    static func defaultName() -> String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 11 ? "Morning" : (hour < 17 ? "Afternoon" : "Evening")
        return "\(part) session"
    }
}
