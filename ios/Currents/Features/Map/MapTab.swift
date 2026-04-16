import SwiftUI
import MapKit

/// Wrapper so CLLocationCoordinate2D can drive a .sheet(item:) binding.
struct IdentifiableCoordinate: Identifiable {
    let coord: CLLocationCoordinate2D
    var id: String { "\(coord.latitude),\(coord.longitude)" }
}

struct MapTab: View {
    @Environment(AppState.self) private var appState
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var spots: [Spot] = []
    @State private var catches: [CatchDetail] = []
    @State private var catchCounts: [String: Int] = [:]
    @State private var showingAddSpot = false
    @State private var selectedSpot: Spot?
    @State private var mapStyle: MapStyleOption = .fishing
    @State private var showCatchPins = true
    @State private var showingSpeciesBrowser = false
    @State private var showingForecast = false
    @State private var showingWeather = false
    @State private var weather: WeatherService.WeatherData?
    @State private var inspectorCoordinate: CLLocationCoordinate2D?
    @State private var spotScores: [String: Int] = [:]
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var needsRefresh = false
    @State private var showWaterbodies = true
    @State private var waterbodies: [Waterbody] = []
    @State private var waterbodyScores: [Int64: Int] = [:] // keyed by id ?? 0
    @State private var selectedWaterbody: Waterbody?
    @State private var isLoadingWaterbodies = false
    @State private var waterbodyDebounceTask: Task<Void, Never>?
    @State private var currentLatSpan: Double = 1.0 // track zoom level for rendering decisions

    enum MapStyleOption: String, CaseIterable {
        case standard = "Standard"
        case imagery = "Satellite"
        case hybrid = "Hybrid"
        case fishing = "Fishing"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()

                    // Spot pins
                    ForEach(spots) { spot in
                        Annotation(spot.name, coordinate: CLLocationCoordinate2D(
                            latitude: spot.latitude,
                            longitude: spot.longitude
                        )) {
                            SpotPin(
                                spot: spot,
                                catchCount: catchCounts[spot.id] ?? 0,
                                isSelected: selectedSpot?.id == spot.id,
                                biteScore: spotScores[spot.id]
                            )
                            .onTapGesture {
                                selectedSpot = spot
                            }
                        }
                    }

                    // Catch location pins (individual catches without spots)
                    if showCatchPins {
                        ForEach(catches.filter { $0.catchRecord.spotId == nil }, id: \.catchRecord.id) { detail in
                            Annotation(
                                detail.species?.commonName ?? "Catch",
                                coordinate: CLLocationCoordinate2D(
                                    latitude: detail.catchRecord.latitude,
                                    longitude: detail.catchRecord.longitude
                                )
                            ) {
                                CatchPin(detail: detail)
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
                                .foregroundStyle(CurrentsTheme.accent.opacity(0.2))
                                .stroke(CurrentsTheme.accent.opacity(0.6), lineWidth: 2)
                            }

                            Annotation(wb.name, coordinate: CLLocationCoordinate2D(
                                latitude: wb.latitude, longitude: wb.longitude
                            )) {
                                WaterbodyPin(
                                    waterbody: wb,
                                    biteScore: waterbodyScores[wb.id ?? 0]
                                )
                                .onTapGesture {
                                    selectedWaterbody = wb
                                }
                            }
                        }
                    }
                }
                .mapStyle(activeMapStyle)
                .mapControls {
                    MapCompass()
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    currentLatSpan = context.region.span.latitudeDelta
                    // Debounce: cancel prior pending load, wait 300ms before firing
                    waterbodyDebounceTask?.cancel()
                    waterbodyDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        await loadWaterbodies(region: context.region)
                    }
                }
                .onTapGesture(coordinateSpace: .local) { screenPoint in
                    if let coord = proxy.convert(screenPoint, from: .local) {
                        inspectorCoordinate = coord
                    }
                }
                } // MapReader

                // Right side control buttons
                VStack(spacing: 10) {
                    // Recentre on user
                    Button {
                        position = .userLocation(fallback: .automatic)
                    } label: {
                        mapButton(icon: "location.fill")
                    }

                    // Map style picker
                    Menu {
                        ForEach(MapStyleOption.allCases, id: \.self) { style in
                            Button {
                                mapStyle = style
                            } label: {
                                Label(style.rawValue, systemImage: mapStyleIcon(style))
                            }
                        }
                    } label: {
                        mapButton(icon: "map.fill")
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

                    // Forecast
                    Button {
                        showingForecast = true
                    } label: {
                        mapButton(icon: "cloud.sun.fill")
                    }
                }
                .padding(.top, 60)
                .padding(.trailing, 12)

                // Search overlay — pinned to top, above map scale
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search dams, rivers, places...", text: $searchText)
                            .textFieldStyle(.plain)
                            .onSubmit { performSearch() }
                            .onChange(of: searchText) { _, newValue in
                                searchDebounceTask?.cancel()
                                if newValue.isEmpty {
                                    searchResults = []
                                    return
                                }
                                searchDebounceTask = Task {
                                    try? await Task.sleep(for: .milliseconds(300))
                                    guard !Task.isCancelled else { return }
                                    performSearch()
                                }
                            }
                        if isSearching {
                            ProgressView()
                                .controlSize(.small)
                        }
                        if !searchText.isEmpty {
                            Button { searchText = ""; searchResults = [] } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: CurrentsTheme.cornerRadius))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .padding(.horizontal)

                    if !searchResults.isEmpty {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(searchResults, id: \.self) { item in
                                    Button {
                                        if let coord = item.placemark.location?.coordinate {
                                            position = .camera(.init(centerCoordinate: coord, distance: 2000))
                                        }
                                        searchResults = []
                                        searchText = item.name ?? ""
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "mappin.circle.fill")
                                                .foregroundStyle(.red)
                                                .font(.caption)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.name ?? "Unknown")
                                                    .font(.subheadline)
                                                    .foregroundStyle(.primary)
                                                if let subtitle = item.placemark.title {
                                                    Text(subtitle)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            Spacer()
                                            if let itemLocation = item.placemark.location,
                                               let userLocation = appState.locationManager.currentLocation {
                                                let distKm = itemLocation.distance(from: userLocation) / 1000
                                                Text(distKm < 100 ? String(format: "%.0f km", distKm) : String(format: "%.0f km", distKm))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                    }
                                    Divider()
                                }
                            }
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: CurrentsTheme.cornerRadius))
                        }
                        .frame(maxHeight: 250)
                        .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .top)

                // Bottom bar
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
            .sheet(item: $selectedSpot, onDismiss: {
                Task { await loadData() }
            }) { spot in
                SpotDetailSheet(spot: spot)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showingAddSpot, onDismiss: {
                Task { await loadData() }
            }) {
                AddSpotSheet()
                    .presentationDetents([.medium])
                    .presentationBackground(.ultraThinMaterial)
            }
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
            .task {
                await loadData()
            }
        }
    }

    @ViewBuilder
    private func mapButton(icon: String) -> some View {
        Image(systemName: icon)
            .font(.title3)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
    }

    private var activeMapStyle: MapStyle {
        switch mapStyle {
        case .standard: .standard(elevation: .realistic)
        case .imagery: .imagery(elevation: .realistic)
        case .hybrid: .hybrid(elevation: .realistic)
        case .fishing: .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll)
        }
    }

    private func mapStyleIcon(_ style: MapStyleOption) -> String {
        switch style {
        case .standard: "map"
        case .imagery: "globe.americas.fill"
        case .hybrid: "square.split.2x2"
        case .fishing: "fish.fill"
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        // Prefer natural features (dams, rivers, lakes)
        request.resultTypes = [.pointOfInterest, .address]

        // Bias results toward user's current location
        if let userLocation = appState.locationManager.currentLocation {
            request.region = MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: 200_000,
                longitudinalMeters: 200_000
            )
        }

        Task {
            let search = MKLocalSearch(request: request)
            let response = try? await search.start()
            var items = response?.mapItems ?? []

            // Sort by distance from user (closer first)
            if let userLocation = appState.locationManager.currentLocation {
                items.sort { a, b in
                    let distA = a.placemark.location?.distance(from: userLocation) ?? .greatestFiniteMagnitude
                    let distB = b.placemark.location?.distance(from: userLocation) ?? .greatestFiniteMagnitude
                    return distA < distB
                }
            }

            searchResults = items
            isSearching = false
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

        // Zoom-adaptive filtering — way fewer at zoom-out for performance + API savings
        let (minArea, limit, showNilArea): (Double, Int, Bool) = switch latSpan {
        case 20...:         (2000, 5, false)   // Continental: only Great Lakes-scale
        case 10..<20:       (500, 8, false)    // Very zoomed out: major bodies only
        case 5..<10:        (100, 15, false)   // Country level
        case 3..<5:         (20, 20, false)    // Regional
        case 1..<3:         (5, 30, false)     // State/province level
        case 0.5..<1:       (1, 40, false)     // Metro area
        case 0.2..<0.5:     (0.1, 50, true)    // City level — start showing small + unknown
        default:            (0, 60, true)      // Street level — show everything
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

        // 3) Only hit Overpass when zoomed in enough (< 1.5° span) to avoid API spam
        guard latSpan < 1.5 else {
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

// MARK: - Catch Pin (for individual catches on map)

struct CatchPin: View {
    let detail: CatchDetail

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(CurrentsTheme.accent)
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

// MARK: - Spot Pin

struct SpotPin: View {
    let spot: Spot
    let catchCount: Int
    let isSelected: Bool
    var biteScore: Int?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(isSelected ? CurrentsTheme.accent : .white)
                        .frame(width: 40, height: 40)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

                    if spot.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(isSelected ? .white : CurrentsTheme.accent)
                    } else {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(isSelected ? .white : CurrentsTheme.accent)
                    }
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
            }
            if catchCount > 0 {
                Text("\(catchCount)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(CurrentsTheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .offset(y: -4)
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
    let spot: Spot
    @State private var catches: [CatchDetail] = []
    @State private var weather: WeatherService.WeatherData?
    @State private var forecast: ForecastEngine.ForecastResult?
    @State private var showingDeleteConfirm = false
    @State private var showingEdit = false
    @State private var editedName = ""
    @State private var editedNotes = ""
    @State private var editedPrivate = true

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
                        if spot.isPrivate {
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
                                            .foregroundStyle(.cyan)
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
                        HStack(spacing: 12) {
                            StatCard(value: "\(catches.count)", label: "Catches", icon: "fish.fill")
                            let species = Set(catches.compactMap { $0.species?.commonName }).count
                            StatCard(value: "\(species)", label: "Species", icon: "leaf.fill")
                            if let best = catches.max(by: { ($0.catchRecord.weightKg ?? 0) < ($1.catchRecord.weightKg ?? 0) }),
                               let weight = best.catchRecord.weightKg {
                                StatCard(value: String(format: "%.1fkg", weight), label: "Best", icon: "trophy.fill")
                            }
                        }
                    }

                    if let notes = spot.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    // Actions
                    HStack(spacing: 12) {
                        Button {
                            editedName = spot.name
                            editedNotes = spot.notes ?? ""
                            editedPrivate = spot.isPrivate
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
                            CatchRow(detail: detail)
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
                dismiss()
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
    @State private var spotType: SpotType = .general
    @State private var usePin: Bool
    @State private var pinCoordinate: CLLocationCoordinate2D?
    @State private var showingLocationPicker = false

    init(prefillCoordinate: CLLocationCoordinate2D? = nil) {
        _usePin = State(initialValue: prefillCoordinate != nil)
        _pinCoordinate = State(initialValue: prefillCoordinate)
    }

    enum SpotType: String, CaseIterable {
        case general = "General"
        case structure = "Structure"
        case dropoff = "Drop-off"
        case weedbed = "Weed Bed"
        case point = "Point"
        case inlet = "Inlet/Outlet"
        case dock = "Dock/Pier"
        case reef = "Reef"
        case channel = "Channel"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Spot Name", text: $name)
                    Picker("Type", selection: $spotType) {
                        ForEach(SpotType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
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
                                    .foregroundStyle(.red)
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

                Section {
                    Toggle("Private Spot", isOn: $isPrivate)
                } footer: {
                    Text("Private spots are never shared.")
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

        let fullNotes = spotType == .general ? notes : "[\(spotType.rawValue)] \(notes)"
        var spot = Spot(
            name: name,
            latitude: lat,
            longitude: lon,
            notes: fullNotes.isEmpty ? nil : fullNotes,
            isPrivate: isPrivate
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
    @State private var latitude: String = ""
    @State private var longitude: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Spot Name", text: $name)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Location") {
                    HStack {
                        Text("Latitude")
                        Spacer()
                        TextField("0.0000", text: $latitude)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 140)
                    }
                    HStack {
                        Text("Longitude")
                        Spacer()
                        TextField("0.0000", text: $longitude)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 140)
                    }
                }

                Section {
                    Toggle("Private Spot", isOn: $isPrivate)
                } footer: {
                    Text("Private spots are never shared.")
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
                        if let lat = Double(latitude) { updated.latitude = lat }
                        if let lon = Double(longitude) { updated.longitude = lon }
                        onSave(updated)
                        dismiss()
                    }
                    .bold()
                    .disabled(name.isEmpty)
                }
            }
            .task {
                name = spot.name
                notes = spot.notes ?? ""
                isPrivate = spot.isPrivate
                latitude = String(format: "%.6f", spot.latitude)
                longitude = String(format: "%.6f", spot.longitude)
            }
        }
    }
}

// MARK: - Waterbody Pin

struct WaterbodyPin: View {
    let waterbody: Waterbody
    var biteScore: Int?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(CurrentsTheme.accent.opacity(0.85))
                        .frame(width: 36, height: 36)
                        .shadow(color: CurrentsTheme.accent.opacity(0.4), radius: 4, y: 2)

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
