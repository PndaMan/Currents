import SwiftUI
import MapKit
import Charts

// The gear checklist lives on the plan (PlanSessionSheet, PlanDetailView)
// only. Live sessions and group trips do not carry one.

// MARK: - Sessions (list, start, plan)

/// Every session: the one running now, plans coming up, and past sessions.
/// Reached from the `sessions` route; the Logbook's Sessions and Plans
/// segments show the same records with the same rows.
struct SessionsView: View {
    @Environment(AppState.self) private var appState
    @State private var sessions: [Trip] = []
    @State private var planned: [Trip] = []
    @State private var catchCounts: [String: Int] = [:]
    @State private var catchPhotos: [String: String] = [:]
    @State private var bestScores: [String: Int] = [:]
    @State private var outlooks: [String: PlanRowOutlook] = [:]
    @State private var loaded = false
    /// The sessions could not be read; the page offers a retry rather than
    /// "No sessions yet".
    @State private var loadFailed = false
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

                ActionTriple {
                    Button { showingNew = true } label: {
                        Label("Start session", systemImage: "play.fill")
                    }
                    .buttonStyle(ActionTileStyle(.primary))
                    .disabled(tracker.isTracking)

                    Button { showingPlanner = true } label: {
                        Label("Plan a session", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(ActionTileStyle(.tonal))
                }
                .padding(.top, DS.Space.s5)

                if let active = tracker.activeTrip {
                    SectionTitle("Now")
                        .padding(.top, DS.Space.s8)
                    NavigationLink { ActiveSessionView() } label: {
                        ActiveSessionRow(trip: active, catchCount: catchCounts[active.id] ?? 0)
                    }
                    .buttonStyle(.dsRow)
                }

                if !planned.isEmpty {
                    SectionTitle("Upcoming", detail: "\(planned.count)")
                        .padding(.top, DS.Space.s8)
                    ForEach(planned) { trip in
                        NavigationLink {
                            PlanDetailView(tripId: trip.id)
                        } label: {
                            PlannedRow(trip: trip, outlook: outlooks[trip.id])
                        }
                        .buttonStyle(.dsRow)
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
                            SessionRow(trip: trip, catchCount: catchCounts[trip.id] ?? 0,
                                       photoPath: catchPhotos[trip.id], bestScore: bestScores[trip.id])
                        }
                        .buttonStyle(.dsRow)
                        .contextMenu { rowMenu(trip) }
                    }
                }

                if loadFailed {
                    InlineEmpty(systemImage: "exclamationmark.triangle",
                                text: "Your sessions could not be read. Nothing is lost.",
                                actionTitle: "Try again") { reload() }
                        .padding(.top, DS.Space.s6)
                } else if loaded && pastSessions.isEmpty && planned.isEmpty && tracker.activeTrip == nil {
                    InlineEmpty(systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                text: "No sessions yet. Start one at the water and your track and catches are saved here.")
                        .padding(.top, DS.Space.s6)
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .dsScreenBackground()
        .detailScrollEdge()
        .pageTitleFade("Sessions")
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
                delete(trip)
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
        // Plans open the full planner (checklist, location, outlook); past
        // sessions use the light editor.
        if trip.isPlanned {
            Button { start(trip) } label: { Label("Start now", systemImage: "play.fill") }
                .disabled(tracker.isTracking)
        }
        Button {
            if trip.isPlanned { editingPlanned = trip } else { editingTrip = trip }
        } label: { Label("Edit", systemImage: "pencil") }
        Divider()
        Button(role: .destructive) { tripToDelete = trip } label: {
            Label(trip.isPlanned ? "Delete plan" : "Delete session", systemImage: "trash")
        }
    }

    private func start(_ trip: Trip) {
        _ = tracker.startPlanned(trip)
        reload()
        ToastCenter.shared.show("Session started", icon: "play.fill")
    }

    private func delete(_ trip: Trip) {
        tripToDelete = nil
        do {
            try appState.tripRepository.delete(trip)
        } catch {
            ToastCenter.shared.show(trip.isPlanned ? "Could not delete this plan" : "Could not delete this session",
                                    style: .error)
            return
        }
        Haptics.warning()
        if trip.isPlanned {
            NotificationManager.shared.cancelPlannedSessionAlert(tripId: trip.id)
            PlanWidget.refresh(appState.tripRepository)
        }
        reload()
        ToastCenter.shared.show(trip.isPlanned ? "Plan deleted" : "Session deleted",
                                style: .info, haptic: false, icon: "trash")
    }

    private func reload() {
        do {
            sessions = try appState.tripRepository.fetchAll()
            planned = try appState.tripRepository.fetchPlanned()
            loadFailed = false
        } catch {
            sessions = []
            planned = []
            loadFailed = true
        }
        // Counts, photos and scores only decorate the rows.
        for trip in sessions {
            let tripCatches = (try? appState.tripRepository.catches(tripId: trip.id)) ?? []
            catchCounts[trip.id] = tripCatches.count
            catchPhotos[trip.id] = tripCatches.lazy.compactMap { $0.catchRecord.allPhotoPaths.first }.first
            bestScores[trip.id] = tripCatches.compactMap { $0.catchRecord.forecastScoreAtCapture }.max()
        }
        let here = appState.locationManager.currentLocation?.coordinate
        var next: [String: PlanRowOutlook] = [:]
        for plan in planned { next[plan.id] = PlanRowOutlook.make(for: plan, fallback: here) }
        outlooks = next
        loaded = true
    }
}

/// The best bite in a plan's hours and the day's best window, for the plan's
/// pin or else where you are now. Moon, sun, tide and season only: live
/// weather is not known days ahead. The plan page rings the same score.
struct PlanRowOutlook {
    let score: Int
    let best: BiteWindows.Window?

    /// A plan's hours: the start hour and the three after it.
    static func hours(from hour: Int) -> ClosedRange<Int> {
        hour...min(23, hour + 3)
    }

    /// The best score in a plan's hours.
    static func hoursBest(_ f: ForecastEngine.ForecastResult, from hour: Int) -> Int {
        let window = hours(from: hour)
        return f.hourlyScores.filter { window.contains($0.hour) }.map(\.score).max() ?? f.score
    }

    static func make(for plan: Trip, fallback: CLLocationCoordinate2D?) -> PlanRowOutlook? {
        guard let coord = plan.plannedCoordinate ?? fallback else { return nil }
        let date = plan.plannedDate ?? plan.startDate
        let hour = Calendar.current.component(.hour, from: date)
        let f = ForecastEngine.forecast(
            date: date, coordinate: coord,
            currentPressureHpa: nil, pressureChange6h: nil, waterTempC: nil,
            windSpeedKmh: nil, windDirection: nil, species: nil, isInSpawningZone: false
        )
        return PlanRowOutlook(score: hoursBest(f, from: hour),
                              best: BiteWindows.best(from: f.hourlyScores).max { $0.peakScore < $1.peakScore })
    }
}

/// A plan in a list, as on the Logbook's Plans pane: a date thumb, the time
/// and day over the name, the best window, and the best bite in its hours.
/// The caller wraps it in the link to the plan.
struct PlannedRow: View {
    let trip: Trip
    var outlook: PlanRowOutlook? = nil
    @AppStorage("use24HourTime") private var use24 = true

    private var date: Date { trip.plannedDate ?? trip.startDate }

    private var subtitle: String {
        guard let outlook else { return "Turn on location to see the bite" }
        guard let best = outlook.best else { return "No strong windows that day" }
        // The grade word, not a bare number beside the ring's own score.
        return "\(ForecastFormat.grade(best.peakScore)) from \(ForecastFormat.hour(best.startHour, use24: use24))"
    }

    /// "Tomorrow, 05:30": the day, then the time, in Today's order.
    private var over: String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day ?? 0
        let day: String
        switch days {
        case ..<0: day = "Overdue"
        case 0: day = "Today"
        case 1: day = "Tomorrow"
        default: day = "In \(days) days"
        }
        return "\(day), \(ForecastFormat.time(date, use24: use24))"
    }

    var body: some View {
        ArtRow(over: over,
               title: trip.name,
               subtitle: subtitle,
               chevron: outlook == nil) {
            PlanDateThumb(date: date, size: 64)
        } trailing: {
            if let outlook {
                ScoreRing(score: outlook.score, size: 44)
                    .accessibilityLabel("Bite \(outlook.score) at best in your hours")
            }
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

/// Edit a past session's name, spot and notes. Plans are edited in
/// PlanSessionSheet, which has the time, checklist and outlook.
struct EditSessionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var trip: Trip
    @State private var spots: [Spot] = []
    @FocusState private var focus: Field?
    private enum Field { case name, notes }
    init(trip: Trip) { _trip = State(initialValue: trip) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TripNameField("Name this session", text: $trip.name)
                        .focused($focus, equals: .name)
                        .padding(.top, DS.Space.s4)

                    SectionTitle("Spot")
                        .padding(.top, DS.Space.s8)
                    SpotChoices(spotId: $trip.spotId, spots: spots, noneSubtitle: nil)

                    SectionTitle("Notes")
                        .padding(.top, DS.Space.s8)
                    TextField("What worked, what the water was like", text: Binding(
                        get: { trip.notes ?? "" },
                        set: { trip.notes = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focus, equals: .notes)
                        .padding(DS.Space.s4)
                        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                        .padding(.horizontal, DS.gutter)
                }
                .padding(.bottom, DS.Space.s6)
                .pageWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .detailScrollEdge()
            .dsScreenBackground()
            .navigationTitle("Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
            .safeAreaInset(edge: .bottom) {
                SheetActionBar("Save", systemImage: "checkmark",
                               disabled: trip.name.trimmingCharacters(in: .whitespaces).isEmpty) {
                    save()
                }
            }
            .task { spots = (try? appState.spotRepository.fetchAll()) ?? [] }
        }
        .dsSheet([.large])
    }

    private func save() {
        var t = trip
        t.name = t.name.trimmingCharacters(in: .whitespaces)
        do {
            try appState.tripRepository.save(&t)
        } catch {
            ToastCenter.shared.show("Could not save this session", style: .error)
            return
        }
        ToastCenter.shared.show("Session updated")
        dismiss()
    }
}

/// The running session in a list, as on the Logbook's Sessions pane.
struct ActiveSessionRow: View {
    let trip: Trip
    var catchCount: Int? = nil
    @AppStorage("use24HourTime") private var use24 = true

    var body: some View {
        ArtRow(over: "Session running", title: trip.name,
               subtitle: "Started \(ForecastFormat.time(trip.startDate, use24: use24))",
               chevron: true) {
            ThumbView(systemImage: "dot.radiowaves.left.and.right", tint: .dsScoreSlow)
        } trailing: {
            if let n = catchCount {
                Text("\(n) \(n == 1 ? "catch" : "catches")")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
            }
        }
    }
}

/// A past session in a list, as on the Logbook's Sessions pane: drawn
/// track, the day and which kind of shared trip it was, name, length and
/// catches, and the best bite score it was fished in.
struct SessionRow: View {
    let trip: Trip
    let catchCount: Int
    /// The newest catch photo, shown when the session has no track.
    var photoPath: String? = nil
    /// The best bite score among its catches.
    var bestScore: Int? = nil

    /// The shared-trip identity of this local session, if any, so the list
    /// says which session was a tournament team, a crew trip, or a plain
    /// shared trip instead of leaving them all indistinguishable.
    private var sharedRef: CommunityService.GroupRef? {
        guard let code = CommunityService.shared.groupCode(forTripId: trip.id) else { return nil }
        return CommunityService.shared.myGroups.first { $0.code == code }
    }

    private var over: String {
        let day = LogbookFormat.longDay(trip.startDate)
        guard let ref = sharedRef else { return day }
        if let team = ref.teamName { return "\(day), team \(team)" }
        if ref.crewCode != nil { return "\(day), crew trip" }
        return "\(day), shared"
    }

    var body: some View {
        ArtRow(over: over, title: trip.name,
               subtitle: "\(LogbookFormat.duration(trip.totalDurationSeconds)), \(catchCount) \(catchCount == 1 ? "catch" : "catches")",
               chevron: bestScore == nil) {
            TrackThumb(points: trip.allTrackPoints, tint: bestScore.map { DS.scoreColor($0) } ?? DS.accent,
                       photoPath: photoPath)
        } trailing: {
            // A small ring, as on the Upcoming rows, rather than a bare number.
            if let bestScore {
                ScoreRing(score: bestScore, size: 44)
                    .accessibilityLabel("Best bite score \(bestScore)")
            }
        }
    }
}

// MARK: - New session

/// Start recording now: a name and, optionally, the spot you are fishing.
struct NewSessionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = SessionFormat.defaultName()
    @State private var spots: [Spot] = []
    @State private var spotId: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TripNameField("Name this session", text: $name)
                        .padding(.top, DS.Space.s4)

                    SectionTitle("Spot")
                        .padding(.top, DS.Space.s8)
                    SpotChoices(spotId: $spotId, spots: spots)
                    SectionFootnote("Records your track, catches and bag limits until you end it.")
                }
                .padding(.bottom, DS.Space.s6)
                .pageWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .detailScrollEdge()
            .dsScreenBackground()
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                SheetActionBar("Start session", systemImage: "play.fill") { start() }
            }
            .task { spots = (try? appState.spotRepository.fetchAll()) ?? [] }
        }
        .dsSheet([.medium, .large])
    }

    private func start() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        _ = appState.tripTracker.start(name: trimmed.isEmpty ? SessionFormat.defaultName() : trimmed, spotId: spotId)
        ToastCenter.shared.show("Session started", icon: "play.fill")
        dismiss()
    }
}

// MARK: - Active session (live)

struct ActiveSessionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var catches: [CatchDetail] = []
    @State private var biteScore: Int?
    @State private var biteHours: [(hour: Int, score: Int)] = []
    @State private var biteHour: Int?
    @AppStorage("use24HourTime") private var use24 = true
    @State private var showingLog = false
    @State private var showingNew = false
    @State private var showingEndConfirm = false
    @State private var showingEndDayConfirm = false

    private var tracker: TripTracker { appState.tripTracker }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let trip = tracker.activeTrip {
                    DetailHeader(over: trip.isMultiDay
                                    ? (tracker.isDayActive ? "Day \(trip.decodedDays.count + 1)" : "\(trip.decodedDays.count) days, paused")
                                    : "Session running",
                                 title: trip.name,
                                 subtitle: "Started \(ForecastFormat.time(trip.startDate, use24: use24))")

                    if tracker.manualPaused {
                        pauseNote("Paused. Your position is not being recorded.")
                    } else if tracker.autoPaused {
                        pauseNote("Paused while you are still. It resumes when you move.")
                    }

                    statsHeader(trip)
                        .padding(.horizontal, DS.gutter)
                        .padding(.top, DS.Space.s4)

                    sessionMap
                        .padding(.horizontal, DS.gutter)
                        .padding(.top, DS.Space.s3)

                    if let biteScore {
                        biteBlock(biteScore)
                            .padding(.horizontal, DS.gutter)
                            .padding(.top, DS.Space.s5)
                    }

                    Button { showingLog = true } label: {
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
                        .padding(.top, DS.Space.s8)
                } else {
                    DetailHeader(title: "No session running")
                    InlineEmpty(systemImage: "figure.fishing",
                                text: "Start a session to record your track, catches and bag limits.",
                                actionTitle: "Start session") { showingNew = true }
                        .padding(.top, DS.Space.s4)
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .dsScreenBackground()
        .detailScrollEdge()
        .pageTitleFade(tracker.activeTrip?.name ?? "Session")
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
        .sheet(isPresented: $showingNew) {
            NewSessionSheet()
        }
        .confirmationDialog(endDayTitle, isPresented: $showingEndDayConfirm, titleVisibility: .visible) {
            Button(endDayAction, role: .destructive) { Haptics.warning(); tracker.endDay() }
            Button("Keep fishing", role: .cancel) {}
        } message: {
            Text("Today is saved and tracking pauses. Start the next day when you are back out.")
        }
        .confirmationDialog("End this session?", isPresented: $showingEndConfirm, titleVisibility: .visible) {
            Button("End session", role: .destructive) { endSession() }
            Button("Keep fishing", role: .cancel) {}
        } message: {
            Text("It will be saved to your Logbook.")
        }
        .task { reload(); await refreshBite() }
        .onChange(of: tracker.activeTrip?.id) { _, id in
            // A session started from the empty state.
            guard id != nil else { return }
            reload()
            Task { await refreshBite() }
        }
    }

    /// A multi-day session ends its day; a single session can carry on
    /// another day.
    private var endDayTitle: String {
        guard let trip = tracker.activeTrip, trip.isMultiDay else { return "Pause until tomorrow?" }
        return "End day \(trip.dayCount)?"
    }

    private var endDayAction: String {
        guard let trip = tracker.activeTrip, trip.isMultiDay else { return "Pause until tomorrow" }
        return "End day \(trip.dayCount)"
    }

    /// The same ending as Today: one dialog, one toast.
    private func endSession() {
        guard tracker.end() != nil else { return }
        Haptics.warning()
        ToastCenter.shared.show("Session saved to Logbook", haptic: false, icon: "checkmark")
        dismiss()
    }

    /// The bite now and across today, so the next window is in view while
    /// you fish.
    private func biteBlock(_ score: Int) -> some View {
        let nowHour = Calendar.current.component(.hour, from: .now)
        let shown = biteHour ?? nowHour
        let shownScore = biteHours.first { $0.hour == shown }?.score ?? score
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                ScoreRing(score: biteHour == nil ? score : shownScore, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(biteHour == nil ? "Bite now" : ForecastFormat.hour(shown, use24: use24))
                        .font(.headline)
                        .foregroundStyle(.dsText)
                    Text(biteHour == nil ? ForecastFormat.verdict(score) : ForecastFormat.grade(shownScore))
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            if biteHours.count > 1 {
                BiteBars(hourly: biteHours, windows: BiteWindows.best(from: biteHours),
                         currentHour: nowHour, selected: $biteHour, height: 52, use24: use24)
                    .padding(.top, DS.Space.s2)
                HourAxis(labels: use24 ? ["00:00", "06:00", "12:00", "18:00", "23:00"]
                                       : ["12 am", "6 am", "Noon", "6 pm", "11 pm"])
            }
        }
    }

    private func pauseNote(_ text: String) -> some View {
        Label(text, systemImage: "pause.circle.fill")
            .font(.footnote)
            .foregroundStyle(Color.dsScoreLow)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s3)
    }

    /// One clear primary above (Log catch); here Pause or Resume and End
    /// session, with End day for a multi-day session. A single session can
    /// pause until tomorrow instead. Between days Start day takes over.
    private func sessionControls(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            controls(trip)
        }
    }

    @ViewBuilder private func controls(_ trip: Trip) -> some View {
        if tracker.isDayActive {
            ActionTriple {
                Button {
                    if tracker.manualPaused { tracker.resumeTracking() } else { tracker.pauseTracking() }
                } label: {
                    Label(tracker.manualPaused ? "Resume" : "Pause",
                          systemImage: tracker.manualPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(ActionTileStyle(.tonal))
                .buttonHaptic(.toggle)

                if trip.isMultiDay {
                    Button { showingEndDayConfirm = true } label: {
                        Label("End day \(trip.dayCount)", systemImage: "moon.zzz.fill")
                    }
                    .buttonStyle(ActionTileStyle(.tonal))
                }

                Button { showingEndConfirm = true } label: {
                    Label("End session", systemImage: "stop.fill")
                }
                .buttonStyle(ActionTileStyle(.destructive))
            }
            if !trip.isMultiDay {
                CardGroup {
                    Button { showingEndDayConfirm = true } label: {
                        CardRow("Pause until tomorrow", subtitle: "Keep this session open and fish another day",
                                systemImage: "moon.zzz.fill", tint: DS.accent, chevron: true)
                    }
                    .buttonStyle(.dsCardRow)
                }
                .padding(.top, DS.Space.s3)
            }
        } else {
            pauseNote("Session paused between days")
            ActionTriple {
                Button { Haptics.success(); tracker.startNextDay(); Task { await refreshBite() } } label: {
                    Label("Start day \(trip.decodedDays.count + 1)", systemImage: "sun.max.fill")
                }
                .buttonStyle(ActionTileStyle(.primary))
                Button { showingEndConfirm = true } label: {
                    Label("End session", systemImage: "stop.fill")
                }
                .buttonStyle(ActionTileStyle(.destructive))
            }
            .padding(.top, DS.Space.s3)
        }
    }

    private func statsHeader(_ trip: Trip) -> some View {
        let priorDist = trip.decodedDays.reduce(0.0) { $0 + $1.distanceMeters }
        let priorDur = trip.decodedDays.reduce(0.0) { $0 + $1.durationSeconds }
        return TimelineView(.periodic(from: .now, by: 1)) { _ in
            let curDur = tracker.isDayActive ? Date.now.timeIntervalSince(trip.currentDayStart ?? trip.startDate) : 0
            HStack(spacing: 10) {
                StatTile(trip.isMultiDay ? "Total time" : "Time", systemImage: "clock", tint: DS.accent,
                         value: SessionFormat.duration(priorDur + curDur), width: nil)
                StatTile("Distance", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                         tint: .dsScoreFair,
                         value: SessionFormat.distance(priorDist + trackDistance()), width: nil)
                StatTile("Catches", systemImage: "fish.fill", tint: .dsScoreGood,
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
        let f = ForecastEngine.forecast(
            coordinate: coord,
            currentPressureHpa: w?.pressureHpa, pressureChange6h: w?.pressureChange6h,
            waterTempC: w?.measured?.waterTempC, windSpeedKmh: w?.measured?.windSpeedKmh,
            windDirection: w?.measured?.windDirectionDeg, species: nil, isInSpawningZone: false
        )
        biteScore = f.score
        biteHours = f.hourlyScores
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

/// A catch inside a session: thumb, the time over the species, its size,
/// and a released mark.
struct SessionCatchRow: View {
    let detail: CatchDetail
    @AppStorage("use24HourTime") private var use24 = true

    var body: some View {
        let r = detail.catchRecord
        ArtRow(over: ForecastFormat.time(r.caughtAt, use24: use24),
               title: detail.species?.commonName ?? "Unknown species",
               subtitle: LogbookFormat.size(r), chevron: true) {
            CatchThumb(detail: detail, size: 52)
        } trailing: {
            if r.released {
                Image(systemName: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.ink(.dsScoreLow))
                    .accessibilityLabel("Released")
            }
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
    @State private var sessionSpot: Spot?
    @State private var recapImage: UIImage?
    @State private var showingShare = false
    @State private var generatingRecap = false
    @State private var replayToken = 0
    @AppStorage("use24HourTime") private var use24 = true

    struct CoordItem: Identifiable {
        let id = UUID()
        let coord: CLLocationCoordinate2D
    }

    private var canReplay: Bool { trip.allTrackPoints.count > 2 }

    private var timeLine: String {
        if trip.isMultiDay {
            return "\(trip.dayCount) days, \(LogbookFormat.shortDay(trip.startDate)) to \(LogbookFormat.shortDay(trip.endDate ?? trip.startDate))"
        }
        guard let end = trip.endDate else { return "Started \(ForecastFormat.time(trip.startDate, use24: use24))" }
        return "\(ForecastFormat.time(trip.startDate, use24: use24)) to \(ForecastFormat.time(end, use24: use24))"
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

                        // Scrolls to the replay and plays it from its playhead,
                        // the same as its own play button. Left out when there
                        // is no track to replay, rather than shown greyed.
                        if canReplay {
                            Button {
                                withAnimation(DS.Motion.softSpring) { proxy.scrollTo("replay", anchor: .top) }
                                replayToken += 1
                            } label: {
                                Label("Replay", systemImage: "play.circle")
                            }
                            .buttonStyle(ActionTileStyle(.tonal))
                        }

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
                    // A key only for a drawn route. Without one, the pins
                    // carry their own names and a key would repeat them.
                    let pointCount = trip.allTrackPoints.count
                    let hasPins = catches.contains(where: SessionTrackMap.hasPin)
                    if pointCount > 1 {
                        TrackLegend(showsStart: true, showsEnd: true, showsCatch: hasPins)
                            .padding(.horizontal, DS.gutter)
                            .padding(.top, DS.Space.s2)
                    }

                    HStack(spacing: 10) {
                        StatTile("Duration", systemImage: "clock", tint: DS.accent,
                                 value: SessionFormat.duration(trip.totalDurationSeconds), width: nil)
                        // No track, no distance: "0 m" only read as a fault.
                        if pointCount > 1 {
                            StatTile("Distance", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                     tint: .dsScoreFair,
                                     value: SessionFormat.distance(trip.totalTrackDistanceMeters), width: nil)
                        }
                        StatTile("Catches", systemImage: "fish.fill", tint: .dsScoreGood,
                                 value: "\(catches.count)", width: nil)
                    }
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s4)

                    SessionBiteChart(trip: trip, catches: catches, spot: sessionSpot)

                    if canReplay {
                        TripScrubberCard(trip: trip, catches: catches, playToken: replayToken)
                            .id("replay")
                    }

                    if trip.isMultiDay { dayBreakdown }

                    SectionTitle("Caught this session", detail: catches.isEmpty ? nil : "\(catches.count)")
                        .padding(.top, DS.Space.s8)
                    if catches.isEmpty {
                        ArtRow(title: "No catches this time", subtitle: "The track and bite are still saved.") {
                            ThumbView(systemImage: "fish", tint: DS.accent, size: 52)
                        }
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

                    if sessionSpot != nil || !suggestedSpots.isEmpty { spotsSection }

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

                    DangerButton(title: "Delete session", systemImage: "trash") { showingDeleteConfirm = true }
                        .padding(.top, DS.Space.s8)
                }
                .padding(.bottom, DS.Space.s8)
                .pageWidth()
            }
        }
        .dsScreenBackground()
        .detailScrollEdge()
        .pageTitleFade(trip.name)
        .sheet(isPresented: $showingEdit, onDismiss: {
            trip = (try? appState.tripRepository.fetch(trip.id)) ?? trip
        }) {
            EditSessionSheet(trip: trip)
        }
        .confirmationDialog("Delete this session?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete session", role: .destructive) { delete() }
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

    private func delete() {
        do {
            try appState.tripRepository.delete(trip)
        } catch {
            ToastCenter.shared.show("Could not delete this session", style: .error)
            return
        }
        Haptics.warning()
        ToastCenter.shared.show("Session deleted", style: .info, haptic: false, icon: "trash")
        dismiss()
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
        sessionSpot = trip.spotId.flatMap { id in existing.first { $0.id == id } }
        // Detected dwell spots not already close to a saved spot.
        let detected = SpotDetector.detectDwellSpots(in: trip.allTrackPoints)
        suggestedSpots = detected.filter { c in
            !existing.contains(where: {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                    .distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) < 80
            })
        }.map { CoordItem(coord: $0) }
    }

    /// The spot picked for the session, then the places you stopped that are
    /// not saved yet. Each opens on the Explore map in its sheet; a stop opens
    /// as a dropped pin there.
    @ViewBuilder private var spotsSection: some View {
        SectionTitle("Spots you fished")
            .padding(.top, DS.Space.s8)
        if let sessionSpot {
            Button { appState.pendingDeepLink = MapLink.spot(sessionSpot) } label: {
                ArtRow(over: "Session spot", title: sessionSpot.name,
                       subtitle: ExploreFormat.spotType(sessionSpot), chevron: true) {
                    PlaceSnapshotThumb(spot: sessionSpot, size: 52)
                }
            }
            .buttonStyle(.dsRow)
        }
        ForEach(Array(suggestedSpots.enumerated()), id: \.element.id) { index, item in
            stopRow(item, title: "Stop \(index + 1)")
        }
    }

    private func stopRow(_ item: CoordItem, title: String) -> some View {
        HStack(spacing: 0) {
            Button {
                appState.pendingDeepLink = MapLink.point(item.coord, title: title)
            } label: {
                ArtRow(title: title, subtitle: "You stayed a while here") {
                    PlaceSnapshotThumb(coordinate: item.coord, size: 52)
                }
            }
            .buttonStyle(.dsRow)

            Button("Save spot") { spotToAdd = item }
                .buttonStyle(TonalButtonStyle(fullWidth: false))
                .accessibilityLabel("Save \(title) as a spot")
                .padding(.trailing, DS.gutter)
        }
    }

    /// Per-day summary for multi-day trips: date, hours, distance, catches.
    @ViewBuilder private var dayBreakdown: some View {
        SectionTitle("Days", detail: "\(trip.allDayLogs.count)")
            .padding(.top, DS.Space.s8)
        ForEach(trip.allDayLogs) { day in
            dayRow(day)
        }
    }

    /// A day's track, or a catch photo from the day when it has no track.
    private func dayRow(_ day: Trip.DayLog) -> some View {
        let dayCatches = catches.filter { $0.catchRecord.caughtAt >= day.start && $0.catchRecord.caughtAt <= day.end }
        let photo = dayCatches.lazy.compactMap { $0.catchRecord.allPhotoPaths.first }.first
        let count = dayCatches.count
        let subtitle = "\(LogbookFormat.duration(day.durationSeconds)), \(SessionFormat.distance(day.distanceMeters)), \(count) \(count == 1 ? "catch" : "catches")"
        return ArtRow(title: "Day \(day.index + 1), \(LogbookFormat.shortDay(day.start))", subtitle: subtitle) {
            TrackThumb(points: day.track, size: 44, photoPath: photo)
        }
    }
}

/// Start, end and catch keys under a session map. Callers leave out the
/// keys for markers the map does not draw.
struct TrackLegend: View {
    var showsStart = true
    var showsEnd = true
    var showsCatch = true

    var body: some View {
        HStack(spacing: 14) {
            if showsStart { item(.dsScoreGood, "Start") }
            if showsEnd { item(.dsScoreSlow, "End") }
            if showsCatch { item(DS.accent, "Catch") }
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
    /// The session's spot, for a session saved without a track.
    var spot: Spot? = nil
    @State private var hours: [HourScore] = []
    @AppStorage("use24HourTime") private var use24 = true

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
                        // Every third hour from the start, so the labels never crowd.
                        AxisMarks(values: axisHours) { value in
                            AxisValueLabel {
                                if let h = value.as(Int.self) { Text(hourLabel(h)) }
                            }
                        }
                    }
                    .frame(height: 150)
                    .padding(.horizontal, DS.gutter)
                    .accessibilityLabel("Bite score by hour")
                    .accessibilityValue(hours.map { "\(hourLabel($0.hour)) \($0.score)" }.joined(separator: ", "))
                    SectionFootnote("Peaked at \(peak.score) around \(hourLabel(peak.hour)). Fish marks the hours you caught.")
                }
            }
        }
        .task(id: originKey) { compute() }
    }

    /// Where the bite is worked out: where the track starts, else the
    /// session's spot or planned place, else the first catch with a pin.
    private var origin: CLLocationCoordinate2D? {
        if let first = trip.allTrackPoints.first ?? trip.allDayLogs.first?.track.first {
            return CLLocationCoordinate2D(latitude: first.lat, longitude: first.lon)
        }
        if let spot {
            return CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
        }
        if let planned = trip.plannedCoordinate { return planned }
        return catches.first(where: SessionTrackMap.hasPin).map {
            CLLocationCoordinate2D(latitude: $0.catchRecord.latitude, longitude: $0.catchRecord.longitude)
        }
    }

    /// Works the chart out again once the spot or catches have loaded.
    private var originKey: String {
        guard let origin else { return "\(trip.id)|none" }
        return "\(trip.id)|\(origin.latitude),\(origin.longitude)"
    }

    private func compute() {
        guard let coord = origin else { hours = []; return }
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

    private var axisHours: [Int] {
        guard let first = hours.first?.hour else { return [] }
        return hours.map(\.hour).filter { ($0 - first) % 3 == 0 }
    }

    private func hourLabel(_ hour: Int) -> String {
        ForecastFormat.hour(hour, use24: use24)
    }
}

// MARK: - Timeline scrubber

/// Drag along the session timeline to replay it: the playhead moves along the
/// route and surfaces the catch logged closest to that moment. Play carries on
/// from the playhead, and starts over only once it has reached the end.
/// Dragging while it plays holds it, and it carries on from where you let go.
struct TripScrubberCard: View {
    let trip: Trip
    let catches: [CatchDetail]
    var playToken: Int = 0
    @State private var progress: Double = 1.0
    @State private var playTask: Task<Void, Never>?
    /// Playing when the drag began, so letting go carries on playing.
    @State private var resumeAfterDrag = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("use24HourTime") private var use24 = true
    @AppStorage("mapStyleOption") private var mapStyleRaw = MapTab.MapStyleOption.standard.rawValue

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

    /// Catches with a real coordinate logged up to the playhead, so fish
    /// appear on the map as the replay reaches them.
    private var caughtSoFar: [CatchDetail] {
        guard let t = currentTime else { return [] }
        return catches.filter {
            $0.catchRecord.caughtAt <= t
                && (abs($0.catchRecord.latitude) > 0.0001 || abs($0.catchRecord.longitude) > 0.0001)
        }
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
            SectionTitle("Replay", detail: currentTime.map { ForecastFormat.time($0, use24: use24) })
                .padding(.top, DS.Space.s8)

            Map(initialPosition: initialPosition) {
                // The route still to come: pale on imagery, the text colour
                // faded on the plain map, where pale would vanish.
                MapPolyline(coordinates: track.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
                    .stroke(SessionMapLook.isImagery(mapStyleRaw) ? Color.white.opacity(0.35) : Color.dsText.opacity(0.3),
                            lineWidth: 3)
                if walked.count > 1 {
                    MapPolyline(coordinates: walked)
                        .stroke(DS.accent, lineWidth: 4)
                }
                ForEach(caughtSoFar, id: \.catchRecord.id) { detail in
                    Annotation(detail.species?.commonName ?? "Catch",
                               coordinate: CLLocationCoordinate2D(latitude: detail.catchRecord.latitude,
                                                                  longitude: detail.catchRecord.longitude)) {
                        Image(systemName: "fish.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Color.dsScoreGood, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                if let c = currentCoord {
                    Annotation("", coordinate: c) {
                        Circle().fill(DS.accent)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                    }
                }
            }
            .mapStyle(SessionMapLook.style(mapStyleRaw))
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .frame(height: 220)
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
                .buttonHaptic(.toggle)
                .accessibilityLabel(playTask != nil ? "Pause replay" : "Play replay")

                Slider(value: Binding(get: { progress }, set: { stop(); progress = $0 }),
                       in: 0...1, onEditingChanged: dragging)
                    .tint(DS.accent)
                    .accessibilityLabel("Replay time")
                    .accessibilityValue(currentTime.map { ForecastFormat.time($0, use24: use24) } ?? "")
            }
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s3)

            if let c = nearbyCatch {
                NavigationLink { CatchDetailView(detail: c) } label: {
                    ArtRow(over: "Caught \(ForecastFormat.time(c.catchRecord.caughtAt, use24: use24))",
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

    /// The playhead counts as at the end within a hair of it.
    private var atEnd: Bool { progress >= 0.999 }

    /// Plays from the playhead to the end, at about eight seconds for the
    /// whole session. From the end it starts over. With Reduce Motion it
    /// steps in larger jumps instead of gliding.
    private func play() {
        stop()
        if atEnd { progress = 0 }
        let step = reduceMotion ? 1.0 / 8 : 1.0 / 160
        let interval: UInt64 = reduceMotion ? 900_000_000 : 50_000_000
        playTask = Task { @MainActor in
            while progress < 1 {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                progress = min(1, progress + step)
            }
            playTask = nil
        }
    }

    /// Holds playback while the playhead is dragged and carries on from where
    /// it is let go. Let go at the end, it stays there.
    private func dragging(_ editing: Bool) {
        if editing {
            let wasPlaying = playTask != nil
            stop()
            resumeAfterDrag = wasPlaying
        } else if resumeAfterDrag {
            resumeAfterDrag = false
            if !atEnd { play() }
        }
    }

    private func stop() {
        playTask?.cancel()
        playTask = nil
    }
}

// MARK: - Trip overview highlights

/// Session highlights: the standout catch, the lure and spot that worked,
/// then species and how many were kept.
struct TripOverviewHighlights: View {
    let catches: [CatchDetail]
    @Environment(AppState.self) private var appState
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }

    var body: some View {
        if !catches.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("Highlights")
                    .padding(.top, DS.Space.s8)
                if let best = largestCatch {
                    NavigationLink { CatchDetailView(detail: best) } label: {
                        ArtRow(over: best.catchRecord.weightKg != nil ? "Heaviest" : "Longest",
                               title: best.species?.commonName ?? "Catch",
                               subtitle: size(of: best), chevron: true) {
                            CatchThumb(detail: best, size: 52)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
                if let tackle = bestTackle {
                    ArtRow(over: "Best lure", title: tackle.name, subtitle: fish(tackle.count)) {
                        LureArtView(name: tackle.name, size: 52)
                    }
                }
                if let best = bestSpot {
                    Button { appState.pendingDeepLink = MapLink.spot(best.spot) } label: {
                        ArtRow(over: "Best spot", title: best.spot.name, subtitle: fish(best.count), chevron: true) {
                            PlaceSnapshotThumb(spot: best.spot, size: 52)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
                // One DS card on its own; the rows above sit on the page, so
                // this never nests inside another card.
                KeyValueList(rows: rows)
                    .padding(.top, DS.Space.s2)
            }
        }
    }

    private func fish(_ n: Int) -> String { "\(n) fish" }

    private func size(of c: CatchDetail) -> String? {
        if let w = c.catchRecord.weightKg { return Units.weight(kg: w, imperial: imperial) }
        if let l = c.catchRecord.lengthCm { return Units.length(cm: l, imperial: imperial) }
        return nil
    }

    private var rows: [(String, String)] {
        var rows: [(String, String)] = []
        if !speciesCounts.isEmpty {
            rows.append(("Species", speciesCounts.map { "\($0.name) \($0.count)" }.joined(separator: ", ")))
        }
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

    private var bestSpot: (spot: Spot, count: Int)? {
        var acc: [String: (spot: Spot, count: Int)] = [:]
        for c in catches {
            guard let spot = c.spot else { continue }
            acc[spot.id, default: (spot, 0)].count += 1
        }
        return acc.values.max { $0.count < $1.count }
    }

    private var bestTackle: (name: String, count: Int)? {
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
                        // Each species opens its page, where its rules are.
                        NavigationLink { SpeciesDetailView(species: item.species) } label: {
                            limitRow(item)
                        }
                        .buttonStyle(.dsRow)
                        if i < items.count - 1 {
                            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                                .padding(.horizontal, DS.gutter)
                        }
                    }
                }
                SectionFootnote("Check local rules before you keep a fish.")
            }
        }
    }

    private func limitRow(_ item: LimitItem) -> some View {
        HStack(spacing: 12) {
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
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.dsText3)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, DS.gutter)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func tint(_ item: LimitItem) -> Color {
        item.remaining == 0 ? .dsScoreSlow : (item.remaining <= 1 ? .dsScoreLow : .dsText2)
    }

    struct LimitItem: Identifiable {
        let species: Species
        let kept: Int
        let limit: Int
        var id: Int64 { species.id }
        var name: String { species.commonName }
        var remaining: Int { max(0, limit - kept) }
    }

    private func limitedSpecies() -> [LimitItem] {
        Self.limitedSpecies(in: catches)
    }

    static func limitedSpecies(in catches: [CatchDetail]) -> [LimitItem] {
        var acc: [Int64: (species: Species, kept: Int, limit: Int)] = [:]
        for c in catches {
            guard let sp = c.species, !c.catchRecord.released,
                  let reg = RegulationsService.shared.regulation(for: sp),
                  let limit = reg.bagLimit else { continue }
            var e = acc[sp.id] ?? (sp, 0, limit)
            e.kept += 1
            acc[sp.id] = e
        }
        return acc.values
            .map { LimitItem(species: $0.species, kept: $0.kept, limit: $0.limit) }
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

/// The map look picked in Explore's layers sheet, for the session maps.
/// Offline packs draw only in Explore's own map view, so Offline shows the
/// satellite hybrid here, as the catch page's map does.
enum SessionMapLook {
    static func style(_ raw: String) -> MapStyle {
        switch MapTab.MapStyleOption(rawValue: raw) ?? .standard {
        case .standard: .standard(elevation: .realistic)
        case .fishing: .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll)
        case .imagery: .imagery(elevation: .realistic)
        case .offline, .hybrid: .hybrid(elevation: .realistic)
        }
    }

    /// Satellite imagery under the route, so lines drawn on it go pale.
    static func isImagery(_ raw: String) -> Bool {
        switch MapTab.MapStyleOption(rawValue: raw) ?? .standard {
        case .standard, .fishing: false
        case .offline, .imagery, .hybrid: true
        }
    }
}

struct SessionTrackMap: View {
    let points: [Trip.TrackPoint]
    var showsUser: Bool
    /// Catches to drop as pins along the route.
    var catches: [CatchDetail] = []
    @AppStorage("mapStyleOption") private var mapStyleRaw = MapTab.MapStyleOption.standard.rawValue

    /// A catch with a real coordinate, not the 0,0 placeholder, gets a pin.
    static func hasPin(_ detail: CatchDetail) -> Bool {
        abs(detail.catchRecord.latitude) > 0.0001 || abs(detail.catchRecord.longitude) > 0.0001
    }

    private var coords: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    /// Catches that carry a real coordinate (skip the 0,0 placeholders).
    private var catchPins: [CatchDetail] {
        catches.filter(Self.hasPin)
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
        .mapStyle(SessionMapLook.style(mapStyleRaw))
        // Pin labels stop growing at xxLarge, so a catch's name is not cut
        // off at the map's edge.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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
        ForecastFormat.elapsed(seconds)
    }
    static func distance(_ meters: Double) -> String {
        Units.distance(m: meters)
    }
    static func defaultName() -> String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 11 ? "Morning" : (hour < 17 ? "Afternoon" : "Evening")
        return "\(part) session"
    }
}
