import SwiftUI
import CoreLocation

/// The home tab: how good the bite is right now, the day's windows, what to
/// tie on and the week ahead. The full forecast pushes from here.
struct TodayTab: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var dayCardWidth: CGFloat = 112
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
    @State private var showPlanner = false
    @State private var confirmEnd = false

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

    /// Today's weather when it is a real reading. Offline with nothing saved,
    /// only the barometer is real, so the picks go without the rest.
    private var measuredWeather: WeatherService.WeatherData? {
        store.weatherIsEstimate ? nil : weather
    }

    private var clarity: WaterClarity {
        WaterClarity(rawValue: clarityOverride) ?? WaterClarity.inferred(precipMm: measuredWeather?.precipMm)
    }

    private var suggestions: [LureEngine.Suggestion] {
        let conditions = LureEngine.Conditions(
            waterTempC: measuredWeather?.waterTempC,
            clarity: clarity,
            cloudCoverPct: measuredWeather?.cloudCoverPct,
            windSpeedKmh: measuredWeather?.windSpeedKmh,
            pressureChange6h: weather?.pressureChange6h
        )
        return LureEngine.recommend(conditions: conditions, species: store.species,
                                    ownedGear: ownedGear, history: history)
    }

    private var locationOff: Bool {
        selectedSpot == nil && !appState.locationManager.isAuthorized && !ScreenshotSupport.isActive
    }

    // MARK: - Body

    var body: some View {
        let today = store.day(0)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LargeTitleHeader("Today") {
                    HeaderIconButton("Plan a session", systemImage: "calendar.badge.plus") {
                        showPlanner = true
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
                        suggestions: suggestions, weather: measuredWeather, isNight: today.isDarkNow,
                        clarity: clarity, clarityIsGuess: clarityOverride.isEmpty, species: store.species,
                        hasGear: !ownedGear.isEmpty, onClarity: { clarityOverride = $0.rawValue }
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
            let live = await reload(force: true)
            ForecastStore.refreshFeedback(live)
        }
        .navigationDestination(for: ForecastRoute.self) { route in
            ForecastDestination(store: store, route: route)
        }
        .syncsTargetSpecies(store)
        .onChange(of: store.species?.id) { _, _ in writeWidget() }
        .task(id: locationKey) {
            let loc = resolvedLocation
            let fresh = selectedSpot.flatMap { ThrowSpeciesChoice.isFreshwater($0.type) }
            store.setLocation(loc.coordinate, name: loc.name, freshwater: fresh)
            await reload(force: false)
            // Name the phone's location after the town, as Explore does.
            // Offline the lookup fails and the line keeps "Current location".
            if loc.name == "Current location", let town = await townName(loc.coordinate), !Task.isCancelled {
                store.setLocation(loc.coordinate, name: town, freshwater: fresh)
                writeWidget()
            }
        }
        .onAppear { refreshLocalData() }
        .onChange(of: appState.tripTracker.isTracking) { _, tracking in
            refreshLocalData()
            // Ended elsewhere (Explore, the Live Activity): close the sheet
            // rather than leave it blank.
            if !tracking { showSession = false }
        }
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
                                  onEnd: endSession,
                                  isDayActive: appState.tripTracker.isDayActive,
                                  onStartNextDay: startNextDay)
            } else {
                TodaySessionEndedSheet()
            }
        }
        .sheet(isPresented: $showPlanner, onDismiss: refreshLocalData) {
            PlanSessionSheet()
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
        // Place and date side by side; at accessibility sizes the date moves
        // under the place, so the place keeps the width for its name.
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            Button { showLocation = true } label: {
                HStack(alignment: stacked ? .firstTextBaseline : .center, spacing: 4) {
                    Image(systemName: selectedSpot == nil ? "location.fill" : "mappin")
                        .font(.footnote)
                    Text(store.placeName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(stacked ? 2 : 1)
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
        // Text and button side by side, stacked at accessibility sizes.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "location.slash")
                    .foregroundStyle(.dsText2)
                Text("Location is off, so this is the forecast for Cape Town.")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            // A small tonal button, as on the Crew notices.
            Button("Turn on location", action: turnOnLocation)
                .buttonStyle(TonalButtonStyle(fullWidth: false))
        }
        .padding(14)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        .padding(.horizontal, DS.gutter)
        .padding(.top, 12)
    }

    // MARK: - Session

    /// The running session, or a multi-day session between days: "Day 1
    /// done" with its time frozen and a button to start the next day.
    private func sessionBanner(_ trip: Trip) -> some View {
        let dayDone = !appState.tripTracker.isDayActive && !trip.decodedDays.isEmpty
        let tint: Color = dayDone ? DS.accent : .dsScoreSlow
        let lines = typeSize.isAccessibilitySize ? 3 : 1
        return VStack(alignment: .leading, spacing: 12) {
            Button { showSession = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: dayDone ? "pause.circle" : "record.circle")
                        .font(.title3)
                        .foregroundStyle(tint)
                        .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion && !dayDone)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(dayDone ? "Day \(trip.decodedDays.count) done" : "Session running")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.dsText)
                        if dayDone {
                            Text("\(trip.name), \(ForecastFormat.elapsed(trip.totalDurationSeconds)) so far")
                                .font(.footnote)
                                .foregroundStyle(.dsText2)
                                .lineLimit(lines)
                        } else {
                            // Redrawn each minute; the total runs to now across every day.
                            TimelineView(.periodic(from: .now, by: 60)) { _ in
                                Text("\(trip.name), \(ForecastFormat.elapsed(trip.totalDurationSeconds))")
                                    .font(.footnote)
                                    .foregroundStyle(.dsText2)
                                    .lineLimit(lines)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.dsText3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.dim)

            if dayDone {
                Button("Start day \(trip.decodedDays.count + 1)", action: startNextDay)
                    .buttonStyle(.dsPrimary)
            }
        }
        .padding(14)
        .background(tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        .padding(.horizontal, DS.gutter)
        .padding(.top, 12)
    }

    // MARK: - Hero

    private func hero(_ day: ForecastDay) -> some View {
        let score = day.result.score
        let reason = day.result.reasons.first.map(ForecastFormat.clean) ?? ForecastFormat.guidance(score)
        let currentHour = Calendar.current.component(.hour, from: .now)
        return VStack(alignment: .leading, spacing: 18) {
            // The verdict already says "now", so the label names the hour.
            // PageHero puts the ring under the text at accessibility sizes.
            PageHero(label: "This hour", value: ForecastFormat.verdict(score), callout: reason) {
                ScoreRing(score: score, size: 100, caption: "of 100")
            }

            VStack(spacing: 8) {
                BiteBars(hourly: day.result.hourlyScores, windows: day.windows,
                         currentHour: currentHour, selected: $selectedHour, height: 72, use24: use24,
                         nowScore: score)
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

    /// The next plan opens on its own page; with none, the row starts one.
    @ViewBuilder
    private var upNextRow: some View {
        if let plan = nextPlan {
            NavigationLink(value: AppRoute.plan(plan.id)) {
                ArtRow(over: "Up next", title: plan.name,
                       subtitle: plan.plannedDate.map { planDate($0) } ?? "Planned",
                       subtitleIcon: "calendar", chevron: true) {
                    ThumbView(systemImage: "calendar", tint: DS.accent, size: 52)
                }
            }
            .buttonStyle(.dsRow)
        } else {
            Button { showPlanner = true } label: {
                ArtRow(over: "Up next", title: "Plan a session",
                       subtitle: "Pick a day and get the best times and a gear list",
                       chevron: true) {
                    ThumbView(systemImage: "calendar.badge.plus", tint: DS.accent, size: 52)
                }
            }
            .buttonStyle(.dsRow)
        }
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
                // Cards share the tallest card's height when one wraps.
                .fixedSize(horizontal: false, vertical: true)
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
            // The ring is the day's peak; once today's has passed, say so.
            Text(d.bestWindow.map { (d.bestWindowPassed ? "Peaked " : "") + ForecastFormat.hour($0.startHour, use24: use24) }
                 ?? "No standout window")
                .font(.footnote)
                .foregroundStyle(.dsText2)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: dayCardWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(14)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ForecastFormat.dayName(d.offset, date: d.date)), best score \(d.peakScore)\(d.bestWindow.map { ", \(d.bestWindowPassed ? "peaked at" : "from") \(ForecastFormat.hour($0.startHour, use24: use24))" } ?? "")")
    }

    // MARK: - Conditions

    private func conditions(_ day: ForecastDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Conditions")
            ConditionGrid(store: store, day: day, use24: use24)
            if store.weatherIsEstimate {
                SectionFootnote("No weather offline. The score uses pressure, tide, moon and season until there is signal.")
            } else if let updated = store.updatedAt {
                SectionFootnote(updatedLine(updated))
            } else if store.hasLoaded {
                SectionFootnote("No weather saved yet. The score uses tide, moon and season until there is signal.")
            }
        }
    }

    /// "Updated 20 min ago.", with a nudge to refresh once it is old.
    private func updatedLine(_ date: Date) -> String {
        let line = ForecastFormat.updated(date)
        if Date.now.timeIntervalSince(date) > 3 * 3600 {
            return line + ". Pull to refresh when you have signal."
        }
        return line + "."
    }

    // MARK: - Actions

    private func startSession() {
        _ = appState.tripTracker.start(name: SessionFormat.defaultName(), spotId: selectedSpot?.id)
        guard appState.tripTracker.isTracking else { return }
        ToastCenter.shared.show("Session started", icon: "play.fill")
        refreshLocalData()
    }

    /// The next day of a multi-day session.
    private func startNextDay() {
        let tracker = appState.tripTracker
        let next = (tracker.activeTrip?.decodedDays.count ?? 0) + 1
        tracker.startNextDay()
        guard tracker.isDayActive else { return }
        ToastCenter.shared.show("Day \(next) started", icon: "play.fill")
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

    /// Reads the local data and the weather. False when the weather service
    /// could not be reached.
    @discardableResult
    private func reload(force: Bool) async -> Bool {
        refreshLocalData()
        let live = await store.load(force: force)
        writeWidget()
        return live
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

    /// The town for a coordinate, or nil when the lookup fails (offline).
    private func townName(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let place = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        return place.locality ?? place.subAdministrativeArea ?? place.name
    }

    /// Back in the app after a while: the score is for an old moment and the
    /// weather may have moved, so read it again.
    private func refreshIfStale() async {
        // No real reading yet (an offline estimate) counts as stale too.
        if let updated = store.updatedAt, Date.now.timeIntervalSince(updated) <= 15 * 60 { return }
        await reload(force: false)
    }
}
