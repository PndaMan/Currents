import SwiftUI
import MapKit

// MARK: - Sessions home (list + start + plan)

struct SessionsView: View {
    @Environment(AppState.self) private var appState
    @State private var sessions: [Trip] = []
    @State private var catchCounts: [String: Int] = [:]
    @State private var showingNew = false
    @State private var showingPlanner = false

    private var tracker: TripTracker { appState.tripTracker }

    var body: some View {
        List {
            if let active = tracker.activeTrip {
                Section {
                    NavigationLink {
                        ActiveSessionView()
                    } label: {
                        ActiveSessionRow(trip: active)
                    }
                }
            }

            Section {
                Button {
                    showingNew = true
                } label: {
                    Label("Start a Session", systemImage: "play.circle.fill")
                }
                .disabled(tracker.isTracking)
                Button {
                    showingPlanner = true
                } label: {
                    Label("Plan a Session", systemImage: "calendar.badge.clock")
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
                    }
                    .onDelete(perform: deleteSessions)
                }
            }
        }
        .navigationTitle("Sessions")
        .sheet(isPresented: $showingNew, onDismiss: reload) { NewSessionSheet() }
        .sheet(isPresented: $showingPlanner) { PlanSessionSheet() }
        .task { reload() }
    }

    private var pastSessions: [Trip] { sessions.filter { !$0.isActive } }

    private func reload() {
        sessions = (try? appState.tripRepository.fetchAll()) ?? []
        for trip in sessions {
            catchCounts[trip.id] = (try? appState.tripRepository.catchCount(tripId: trip.id)) ?? 0
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        let items = offsets.map { pastSessions[$0] }
        for trip in items { try? appState.tripRepository.delete(trip) }
        reload()
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

    private var tracker: TripTracker { appState.tripTracker }

    var body: some View {
        ScrollView {
            VStack(spacing: CurrentsTheme.paddingM) {
                if let trip = tracker.activeTrip {
                    statsHeader(trip)
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

                    Button(role: .destructive) { showingEndConfirm = true } label: {
                        Label("End Session", systemImage: "stop.circle").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                } else {
                    ContentUnavailableView("No Active Session", systemImage: "figure.fishing")
                }
            }
            .padding()
        }
        .navigationTitle(tracker.activeTrip?.name ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingLog, onDismiss: reload) { LogCatchView() }
        .alert("End Session?", isPresented: $showingEndConfirm) {
            Button("End", role: .destructive) { tracker.end(); dismiss() }
            Button("Keep Going", role: .cancel) {}
        }
        .task { reload(); await refreshBite() }
    }

    private func statsHeader(_ trip: Trip) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 12) {
                sessionStat(SessionFormat.duration(trip.durationSeconds), "Elapsed", "clock")
                sessionStat(SessionFormat.distance(tracker.track.isEmpty ? trip.trackDistanceMeters : trackDistance()), "Distance", "point.topleft.down.to.point.bottomright.curvepath")
                sessionStat("\(catches.count)", "Catches", "fish.fill")
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
        SessionTrackMap(points: tracker.track, showsUser: true)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func reload() {
        guard let id = tracker.activeTrip?.id else { catches = []; return }
        catches = (try? appState.tripRepository.catches(tripId: id)) ?? []
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
    }
}

// MARK: - Session detail (past)

struct SessionDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State var trip: Trip
    @State private var catches: [CatchDetail] = []
    @State private var showingDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: CurrentsTheme.paddingM) {
                SessionTrackMap(points: trip.decodedTrack, showsUser: false)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 12) {
                    stat(SessionFormat.duration(trip.durationSeconds), "Duration", "clock")
                    stat(SessionFormat.distance(trip.trackDistanceMeters), "Distance", "map")
                    stat("\(catches.count)", "Catches", "fish.fill")
                }

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

                Button(role: .destructive) { showingDeleteConfirm = true } label: {
                    Label("Delete Session", systemImage: "trash").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Session?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                try? appState.tripRepository.delete(trip); dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .task { catches = (try? appState.tripRepository.catches(tripId: trip.id)) ?? [] }
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
}

// MARK: - Track map

struct SessionTrackMap: View {
    let points: [Trip.TrackPoint]
    var showsUser: Bool

    private var coords: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
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
            if showsUser { UserAnnotation() }
        }
        .mapStyle(.hybrid)
    }

    private var initialPosition: MapCameraPosition {
        if let first = coords.first {
            return .region(MKCoordinateRegion(center: first,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
        }
        return .userLocation(fallback: .automatic)
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
