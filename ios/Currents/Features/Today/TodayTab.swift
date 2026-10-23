import SwiftUI
import CoreLocation

/// The home tab: how good the bite is right now, the day's windows, what to
/// tie on and the week ahead. The full forecast pushes from here.
struct TodayTab: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("use24HourTime") private var use24 = true
    /// Angler's clarity call, remembered between sessions. Empty means infer it.
    @AppStorage("waterClarityOverride") private var clarityOverride = ""
    /// Saved spot the forecast is for. Empty means the phone's location.
    @AppStorage("todaySpotId") private var spotId = ""

    @State private var store = ForecastStore()
    @State private var spots: [Spot] = []
    @State private var ownedGear: [OwnedGear] = []
    @State private var history: [CatchDetail] = []
    @State private var nextPlan: Trip?
    @State private var sessionCatches = 0
    @State private var selectedHour: Int?
    /// Set by the session sheet's "Live map"; acted on when the sheet closes.
    @State private var openMapAfterSession = false

    @State private var showLocation = false
    @State private var showSession = false
    @State private var planning: PlanTarget?
    @State private var confirmEnd = false

    /// What the planner sheet opens with.
    private enum PlanTarget: Identifiable {
        case new
        case edit(Trip)
        var id: String {
            switch self {
            case .new: "new"
            case .edit(let t): t.id
            }
        }
    }

    // MARK: - Derived

    private var selectedSpot: Spot? {
        spotId.isEmpty ? nil : spots.first { $0.id == spotId }
    }

    private var resolvedLocation: (coordinate: CLLocationCoordinate2D, name: String) {
        if let spot = selectedSpot {
            return (CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude), spot.name)
        }
        if let loc = appState.locationManager.currentLocation {
            // Name the place after a saved spot when standing at one.
            let near = spots.first {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: loc) < 2_000
            }
            return (loc.coordinate, near?.name ?? "Current location")
        }
        return (ForecastStore.fallbackCoordinate, "Cape Town")
    }

    /// Re-run the load when the place changes by more than about a kilometre.
    private var locationKey: String {
        let c = resolvedLocation.coordinate
        return "\(spotId)|\((c.latitude * 100).rounded())|\((c.longitude * 100).rounded())"
    }

    private var weather: WeatherService.WeatherData? { store.weather(for: 0) }

    private var clarity: WaterClarity {
        WaterClarity(rawValue: clarityOverride) ?? WaterClarity.inferred(precipMm: weather?.precipMm)
    }

    private var suggestions: [LureEngine.Suggestion] {
        let conditions = LureEngine.Conditions(
            waterTempC: weather?.waterTempC,
            clarity: clarity,
            cloudCoverPct: weather?.cloudCoverPct,
            windSpeedKmh: weather?.windSpeedKmh,
            pressureChange6h: weather?.pressureChange6h
        )
        return LureEngine.recommend(conditions: conditions, species: store.species,
                                    ownedGear: ownedGear, history: history)
    }

    private var locationOff: Bool {
        selectedSpot == nil && !appState.locationManager.isAuthorized
    }

    // MARK: - Body

    var body: some View {
        let today = store.day(0)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LargeTitleHeader("Today") {
                    HeaderIconButton("Plan a session", systemImage: "calendar.badge.plus") {
                        planning = .new
                    }
                }

                placeLine
                if locationOff { locationNotice }
                if let trip = appState.tripTracker.activeTrip { sessionBanner(trip) }

                if store.hasLoaded || store.current != nil {
                    hero(today)
                        .padding(.top, 20)
                    TargetRow(store: store).padding(.top, 20)
                    upNextRow
                    WhatToThrowSection(
                        suggestions: suggestions, weather: weather, clarity: clarity,
                        clarityIsGuess: clarityOverride.isEmpty, hasGear: !ownedGear.isEmpty,
                        onClarity: { clarityOverride = $0.rawValue }
                    )
                    .padding(.top, 12)
                    weekStrip.padding(.top, 20)
                    conditions(today).padding(.top, 20)
                } else {
                    FishLoader(message: "Reading the bite")
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .dsScreenBackground()
        .largeTitleChrome("Today")
        .refreshable {
            await reload(force: true)
            Haptics.softPress()
        }
        .navigationDestination(for: ForecastRoute.self) { route in
            ForecastDestination(store: store, route: route)
        }
        .syncsTargetSpecies(store)
        .onChange(of: store.species?.id) { _, _ in writeWidget() }
        .task(id: locationKey) {
            let loc = resolvedLocation
            store.setLocation(loc.coordinate, name: loc.name)
            await reload(force: false)
        }
        .onAppear { refreshLocalData() }
        .onChange(of: appState.tripTracker.isTracking) { _, _ in refreshLocalData() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshIfStale() } }
        }
        .sheet(isPresented: $showLocation) {
            TodayLocationSheet(
                spots: spots,
                selectedSpotId: selectedSpot == nil ? "" : spotId,
                locationAuthorized: appState.locationManager.isAuthorized,
                onSelect: { id in spotId = id },
                onRequestLocation: turnOnLocation,
                onOpenExplore: { appState.pendingDeepLink = URL(string: "currents://map") }
            )
        }
        .sheet(isPresented: $showSession, onDismiss: {
            // Open the live map once the sheet has gone, so the map's own
            // presentation does not race this one closing.
            if openMapAfterSession {
                openMapAfterSession = false
                appState.pendingDeepLink = URL(string: "currents://session")
            }
        }) {
            if let trip = appState.tripTracker.activeTrip {
                TodaySessionSheet(trip: trip, catches: sessionCatches,
                                  onLogCatch: logCatch,
                                  onOpenMap: { openMapAfterSession = true },
                                  onEnd: endSession)
            }
        }
        .sheet(item: $planning, onDismiss: refreshLocalData) { target in
            switch target {
            case .new: PlanSessionSheet()
            case .edit(let trip): PlanSessionSheet(editingTrip: trip)
            }
        }
        .confirmationDialog("End this session?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End session", role: .destructive) { endSession() }
            Button("Keep fishing", role: .cancel) {}
        } message: {
            Text("It will be saved to your Logbook.")
        }
    }

    // MARK: - Place

    private var placeLine: some View {
        HStack(spacing: 6) {
            Button { showLocation = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: selectedSpot == nil ? "location.fill" : "mappin")
                        .font(.footnote)
                    Text(store.placeName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(DS.accent)
            }
            .buttonStyle(.dim)
            .accessibilityLabel("Forecast for \(store.placeName). Change place")

            Text(ForecastFormat.longDate(.now))
                .font(.subheadline)
                .foregroundStyle(.dsText2)
        }
        .padding(.horizontal, DS.gutter)
    }

    private var locationNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.slash")
                .foregroundStyle(.dsText2)
            Text("Location is off, so this is the forecast for Cape Town.")
                .font(.subheadline)
                .foregroundStyle(.dsText2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Turn on location", action: turnOnLocation)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.dim)
                .foregroundStyle(DS.accent)
        }
        .padding(14)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        .padding(.horizontal, DS.gutter)
        .padding(.top, 12)
    }

    // MARK: - Session

    private func sessionBanner(_ trip: Trip) -> some View {
        Button { showSession = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "record.circle")
                    .font(.title3)
                    .foregroundStyle(Color.dsScoreSlow)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Session running")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.dsText)
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text("\(trip.name), \(minutes(since: trip.currentDayStart ?? trip.startDate, now: context.date))")
                            .font(.footnote)
                            .foregroundStyle(.dsText2)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.dsText3)
            }
            .padding(14)
            .background(Color.dsScoreSlow.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        }
        .buttonStyle(.dim)
        .padding(.horizontal, DS.gutter)
        .padding(.top, 12)
    }

    private func minutes(since start: Date, now: Date) -> String {
        let m = max(0, Int(now.timeIntervalSince(start) / 60))
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }

    // MARK: - Hero

    private func hero(_ day: ForecastDay) -> some View {
        let score = day.result.score
        let reason = day.result.reasons.first.map(ForecastFormat.clean) ?? ForecastFormat.guidance(score)
        let currentHour = Calendar.current.component(.hour, from: .now)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bite right now")
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                    Text(ForecastFormat.verdict(score))
                        .font(.title.bold())
                        .foregroundStyle(.dsText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.dsText2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ScoreRing(score: score, size: 100, caption: "of 100")
            }
            .padding(.horizontal, DS.gutter)
            .accessibilityElement(children: .combine)

            VStack(spacing: 8) {
                BiteBars(hourly: day.result.hourlyScores, windows: day.windows,
                         currentHour: currentHour, selected: $selectedHour, height: 72, use24: use24)
                HourAxis(labels: use24 ? ["00:00", "06:00", "12:00", "18:00", "23:00"]
                                       : ["12 am", "6 am", "Noon", "6 pm", "11 pm"])
                Group {
                    if let hour = selectedHour {
                        HourInfoBox(store: store, day: day, hour: hour, use24: use24) {
                            withAnimation(reduceMotion ? nil : DS.Motion.softSpring) { selectedHour = nil }
                        }
                    } else {
                        WindowTiles(day: day, use24: use24) { hour in
                            withAnimation(reduceMotion ? nil : DS.Motion.softSpring) { selectedHour = hour }
                        }
                    }
                }
                .padding(.top, 6)
                .transition(.opacity)
                .animation(reduceMotion ? nil : DS.Motion.softSpring, value: selectedHour)
            }
            .padding(.horizontal, DS.gutter)

            actions
        }
    }

    private var actions: some View {
        ActionTriple {
            if appState.tripTracker.isTracking {
                Button { confirmEnd = true } label: {
                    Label("End session", systemImage: "stop.fill")
                }
                .buttonStyle(ActionTileStyle(.destructive))
            } else {
                Button(action: startSession) {
                    Label("Start session", systemImage: "play.fill")
                }
                .buttonStyle(ActionTileStyle(.primary))
            }

            Button(action: logCatch) {
                Label("Log catch", systemImage: "plus")
            }
            .buttonStyle(ActionTileStyle(.tonal))

            NavigationLink(value: ForecastRoute.day(offset: 0, hour: nil)) {
                ActionTileLabel("Forecast", systemImage: "chart.bar.xaxis")
            }
            .buttonStyle(.dim)
        }
    }

    // MARK: - Plans

    private var upNextRow: some View {
        Button {
            planning = nextPlan.map { PlanTarget.edit($0) } ?? PlanTarget.new
        } label: {
            if let plan = nextPlan {
                ArtRow(over: "Up next", title: plan.name,
                       subtitle: plan.plannedDate.map { planDate($0) } ?? "Planned",
                       subtitleIcon: "calendar", chevron: true) {
                    ThumbView(systemImage: "calendar", tint: DS.accent, size: 52)
                }
            } else {
                ArtRow(over: "Up next", title: "Plan a session",
                       subtitle: "Pick a day and get the best times and a gear list",
                       chevron: true) {
                    ThumbView(systemImage: "calendar.badge.plus", tint: DS.accent, size: 52)
                }
            }
        }
        .buttonStyle(.dsRow)
    }

    private func planDate(_ date: Date) -> String {
        let cal = Calendar.current
        let day = cal.isDateInToday(date) ? "Today"
            : cal.isDateInTomorrow(date) ? "Tomorrow"
            : ForecastFormat.longDate(date)
        return "\(day), \(ForecastFormat.time(date, use24: use24))"
    }

    // MARK: - Week

    private var weekStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: ForecastRoute.week) {
                SectionTitle("Next 7 days", chevron: true)
            }
            .buttonStyle(.dim)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(0..<7, id: \.self) { i in
                        let d = store.day(i)
                        NavigationLink(value: ForecastRoute.day(offset: i, hour: nil)) {
                            dayCard(d)
                        }
                        .buttonStyle(.dim)
                    }
                }
                .padding(.horizontal, DS.gutter)
            }
        }
    }

    private func dayCard(_ d: ForecastDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(d.offset == 0 ? "Today" : d.offset == 1 ? "Tomorrow" : ForecastFormat.shortDay(d.date))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.dsText)
                Spacer(minLength: 4)
                if let w = d.weather {
                    Image(systemName: WeatherIcon(condition: w.condition).systemName)
                        .symbolRenderingMode(.multicolor)
                        .font(.subheadline)
                }
            }
            ScoreRing(score: d.peakScore, size: 52)
            Text(d.bestWindow.map { ForecastFormat.hour($0.startHour, use24: use24) } ?? "No window")
                .font(.footnote)
                .foregroundStyle(.dsText2)
                .monospacedDigit()
        }
        .frame(width: 112, alignment: .leading)
        .padding(14)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ForecastFormat.dayName(d.offset, date: d.date)), best score \(d.peakScore)\(d.bestWindow.map { ", from \(ForecastFormat.hour($0.startHour, use24: use24))" } ?? "")")
    }

    // MARK: - Conditions

    private func conditions(_ day: ForecastDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Conditions")
            ConditionGrid(store: store, day: day, use24: use24)
            if let updated = store.updatedAt {
                Text(updatedLine(updated))
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, 10)
            } else if store.hasLoaded {
                Text("No weather saved yet. The score uses tide, moon and season until there is a connection.")
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, 10)
            }
        }
    }

    private func updatedLine(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        let ago = f.localizedString(for: date, relativeTo: .now)
        if Date.now.timeIntervalSince(date) > 3 * 3600 {
            return "Weather is stale since \(ago). Pull to refresh when you have signal."
        }
        return "Weather updated \(ago)."
    }

    // MARK: - Actions

    private func startSession() {
        _ = appState.tripTracker.start(name: SessionFormat.defaultName(), spotId: selectedSpot?.id)
        ToastCenter.shared.show("Session started. Tracking your spot", icon: "play.fill")
        refreshLocalData()
    }

    private func endSession() {
        guard appState.tripTracker.end() != nil else { return }
        Haptics.warning()
        ToastCenter.shared.show("Session saved to Logbook", haptic: false, icon: "checkmark")
        refreshLocalData()
    }

    /// Same path as the Logbook's log button and Siri: the root switches to
    /// Logbook and opens the log flow.
    private func logCatch() {
        appState.siriRequestedLogCatch = true
    }

    private func turnOnLocation() {
        if appState.locationManager.authorizationStatus == .notDetermined {
            appState.locationManager.requestPermission()
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    // MARK: - Data

    private func refreshLocalData() {
        spots = (try? appState.spotRepository.fetchAll()) ?? []
        ownedGear = (try? appState.ownedGearRepository.fetchAll()) ?? []
        history = (try? appState.catchRepository.fetchAll(limit: 200)) ?? []
        nextPlan = ((try? appState.tripRepository.fetchPlanned()) ?? [])
            .filter { ($0.plannedDate ?? .distantPast) > .now.addingTimeInterval(-3 * 3600) }
            .min { ($0.plannedDate ?? .distantFuture) < ($1.plannedDate ?? .distantFuture) }
        if let trip = appState.tripTracker.activeTrip {
            sessionCatches = (try? appState.tripRepository.catchCount(tripId: trip.id)) ?? 0
        }
    }

    private func reload(force: Bool) async {
        refreshLocalData()
        await store.load(force: force)
        writeWidget()
    }

    private func writeWidget() {
        let today = store.day(0).result
        let hourly = WidgetSnapshotWriter.hourlyEntries(today: today.hourlyScores,
                                                        tomorrow: store.day(1).result.hourlyScores)
        WidgetSnapshotWriter.writeBite(
            score: today.score, location: store.placeName,
            latitude: store.coordinate.latitude, longitude: store.coordinate.longitude,
            hourly: hourly)
    }

    /// Back in the app after a while: the score is for an old moment and the
    /// weather may have moved, so read it again.
    private func refreshIfStale() async {
        guard let updated = store.updatedAt, Date.now.timeIntervalSince(updated) > 15 * 60 else { return }
        await reload(force: false)
    }
}
