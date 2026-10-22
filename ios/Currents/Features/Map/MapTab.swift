import SwiftUI
import MapKit

/// Wrapper so CLLocationCoordinate2D can drive a .sheet(item:) binding.
struct IdentifiableCoordinate: Identifiable {
    let coord: CLLocationCoordinate2D
    var id: String { "\(coord.latitude),\(coord.longitude)" }
}

/// Explore: the full-bleed map. Search and shortcuts sit at the top, map
/// controls down the right, the bite near you at the bottom. Pins open a peek
/// sheet; spots, water, lists and the species guide push onto this tab's stack.
struct MapTab: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var mapScope
    @State private var position: MapCameraPosition = ScreenshotSupport.isActive
        ? .camera(MapCamera(centerCoordinate: ScreenshotSupport.demoCoordinate, distance: 42000))
        : .userLocation(fallback: .automatic)
    @State private var spots: [Spot] = []
    @State private var catches: [CatchDetail] = []
    @State private var topSpecies: [String: Species] = [:]
    @State private var showingLiveTrip = false
    @State private var showingNewTrip = false
    // The standard Apple map is the default view; persisted so a style choice
    // (incl. the offline cached-tile map) sticks across launches.
    @AppStorage("mapStyleOption") private var mapStyleRaw = MapStyleOption.standard.rawValue
    @AppStorage("showCatchPins") private var showCatchPins = false
    @AppStorage("mapLayer_spots") private var showSpots = true
    @AppStorage("mapLayer_water") private var showWaterbodies = true
    @State private var flyToCoordinate: CLLocationCoordinate2D?
    @State private var weather: WeatherService.WeatherData?
    @State private var nearBite: BiteSnapshot?
    @State private var inspector: InspectTarget?
    @State private var spotScores: [String: Int] = [:]
    @State private var waterbodies: [Waterbody] = []
    @State private var waterbodyScores: [Int64: Int] = [:] // keyed by id ?? 0
    @State private var isLoadingWaterbodies = false
    @State private var waterbodyDebounceTask: Task<Void, Never>?
    @State private var currentLatSpan: Double = 1.0
    @State private var lastMapCenter: CLLocationCoordinate2D?
    @State private var lastRegion: MKCoordinateRegion?
    // Optional overlay layers, off by default, toggled from the layers sheet.
    @AppStorage("mapLayer_nautical") private var layerNautical = false
    @AppStorage("mapLayer_radar") private var layerRadar = false
    @AppStorage("mapLayer_wind") private var layerWind = false
    @AppStorage("mapLayer_current") private var layerCurrent = false
    @State private var radarOverlay: MKTileOverlay?
    // Public fishing access points and boat ramps (OpenStreetMap, bundled for
    // South Africa). On by default: they are the public fishing spots.
    @AppStorage("mapLayer_ramps") private var layerRamps = true
    @StateObject private var rampService = BoatRampService.shared

    // Sheets and pushes
    @State private var peek: PinPeek?
    @State private var selectedRamp: BoatRamp?
    @State private var showingLayers = false
    @State private var addSpotAt: AddSpotTarget?
    @State private var isDropping = false
    @State private var pendingRoute: ExploreRoute?

    // Search
    @State private var isSearchOpen = false
    @State private var searchText = ""
    @State private var searchModel = MapSearchCompleter()
    @State private var isSearching = false
    @State private var searchSpecies: [Species] = []
    @State private var searchWaters: [Waterbody] = []
    @FocusState private var searchFocused: Bool

    enum MapStyleOption: String, CaseIterable {
        case offline = "Offline"
        case standard = "Standard"
        case imagery = "Satellite"
        case hybrid = "Hybrid"
        case fishing = "Fishing"

        /// Sentence-case name for the layers sheet. The raw value is what is stored.
        var title: String {
            switch self {
            case .offline: "Offline"
            case .standard: "Standard"
            case .imagery: "Satellite"
            case .hybrid: "Hybrid"
            case .fishing: "Fishing"
            }
        }
    }

    /// A tapped or inspected point. The user's own location gets its own lead line.
    struct InspectTarget: Identifiable {
        let coord: CLLocationCoordinate2D
        var isUserLocation = false
        var id: String { "\(coord.latitude),\(coord.longitude),\(isUserLocation)" }
    }

    /// Where a new spot goes; nil coordinate means "where I am now".
    struct AddSpotTarget: Identifiable {
        let id = UUID()
        let coord: CLLocationCoordinate2D?
    }

    private var mapStyle: MapStyleOption {
        get { MapStyleOption(rawValue: mapStyleRaw) ?? .offline }
        nonmutating set { mapStyleRaw = newValue.rawValue }
    }

    private var accent: Color { DS.accent }

    private var userCoordinate: CLLocationCoordinate2D? {
        appState.locationManager.currentLocation?.coordinate
    }

    private var overlaysOn: Bool { layerNautical || layerRadar || layerWind || layerCurrent }

    /// Catches without an assigned spot, minus any that sit on top of a saved
    /// spot so they don't render over the spot pin.
    private var unassignedCatches: [CatchDetail] {
        catches.filter { detail in
            guard detail.catchRecord.spotId == nil else { return false }
            let loc = CLLocation(
                latitude: detail.catchRecord.latitude,
                longitude: detail.catchRecord.longitude
            )
            return !spots.contains { spot in
                CLLocation(latitude: spot.latitude, longitude: spot.longitude)
                    .distance(from: loc) < 75
            }
        }
    }

    private var visibleWaterbodies: [Waterbody] {
        showWaterbodies && currentLatSpan < 3 ? waterbodies : []
    }

    private var visibleRamps: [BoatRamp] {
        layerRamps && currentLatSpan < 2.5 ? rampService.ramps : []
    }

    private var clusters: [PinCluster] {
        var features: [ExploreFeature] = []
        if showSpots { features += spots.map(ExploreFeature.spot) }
        features += visibleWaterbodies.map(ExploreFeature.water)
        if showCatchPins { features += unassignedCatches.map(ExploreFeature.catchPin) }
        features += visibleRamps.map(ExploreFeature.ramp)
        return PinClustering.cluster(features, latSpan: currentLatSpan)
    }

    var body: some View {
        ZStack {
            mapLayer
                .ignoresSafeArea()

            if isDropping {
                dropPin
            }

            if !isSearchOpen {
                VStack(spacing: 0) {
                    if isDropping {
                        dropHeader
                    } else {
                        topChrome
                    }
                    Spacer(minLength: 0)
                    if isDropping {
                        dropBar
                    } else {
                        nearYouCapsule
                    }
                }
                .transition(.opacity)
            }

            if isSearchOpen {
                searchPane
                    .transition(.opacity)
            }
        }
        // Keeps the clock legible over bright tiles and the top controls clear of it.
        .statusBarScrim()
        .mapScope(mapScope)
        .animation(reduceMotion ? nil : DS.Motion.easeOut, value: isSearchOpen)
        .animation(reduceMotion ? nil : DS.Motion.easeOut, value: isDropping)
        // Discrete map-style / overlay / pin toggles get a light selection
        // tick. Bound to the stored values so only real changes fire (never
        // pan/zoom).
        .sensoryFeedback(.selection, trigger: mapStyleRaw)
        .sensoryFeedback(.selection, trigger: layerNautical)
        .sensoryFeedback(.selection, trigger: layerRadar)
        .sensoryFeedback(.selection, trigger: layerWind)
        .sensoryFeedback(.selection, trigger: layerCurrent)
        .sensoryFeedback(.selection, trigger: showWaterbodies)
        .sensoryFeedback(.selection, trigger: showCatchPins)
        .sensoryFeedback(.selection, trigger: showSpots)
        .sensoryFeedback(.selection, trigger: layerRamps)
        .sensoryFeedback(.impact(weight: .medium), trigger: isDropping) { _, new in new }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: ExploreRoute.self) { ExploreDestination(route: $0) }
        .navigationDestination(item: $pendingRoute) { ExploreDestination(route: $0) }
        .sheet(item: $peek, onDismiss: { Task { await loadData() } }) { p in
            PinPeekSheet(peek: p) { route in openRoute(route) }
        }
        .sheet(item: $selectedRamp) { ramp in
            RampDetailSheet(ramp: ramp)
        }
        .sheet(item: $inspector, onDismiss: { Task { await loadData() } }) { target in
            LocationInspectorSheet(coordinate: target.coord, isUserLocation: target.isUserLocation) { route in
                openRoute(route)
            }
        }
        .sheet(item: $addSpotAt, onDismiss: { Task { await loadData() } }) { target in
            AddSpotSheet(prefillCoordinate: target.coord)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingLayers) {
            MapLayersSheet(
                style: Binding(get: { mapStyle }, set: { mapStyle = $0 }),
                showSpots: $showSpots,
                showCatches: $showCatchPins,
                showWater: $showWaterbodies,
                showRamps: $layerRamps,
                nautical: $layerNautical,
                radar: $layerRadar,
                wind: $layerWind,
                current: $layerCurrent
            )
        }
        .sheet(isPresented: $showingNewTrip, onDismiss: {
            if appState.tripTracker.isTracking { showingLiveTrip = true }
        }) {
            NewSessionSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingLiveTrip) {
            NavigationStack {
                ActiveSessionView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Minimise") { showingLiveTrip = false }
                        }
                    }
            }
            // Pull the sheet down to minimise it (the session keeps
            // recording in the background); ending is a separate action.
            .presentationDetents([.large, .medium])
            .presentationDragIndicator(.visible)
        }
        .task(id: layerRadar) {
            // Fetch the latest radar frame when the layer is turned on;
            // clear it when off.
            if layerRadar {
                radarOverlay = await RadarTiles.latest()
            } else {
                radarOverlay = nil
            }
        }
        // Overlays only render on the offline (MKMapView) map, so switch to
        // it automatically when a layer is enabled.
        .onChange(of: layerNautical) { _, on in if on { mapStyle = .offline } }
        .onChange(of: layerRadar) { _, on in if on { mapStyle = .offline } }
        .onChange(of: layerWind) { _, on in if on { mapStyle = .offline } }
        .onChange(of: layerCurrent) { _, on in if on { mapStyle = .offline } }
        // Fetch ramps as soon as the layer is switched on for wherever the
        // camera already sits.
        .onChange(of: layerRamps) { _, on in
            guard on else { return }
            let center = lastMapCenter ?? userCoordinate
            let span = currentLatSpan
            if let center { Task { await rampService.load(around: center, latSpan: span) } }
        }
        .onChange(of: appState.openLiveSession) { _, open in
            // A Live Activity / notification tap asked to open the live
            // session so a catch can be logged straight away.
            guard open else { return }
            appState.openLiveSession = false
            if appState.tripTracker.isTracking { showingLiveTrip = true }
        }
        .task {
            // Cold-launch case: the flag may already be set before onChange
            // starts observing.
            if appState.openLiveSession {
                appState.openLiveSession = false
                if appState.tripTracker.isTracking { showingLiveTrip = true }
            }
        }
        .task {
            appState.mapManager.refreshDownloadedRegions()
            await loadData()
            if let loc = appState.locationManager.currentLocation {
                appState.mapManager.maintainOfflineCache(around: loc.coordinate)
            }
            // Screenshot mode: frame the demo coast AND the seeded dam/lake
            // bubbles after first layout. A runtime .camera applies
            // reliably (an initial @State camera and .region do not);
            // ~90 km out zooms far enough to show the dam cluster.
            if ScreenshotSupport.isActive {
                position = .camera(.init(
                    centerCoordinate: CLLocationCoordinate2D(latitude: -34.275, longitude: 18.865),
                    distance: 90000
                ))
            }
        }
        // Cache follows the PERSON: whenever their position updates, the
        // manager re-anchors the offline cache if they've moved far
        // (pruning tiles around the old area, prefetching the new one).
        .onChange(of: appState.locationManager.currentLocation) { _, loc in
            if let loc {
                appState.mapManager.maintainOfflineCache(around: loc.coordinate)
            }
        }
    }

    // MARK: - Map

    @ViewBuilder
    private var mapLayer: some View {
        if mapStyle == .offline {
            // Cached satellite tiles as the main map, which works offline
            // for everywhere the auto-cache has covered.
            OfflineMapView(
                overlay: appState.mapManager.offlineOverlay,
                spots: showSpots ? spots : [],
                catches: showCatchPins ? unassignedCatches : [],
                waterbodies: visibleWaterbodies,
                spotScores: spotScores,
                waterbodyScores: waterbodyScores,
                accent: accent,
                showNautical: layerNautical,
                radarOverlay: layerRadar ? radarOverlay : nil,
                showWind: layerWind,
                showCurrent: layerCurrent,
                windSpeedKmh: weather?.windSpeedKmh,
                windFromDeg: weather?.windDirectionDeg ?? 0,
                flyTo: $flyToCoordinate,
                onSelectSpot: { peek = PinPeek(target: .spot($0)) },
                onSelectWaterbody: { peek = PinPeek(target: .water($0)) },
                onTap: { coord in
                    guard !isDropping else { return }
                    inspector = InspectTarget(coord: coord)
                },
                onRegionChange: { handleRegionChange($0) },
                ramps: visibleRamps,
                onSelectRamp: { selectedRamp = $0 },
                onSelectCatch: { peek = PinPeek(target: .catchItem($0)) },
                onLongPress: { coord in dropSpot(at: coord) },
                compassTopInset: 164
            )
        } else {
            MapReader { proxy in
                Map(position: $position, scope: mapScope) {
                    UserAnnotation(anchor: .center) { _ in
                        UserLocationMarker(
                            heading: appState.locationManager.heading,
                            accent: accent
                        )
                    }

                    // Water body outlines, only when zoomed in enough to see them.
                    if currentLatSpan < 1.0 {
                        ForEach(visibleWaterbodies) { wb in
                            MapCircle(
                                center: CLLocationCoordinate2D(latitude: wb.latitude, longitude: wb.longitude),
                                radius: CLLocationDistance(min(wb.approximateRadiusM, 50000))
                            )
                            .foregroundStyle(Color.exploreWater.opacity(0.16))
                            .stroke(Color.exploreWater.opacity(0.55), lineWidth: 1.5)
                        }
                    }

                    ForEach(clusters) { cluster in
                        Annotation("", coordinate: cluster.coordinate) {
                            pinView(cluster)
                        }
                    }
                }
                .mapStyle(activeMapStyle)
                // Built-in controls off; the compass sits under the top chrome.
                .mapControls { }
                .onMapCameraChange(frequency: .onEnd) { context in
                    handleRegionChange(context.region)
                }
                .onTapGesture(coordinateSpace: .local) { screenPoint in
                    guard !isDropping else { return }
                    if let coord = proxy.convert(screenPoint, from: .local) {
                        inspector = InspectTarget(coord: coord)
                    }
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                        .onEnded { value in
                            guard case .second(true, let drag?) = value,
                                  let coord = proxy.convert(drag.location, from: .local) else { return }
                            dropSpot(at: coord)
                        }
                )
            }
        }
    }

    @ViewBuilder
    private func pinView(_ cluster: PinCluster) -> some View {
        if cluster.members.count == 1 {
            let feature = cluster.lead
            ExplorePin(
                feature: feature,
                score: score(for: feature),
                topSpecies: spotSpecies(feature),
                showsLabel: showsLabel(feature)
            )
            .onTapGesture { select(feature) }
        } else {
            ClusterPin(cluster: cluster, topSpecies: { topSpecies[$0.id] })
                .onTapGesture {
                    Haptics.tap()
                    let region = PinClustering.region(for: cluster, currentSpan: currentLatSpan)
                    withAnimation(reduceMotion ? nil : DS.Motion.softSpring) {
                        position = .region(region)
                    }
                }
        }
    }

    private func score(for feature: ExploreFeature) -> Int? {
        switch feature {
        case .spot(let s): spotScores[s.id]
        case .water(let w): waterbodyScores[w.id ?? 0]
        case .catchPin, .ramp: nil
        }
    }

    private func spotSpecies(_ feature: ExploreFeature) -> Species? {
        if case .spot(let s) = feature { return topSpecies[s.id] }
        return nil
    }

    private func showsLabel(_ feature: ExploreFeature) -> Bool {
        switch feature {
        case .spot: true
        case .water: currentLatSpan < 0.6
        case .ramp: currentLatSpan < 0.08
        case .catchPin: false
        }
    }

    private func select(_ feature: ExploreFeature) {
        Haptics.tap()
        switch feature {
        case .spot(let s): peek = PinPeek(target: .spot(s))
        case .water(let w): peek = PinPeek(target: .water(w))
        case .catchPin(let c): peek = PinPeek(target: .catchItem(c))
        case .ramp(let r): selectedRamp = r
        }
    }

    private var activeMapStyle: MapStyle {
        switch mapStyle {
        case .offline: .imagery(elevation: .realistic) // unused; offline uses MKMapView
        case .standard: .standard(elevation: .realistic)
        case .imagery: .imagery(elevation: .realistic)
        case .hybrid: .hybrid(elevation: .realistic)
        case .fishing: .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll)
        }
    }

    // MARK: - Top chrome

    private var topChrome: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s3) {
                ProfileAvatarButton()
                Button {
                    openSearch()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.dsText2)
                        Text("Spots, water, ramps, species")
                            .font(.body)
                            .foregroundStyle(.dsText2)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .contentShape(Capsule())
                    .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.dim)
                .accessibilityLabel("Search spots, water, ramps and species")
            }
            .padding(.horizontal, DS.Space.s4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    chip("Your spots", systemImage: "mappin", route: .spots)
                    chip("Species", systemImage: "fish", route: .speciesGuide)
                    chip("Water", systemImage: "water.waves", route: .waters)
                    chip("Ramps and access", systemImage: "figure.fishing", route: .ramps)
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, 2)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    offlineBadge
                    if isLoadingWaterbodies {
                        Label {
                            Text("Finding water")
                        } icon: {
                            ProgressView().controlSize(.mini)
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.dsText2)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .glassEffect(.regular, in: Capsule())
                        .transition(.opacity)
                    }
                    if mapStyle != .offline {
                        MapCompass(scope: mapScope)
                    }
                }
                Spacer(minLength: 0)
                sideButtons
            }
            .padding(.horizontal, DS.Space.s4)
        }
        // A little air under the status bar so the clock and the search
        // field never read as one row.
        .padding(.top, DS.Space.s3)
        .animation(reduceMotion ? nil : DS.Motion.easeOut, value: isLoadingWaterbodies)
    }

    private func chip(_ title: String, systemImage: String, route: ExploreRoute) -> some View {
        NavigationLink(value: route) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.dsText)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.dim)
    }

    /// Which offline region the map covers, or when scores were last worked
    /// out if the weather is old. Opens offline maps and storage.
    private var offlineBadge: some View {
        let regions = appState.mapManager.downloadedRegions
        let stale = weather.map { Date.now.timeIntervalSince($0.fetchedAt) > 3 * 3600 } ?? false
        let text: String
        let icon: String
        if stale, let w = weather {
            text = "Offline. Scores from \(w.fetchedAt.formatted(date: .omitted, time: .shortened))"
            icon = "icloud.slash"
        } else if regions.count == 1, let region = regions.first {
            text = "\(region.name) offline"
            icon = "arrow.down.circle"
        } else if regions.count > 1 {
            text = "\(regions.count) regions offline"
            icon = "arrow.down.circle"
        } else {
            text = "Offline maps"
            icon = "arrow.down.circle"
        }
        return NavigationLink(value: ExploreRoute.offlineMaps) {
            Label(text, systemImage: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(stale ? Color.dsScoreFair : Color.dsText)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.dim)
    }

    private var sideButtons: some View {
        VStack(spacing: 10) {
            Button { showingLayers = true } label: {
                glassCircle("square.3.layers.3d", dot: overlaysOn || mapStyle != .standard ? DS.accent : nil)
            }
            .buttonStyle(.dim)
            .accessibilityLabel("Map layers")

            Button { locateMe() } label: {
                glassCircle("location")
            }
            .buttonStyle(.dim)
            .accessibilityLabel("Show my location")

            Button { isDropping = true } label: {
                glassCircle("mappin.and.ellipse")
            }
            .buttonStyle(.dim)
            .accessibilityLabel("Add spot")

            // Start or resume a fishing session.
            if FeatureFlags.liveTrips {
                Button {
                    if appState.tripTracker.isTracking {
                        showingLiveTrip = true
                    } else {
                        showingNewTrip = true
                    }
                } label: {
                    glassCircle(appState.tripTracker.isTracking ? "figure.fishing" : "play.fill",
                                dot: appState.tripTracker.isTracking ? Color.dsScoreSlow : nil)
                }
                .buttonStyle(.dim)
                .accessibilityLabel(appState.tripTracker.isTracking ? "Open live session" : "Start a session")
            }
        }
    }

    private func glassCircle(_ systemImage: String, dot: Color? = nil) -> some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.medium))
            .foregroundStyle(.dsText)
            .frame(width: 46, height: 46)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: Circle())
            .overlay(alignment: .topTrailing) {
                if let dot {
                    Circle()
                        .fill(dot)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Color.dsBackground, lineWidth: 1.5))
                        .offset(x: -3, y: 3)
                }
            }
    }

    // MARK: - Biting near you

    private var nearYouCapsule: some View {
        Button {
            if let coord = userCoordinate {
                inspector = InspectTarget(coord: coord, isUserLocation: true)
            } else if let coord = lastMapCenter {
                inspector = InspectTarget(coord: coord)
            }
        } label: {
            HStack(spacing: DS.Space.s3) {
                if let nearBite {
                    ScoreDisc(score: nearBite.now, size: 44)
                } else {
                    Circle().fill(Color.dsFill).frame(width: 44, height: 44)
                        .overlay(ProgressView().controlSize(.small))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(userCoordinate == nil ? "Biting here" : "Biting near you")
                        .font(.headline)
                        .foregroundStyle(.dsText)
                    Text(nearSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.dsText3)
            }
            .padding(.leading, 10)
            .padding(.trailing, 18)
            .padding(.vertical, 10)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous))
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous))
        }
        .buttonStyle(.dim)
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .accessibilityHint("Shows the bite, conditions and water near you")
    }

    private var nearSubtitle: String {
        guard let nearBite else { return "Working out the bite" }
        let use24 = UserDefaults.standard.object(forKey: "use24HourTime") as? Bool ?? true
        if let best = spots.filter({ spotScores[$0.id] != nil })
            .max(by: { (spotScores[$0.id] ?? 0) < (spotScores[$1.id] ?? 0) }) {
            return "Best spot now \(best.name)"
        }
        if let window = nearBite.best {
            return "\(ExploreFormat.verdict(nearBite.now)), best \(ExploreFormat.window(window, use24Hour: use24))"
        }
        return ExploreFormat.verdict(nearBite.now)
    }

    // MARK: - Drop mode

    /// The pin fixed at the map's centre while placing a spot.
    private var dropPin: some View {
        Image(systemName: "mappin")
            .font(.largeTitle.weight(.semibold))
            .imageScale(.large)
            .foregroundStyle(Color.dsScoreSlow)
            .mapPinShadow()
            .offset(y: -20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var dropHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Place your spot")
                .font(.headline)
                .foregroundStyle(.dsText)
            Text("Move the map under the pin, or long press anywhere")
                .font(.subheadline)
                .foregroundStyle(.dsText2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous))
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
    }

    private var dropBar: some View {
        HStack(spacing: DS.Space.s3) {
            Button("Cancel") { isDropping = false }
                .buttonStyle(TonalButtonStyle())
            Button("Use this spot") {
                dropSpot(at: lastMapCenter ?? userCoordinate)
            }
            .buttonStyle(.dsPrimary)
        }
        .padding(DS.Space.s3)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous))
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }

    private func dropSpot(at coord: CLLocationCoordinate2D?) {
        Haptics.tap()
        isDropping = false
        addSpotAt = AddSpotTarget(coord: coord)
    }

    private func locateMe() {
        if mapStyle == .offline {
            flyToCoordinate = userCoordinate
        } else {
            withAnimation(reduceMotion ? nil : DS.Motion.softSpring) {
                position = .userLocation(fallback: .automatic)
            }
        }
    }

    // MARK: - Search

    private func openSearch() {
        isSearchOpen = true
        searchFocused = true
        if searchSpecies.isEmpty {
            searchSpecies = (try? appState.speciesRepository.fetchAll()) ?? []
        }
        // Re-read each time: bundled and Overpass water arrive after launch.
        searchWaters = (try? appState.waterbodyRepository.fetchAll()) ?? []
    }

    private func closeSearch() {
        searchFocused = false
        searchText = ""
        searchModel.clear()
        isSearchOpen = false
    }

    private var query: String { searchText.trimmingCharacters(in: .whitespaces) }

    private var spotResults: [Spot] {
        spots.filter { $0.name.localizedCaseInsensitiveContains(query) }.prefix(5).map { $0 }
    }

    /// Names that start with the query first, then the biggest water.
    private var waterResults: [Waterbody] {
        var seen = Set<String>()
        let q = query.lowercased()
        let hits = (waterbodies + searchWaters)
            .filter { $0.name.localizedCaseInsensitiveContains(query) }
            .filter { seen.insert("\($0.id ?? 0)-\($0.name)").inserted }
        let ranked = hits.sorted { a, b in
            let ap = a.name.lowercased().hasPrefix(q), bp = b.name.lowercased().hasPrefix(q)
            if ap != bp { return ap }
            return (a.surfaceAreaKm2 ?? 0) > (b.surfaceAreaKm2 ?? 0)
        }
        return Array(ranked.prefix(5))
    }

    private var rampResults: [BoatRamp] {
        rampService.ramps.filter { $0.name.localizedCaseInsensitiveContains(query) }.prefix(4).map { $0 }
    }

    private var speciesResults: [Species] {
        let q = query
        let hits = searchSpecies.filter {
            $0.commonName.localizedCaseInsensitiveContains(q) || $0.scientificName.localizedCaseInsensitiveContains(q)
        }
        let prefix = hits.filter { $0.commonName.lowercased().hasPrefix(q.lowercased()) }
        let rest = hits.filter { !$0.commonName.lowercased().hasPrefix(q.lowercased()) }
        return Array((prefix + rest).prefix(5))
    }

    private var searchPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.s3) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.dsText2)
                    TextField("Spots, water, ramps, species", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onSubmit(submitSearch)
                        .onChange(of: searchText) { _, newValue in
                            searchModel.update(query: newValue, near: userCoordinate ?? lastMapCenter)
                        }
                    if isSearching {
                        ProgressView().controlSize(.small)
                    }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchModel.clear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.dsText3)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.dsFill, in: Capsule())

                Button("Cancel") { closeSearch() }
                    .foregroundStyle(.dsText)
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s2)
            .padding(.bottom, DS.Space.s2)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if query.isEmpty {
                        GroupLabel("Browse")
                        browseRow("Species guide", "fish", .speciesGuide)
                        browseRow("Your spots", "mappin", .spots)
                        browseRow("Water", "water.waves", .waters)
                        browseRow("Access and ramps", "figure.fishing", .ramps)
                    } else {
                        searchResults
                    }
                }
                .padding(.bottom, DS.Space.s8)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Color.dsBackground.ignoresSafeArea())
    }

    @ViewBuilder
    private var searchResults: some View {
        let spotHits = spotResults
        let waterHits = waterResults
        let rampHits = rampResults
        let speciesHits = speciesResults
        let places = Array(searchModel.completions.prefix(6))
        if spotHits.isEmpty && waterHits.isEmpty && rampHits.isEmpty && speciesHits.isEmpty && places.isEmpty {
            ContentUnavailableView {
                Label("No results for \u{201C}\(query)\u{201D}", systemImage: "magnifyingglass")
            } description: {
                Text("Search covers your spots, water bodies and ramps, every species in the guide, and places on the map.")
            }
            .padding(.top, DS.Space.s8)
        } else {
            if !spotHits.isEmpty {
                GroupLabel("Your spots")
                ForEach(spotHits) { spot in
                    resultButton {
                        openRoute(.spot(SpotRef(spot)), fromSearch: true)
                    } label: {
                        ArtRow(title: spot.name, subtitle: ExploreFormat.spotType(spot), chevron: true) {
                            if let sp = topSpecies[spot.id] {
                                ThumbView(species: sp, size: 48)
                            } else {
                                ThumbView(systemImage: spot.type.icon, tint: DS.accent, size: 48)
                            }
                        }
                    }
                }
            }
            if !waterHits.isEmpty {
                GroupLabel("Water")
                ForEach(waterHits) { wb in
                    resultButton {
                        openRoute(.waterbody(WaterbodyRef(wb)), fromSearch: true)
                    } label: {
                        ArtRow(title: wb.name, subtitle: waterSubtitle(wb), chevron: true) {
                            ThumbView(systemImage: ExploreFormat.waterIcon(wb.type),
                                      tint: Color.exploreWater, size: 48)
                        }
                    }
                }
            }
            if !rampHits.isEmpty {
                GroupLabel("Access and ramps")
                ForEach(rampHits) { ramp in
                    resultButton {
                        closeSearch()
                        fly(to: ramp.coordinate)
                        selectedRamp = ramp
                    } label: {
                        ArtRow(title: ramp.name, subtitle: ramp.kind.label) {
                            ThumbView(systemImage: ramp.kind.icon, tint: ExploreFormat.placeTint(ramp.kind), size: 48)
                        }
                    }
                }
            }
            if !speciesHits.isEmpty {
                GroupLabel("Species")
                ForEach(speciesHits) { sp in
                    resultButton {
                        openRoute(.species(sp), fromSearch: true)
                    } label: {
                        ArtRow(title: sp.commonName, subtitle: sp.scientificName, chevron: true) {
                            ThumbView(species: sp, size: 48)
                        }
                    }
                }
            }
            if !places.isEmpty {
                GroupLabel("Places")
                ForEach(Array(places.enumerated()), id: \.offset) { _, completion in
                    resultButton {
                        select(completion)
                    } label: {
                        ArtRow(title: completion.title, subtitle: completion.subtitle) {
                            ThumbView(systemImage: "mappin.and.ellipse", tint: .gray, size: 48)
                        }
                    }
                }
            }
        }
    }

    private func waterSubtitle(_ wb: Waterbody) -> String {
        let type = ExploreFormat.waterType(wb.type)
        guard let area = wb.surfaceAreaKm2, area > 0 else { return type }
        return "\(type), \(ExploreFormat.area(area))"
    }

    private func browseRow(_ title: String, _ icon: String, _ route: ExploreRoute) -> some View {
        resultButton {
            openRoute(route, fromSearch: true)
        } label: {
            ArtRow(title: title, chevron: true) {
                ThumbView(systemImage: icon, tint: DS.accent, size: 48)
            }
        }
    }

    private func resultButton<L: View>(action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action, label: label)
            .buttonStyle(.dsRow)
    }

    private func submitSearch() {
        if let spot = spotResults.first {
            openRoute(.spot(SpotRef(spot)), fromSearch: true)
        } else if let wb = waterResults.first {
            openRoute(.waterbody(WaterbodyRef(wb)), fromSearch: true)
        } else if let first = searchModel.completions.first {
            select(first)
        }
    }

    /// Resolve a tapped place suggestion to coordinates and fly the map there.
    private func select(_ completion: MKLocalSearchCompletion) {
        searchFocused = false
        isSearching = true
        Task {
            let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
            let response = try? await search.start()
            isSearching = false
            if let coord = response?.mapItems.first?.placemark.location?.coordinate {
                closeSearch()
                fly(to: coord)
            } else {
                ToastCenter.shared.show("Could not find that place", style: .error)
            }
        }
    }

    private func fly(to coord: CLLocationCoordinate2D) {
        if mapStyle == .offline {
            flyToCoordinate = coord
        } else {
            withAnimation(reduceMotion ? nil : DS.Motion.softSpring) {
                position = .camera(.init(centerCoordinate: coord, distance: 2000))
            }
        }
    }

    // MARK: - Routing

    /// Push a page on the Explore stack. From a sheet, close it first and push
    /// once it has gone.
    private func openRoute(_ route: ExploreRoute, fromSearch: Bool = false) {
        if fromSearch {
            closeSearch()
            pendingRoute = route
            return
        }
        peek = nil
        inspector = nil
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            pendingRoute = route
        }
    }

    // MARK: - Data

    /// Shared camera-change handler for both map backends: tracks span,
    /// prefetches tiles around the viewed area, and debounces waterbody loads.
    private func handleRegionChange(_ region: MKCoordinateRegion) {
        currentLatSpan = region.span.latitudeDelta
        lastMapCenter = region.center
        lastRegion = region
        // Background-cache tiles around the viewed area for offline use.
        appState.mapManager.prefetchOfflineTiles(around: region.center)
        if layerRamps {
            let center = region.center, span = region.span.latitudeDelta
            Task { await rampService.load(around: center, latSpan: span) }
        }
        waterbodyDebounceTask?.cancel()
        waterbodyDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await loadWaterbodies(region: region)
        }
    }

    private func loadData() async {
        spots = (try? appState.spotRepository.fetchAll()) ?? []
        catches = (try? appState.catchRepository.fetchAll(limit: 200)) ?? []

        // The most caught species at each spot draws its pin.
        var tops: [String: Species] = [:]
        for spot in spots {
            let spotCatches = (try? appState.catchRepository.fetchForSpot(spot.id)) ?? []
            let grouped = Dictionary(grouping: spotCatches.compactMap(\.species), by: \.id)
            if let top = grouped.values.max(by: { $0.count < $1.count })?.first {
                tops[spot.id] = top
            }
        }
        topSpecies = tops

        // Water comes from the local database, filled from the bundled
        // extract on first run, so pins show before any network call and
        // without one. Weather waits until the pins are up.
        if !ScreenshotSupport.isActive {
            await BundledMapData.importWaterIfNeeded(into: appState.db)
        }
        let coord = userCoordinate ?? CLLocationCoordinate2D(latitude: -33.9, longitude: 18.4)
        let region = lastRegion ?? MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: currentLatSpan, longitudeDelta: currentLatSpan)
        )
        await loadWaterbodies(region: region)

        // Bite and weather where the angler is (also feeds the wind overlay).
        let (bite, w) = await BiteSnapshot.load(at: coord)
        nearBite = bite
        weather = w

        // Compute bite scores for each spot
        for spot in spots {
            let spotCoord = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
            let w = await WeatherService.shared.current(for: spotCoord)
            let result = ForecastEngine.forecast(
                coordinate: spotCoord,
                currentPressureHpa: w?.pressureHpa,
                pressureChange6h: w?.pressureChange6h,
                waterTempC: w?.waterTempC,
                windSpeedKmh: w?.windSpeedKmh,
                windDirection: w?.windDirectionDeg,
                species: nil,
                isInSpawningZone: false
            )
            spotScores[spot.id] = result.score
        }

        // Compute a shared bite score for nearby waterbodies
        let regionForScore = MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        )
        await computeRegionScore(region: regionForScore)
    }

    private func loadWaterbodies(region: MKCoordinateRegion) async {
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2
        let latSpan = region.span.latitudeDelta

        // Zoom-adaptive filtering: fewer at zoom-out, show nil-area from metro level
        let (minArea, limit, showNilArea): (Double, Int, Bool) = switch latSpan {
        case 20...:         (2000, 8, false)   // Continental: only Great Lakes-scale
        case 10..<20:       (500, 12, false)   // Very zoomed out: major bodies only
        case 5..<10:        (100, 20, false)   // Country level
        case 3..<5:         (20, 25, false)    // Regional
        case 1..<3:         (5, 35, true)      // State/province, start showing unknown-size
        case 0.5..<1:       (0.5, 50, true)    // Metro area
        case 0.2..<0.5:     (0.05, 60, true)   // City level
        default:            (0, 80, true)      // Street level, show everything
        }

        // 1) Show cached DB results instantly (no network wait)
        waterbodies = (try? appState.waterbodyRepository.fetchForRegion(
            minLat: minLat, maxLat: maxLat,
            minLon: minLon, maxLon: maxLon,
            minSurfaceAreaKm2: minArea,
            includeNilArea: showNilArea,
            limit: limit
        )) ?? []

        // 2) Compute bite score in background, don't block waterbody display
        Task { await computeRegionScore(region: region) }

        // 3) Only hit Overpass when zoomed in enough (< 2.5° span) to avoid API
        // spam, and never in screenshot mode, so captures show only the clean
        // seeded set deterministically (no async network results mid-capture).
        // The bundled extract already holds everything Overpass would return
        // inside its tiles, so only ask Overpass outside them.
        guard latSpan < 2.5, !ScreenshotSupport.isActive,
              !BundledMapData.covers(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon) else {
            isLoadingWaterbodies = false
            return
        }

        isLoadingWaterbodies = true
        Task {
            if let overpassResults = await OverpassService.shared.fetchWaterbodies(
                minLat: minLat, maxLat: maxLat,
                minLon: minLon, maxLon: maxLon
            ) {
                let _ = try? appState.waterbodyRepository.insertFromOverpass(overpassResults)
                // Refresh from DB with new entries
                waterbodies = (try? appState.waterbodyRepository.fetchForRegion(
                    minLat: minLat, maxLat: maxLat,
                    minLon: minLon, maxLon: maxLon,
                    minSurfaceAreaKm2: minArea,
                    includeNilArea: showNilArea,
                    limit: limit
                )) ?? []
            }
            isLoadingWaterbodies = false
        }
    }

    /// Compute a single bite score for the region center and apply it to all waterbodies.
    /// This avoids making a weather API call per waterbody.
    private func computeRegionScore(region: MKCoordinateRegion) async {
        let center = region.center
        // Skip if we already have a score for this approximate area
        let regionKey = Int64(center.latitude * 100) * 100000 + Int64(center.longitude * 100)
        if let score = waterbodyScores[regionKey] {
            // Apply existing region score to new waterbodies
            for wb in waterbodies where waterbodyScores[wb.id ?? 0] == nil {
                waterbodyScores[wb.id ?? 0] = score
            }
            return
        }

        let w = await WeatherService.shared.current(for: center)
        let result = ForecastEngine.forecast(
            coordinate: center,
            currentPressureHpa: w?.pressureHpa,
            pressureChange6h: w?.pressureChange6h,
            waterTempC: w?.waterTempC,
            windSpeedKmh: w?.windSpeedKmh,
            windDirection: w?.windDirectionDeg,
            species: nil,
            isInSpawningZone: false
        )
        waterbodyScores[regionKey] = result.score
        // Apply this score to all waterbodies in view
        for wb in waterbodies {
            waterbodyScores[wb.id ?? 0] = result.score
        }
    }
}

// MARK: - Search Completer

/// Live type-ahead suggestions for the map search bar, biased to a region
/// around the user so nearby water and places rank first.
@Observable
final class MapSearchCompleter: NSObject, MKLocalSearchCompleterDelegate {
    var completions: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address, .query]
    }

    func update(query: String, near coordinate: CLLocationCoordinate2D?) {
        if let coordinate {
            completer.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 120_000,
                longitudinalMeters: 120_000
            )
        }
        guard !query.isEmpty else {
            clear()
            return
        }
        completer.queryFragment = query
    }

    func clear() {
        completions = []
        completer.cancel()
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        completions = []
    }
}
