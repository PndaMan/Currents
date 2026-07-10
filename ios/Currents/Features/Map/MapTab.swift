import SwiftUI
import MapKit

/// Wrapper so CLLocationCoordinate2D can drive a .sheet(item:) binding.
struct IdentifiableCoordinate: Identifiable {
    let coord: CLLocationCoordinate2D
    var id: String { "\(coord.latitude),\(coord.longitude)" }
}

struct MapTab: View {
    @Environment(AppState.self) private var appState
    // Observed so map pins re-render the moment the theme changes,
    // instead of waiting for the next zoom-triggered rebuild.
    @AppStorage("selectedTheme") private var selectedThemeRaw = ThemeOption.ocean.rawValue
    @Namespace private var mapScope
    @State private var position: MapCameraPosition = ScreenshotSupport.isActive
        ? .camera(MapCamera(centerCoordinate: ScreenshotSupport.demoCoordinate, distance: 42000))
        : .userLocation(fallback: .automatic)
    @State private var spots: [Spot] = []
    @State private var catches: [CatchDetail] = []
    @State private var catchCounts: [String: Int] = [:]
    @State private var showingAddSpot = false
    @State private var selectedSpot: Spot?
    @State private var showingLiveTrip = false
    @State private var showingNewTrip = false
    // The offline (cached-tile) map is the default main map; persisted so a
    // style choice sticks across launches.
    @AppStorage("mapStyleOption") private var mapStyleRaw = MapStyleOption.offline.rawValue
    @AppStorage("showCatchPins") private var showCatchPins = false
    @State private var flyToCoordinate: CLLocationCoordinate2D?
    @State private var showingSpeciesBrowser = false
    @State private var showingForecast = false
    @State private var showingWeather = false
    @State private var weather: WeatherService.WeatherData?
    @State private var inspectorCoordinate: CLLocationCoordinate2D?
    @State private var spotScores: [String: Int] = [:]
    @State private var searchText = ""
    @State private var searchModel = MapSearchCompleter()
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool
    @State private var needsRefresh = false
    @State private var showWaterbodies = true
    @State private var waterbodies: [Waterbody] = []
    @State private var waterbodyScores: [Int64: Int] = [:] // keyed by id ?? 0
    @State private var selectedWaterbody: Waterbody?
    @State private var isLoadingWaterbodies = false
    @State private var waterbodyDebounceTask: Task<Void, Never>?
    @State private var currentLatSpan: Double = 1.0
    @State private var lastMapCenter: CLLocationCoordinate2D?
    // Optional overlay layers — off by default, toggled from the layers button.
    @AppStorage("mapLayer_nautical") private var layerNautical = false
    @AppStorage("mapLayer_radar") private var layerRadar = false
    @AppStorage("mapLayer_wind") private var layerWind = false
    @AppStorage("mapLayer_current") private var layerCurrent = false
    @State private var radarOverlay: MKTileOverlay?

    enum MapStyleOption: String, CaseIterable {
        case offline = "Offline"
        case standard = "Standard"
        case imagery = "Satellite"
        case hybrid = "Hybrid"
        case fishing = "Fishing"
    }

    private var mapStyle: MapStyleOption {
        get { MapStyleOption(rawValue: mapStyleRaw) ?? .offline }
        nonmutating set { mapStyleRaw = newValue.rawValue }
    }

    /// Theme accent, re-read whenever the stored theme changes so annotations
    /// re-render immediately.
    private var accent: Color {
        (ThemeOption(rawValue: selectedThemeRaw) ?? .ocean).primary
    }

    /// Catches without an assigned spot — but hide any that sit on top of a
    /// saved spot's marker so they don't render over the spot pin.
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

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                if mapStyle == .offline {
                    // Cached satellite tiles as the main map — works offline
                    // for everywhere the auto-cache has covered.
                    OfflineMapView(
                        overlay: appState.mapManager.offlineOverlay,
                        spots: spots,
                        catches: showCatchPins ? unassignedCatches : [],
                        waterbodies: showWaterbodies && currentLatSpan < 3 ? waterbodies : [],
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
                        onSelectSpot: { selectedSpot = $0 },
                        onSelectWaterbody: { selectedWaterbody = $0 },
                        onTap: { inspectorCoordinate = $0 },
                        onRegionChange: { handleRegionChange($0) }
                    )
                    .ignoresSafeArea()
                } else {
                MapReader { proxy in
                Map(position: $position, scope: mapScope) {
                    UserAnnotation(anchor: .center) { _ in
                        UserLocationMarker(
                            heading: appState.locationManager.heading,
                            accent: accent
                        )
                    }

                    // Spot pins (empty annotation title — the pin renders its own label)
                    ForEach(spots) { spot in
                        Annotation("", coordinate: CLLocationCoordinate2D(
                            latitude: spot.latitude,
                            longitude: spot.longitude
                        )) {
                            SpotPin(
                                spot: spot,
                                catchCount: catchCounts[spot.id] ?? 0,
                                isSelected: selectedSpot?.id == spot.id,
                                biteScore: spotScores[spot.id],
                                accent: accent
                            )
                            .onTapGesture {
                                selectedSpot = spot
                            }
                        }
                    }

                    // Catch location pins (individual catches without spots)
                    if showCatchPins {
                        ForEach(unassignedCatches, id: \.catchRecord.id) { detail in
                            Annotation(
                                "",
                                coordinate: CLLocationCoordinate2D(
                                    latitude: detail.catchRecord.latitude,
                                    longitude: detail.catchRecord.longitude
                                )
                            ) {
                                CatchPin(detail: detail, accent: accent)
                            }
                        }
                    }

                    // Water body overlays
                    if showWaterbodies {
                        ForEach(waterbodies) { wb in
                            // Only render circles when zoomed in enough to see them
                            if currentLatSpan < 1.0 {
                                MapCircle(
                                    center: CLLocationCoordinate2D(latitude: wb.latitude, longitude: wb.longitude),
                                    radius: CLLocationDistance(min(wb.approximateRadiusM, 50000))
                                )
                                .foregroundStyle(accent.opacity(0.2))
                                .stroke(accent.opacity(0.6), lineWidth: 2)
                            }

                            Annotation("", coordinate: CLLocationCoordinate2D(
                                latitude: wb.latitude, longitude: wb.longitude
                            )) {
                                WaterbodyPin(
                                    waterbody: wb,
                                    biteScore: waterbodyScores[wb.id ?? 0],
                                    accent: accent
                                )
                                .onTapGesture {
                                    selectedWaterbody = wb
                                }
                            }
                        }
                    }
                }
                .mapStyle(activeMapStyle)
                // Suppress the built-in controls (the default compass sits
                // top-right when rotated, clipping under our recentre button).
                // The rotation compass is provided separately, pinned top-left.
                .mapControls { }
                .onMapCameraChange(frequency: .onEnd) { context in
                    handleRegionChange(context.region)
                }
                .onTapGesture(coordinateSpace: .local) { screenPoint in
                    if let coord = proxy.convert(screenPoint, from: .local) {
                        inspectorCoordinate = coord
                    }
                }
                } // MapReader
                } // style switch

                // Compass (shows when the map is rotated) — placed top-LEADING
                // with a custom scope so the right-hand button column and the
                // search bar can never sit on top of it. The offline MKMapView
                // draws its own compass.
                if mapStyle != .offline {
                    MapCompass(scope: mapScope)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, 8)
                        .padding(.leading, 12)
                }

                // Right side control buttons — out of the way while searching.
                if !searchActive {
                VStack(spacing: 10) {
                    // Recentre on user
                    Button {
                        if mapStyle == .offline {
                            flyToCoordinate = appState.locationManager.currentLocation?.coordinate
                        } else {
                            position = .userLocation(fallback: .automatic)
                        }
                    } label: {
                        mapButton(icon: "location.fill")
                    }

                    // Map style + overlay layers picker
                    Menu {
                        Picker("Map Style", selection: Binding(
                            get: { mapStyle },
                            set: { mapStyle = $0 }
                        )) {
                            ForEach(MapStyleOption.allCases, id: \.self) { style in
                                Label(style.rawValue, systemImage: mapStyleIcon(style)).tag(style)
                            }
                        }

                        Section("Overlays (offline map)") {
                            Toggle(isOn: $layerNautical) {
                                Label("Nautical / Depth", systemImage: "water.waves")
                            }
                            Toggle(isOn: $layerRadar) {
                                Label("Weather Radar", systemImage: "cloud.rain")
                            }
                            Toggle(isOn: $layerWind) {
                                Label("Wind (animated)", systemImage: "wind")
                            }
                            Toggle(isOn: $layerCurrent) {
                                Label("Current (animated)", systemImage: "arrow.left.arrow.right")
                            }
                        }
                    } label: {
                        mapButton(icon: "map.fill")
                            .overlay(alignment: .topTrailing) {
                                if layerNautical || layerRadar || layerWind || layerCurrent {
                                    Circle().fill(CurrentsTheme.accent)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 2, y: -2)
                                }
                            }
                    }

                    // Add spot
                    Button {
                        showingAddSpot = true
                    } label: {
                        mapButton(icon: "mappin.and.ellipse")
                    }

                    // Toggle water body overlays
                    Button {
                        showWaterbodies.toggle()
                    } label: {
                        mapButton(icon: showWaterbodies ? "water.waves" : "water.waves")
                            .opacity(showWaterbodies ? 1.0 : 0.5)
                    }

                    // Toggle catch pins
                    Button {
                        showCatchPins.toggle()
                    } label: {
                        mapButton(icon: showCatchPins ? "fish.fill" : "fish")
                    }

                    // Species browser
                    Button {
                        showingSpeciesBrowser = true
                    } label: {
                        mapButton(icon: "book.fill")
                    }

                    // (Forecast lives on the main tab bar — no duplicate button
                    // here. This column slot is used by the trip button below.)

                    // Start / resume a fishing session
                    if FeatureFlags.liveTrips {
                        Button {
                            if appState.tripTracker.isTracking {
                                showingLiveTrip = true
                            } else {
                                showingNewTrip = true
                            }
                        } label: {
                            mapButton(icon: appState.tripTracker.isTracking ? "figure.fishing" : "play.fill")
                                .overlay(alignment: .topTrailing) {
                                    if appState.tripTracker.isTracking {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 8, height: 8)
                                            .offset(x: 2, y: -2)
                                    }
                                }
                        }
                    }
                }
                // The rotation compass now sits top-LEFT on every style, so the
                // right-hand button column can start at the normal inset.
                .padding(.top, 8)
                .padding(.trailing, 12)
                }

                // Bottom bar
                if !searchActive {
                VStack {
                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap.fill")
                            .font(.caption2)
                        Text("Tap anywhere to analyse the bite")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 4)

                    HStack(spacing: 12) {
                        // Weather quick view
                        if let weather {
                            HStack(spacing: 6) {
                                WeatherIcon(condition: weather.condition)
                                Text("\(Int(weather.temperatureC))°")
                                    .font(.subheadline.bold())
                                    .monospacedDigit()
                                Text("\(Int(weather.windSpeedKmh))km/h")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if showWaterbodies && !waterbodies.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "water.waves")
                                    .foregroundStyle(CurrentsTheme.accent)
                                    .font(.caption)
                                Text("\(waterbodies.count)")
                                    .font(.caption.bold())
                                if isLoadingWaterbodies {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                            }
                        }

                        if !spots.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(CurrentsTheme.accent)
                                Text("\(spots.count) spots")
                                    .font(.subheadline.bold())
                                let totalCatches = catchCounts.values.reduce(0, +)
                                Text("\(totalCatches) catches")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                }
            }
            .mapScope(mapScope)
            // No navigation bar on the map — its invisible bar was reserving a
            // big empty band above the search field.
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                searchBar
            }
            .overlay(alignment: .top) {
                searchResultsList
            }
            .sheet(item: $selectedSpot, onDismiss: {
                Task { await loadData() }
            }) { spot in
                SpotDetailSheet(spot: spot)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
                    .presentationDragIndicator(.visible)
                    // Dragging anywhere on the sheet resizes it between half
                    // and full screen instead of scrolling the content.
                    .presentationContentInteraction(.resizes)
            }
            .sheet(isPresented: $showingAddSpot, onDismiss: {
                Task { await loadData() }
            }) {
                AddSpotSheet()
                    .presentationDetents([.medium])
                    .presentationBackground(.ultraThinMaterial)
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
            .sheet(isPresented: $showingSpeciesBrowser) {
                NavigationStack {
                    SpeciesBrowserView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showingSpeciesBrowser = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingForecast) {
                ForecastTab(presentedAsSheet: true)
            }
            .sheet(item: Binding(
                get: { inspectorCoordinate.map { IdentifiableCoordinate(coord: $0) } },
                set: { inspectorCoordinate = $0?.coord }
            ), onDismiss: {
                Task { await loadData() }
            }) { wrapper in
                LocationInspectorSheet(coordinate: wrapper.coord)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(item: $selectedWaterbody) { wb in
                WaterbodyDetailSheet(waterbody: wb)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showingNewTrip, onDismiss: {
                if appState.tripTracker.isTracking { showingLiveTrip = true }
            }) {
                NewSessionSheet()
                    .presentationDetents([.medium])
                    .presentationBackground(.ultraThinMaterial)
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
            .task {
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
    }

    /// True while the user is actively searching — the map buttons and bottom
    /// bar get out of the way.
    private var searchActive: Bool {
        searchFocused || (!searchText.isEmpty && !searchModel.completions.isEmpty)
    }

    /// Just the search FIELD, pinned right under the status bar via
    /// `.safeAreaInset(edge: .top)` (the invisible navigation bar is hidden).
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search dams, rivers, places...", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit {
                    if let first = searchModel.completions.first {
                        select(first)
                    }
                    searchFocused = false
                }
                .onChange(of: searchText) { _, newValue in
                    searchModel.update(
                        query: newValue,
                        near: appState.locationManager.currentLocation?.coordinate ?? lastMapCenter
                    )
                }
            if isSearching {
                ProgressView()
                    .controlSize(.small)
            }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchModel.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            if searchFocused {
                // Explicit way to put the keyboard away.
                Button {
                    searchFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .foregroundStyle(accent)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: CurrentsTheme.cornerRadius))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    /// Type-ahead results rendered as a plain overlay directly under the
    /// search bar — NOT inside the safe-area inset and NOT a ScrollView, so
    /// the list is visible immediately while the keyboard is still up.
    @ViewBuilder
    private var searchResultsList: some View {
        if !searchModel.completions.isEmpty && !searchText.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(searchModel.completions.prefix(7).enumerated()), id: \.offset) { index, completion in
                    Button {
                        select(completion)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(accent)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                    if index < min(searchModel.completions.count, 7) - 1 {
                        Divider()
                    }
                }
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: CurrentsTheme.cornerRadius))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .padding(.horizontal, 12)
        }
    }

    /// Resolve a tapped suggestion to coordinates and fly the map there.
    private func select(_ completion: MKLocalSearchCompletion) {
        searchFocused = false
        isSearching = true
        searchText = completion.title
        Task {
            let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
            let response = try? await search.start()
            if let coord = response?.mapItems.first?.placemark.location?.coordinate {
                if mapStyle == .offline {
                    flyToCoordinate = coord
                } else {
                    position = .camera(.init(centerCoordinate: coord, distance: 2000))
                }
            }
            searchModel.clear()
            isSearching = false
        }
    }

    @ViewBuilder
    private func mapButton(icon: String) -> some View {
        Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(accent)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
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

    private func mapStyleIcon(_ style: MapStyleOption) -> String {
        switch style {
        case .offline: "wifi.slash"
        case .standard: "map"
        case .imagery: "globe.americas.fill"
        case .hybrid: "square.split.2x2"
        case .fishing: "fish.fill"
        }
    }

    /// Shared camera-change handler for both map backends: tracks span,
    /// prefetches tiles around the viewed area, and debounces waterbody loads.
    private func handleRegionChange(_ region: MKCoordinateRegion) {
        currentLatSpan = region.span.latitudeDelta
        lastMapCenter = region.center
        // Background-cache tiles around the viewed area for offline use.
        appState.mapManager.prefetchOfflineTiles(around: region.center)
        // Debounce: cancel prior pending load, wait 300ms before firing
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

        for spot in spots {
            let spotCatches = (try? appState.catchRepository.fetchForSpot(spot.id)) ?? []
            catchCounts[spot.id] = spotCatches.count
        }

        // Fetch weather for map overlay
        let coord = appState.locationManager.currentLocation?.coordinate ??
            CLLocationCoordinate2D(latitude: -33.9, longitude: 18.4)
        weather = await WeatherService.shared.current(for: coord)

        // Show cached waterbodies instantly, fetch more from Overpass in background
        let userLat = coord.latitude
        let userLon = coord.longitude
        waterbodies = (try? appState.waterbodyRepository.fetchForRegion(
            minLat: userLat - 0.5, maxLat: userLat + 0.5,
            minLon: userLon - 0.5, maxLon: userLon + 0.5,
            minSurfaceAreaKm2: 0,
            includeNilArea: true,
            limit: 50
        )) ?? []

        // Background Overpass fetch for new data
        Task {
            if let results = await OverpassService.shared.fetchWaterbodies(
                minLat: userLat - 0.5, maxLat: userLat + 0.5,
                minLon: userLon - 0.5, maxLon: userLon + 0.5
            ) {
                let _ = try? appState.waterbodyRepository.insertFromOverpass(results)
                waterbodies = (try? appState.waterbodyRepository.fetchForRegion(
                    minLat: userLat - 0.5, maxLat: userLat + 0.5,
                    minLon: userLon - 0.5, maxLon: userLon + 0.5,
                    minSurfaceAreaKm2: 0,
                    includeNilArea: true,
                    limit: 50
                )) ?? []
            }
        }

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

        // Zoom-adaptive filtering — fewer at zoom-out, show nil-area from metro level
        let (minArea, limit, showNilArea): (Double, Int, Bool) = switch latSpan {
        case 20...:         (2000, 8, false)   // Continental: only Great Lakes-scale
        case 10..<20:       (500, 12, false)   // Very zoomed out: major bodies only
        case 5..<10:        (100, 20, false)   // Country level
        case 3..<5:         (20, 25, false)    // Regional
        case 1..<3:         (5, 35, true)      // State/province — start showing unknown-size
        case 0.5..<1:       (0.5, 50, true)    // Metro area
        case 0.2..<0.5:     (0.05, 60, true)   // City level
        default:            (0, 80, true)      // Street level — show everything
        }

        // 1) Show cached DB results INSTANTLY (no network wait)
        waterbodies = (try? appState.waterbodyRepository.fetchForRegion(
            minLat: minLat, maxLat: maxLat,
            minLon: minLon, maxLon: maxLon,
            minSurfaceAreaKm2: minArea,
            includeNilArea: showNilArea,
            limit: limit
        )) ?? []

        // 2) Compute bite score in background — don't block waterbody display
        Task { await computeRegionScore(region: region) }

        // 3) Only hit Overpass when zoomed in enough (< 2.5° span) to avoid API
        // spam — and never in screenshot mode, so captures show only the clean
        // seeded set deterministically (no async network results mid-capture).
        guard latSpan < 2.5, !ScreenshotSupport.isActive else {
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
        guard waterbodyScores[regionKey] == nil else {
            // Apply existing region score to new waterbodies
            let score = waterbodyScores[regionKey]!
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

// MARK: - Catch Pin (for individual catches on map)

struct CatchPin: View {
    let detail: CatchDetail
    var accent: Color = CurrentsTheme.accent

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(accent)
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                Image(systemName: "fish.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
            if let name = detail.species?.commonName {
                Text(name)
                    .font(.system(size: 9).bold())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - User Location Marker

/// Precise location dot with a Life360-style heading cone showing which way
/// the user is facing (driven by the compass/gyro).
struct UserLocationMarker: View {
    let heading: Double
    var accent: Color = CurrentsTheme.accent

    var body: some View {
        ZStack {
            // Facing-direction cone
            HeadingCone()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.55), accent.opacity(0.0)],
                        startPoint: .center,
                        endPoint: .top
                    )
                )
                .frame(width: 72, height: 72)
                .rotationEffect(.degrees(heading))
                .animation(.easeOut(duration: 0.2), value: heading)

            // Exact position dot
            Circle()
                .fill(accent)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        }
    }
}

/// A ~56° wedge pointing north (up); rotate it by the device heading.
struct HeadingCone: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        p.move(to: center)
        p.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-118),
            endAngle: .degrees(-62),
            clockwise: false
        )
        p.closeSubpath()
        return p
    }
}

// MARK: - Spot Pin

struct SpotPin: View {
    let spot: Spot
    let catchCount: Int
    let isSelected: Bool
    var biteScore: Int?
    var accent: Color = CurrentsTheme.accent

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 40, height: 40)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .overlay(
                            Circle().stroke(.white, lineWidth: isSelected ? 3 : 1.5)
                        )

                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }

                // Bite score badge
                if let score = biteScore {
                    Text("\(score)")
                        .font(.system(size: 9, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(CurrentsTheme.scoreColor(score))
                        .clipShape(Capsule())
                        .offset(x: 8, y: -6)
                }

                // Catch count badge
                if catchCount > 0 {
                    Text("\(catchCount)")
                        .font(.system(size: 9, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.65))
                        .clipShape(Capsule())
                        .offset(x: -26, y: -6)
                }
            }
            Text(spot.name)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Spot Detail Sheet

struct SpotDetailSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var spot: Spot
    @State private var catches: [CatchDetail] = []
    @State private var weather: WeatherService.WeatherData?
    @State private var forecast: ForecastEngine.ForecastResult?
    @State private var showingDeleteConfirm = false
    @State private var showingEdit = false
    @State private var shareImage: UIImage?
    @State private var showingShareSheet = false
    @State private var isGeneratingShare = false

    init(spot: Spot) {
        _spot = State(initialValue: spot)
    }

    private var spotCoord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CurrentsTheme.paddingM) {
                    // Map preview
                    Map(initialPosition: .camera(.init(
                        centerCoordinate: spotCoord,
                        distance: 1500
                    ))) {
                        Annotation(spot.name, coordinate: spotCoord) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(CurrentsTheme.accent)
                        }
                    }
                    .mapStyle(.hybrid)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .allowsHitTesting(false)

                    HStack {
                        VStack(alignment: .leading) {
                            Text(spot.name)
                                .font(.title2.bold())
                            Text(String(format: "%.4f, %.4f", spot.latitude, spot.longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if spot.type != .general {
                            Label(spot.type.rawValue, systemImage: spot.type.icon)
                                .font(.caption)
                                .glassPill()
                        }
                        if FeatureFlags.spotPrivacy, spot.isPrivate {
                            Label("Private", systemImage: "lock.fill")
                                .font(.caption)
                                .glassPill()
                        }
                    }

                    // Weather + Bite Score
                    if let weather {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Conditions Now", systemImage: "cloud.sun.fill")
                                    .font(.headline)
                                Spacer()
                                if let f = forecast {
                                    HStack(spacing: 4) {
                                        ScoreGauge(score: f.score, label: "", size: 36)
                                        Text("bite")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            HStack(spacing: 16) {
                                VStack(spacing: 2) {
                                    WeatherIcon(condition: weather.condition)
                                    Text("\(Int(weather.temperatureC))°")
                                        .font(.subheadline.bold().monospacedDigit())
                                    Text("Air")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if let wt = weather.waterTempC {
                                    VStack(spacing: 2) {
                                        Image(systemName: "drop.fill")
                                            .foregroundStyle(CurrentsTheme.accent)
                                        Text("\(Int(wt))°")
                                            .font(.subheadline.bold().monospacedDigit())
                                        Text("Water")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                VStack(spacing: 2) {
                                    Image(systemName: "wind")
                                        .foregroundStyle(.secondary)
                                    Text("\(Int(weather.windSpeedKmh))")
                                        .font(.subheadline.bold().monospacedDigit())
                                    Text("km/h")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                VStack(spacing: 2) {
                                    Image(systemName: "barometer")
                                        .foregroundStyle(.secondary)
                                    Text("\(Int(weather.pressureHpa))")
                                        .font(.subheadline.bold().monospacedDigit())
                                    Text("hPa")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let f = forecast, !f.reasons.isEmpty {
                                ForEach(f.reasons.prefix(2), id: \.self) { reason in
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(CurrentsTheme.scoreColor(f.score))
                                            .frame(width: 5, height: 5)
                                        Text(reason)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .glassCard()
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading weather...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .glassCard()
                    }

                    if !catches.isEmpty {
                        HStack(spacing: 10) {
                            StatCard(value: "\(catches.count)", label: "Catches", icon: "fish.fill")
                            let species = Set(catches.compactMap { $0.species?.commonName }).count
                            StatCard(value: "\(species)", label: "Species", icon: "leaf.fill")
                            if let best = catches.max(by: { ($0.catchRecord.weightKg ?? 0) < ($1.catchRecord.weightKg ?? 0) }),
                               let weight = best.catchRecord.weightKg {
                                StatCard(value: String(format: "%.1fkg", weight), label: "Best", icon: "trophy.fill")
                            }
                            let released = catches.filter { $0.catchRecord.released }.count
                            let releaseRate = Int(Double(released) / Double(catches.count) * 100)
                            StatCard(value: "\(releaseRate)%", label: "Released", icon: "arrow.uturn.backward")
                        }
                    }

                    if let notes = spot.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    // Share — renders a map card + attaches an Apple Maps pin link.
                    Button {
                        generateShareCard()
                    } label: {
                        if isGeneratingShare {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text("Preparing…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Label("Share Spot", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CurrentsTheme.accent)
                    .disabled(isGeneratingShare)

                    // Actions
                    HStack(spacing: 12) {
                        Button {
                            showingEdit = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if !catches.isEmpty {
                        Text("Catches Here")
                            .font(.headline)
                        ForEach(catches, id: \.catchRecord.id) { detail in
                            NavigationLink {
                                CatchDetailView(detail: detail)
                            } label: {
                                CatchRow(detail: detail)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        ContentUnavailableView(
                            "No catches yet",
                            systemImage: "fish",
                            description: Text("Log your first catch at this spot")
                        )
                    }
                }
                .padding()
            }
        }
        .task {
            catches = (try? appState.catchRepository.fetchForSpot(spot.id)) ?? []
            let w = await WeatherService.shared.current(for: spotCoord)
            weather = w
            forecast = ForecastEngine.forecast(
                coordinate: spotCoord,
                currentPressureHpa: w?.pressureHpa,
                pressureChange6h: w?.pressureChange6h,
                waterTempC: w?.waterTempC,
                windSpeedKmh: w?.windSpeedKmh,
                windDirection: w?.windDirectionDeg,
                species: nil,
                isInSpawningZone: false
            )
        }
        .alert("Delete Spot?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                try? appState.spotRepository.delete(spot)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the spot but keep any catches logged here.")
        }
        .sheet(isPresented: $showingEdit) {
            EditSpotSheet(spot: spot) { updated in
                var record = updated
                try? appState.spotRepository.save(&record)
                // Refresh in place — closing the whole spot sheet after an
                // edit made it feel like the app threw the user out.
                spot = record
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let shareImage {
                ImageShareSheet(
                    image: shareImage,
                    filename: "Currents-\(spot.name)",
                    caption: SpotShareCard.caption(for: spot)
                )
            }
        }
    }

    private func generateShareCard() {
        isGeneratingShare = true
        Task {
            let card = await SpotShareCard.render(
                spot: spot,
                catchCount: catches.count,
                biteScore: forecast?.score
            )
            isGeneratingShare = false
            if let card {
                shareImage = card
                showingShareSheet = true
            }
        }
    }
}

// MARK: - Add Spot Sheet

struct AddSpotSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var notes = ""
    @State private var isPrivate = true
    @State private var spotType: Spot.SpotType = .general
    @State private var usePin: Bool
    @State private var pinCoordinate: CLLocationCoordinate2D?
    @State private var showingLocationPicker = false

    init(prefillCoordinate: CLLocationCoordinate2D? = nil) {
        _usePin = State(initialValue: prefillCoordinate != nil)
        _pinCoordinate = State(initialValue: prefillCoordinate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Spot Name", text: $name)
                    Picker("Type", selection: $spotType) {
                        ForEach(Spot.SpotType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Location") {
                    Toggle("Drop pin on map", isOn: $usePin)

                    if usePin {
                        if let coord = pinCoordinate {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(CurrentsTheme.accent)
                                Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Change") {
                                    showingLocationPicker = true
                                }
                                .font(.caption)
                            }
                        } else {
                            Button {
                                showingLocationPicker = true
                            } label: {
                                Label("Choose location on map", systemImage: "map")
                            }
                        }
                    } else {
                        if let loc = appState.locationManager.currentLocation {
                            HStack {
                                Image(systemName: "location.fill")
                                    .foregroundStyle(CurrentsTheme.accent)
                                Text(String(format: "%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Label("Waiting for location...", systemImage: "location.slash")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if FeatureFlags.spotPrivacy {
                    Section {
                        Toggle("Private Spot", isOn: $isPrivate)
                    } footer: {
                        Text("Private spots are never shared.")
                    }
                }
            }
            .navigationTitle("New Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveSpot() }
                        .disabled(name.isEmpty)
                        .bold()
                }
            }
            .sheet(isPresented: $showingLocationPicker) {
                LocationPickerSheet(coordinate: $pinCoordinate)
            }
        }
    }

    private func saveSpot() {
        let lat: Double
        let lon: Double

        if usePin, let coord = pinCoordinate {
            lat = coord.latitude
            lon = coord.longitude
        } else if let location = appState.locationManager.currentLocation {
            lat = location.coordinate.latitude
            lon = location.coordinate.longitude
        } else {
            return
        }

        var spot = Spot(
            name: name,
            latitude: lat,
            longitude: lon,
            notes: notes.isEmpty ? nil : notes,
            isPrivate: isPrivate,
            spotType: spotType
        )
        try? appState.spotRepository.save(&spot)
        dismiss()
    }
}

// MARK: - Edit Spot Sheet (Full Field Editing)

struct EditSpotSheet: View {
    @Environment(\.dismiss) private var dismiss
    let spot: Spot
    let onSave: (Spot) -> Void

    @State private var name: String = ""
    @State private var notes: String = ""
    @State private var isPrivate: Bool = true
    @State private var spotType: Spot.SpotType = .general
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var showingLocationPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Spot Name", text: $name)
                    Picker("Type", selection: $spotType) {
                        ForEach(Spot.SpotType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Location") {
                    // Mini map preview of the (possibly moved) location
                    if let coord = coordinate {
                        Map(position: .constant(.camera(.init(
                            centerCoordinate: coord,
                            distance: 2500
                        )))) {
                            Annotation("", coordinate: coord) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(CurrentsTheme.accent)
                            }
                        }
                        .mapStyle(.hybrid)
                        .frame(height: 130)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .allowsHitTesting(false)
                        .listRowInsets(EdgeInsets())

                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(CurrentsTheme.accent)
                            Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Move on Map") {
                                showingLocationPicker = true
                            }
                            .font(.caption.bold())
                        }
                    }
                }

                if FeatureFlags.spotPrivacy {
                    Section {
                        Toggle("Private Spot", isOn: $isPrivate)
                    } footer: {
                        Text("Private spots are never shared.")
                    }
                }
            }
            .navigationTitle("Edit Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = spot
                        updated.name = name
                        updated.notes = notes.isEmpty ? nil : notes
                        updated.isPrivate = isPrivate
                        updated.type = spotType
                        if let coord = coordinate {
                            updated.latitude = coord.latitude
                            updated.longitude = coord.longitude
                            updated.geohash = Geohash.encode(
                                latitude: coord.latitude,
                                longitude: coord.longitude,
                                precision: 7
                            )
                        }
                        onSave(updated)
                        dismiss()
                    }
                    .bold()
                    .disabled(name.isEmpty)
                }
            }
            .sheet(isPresented: $showingLocationPicker) {
                LocationPickerSheet(coordinate: $coordinate)
            }
            .task {
                name = spot.name
                notes = spot.notes ?? ""
                isPrivate = spot.isPrivate
                spotType = spot.type
                if coordinate == nil {
                    coordinate = CLLocationCoordinate2D(
                        latitude: spot.latitude,
                        longitude: spot.longitude
                    )
                }
            }
        }
    }
}

// MARK: - Waterbody Pin

struct WaterbodyPin: View {
    let waterbody: Waterbody
    var biteScore: Int?
    var accent: Color = CurrentsTheme.accent

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.85))
                        .frame(width: 36, height: 36)
                        .shadow(color: accent.opacity(0.4), radius: 4, y: 2)

                    Image(systemName: waterbodyIcon)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                }

                if let score = biteScore {
                    Text("\(score)")
                        .font(.system(size: 9, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(CurrentsTheme.scoreColor(score))
                        .clipShape(Capsule())
                        .offset(x: 8, y: -6)
                }
            }
            Text(waterbody.name)
                .font(.system(size: 9).bold())
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .lineLimit(1)
        }
    }

    private var waterbodyIcon: String {
        switch waterbody.type {
        case .lake: "water.waves"
        case .dam: "water.waves.and.arrow.down"
        case .river: "arrow.left.arrow.right"
        case .estuary: "water.waves.slash"
        case .coast: "sailboat.fill"
        }
    }
}

// MARK: - Map Layers Sheet

/// Toggle the optional overlay layers. All off by default; choices persist via
/// @AppStorage in MapTab.
struct MapLayersSheet: View {
    @Binding var nautical: Bool
    @Binding var radar: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $nautical) {
                        Label("Nautical / Depth", systemImage: "water.waves")
                    }
                    Toggle(isOn: $radar) {
                        Label("Weather Radar", systemImage: "cloud.rain")
                    }
                } footer: {
                    Text("Nautical shows depth soundings, buoys and chart marks (OpenSeaMap). Weather radar shows live precipitation (RainViewer). Both need a connection to load new tiles; nautical tiles you've viewed are cached like the base map.")
                }
            }
            .navigationTitle("Map Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
