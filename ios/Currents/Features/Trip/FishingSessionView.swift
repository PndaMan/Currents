import SwiftUI
import MapKit

// MARK: - Sessions home (list + start + plan)

struct SessionsView: View {
    @Environment(AppState.self) private var appState
    @State private var sessions: [Trip] = []
    @State private var planned: [Trip] = []
    @State private var catchCounts: [String: Int] = [:]
    @State private var showingNew = false
    @State private var showingPlanner = false
    @State private var editingTrip: Trip?
    @State private var tripToDelete: Trip?

    private var tracker: TripTracker { appState.tripTracker }

    var body: some View {
        List {
            if let active = tracker.activeTrip {
                Section {
                    NavigationLink { ActiveSessionView() } label: { ActiveSessionRow(trip: active) }
                }
            }

            Section {
                Button { showingNew = true } label: {
                    Label("Start a Session", systemImage: "play.circle.fill")
                }
                .disabled(tracker.isTracking)
                Button { showingPlanner = true } label: {
                    Label("Plan a Session", systemImage: "calendar.badge.clock")
                }
            }

            if !planned.isEmpty {
                Section("Planned") {
                    ForEach(planned) { trip in
                        PlannedRow(trip: trip, canStart: !tracker.isTracking) {
                            _ = tracker.startPlanned(trip); reload()
                        }
                        .contextMenu { rowMenu(trip) }
                    }
                }
            }

            if !pastSessions.isEmpty {
                Section("History") {
                    ForEach(pastSessions) { trip in
                        NavigationLink {
                            SessionDetailView(trip: trip)
                        } label: {
                            SessionRow(trip: trip, catchCount: catchCounts[trip.id] ?? 0)
                        }
                        .contextMenu { rowMenu(trip) }
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .sheet(isPresented: $showingNew, onDismiss: reload) { NewSessionSheet() }
        .sheet(isPresented: $showingPlanner, onDismiss: reload) { PlanSessionSheet() }
        .sheet(item: $editingTrip, onDismiss: reload) { EditSessionSheet(trip: $0) }
        .confirmationDialog(
            "Delete this session?",
            isPresented: Binding(get: { tripToDelete != nil }, set: { if !$0 { tripToDelete = nil } }),
            presenting: tripToDelete
        ) { trip in
            Button("Delete", role: .destructive) {
                try? appState.tripRepository.delete(trip); tripToDelete = nil; reload()
            }
            Button("Cancel", role: .cancel) { tripToDelete = nil }
        } message: { _ in
            Text("Catches you logged are kept — only the session is removed.")
        }
        .task { reload() }
    }

    @ViewBuilder private func rowMenu(_ trip: Trip) -> some View {
        Button { editingTrip = trip } label: { Label("Edit", systemImage: "pencil") }
        Button(role: .destructive) { tripToDelete = trip } label: { Label("Delete", systemImage: "trash") }
    }

    private var pastSessions: [Trip] { sessions.filter { $0.isCompleted } }

    private func reload() {
        sessions = (try? appState.tripRepository.fetchAll()) ?? []
        planned = (try? appState.tripRepository.fetchPlanned()) ?? []
        for trip in sessions {
            catchCounts[trip.id] = (try? appState.tripRepository.catchCount(tripId: trip.id)) ?? 0
        }
    }
}

struct PlannedRow: View {
    let trip: Trip
    let canStart: Bool
    let onStart: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock").foregroundStyle(CurrentsTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.name).font(.subheadline.bold())
                if let d = trip.plannedDate {
                    Text(d.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Start", action: onStart)
                .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
                .disabled(!canStart)
        }
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
                        DatePicker("Planned", selection: Binding(
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
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.bold() }
            }
            .task { spots = (try? appState.spotRepository.fetchAll()) ?? [] }
        }
    }

    private func save() {
        var t = trip
        try? appState.tripRepository.save(&t)
        if t.isPlanned { Task { await NotificationManager.shared.schedulePlannedSessionAlert(trip: t) } }
        dismiss()
    }
}

struct ActiveSessionRow: View {
    let trip: Trip
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.name).font(.subheadline.bold())
                Text("Recording • started \(trip.startDate.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

struct SessionRow: View {
    let trip: Trip
    let catchCount: Int
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.name).font(.subheadline.bold())
                Text(trip.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(catchCount) 🎣").font(.caption.bold())
                Text(SessionFormat.duration(trip.durationSeconds))
                    .font(.caption2).foregroundStyle(.secondary)
            }
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
                Section("Session") {
                    TextField("Name", text: $name)
                    Picker("Spot (optional)", selection: $spotId) {
                        Text("None").tag(nil as String?)
                        ForEach(spots) { spot in Text(spot.name).tag(spot.id as String?) }
                    }
                }
                Section {
                    Text("Currents records your GPS track, catches, and catch limits for the session.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        _ = appState.tripTracker.start(name: name.isEmpty ? SessionFormat.defaultName() : name, spotId: spotId)
                        dismiss()
                    }.bold()
                }
            }
            .task { spots = (try? appState.spotRepository.fetchAll()) ?? [] }
        }
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
            VStack(spacing: CurrentsTheme.paddingM) {
                if let trip = tracker.activeTrip {
                    statsHeader(trip)
                    if tracker.autoPaused {
                        Label("Auto-paused — you've stopped moving. Tracking resumes when you move.",
                              systemImage: "pause.circle.fill")
                            .font(.caption).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    sessionMap
                    if let biteScore {
                        HStack {
                            Label("Bite now", systemImage: "gauge.with.needle").font(.subheadline.bold())
                            Spacer()
                            ScoreGauge(score: biteScore, label: "", size: 40)
                        }
                        .glassCard()
                    }
                    CatchLimitBar(catches: catches)

                    Button { showingLog = true } label: {
                        Label("Log a Catch", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)

                    if !catches.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Caught this session").font(.headline)
                            ForEach(catches, id: \.catchRecord.id) { detail in
                                NavigationLink { CatchDetailView(detail: detail) } label: {
                                    CatchRow(detail: detail)
                                }.buttonStyle(.plain)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    sessionControls(trip)
                } else {
                    ContentUnavailableView("No Active Session", systemImage: "figure.fishing")
                }
            }
            .padding()
        }
        .navigationTitle(tracker.activeTrip?.name ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingLog, onDismiss: reload) { LogCatchView() }
        .alert("End this day?", isPresented: $showingEndDayConfirm) {
            Button("End Day", role: .destructive) { tracker.endDay() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Saves today's stats and pauses tracking. The trip stays open — start the next day whenever you're back out.")
        }
        .alert("End the whole trip?", isPresented: $showingEndConfirm) {
            Button("End Trip", role: .destructive) { tracker.end(); dismiss() }
            Button("Keep Going", role: .cancel) {}
        }
        .task { reload(); await refreshBite() }
    }

    /// Multi-day controls: while a day is recording you can end just the day
    /// (keeping the trip) or end the whole trip; between days you can start the
    /// next day.
    @ViewBuilder private func sessionControls(_ trip: Trip) -> some View {
        VStack(spacing: 10) {
            if tracker.isDayActive {
                Button { showingEndDayConfirm = true } label: {
                    Label("End Day \(trip.dayCount)", systemImage: "moon.zzz.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).tint(.orange)
            } else {
                Label("Trip paused between days", systemImage: "pause.circle")
                    .font(.caption).foregroundStyle(.secondary)
                Button { tracker.startNextDay(); Task { await refreshBite() } } label: {
                    Label("Start Day \(trip.decodedDays.count + 1)", systemImage: "sun.max.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
            }
            Button(role: .destructive) { showingEndConfirm = true } label: {
                Label("End Trip", systemImage: "stop.circle").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
        }
    }

    private func statsHeader(_ trip: Trip) -> some View {
        let priorDist = trip.decodedDays.reduce(0.0) { $0 + $1.distanceMeters }
        let priorDur = trip.decodedDays.reduce(0.0) { $0 + $1.durationSeconds }
        return VStack(spacing: 8) {
            if trip.isMultiDay {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(tracker.isDayActive ? "Day \(trip.decodedDays.count + 1)" : "\(trip.decodedDays.count) days • paused")
                        .font(.caption.bold())
                }
                .foregroundStyle(CurrentsTheme.accent)
                .frame(maxWidth: .infinity)
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let curDur = tracker.isDayActive ? Date.now.timeIntervalSince(trip.currentDayStart ?? trip.startDate) : 0
                HStack(spacing: 12) {
                    sessionStat(SessionFormat.duration(priorDur + curDur), trip.isMultiDay ? "Total Time" : "Elapsed", "clock")
                    sessionStat(SessionFormat.distance(priorDist + trackDistance()), "Distance", "point.topleft.down.to.point.bottomright.curvepath")
                    sessionStat("\(catches.count)", "Catches", "fish.fill")
                }
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

    private func sessionStat(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(CurrentsTheme.accent)
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).glassCard()
    }

    private var sessionMap: some View {
        // Prior days (persisted) + the live current day + catch pins.
        let prior = tracker.activeTrip?.decodedDays.flatMap(\.track) ?? []
        return SessionTrackMap(points: prior + tracker.track, showsUser: true, catches: catches)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func reload() {
        guard let id = tracker.activeTrip?.id else { catches = []; return }
        catches = (try? appState.tripRepository.catches(tripId: id)) ?? []
        pushLiveUpdate()
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

    struct CoordItem: Identifiable {
        let id = UUID()
        let coord: CLLocationCoordinate2D
    }

    var body: some View {
        ScrollView {
            VStack(spacing: CurrentsTheme.paddingM) {
                SessionTrackMap(points: trip.allTrackPoints, showsUser: false, catches: catches)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 12) {
                    stat(SessionFormat.duration(trip.totalDurationSeconds), "Duration", "clock")
                    stat(SessionFormat.distance(trip.totalTrackDistanceMeters), "Distance", "map")
                    stat("\(catches.count)", "Catches", "fish.fill")
                }

                if trip.allTrackPoints.count > 2 {
                    TripScrubberCard(trip: trip, catches: catches)
                }

                if trip.isMultiDay { dayBreakdown }

                if !suggestedSpots.isEmpty { suggestedSpotsCard }

                TripOverviewHighlights(catches: catches)

                CatchLimitBar(catches: catches)

                if !catches.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Catches").font(.headline)
                        ForEach(catches, id: \.catchRecord.id) { detail in
                            NavigationLink { CatchDetailView(detail: detail) } label: {
                                CatchRow(detail: detail)
                            }.buttonStyle(.plain)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }

                if let notes = trip.notes, !notes.isEmpty {
                    Text(notes).font(.body).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).glassCard()
                }

                Button {
                    recapImage = TripRecapCard.render(trip: trip, catches: catches)
                    showingShare = true
                } label: {
                    Label("Share Recap", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)

                Button(role: .destructive) { showingDeleteConfirm = true } label: {
                    Label("Delete Session", systemImage: "trash").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Edit") { showingEdit = true } }
        }
        .sheet(isPresented: $showingEdit, onDismiss: {
            trip = (try? appState.tripRepository.fetch(trip.id)) ?? trip
        }) {
            EditSessionSheet(trip: trip)
        }
        .alert("Delete Session?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                try? appState.tripRepository.delete(trip); dismiss()
            }
            Button("Cancel", role: .cancel) {}
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

    private var suggestedSpotsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Spots you fished", systemImage: "mappin.and.ellipse")
                .font(.headline)
            Text("You lingered at these spots — save them for next time.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(suggestedSpots) { item in
                HStack {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(CurrentsTheme.accent)
                    Text(String(format: "%.4f, %.4f", item.coord.latitude, item.coord.longitude))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") { spotToAdd = item }
                        .font(.caption.bold()).buttonStyle(.bordered).tint(CurrentsTheme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// Per-day summary for multi-day trips: date, hours, distance, catches.
    private var dayBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Days").font(.headline)
            ForEach(trip.allDayLogs) { day in
                let dayCatches = catches.filter { $0.catchRecord.caughtAt >= day.start && $0.catchRecord.caughtAt <= day.end }.count
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(CurrentsTheme.accent.opacity(0.15)).frame(width: 34, height: 34)
                        Text("\(day.index + 1)").font(.subheadline.bold()).foregroundStyle(CurrentsTheme.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.start.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.bold())
                        Text("\(SessionFormat.duration(day.durationSeconds)) · \(SessionFormat.distance(day.distanceMeters))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if dayCatches > 0 {
                        Label("\(dayCatches)", systemImage: "fish.fill")
                            .font(.caption.bold()).foregroundStyle(CurrentsTheme.accent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func stat(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(CurrentsTheme.accent)
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).glassCard()
    }
}

// MARK: - Timeline scrubber

/// Drag along the session timeline to replay it: the playhead moves along the
/// route and surfaces the catch logged closest to that moment.
struct TripScrubberCard: View {
    let trip: Trip
    let catches: [CatchDetail]
    @State private var progress: Double = 1.0

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

    /// Catch logged within 15 min of the scrubbed time (nearest wins).
    private var nearbyCatch: CatchDetail? {
        guard let t = currentTime else { return nil }
        return catches
            .filter { abs($0.catchRecord.caughtAt.timeIntervalSince(t)) < 900 }
            .min { abs($0.catchRecord.caughtAt.timeIntervalSince(t)) < abs($1.catchRecord.caughtAt.timeIntervalSince(t)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Replay", systemImage: "timeline.selection").font(.headline)
                Spacer()
                if let t = currentTime {
                    Text(t.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.bold().monospacedDigit()).foregroundStyle(CurrentsTheme.accent)
                }
            }

            Map {
                MapPolyline(coordinates: track.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
                    .stroke(CurrentsTheme.accent.opacity(0.5), lineWidth: 3)
                if let c = currentCoord {
                    Annotation("", coordinate: c) {
                        Circle().fill(CurrentsTheme.accent)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                            .shadow(radius: 3)
                    }
                }
            }
            .mapStyle(.hybrid)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .allowsHitTesting(false)

            Slider(value: $progress, in: 0...1)
                .tint(CurrentsTheme.accent)

            if let c = nearbyCatch {
                NavigationLink { CatchDetailView(detail: c) } label: {
                    HStack(spacing: 10) {
                        if let sp = c.species { SpeciesArtworkView(species: sp, caught: true, size: 30) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.species?.commonName ?? "Catch").font(.subheadline.bold())
                            Text("Caught \(c.catchRecord.caughtAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }.buttonStyle(.plain)
            } else {
                Text("No catch around this time").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

// MARK: - Trip overview highlights

/// Rich session summary: the standout catch (with artwork + photo), a species
/// breakdown, and the most productive spot & tackle.
struct TripOverviewHighlights: View {
    let catches: [CatchDetail]
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }

    var body: some View {
        if !catches.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if let best = largestCatch { largestCard(best) }
                if speciesCounts.count > 0 { speciesBreakdown }
                HStack(spacing: 12) {
                    if let spot = bestSpot { miniStat("Best Spot", spot.0, "\(spot.1) fish", "mappin.circle.fill") }
                    if let tackle = bestTackle { miniStat("Top Tackle", tackle.0, "\(tackle.1) fish", "wrench.and.screwdriver.fill") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Standout catch

    private var largestCatch: CatchDetail? {
        // Rank by weight when any catch is weighed; otherwise by length. Mixing
        // the two magnitudes would let a long-but-light fish outrank a heavy one.
        if catches.contains(where: { $0.catchRecord.weightKg != nil }) {
            return catches.max { ($0.catchRecord.weightKg ?? 0) < ($1.catchRecord.weightKg ?? 0) }
        }
        return catches.max { ($0.catchRecord.lengthCm ?? 0) < ($1.catchRecord.lengthCm ?? 0) }
    }

    @ViewBuilder private func largestCard(_ detail: CatchDetail) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(CurrentsTheme.accent.opacity(0.12)).frame(width: 62, height: 62)
                if let photo = detail.catchRecord.allPhotoPaths.first, let img = PhotoManager.load(photo) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 62, height: 62).clipShape(Circle())
                } else if let species = detail.species {
                    SpeciesArtworkView(species: species, caught: true, size: 54)
                } else {
                    Image(systemName: "trophy.fill").font(.title2).foregroundStyle(CurrentsTheme.accent)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Label("Catch of the Trip", systemImage: "trophy.fill")
                    .font(.caption.bold()).foregroundStyle(CurrentsTheme.accent)
                Text(detail.species?.commonName ?? "Catch").font(.headline)
                HStack(spacing: 8) {
                    if let w = detail.catchRecord.weightKg {
                        Text(Units.weight(kg: w, imperial: imperial)).font(.subheadline.bold())
                    }
                    if let l = detail.catchRecord.lengthCm {
                        Text(Units.length(cm: l, imperial: imperial))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(12)
        .glassCard()
    }

    // MARK: Species breakdown

    private var speciesCounts: [(name: String, count: Int, species: Species?)] {
        var acc: [String: (Int, Species?)] = [:]
        for c in catches {
            let name = c.species?.commonName ?? "Unknown"
            let e = acc[name] ?? (0, c.species)
            acc[name] = (e.0 + 1, e.1)
        }
        return acc.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.count > $1.count }
    }

    private var speciesBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Species").font(.subheadline.bold())
            ForEach(speciesCounts, id: \.name) { row in
                HStack(spacing: 10) {
                    if let sp = row.species {
                        SpeciesArtworkView(species: sp, caught: true, size: 30)
                    } else {
                        Image(systemName: "fish.fill").foregroundStyle(.secondary).frame(width: 30)
                    }
                    Text(row.name).font(.subheadline)
                    Spacer()
                    Text("×\(row.count)").font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(CurrentsTheme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: Best spot & tackle

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

    private func miniStat(_ title: String, _ value: String, _ sub: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption2.bold()).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).lineLimit(1)
            Text(sub).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

// MARK: - Catch-limit countdown

struct CatchLimitBar: View {
    let catches: [CatchDetail]

    var body: some View {
        let items = limitedSpecies()
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Catch Limits", systemImage: "exclamationmark.shield")
                    .font(.subheadline.bold())
                ForEach(items) { item in
                    HStack {
                        Text(item.name).font(.caption)
                        Spacer()
                        Text("\(item.kept)/\(item.limit) kept")
                            .font(.caption.bold())
                            .foregroundStyle(item.remaining == 0 ? .red : (item.remaining <= 1 ? .orange : .secondary))
                        Text(item.remaining == 0 ? "limit reached" : "\(item.remaining) left")
                            .font(.caption2)
                            .foregroundStyle(item.remaining == 0 ? .red : .secondary)
                    }
                }
                Text("Informational — confirm current local rules.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
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
                    .stroke(CurrentsTheme.accent, lineWidth: 4)
            }
            if let start = coords.first {
                Marker("Start", systemImage: "flag.fill", coordinate: start).tint(.green)
            }
            if coords.count > 1, let end = coords.last {
                Marker("End", systemImage: "checkered.flag", coordinate: end).tint(.red)
            }
            ForEach(catchPins, id: \.catchRecord.id) { detail in
                Marker(detail.species?.commonName ?? "Catch",
                       systemImage: "fish.fill",
                       coordinate: CLLocationCoordinate2D(latitude: detail.catchRecord.latitude,
                                                          longitude: detail.catchRecord.longitude))
                    .tint(CurrentsTheme.accent)
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
        return "\(part) Session"
    }
}
