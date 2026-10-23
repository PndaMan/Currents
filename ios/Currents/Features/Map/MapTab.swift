import SwiftUI
import MapKit

/// Wrapper so CLLocationCoordinate2D can drive a .sheet(item:) binding.
struct IdentifiableCoordinate: Identifiable {
    let coord: CLLocationCoordinate2D
    var id: String { "\(coord.latitude),\(coord.longitude)" }
}

/// A spot or a water shown over the map as a sheet.
enum ExplorePlace: Identifiable {
    case spot(Spot)
    case water(Waterbody)

    var id: String {
        switch self {
        case .spot(let s): "spot:\(s.id)"
        case .water(let w): "water:\(w.id ?? 0):\(w.name)"
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .spot(let s): CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude)
        case .water(let w): CLLocationCoordinate2D(latitude: w.latitude, longitude: w.longitude)
        }
    }
}

/// Explore: the full-bleed map. Search and shortcuts sit at the top, map
/// controls down the right, the bite near you at the bottom. A spot or a
/// water opens its page as a sheet over the map, at half height first and
/// swiped up for full screen. Catches open a peek; lists and the species
/// guide push onto this tab's stack.
struct MapTab: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
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
    /// The style the map was on before a layer that only the offline map can
    /// draw switched it over; it goes back when the last such layer is off.
    @AppStorage("mapStyleBeforeLayers") private var styleBeforeLayers = ""
    // On by default: anglers want to see their catches on the map.
    @AppStorage("showCatchPins") private var showCatchPins = true
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
    @State private var catchStack: CatchStackSelection?
    /// The catch picked from a stack list, opened once the list has gone.
    @State private var pendingCatch: CatchDetail?
    @State private var selectedRamp: BoatRamp?
    @State private var showingLayers = false
    // Offline download of the area in view, opened from the layers sheet
    // once that sheet has gone.
    @State private var downloadRegion: MKCoordinateRegion?
    @State private var showingDownload = false
    @State private var pendingDownload = false
    @State private var addSpotAt: AddSpotTarget?
    @State private var isDropping = false
    @State private var pendingRoute: ExploreRoute?

    // The place sheet. `shownPlace` is kept after closing so the sheet does
    // not go blank while it slides away; a new tap swaps it in place.
    @State private var shownPlace: ExplorePlace?
    @State private var isPlaceOpen = false
    @State private var placeDetent: PresentationDetent = .medium
    /// Counts links opened into the place sheet, so a link to the place
    /// already showing starts its page again instead of leaving a page
    /// pushed inside the sheet on top.
    @State private var placeVisit = 0

    @State private var isSearchOpen = false
    /// A fish tapped under "Biting near you": only the places where it is
    /// confirmed stay on the map until the filter is cleared.
    @State private var speciesFilter: SpeciesMapFilter?
    /// Where the record lookup for the filtered fish stands.
    @State private var waterLookup: WaterLookup = .idle

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
        /// A name from the list that opened it, such as a session stop.
        var title: String? = nil
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
            if let speciesFilter, !speciesFilter.catchIds.contains(detail.catchRecord.id) { return false }
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

    /// Spots on the map: those a species filter keeps, else every spot
    /// while the layer is on.
    private var shownSpots: [Spot] {
        if let speciesFilter { return spots.filter { speciesFilter.spotIds.contains($0.id) } }
        return showSpots ? spots : []
    }

    /// Water in view, outlines included. A species filter shows the waters
    /// that hold it wherever they are.
    private var waterInView: [Waterbody] {
        if let speciesFilter { return speciesFilter.waters }
        return showWaterbodies && currentLatSpan < 3 ? waterbodies : []
    }

    /// Water that gets its own pin. A saved water is a spot, so while spots
    /// are on the map its spot pin stands for it and the water pin is left
    /// out; it comes back when the spot is removed.
    private var visibleWaterbodies: [Waterbody] {
        guard showSpots, speciesFilter == nil else { return waterInView }
        let saved = Set(spots.compactMap(\.waterbodyId))
        guard !saved.isEmpty else { return waterInView }
        return waterInView.filter { wb in
            guard let id = wb.id else { return true }
            return !saved.contains(id)
        }
    }

    private var visibleRamps: [BoatRamp] {
        guard layerRamps && currentLatSpan < 2.5 && speciesFilter == nil else {
            // A ramp opened from a list or search keeps its pin while its
            // sheet is up, even with the layer off.
            return selectedRamp.map { [$0] } ?? []
        }
        return rampService.ramps
    }

    private var clusters: [PinCluster] {
        var features: [ExploreFeature] = []
        features += shownSpots.map(ExploreFeature.spot)
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
                ExploreSearchPane(
                    spots: spots,
                    topSpecies: topSpecies,
                    origin: userCoordinate ?? lastMapCenter,
                    onClose: closeSearch,
                    onPick: handlePick
                )
                .transition(.opacity)
            }
        }
        // Keeps the clock legible over bright tiles and the top controls clear of it.
        .statusBarScrim()
        .mapScope(mapScope)
        .animation(reduceMotion ? nil : DS.Motion.easeOut, value: isSearchOpen)
        .animation(reduceMotion ? nil : DS.Motion.easeOut, value: isDropping)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: ExploreRoute.self) { ExploreDestination(route: $0) }
        .navigationDestination(item: $pendingRoute) { ExploreDestination(route: $0) }
        .sheet(isPresented: $isPlaceOpen, onDismiss: { Task { await loadData() } }) {
            placeSheet
        }
        .sheet(item: $peek, onDismiss: { Task { await loadData() } }) { p in
            PinPeekSheet(peek: p) { route in openRoute(route) }
        }
        .sheet(item: $catchStack, onDismiss: {
            // The list closes itself; the catch opens once it has gone.
            if let c = pendingCatch {
                pendingCatch = nil
                peek = PinPeek(target: .catchItem(c))
            }
        }) { stack in
            CatchStackSheet(catches: stack.catches) { pendingCatch = $0 }
        }
        .sheet(item: $selectedRamp) { ramp in
            RampDetailSheet(ramp: ramp)
        }
        .sheet(item: $inspector, onDismiss: { Task { await loadData() } }) { target in
            LocationInspectorSheet(coordinate: target.coord, isUserLocation: target.isUserLocation,
                                   title: target.title,
                                   onOpen: { route in openRoute(route) },
                                   onShowSpecies: { species in showSpecies(species, near: target.coord) })
        }
        .sheet(item: $addSpotAt, onDismiss: { Task { await loadData() } }) { target in
            AddSpotSheet(prefillCoordinate: target.coord)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingLayers, onDismiss: {
            if pendingDownload {
                pendingDownload = false
                showingDownload = true
            }
        }) {
            MapLayersSheet(
                style: Binding(get: { mapStyle }, set: { mapStyle = $0; styleBeforeLayers = "" }),
                showSpots: $showSpots,
                showCatches: $showCatchPins,
                showWater: $showWaterbodies,
                showRamps: $layerRamps,
                nautical: $layerNautical,
                radar: $layerRadar,
                wind: $layerWind,
                current: $layerCurrent,
                onDownloadArea: {
                    downloadRegion = lastRegion
                    pendingDownload = true
                }
            )
        }
        .sheet(isPresented: $showingDownload, onDismiss: { appState.mapManager.refreshDownloadedRegions() }) {
            OfflineDownloadSheet(region: downloadRegion)
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
        .onChange(of: layerNautical) { _, on in layerToggled(on) }
        .onChange(of: layerRadar) { _, on in layerToggled(on) }
        .onChange(of: layerWind) { _, on in layerToggled(on) }
        .onChange(of: layerCurrent) { _, on in layerToggled(on) }
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
            if open { openLiveSession() }
        }
        .task {
            // Cold-launch case: the flag may already be set before onChange
            // starts observing.
            if appState.openLiveSession { openLiveSession() }
        }
        .task {
            appState.mapManager.refreshDownloadedRegions()
            await loadData()
            if let loc = appState.locationManager.currentLocation {
                appState.mapManager.maintainOfflineCache(around: loc.coordinate)
                downloadFishArea(around: loc.coordinate)
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
        // Another tab asked to show a spot or a water here.
        .onChange(of: ExploreFocus.shared.target) { _, target in
            if target != nil { openFocus() }
        }
        .task { openFocus() }
        // Cache follows the PERSON: whenever their position updates, the
        // manager re-anchors the offline cache if they've moved far
        // (pruning tiles around the old area, prefetching the new one).
        .onChange(of: appState.locationManager.currentLocation) { _, loc in
            if let loc {
                appState.mapManager.maintainOfflineCache(around: loc.coordinate)
                downloadFishArea(around: loc.coordinate)
            }
        }
    }

    /// Which fish are on record at the waters around the user, fetched once
    /// a month per area so filtering by a fish works offline there. An open
    /// filter picks up what arrives.
    private func downloadFishArea(around origin: CLLocationCoordinate2D) {
        guard !ScreenshotSupport.isActive else { return }
        Task {
            let added = await WaterSpeciesService.shared.downloadArea(
                around: origin, waters: appState.waterbodyRepository, database: appState.db)
            guard let added, added > 0, let current = speciesFilter else { return }
            speciesFilter = SpeciesMapFilter.load(current.species, near: current.origin, appState: appState)
        }
    }

    /// Nautical, radar, wind and current draw only on the offline map, so
    /// turning one on switches to it, and turning the last one off returns
    /// to the style from before. Picking a style by hand forgets that.
    private func layerToggled(_ on: Bool) {
        if on {
            if mapStyle != .offline {
                styleBeforeLayers = mapStyle.rawValue
                mapStyle = .offline
            }
            return
        }
        guard !(layerNautical || layerRadar || layerWind || layerCurrent),
              mapStyle == .offline,
              let previous = MapStyleOption(rawValue: styleBeforeLayers) else { return }
        styleBeforeLayers = ""
        mapStyle = previous
    }

    // MARK: - Map

    @ViewBuilder
    private var mapLayer: some View {
        if mapStyle == .offline {
            // Cached satellite tiles as the main map, which works offline
            // for everywhere the auto-cache has covered.
            OfflineMapView(
                overlay: appState.mapManager.offlineOverlay,
                pins: clusters,
                pinFace: { cluster in
                    AnyView(pinFace(cluster).environment(appState).tint(accent).environment(\.colorScheme, colorScheme))
                },
                onSelectPin: { tapPin($0) },
                waterOutlines: currentLatSpan < 1.0 ? waterInView : [],
                userMarker: AnyView(UserLocationMarker(heading: appState.locationManager.heading, accent: accent)),
                region: position.region,
                showNautical: layerNautical,
                radarOverlay: layerRadar ? radarOverlay : nil,
                showWind: layerWind,
                showCurrent: layerCurrent,
                windSpeedKmh: weather?.windSpeedKmh,
                windFromDeg: weather?.windDirectionDeg ?? 0,
                flyTo: $flyToCoordinate,
                onTap: { coord in mapTapped(at: coord) },
                onRegionChange: { handleRegionChange($0) },
                onLongPress: { coord in Haptics.press(); dropSpot(at: coord) },
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
                        ForEach(waterInView) { wb in
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
                    if let coord = proxy.convert(screenPoint, from: .local) {
                        mapTapped(at: coord)
                    }
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                        .onEnded { value in
                            guard case .second(true, let drag?) = value,
                                  let coord = proxy.convert(drag.location, from: .local) else { return }
                            Haptics.press()
                            dropSpot(at: coord)
                        }
                )
            }
        }
    }

    private func pinView(_ cluster: PinCluster) -> some View {
        pinFace(cluster)
            .onTapGesture { tapPin(cluster) }
    }

    /// A pin's look, shared by every map style. The offline map hosts it in
    /// its own annotation views and routes taps to `tapPin`.
    @ViewBuilder
    private func pinFace(_ cluster: PinCluster) -> some View {
        if cluster.members.count == 1 {
            let feature = cluster.lead
            ExplorePin(
                feature: feature,
                score: score(for: feature),
                topSpecies: spotSpecies(feature),
                showsLabel: showsLabel(feature)
            )
        } else {
            ClusterPin(cluster: cluster, topSpecies: { topSpecies[$0.id] })
        }
    }

    private func tapPin(_ cluster: PinCluster) {
        guard cluster.members.count > 1 else {
            select(cluster.lead)
            return
        }
        // Catches logged on the same few metres never split: list them
        // instead of zooming.
        if let list = PinClustering.inseparableCatches(cluster) {
            openStack(list)
            return
        }
        Haptics.tap()
        let region = PinClustering.region(for: cluster, currentSpan: currentLatSpan)
        withAnimation(reduceMotion ? nil : DS.Motion.softSpring) {
            position = .region(region)
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
        case .spot(let s):
            showPlace(.spot(s))
            revealAboveSheet(feature.coordinate)
        case .water(let w):
            showPlace(.water(w))
            revealAboveSheet(feature.coordinate)
        case .catchPin(let c):
            afterClosingPlace { peek = PinPeek(target: .catchItem(c)) }
        case .ramp(let r):
            afterClosingPlace { selectedRamp = r }
        }
    }

    private func openStack(_ catches: [CatchDetail]) {
        Haptics.tap()
        afterClosingPlace { catchStack = CatchStackSelection(catches: catches) }
    }

    /// A tap on open map closes the place sheet first, like Apple Maps;
    /// otherwise it inspects that point.
    private func mapTapped(at coord: CLLocationCoordinate2D) {
        guard !isDropping else { return }
        if isPlaceOpen {
            isPlaceOpen = false
            return
        }
        inspector = InspectTarget(coord: coord)
    }

    // MARK: - Place sheet

    @ViewBuilder
    private var placeSheet: some View {
        if let place = shownPlace {
            NavigationStack {
                switch place {
                case .spot(let s):
                    ExplorePlacePage(spot: s, style: .sheet, onSavedChange: reloadSpots)
                case .water(let w):
                    ExplorePlacePage(waterbody: w, style: .sheet, onSavedChange: reloadSpots)
                }
            }
            .id("\(place.id)#\(placeVisit)")
            // Only a drag ticks; showPlace resetting the detent stays quiet.
            .presentationDetents([.medium, .large], selection: $placeDetent.haptic())
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationContentInteraction(.resizes)
        }
    }

    /// Opens a place at half height, or swaps it in if the sheet is up.
    private func showPlace(_ place: ExplorePlace) {
        shownPlace = place
        placeDetent = .medium
        isPlaceOpen = true
    }

    /// Runs `action` once the place sheet has gone, so a second sheet never
    /// tries to present over it.
    private func afterClosingPlace(_ action: @escaping () -> Void) {
        guard isPlaceOpen else {
            action()
            return
        }
        isPlaceOpen = false
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            action()
        }
    }

    /// Pans the map so a tapped place sits in the open part above the
    /// half-height sheet, at the same zoom. The offline map can only fly to a
    /// fixed zoom, so there the map stays put.
    private func revealAboveSheet(_ coord: CLLocationCoordinate2D) {
        guard mapStyle != .offline, let region = lastRegion else { return }
        let span = region.span.latitudeDelta
        // Already in the top half: nothing hides it.
        guard coord.latitude < region.center.latitude + span * 0.05 else { return }
        let center = CLLocationCoordinate2D(latitude: coord.latitude - span * 0.25, longitude: coord.longitude)
        withAnimation(reduceMotion ? nil : DS.Motion.softSpring) {
            position = .region(MKCoordinateRegion(center: center, span: region.span))
        }
    }

    /// Flies to a place picked in search or a list, framed above the sheet.
    private func frameAboveSheet(_ place: ExplorePlace) {
        var span = 0.02
        if case .water(let w) = place {
            span = min(max(w.approximateRadiusM * 3 / 111_000, 0.02), 1.0)
        }
        frameAboveSheet(at: place.coordinate, span: span)
    }

    /// `span` is in degrees of latitude; the default is about 2 km, a spot
    /// and its shore.
    private func frameAboveSheet(at coord: CLLocationCoordinate2D, span: Double = 0.02) {
        if mapStyle == .offline {
            // The offline map flies to a 2 km square around the point.
            flyToCoordinate = CLLocationCoordinate2D(latitude: coord.latitude - 0.25 * 2000 / 111_000,
                                                     longitude: coord.longitude)
            return
        }
        let center = CLLocationCoordinate2D(latitude: coord.latitude - span * 0.25, longitude: coord.longitude)
        withAnimation(reduceMotion ? nil : DS.Motion.softSpring) {
            position = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span * 0.4)
            ))
        }
    }

    /// Opens the place a `currents://map/...` link named, centred above its
    /// half-height sheet: a spot or water as the place sheet, a ramp as its
    /// own sheet, any other point as the dropped-pin sheet.
    private func openFocus() {
        guard let target = ExploreFocus.shared.target else { return }
        ExploreFocus.shared.target = nil
        // A page pushed from a sheet sits outside the stack's path, which
        // the link has already emptied, so it is popped here.
        pendingRoute = nil
        isSearchOpen = false
        peek = nil
        inspector = nil
        selectedRamp = nil
        catchStack = nil
        showingLayers = false
        // A filter that would hide the linked place goes.
        if let speciesFilter, !speciesFilter.keeps(target) { self.speciesFilter = nil }
        // A link from a page inside the live session sheet; the session
        // keeps recording, as when it is minimised.
        showingLiveTrip = false
        // The place sheet swaps to another spot or water where it is; a ramp
        // or point needs it gone.
        switch target {
        case .spot, .water: break
        case .ramp, .point: isPlaceOpen = false
        }
        // The link usually comes from a list on another tab or a page pushed
        // over the map, so the sheet waits for the switch or pop back and for
        // any sheet closing above: a sheet cannot present before then.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            await showFocus(target)
        }
    }

    private func showFocus(_ target: ExploreFocus.Target) async {
        switch target {
        case .spot(let id):
            let saved = (try? appState.spotRepository.fetchAll()) ?? []
            guard let spot = saved.first(where: { $0.id == id }) else { return }
            frameAboveSheet(.spot(spot))
            placeVisit += 1
            showPlace(.spot(spot))
        case .water(let id):
            guard let place = focusedWater(id) else { return }
            frameAboveSheet(place)
            placeVisit += 1
            showPlace(place)
        case .ramp(let id, let lat, let lon):
            var near: CLLocationCoordinate2D?
            if let lat, let lon { near = CLLocationCoordinate2D(latitude: lat, longitude: lon) }
            if let ramp = await focusedRamp(id, near: near) {
                frameAboveSheet(at: ramp.coordinate)
                selectedRamp = ramp
            } else if let near {
                frameAboveSheet(at: near)
                inspector = InspectTarget(coord: near)
            }
        case .point(let lat, let lon, let title):
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            frameAboveSheet(at: coord)
            inspector = InspectTarget(coord: coord, title: title)
        }
    }

    /// A saved water opens as its spot.
    private func focusedWater(_ id: Int64) -> ExplorePlace? {
        let saved = (try? appState.spotRepository.fetchAll()) ?? []
        if let spot = saved.first(where: { $0.waterbodyId == id }) { return .spot(spot) }
        guard let wb = try? appState.waterbodyRepository.fetch(id: id) else { return nil }
        return .water(wb)
    }

    /// A ramp from those already loaded, or loaded around where the link
    /// says it is.
    private func focusedRamp(_ id: String, near: CLLocationCoordinate2D?) async -> BoatRamp? {
        if let hit = rampService.ramps.first(where: { $0.id == id }) { return hit }
        guard let near else { return nil }
        await rampService.load(around: near, latSpan: 0.1)
        return rampService.ramps.first { $0.id == id }
    }

    /// Shows the live session sheet a `currents://session` link asked for.
    /// Anything else over the map closes first, and the sheet waits for the
    /// tab switch and any closing sheet (the link can come from a sheet on
    /// another tab), since a sheet cannot present while another is up.
    private func openLiveSession() {
        appState.openLiveSession = false
        guard appState.tripTracker.isTracking, !showingLiveTrip else { return }
        isPlaceOpen = false
        peek = nil
        inspector = nil
        selectedRamp = nil
        catchStack = nil
        showingLayers = false
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            if appState.tripTracker.isTracking { showingLiveTrip = true }
        }
    }

    /// Saving or removing on the place sheet swaps the water and spot pins
    /// straight away, while the sheet is still up.
    private func reloadSpots() {
        spots = (try? appState.spotRepository.fetchAll()) ?? []
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
                    .simultaneousGesture(TapGesture().onEnded { isPlaceOpen = false })
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

            if let speciesFilter {
                filterChip(speciesFilter)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, 2)
            } else {
                shortcutChips
            }

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

    private var shortcutChips: some View {
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
    }

    /// The species the map is narrowed to and how many places it is
    /// confirmed at, or that it is confirmed nowhere yet. The cross clears it.
    private func filterChip(_ filter: SpeciesMapFilter) -> some View {
        HStack(spacing: DS.Space.s2) {
            if filter.placeCount == 0, waterLookup == .searching {
                ProgressView()
                    .frame(width: 28, height: 28)
            } else {
                ThumbView(species: filter.species, size: 28)
            }
            Text(filterTitle(filter))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.dsText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Button { speciesFilter = nil } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.dsText2)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.dim)
            .accessibilityLabel("Clear \(filter.species.commonName) filter")
        }
        .padding(.leading, 4)
        .padding(.trailing, 2)
        .frame(minHeight: 36)
        .glassEffect(.regular, in: Capsule())
    }

    private func filterTitle(_ filter: SpeciesMapFilter) -> String {
        let name = filter.species.commonName
        let n = filter.placeCount
        if n == 0 {
            switch waterLookup {
            case .searching: return "Finding waters with \(name)"
            case .offline: return "\(name) records load when you have signal"
            case .idle: return "No \(name) on record nearby"
            }
        }
        return "\(name) in \(n) \(n == 1 ? "place" : "places")"
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
        // The page pushes under the place sheet, so the sheet goes.
        .simultaneousGesture(TapGesture().onEnded { isPlaceOpen = false })
    }

    /// Which offline region the map covers, or when scores were last worked
    /// out if the weather is old. Opens Offline maps.
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
            text = "\(regions.count) maps offline"
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
        .simultaneousGesture(TapGesture().onEnded { isPlaceOpen = false })
    }

    private var sideButtons: some View {
        VStack(spacing: 10) {
            Button { afterClosingPlace { showingLayers = true } } label: {
                glassCircle("square.3.layers.3d", dot: overlaysOn || mapStyle != .standard ? DS.accent : nil)
            }
            .buttonStyle(.dim)
            .accessibilityLabel("Map layers")

            Button { locateMe() } label: {
                glassCircle("location")
            }
            .buttonStyle(.dim)
            .accessibilityLabel("Show my location")

            Button {
                isPlaceOpen = false
                isDropping = true
            } label: {
                glassCircle("mappin.and.ellipse")
            }
            .buttonStyle(.dim)
            .buttonHaptic(.press)
            .accessibilityLabel("Add spot")

            // Start or resume a fishing session.
            if FeatureFlags.liveTrips {
                Button {
                    afterClosingPlace {
                        if appState.tripTracker.isTracking {
                            showingLiveTrip = true
                        } else {
                            showingNewTrip = true
                        }
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
            afterClosingPlace {
                if let coord = userCoordinate {
                    inspector = InspectTarget(coord: coord, isUserLocation: true)
                } else if let coord = lastMapCenter {
                    inspector = InspectTarget(coord: coord)
                }
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

    // MARK: - Species filter

    /// Narrows the map to where a fish tapped in the inspector is confirmed
    /// and frames those places.
    private func showSpecies(_ species: Species, near origin: CLLocationCoordinate2D) {
        inspector = nil
        let filter = SpeciesMapFilter.load(species, near: origin, appState: appState)
        speciesFilter = filter
        frameFilter(filter)
        lookUpWaters(for: species, near: origin)
    }

    enum WaterLookup { case idle, searching, offline }

    /// Asks GBIF which waters around here have the fish on record, then
    /// redraws the filter with any new ones and frames them if the map had
    /// nothing to show before.
    private func lookUpWaters(for species: Species, near origin: CLLocationCoordinate2D) {
        guard !ScreenshotSupport.isActive else { return }
        waterLookup = .searching
        Task {
            let found = await WaterSpeciesService.shared.findWaters(
                for: species, near: origin,
                waters: appState.waterbodyRepository, database: appState.db)
            guard speciesFilter?.species.id == species.id else { return }
            waterLookup = found == nil ? .offline : .idle
            guard let found, found > 0 else { return }
            let wasEmpty = speciesFilter?.placeCount == 0
            let filter = SpeciesMapFilter.load(species, near: origin, appState: appState)
            speciesFilter = filter
            if wasEmpty { frameFilter(filter) }
        }
    }

    private func filterCoordinates(_ filter: SpeciesMapFilter) -> [CLLocationCoordinate2D] {
        let spotCoords = spots.filter { filter.spotIds.contains($0.id) }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let waterCoords = filter.waters.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        return spotCoords + waterCoords
    }

    /// Fits the filtered places within 400 km of where it was asked for, or
    /// the nearest one when all are further. The offline map can only fly to
    /// a fixed zoom, so there it goes to the nearest.
    private func frameFilter(_ filter: SpeciesMapFilter) {
        let here = CLLocation(latitude: filter.origin.latitude, longitude: filter.origin.longitude)
        func distance(_ c: CLLocationCoordinate2D) -> CLLocationDistance {
            here.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
        }
        let sorted = filterCoordinates(filter).sorted { distance($0) < distance($1) }
        guard let nearest = sorted.first else { return }
        if mapStyle == .offline {
            flyToCoordinate = nearest
            return
        }
        let near = sorted.filter { distance($0) < 400_000 }
        let framed = near.isEmpty ? [nearest] : near
        let lats = framed.map(\.latitude)
        let lons = framed.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.4, 0.05),
                                    longitudeDelta: max((maxLon - minLon) * 1.4, 0.05))
        withAnimation(reduceMotion ? nil : DS.Motion.softSpring) {
            position = .region(MKCoordinateRegion(center: center, span: span))
        }
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
        isPlaceOpen = false
        isSearchOpen = true
    }

    private func closeSearch() {
        isSearchOpen = false
    }

    /// Opens what was picked in search: spots and water as the place sheet
    /// over the map, ramps as their sheet, species as their page, and a town
    /// or address by moving the map there.
    private func handlePick(_ pick: ExploreSearchPick) {
        closeSearch()
        switch pick {
        case .spot(let s):
            frameAboveSheet(.spot(s))
            showPlace(.spot(s))
        case .water(let w):
            // A saved water opens as its spot.
            let place: ExplorePlace = spots.first { $0.waterbodyId != nil && $0.waterbodyId == w.id }
                .map(ExplorePlace.spot) ?? .water(w)
            frameAboveSheet(place)
            showPlace(place)
        case .ramp(let r):
            frameAboveSheet(at: r.coordinate)
            selectedRamp = r
        case .species(let sp):
            pendingRoute = .species(sp)
        case .place(let coord, _):
            fly(to: coord, distance: 12_000)
        }
    }

    private func fly(to coord: CLLocationCoordinate2D, distance: CLLocationDistance = 2000) {
        if mapStyle == .offline {
            flyToCoordinate = coord
        } else {
            withAnimation(reduceMotion ? nil : DS.Motion.softSpring) {
                position = .camera(.init(centerCoordinate: coord, distance: distance))
            }
        }
    }

    // MARK: - Routing

    /// Spots and water open as the place sheet; anything else pushes on the
    /// Explore stack. From a sheet, close it first and go once it has gone.
    private func openRoute(_ route: ExploreRoute) {
        peek = nil
        inspector = nil
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            switch route {
            case .spot(let ref):
                frameAboveSheet(.spot(ref.spot))
                showPlace(.spot(ref.spot))
            case .waterbody(let ref):
                let place: ExplorePlace = spots.first { $0.waterbodyId != nil && $0.waterbodyId == ref.waterbody.id }
                    .map(ExplorePlace.spot) ?? .water(ref.waterbody)
                frameAboveSheet(place)
                showPlace(place)
            default:
                pendingRoute = route
            }
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
        // A spot saved or a catch logged since can change where it is confirmed.
        if let filter = speciesFilter {
            speciesFilter = SpeciesMapFilter.load(filter.species, near: filter.origin, appState: appState)
        }

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
