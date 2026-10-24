import SwiftUI
import MapKit
import CoreLocation

/// Sheet shown when the user taps anywhere on the map, or the "Biting near
/// you" capsule. Why (or why not) that point is worth fishing: the bite now,
/// what has been recorded there, conditions, water and saved spots nearby.
struct LocationInspectorSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("use24HourTime") private var use24HourTime = true

    let coordinate: CLLocationCoordinate2D
    var isUserLocation = false
    /// A name the caller already has for the point, such as a session stop.
    var title: String? = nil
    /// Closes the sheet. The map opens a spot or water as its place sheet
    /// and pushes anything else on the Explore stack.
    var onOpen: (ExploreRoute) -> Void = { _ in }
    /// A fish tapped under "Biting near you": the map narrows to the spots
    /// and waters where it is confirmed.
    var onShowSpecies: (Species) -> Void = { _ in }

    @State private var weather: WeatherService.WeatherData?
    @State private var bite: BiteSnapshot?
    @State private var placeName: String?
    @State private var nearbySpots: [ScoredSpot] = []
    @State private var probableSpots: [ProbableSpot] = []
    @State private var biting: [BitingFish] = []
    /// Recorded fish that are not in the species guide, so have no art or
    /// bite of their own.
    @State private var unlistedFish = 0
    @State private var isLoading = true
    @State private var isLoadingFish = true
    @State private var isLoadingWater = true
    @State private var showingSaveForm = false
    /// The spot saved here, from this sheet or before it opened. Once set,
    /// Save spot shows "Saved" and opens that spot instead of saving again.
    @State private var savedSpot: Spot?
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if isLoading && bite == nil {
                        SheetSkeleton().padding(.top, DS.Space.s5)
                    } else {
                        content
                            .transition(.opacity)
                    }
                }
                .padding(.bottom, DS.Space.s8)
                .pageWidth()
            }
            .detailScrollEdge()
            .background(Color.dsBackground.ignoresSafeArea())
            .exploreInlineTitle(heading)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    SheetDoneButton()
                }
            }
            .task { await load() }
            // The form is pushed inside this sheet rather than stacked on it.
            .navigationDestination(isPresented: $showingSaveForm) {
                AddSpotForm(prefillCoordinate: coordinate, isPushed: true) { spot in
                    savedSpot = spot
                    nearbySpots = savedSpotsNearby()
                }
            }
        }
        // The detent is bound so the form opens at full height.
        .dsSheet([.medium, .large], selection: $detent)
    }

    // MARK: - Header

    private var heading: String {
        title ?? placeName ?? (isUserLocation ? "Near you" : "Dropped pin")
    }

    /// Under a given title the place name, once found, replaces the coordinates.
    private var subheading: String {
        if isUserLocation { return "Your location" }
        if title != nil, let placeName { return placeName }
        return ExploreFormat.coords(coordinate)
    }

    /// The place sheet's header: name, then the bite now beside its ring.
    private var header: some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            DetailHeader(over: subheading, title: heading, subtitle: biteLine)
            if let bite {
                ScoreRing(score: bite.now, size: 88, caption: "now")
                    .padding(.trailing, DS.gutter)
            }
        }
        .padding(.top, DS.Space.s2)
    }

    /// "Excellent now. Best 06:00 to 09:00, peaking at 81."
    private var biteLine: String? {
        guard let bite else { return nil }
        let grade = "\(ForecastFormat.grade(bite.now)) now"
        let detail = bite.bestLine(use24: use24HourTime)
            ?? bite.reasons.first.map(ExploreFormat.sentence)
            ?? "No strong window left today"
        let line = "\(grade). \(detail)"
        return line.hasSuffix(".") ? line : line + "."
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ActionTriple {
            Button {
                // Saved here already: the tile opens that spot.
                if let savedSpot {
                    onOpen(.spot(SpotRef(savedSpot)))
                    return
                }
                guard !showingSaveForm else { return }
                detent = .large
                showingSaveForm = true
            } label: {
                Label(savedSpot == nil ? "Save spot" : "Saved",
                      systemImage: savedSpot == nil ? "bookmark" : "bookmark.fill")
            }
            .buttonStyle(ActionTileStyle(savedSpot == nil ? .primary : .tonal))
            .accessibilityHint(savedSpot == nil ? "Adds this place to your spots" : "Opens this spot")
            DirectionsMenu(coordinate: coordinate, name: heading) {
                ActionTileLabel("Directions", systemImage: "location.north.line")
            }
            ShareLink(item: mapsURL) {
                ActionTileLabel("Share", systemImage: "square.and.arrow.up")
            }
        }
        .padding(.top, DS.Space.s4)

        bitingSection

        if weather != nil {
            section {
                SectionTitle("Conditions")
                ExploreConditions(weather: weather)
            }
        }

        waterSection

        if !nearbySpots.isEmpty {
            section {
                SectionTitle("Your spots nearby")
                ForEach(nearbySpots) { entry in
                    Button {
                        onOpen(.spot(SpotRef(entry.spot)))
                    } label: {
                        ArtRow(title: entry.spot.name,
                               subtitle: "\(entry.catchCount) \(entry.catchCount == 1 ? "catch" : "catches"), \(entry.distanceString)",
                               chevron: true) {
                            PlaceSnapshotThumb(spot: entry.spot, size: 48)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
            }
        }
    }

    private var waterSection: some View {
        section {
            SectionTitle("Water nearby")
            if probableSpots.isEmpty {
                if isLoadingWater {
                    loadingRow("Looking for water")
                } else {
                    InlineEmpty(systemImage: "water.waves",
                                text: "No mapped dams, rivers or lakes near this point. Try closer to water.")
                }
            } else {
                ForEach(probableSpots.prefix(6)) { p in
                    Button {
                        onOpen(.waterbody(WaterbodyRef(p.waterbody)))
                    } label: {
                        ArtRow(title: p.name, subtitle: "\(p.reason), \(p.distanceString)", chevron: true) {
                            PlaceSnapshotThumb(water: p.waterbody, size: 48)
                        } trailing: {
                            Text("\(p.score)")
                                .foregroundStyle(DS.scoreInk(p.score))
                        }
                    }
                    .buttonStyle(.dsRow)
                }
            }
        }
    }

    // MARK: - Biting

    private var bitingSection: some View {
        section {
            SectionTitle(isUserLocation ? "Biting near you" : "Biting here")
            if isLoadingFish {
                loadingRow("Checking fish records near here")
            } else if biting.isEmpty {
                InlineEmpty(systemImage: "fish", text: bitingEmptyText)
            } else {
                ForEach(biting.prefix(8)) { fish in
                    fishRow(fish)
                }
                ExploreFootnote(bitingNote)
            }
        }
    }

    private func fishRow(_ fish: BitingFish) -> some View {
        Button { onShowSpecies(fish.species) } label: {
            ArtRow(over: "\(fish.records) \(fish.records == 1 ? "record" : "records") nearby",
                   title: fish.species.commonName,
                   subtitle: fish.why) {
                ThumbView(species: fish.species, size: 56)
            } trailing: {
                Text("\(fish.score)")
                    .foregroundStyle(DS.scoreInk(fish.score))
            }
        }
        .buttonStyle(.dsRow)
        .accessibilityHint("Shows the spots and waters where it is confirmed")
        .contextMenu {
            Button { onOpen(.species(fish.species)) } label: {
                Label("Open species page", systemImage: "book")
            }
        }
    }

    private var bitingEmptyText: String {
        if unlistedFish > 0 {
            return "Fish have been recorded near here, but none of them are in the species guide yet."
        }
        return "No fish records near here yet. They load from iNaturalist and GBIF when you have signal."
    }

    private var bitingNote: String {
        "Tap a fish to see where it is recorded."
    }

    // MARK: - Layout

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.top, DS.Space.s8)
    }

    /// Section loading, as the place page shows it.
    private func loadingRow(_ text: String) -> some View {
        FishLoader(message: text)
            .frame(minHeight: 90)
            .frame(maxWidth: .infinity)
    }

    private var mapsURL: URL {
        URL(string: "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)")!
    }

    // MARK: - Loading

    private func load() async {
        async let placeNameTask = reverseGeocode(coordinate)
        async let fishTask = appState.observedSpeciesRepository.fishNear(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            speciesRepository: appState.speciesRepository
        )

        let (b, w) = await BiteSnapshot.load(at: coordinate)
        withAnimation(DS.Motion.easeOut) {
            bite = b
            weather = w
        }

        placeName = await placeNameTask

        // Saved spots and mapped water come from the phone first, so the
        // list never waits on the network.
        nearbySpots = savedSpotsNearby()
        if savedSpot == nil, let here = nearbySpots.first(where: { $0.distanceMeters < 25 }) {
            savedSpot = here.spot
        }
        if !ScreenshotSupport.isActive {
            await BundledMapData.importWaterIfNeeded(into: appState.db)
        }
        probableSpots = probableWater(baseScore: b.now)
        isLoadingWater = false

        // The fish list does not wait on the water top-up.
        async let topUp: Void = topUpWater(baseScore: b.now)

        let fish = await fishTask
        biting = bitingFish(from: fish, weather: w)
        unlistedFish = Set(fish.filter { $0.localSpecies == nil }.map(\.scientificName)).count
        isLoadingFish = false

        await topUp
        isLoading = false
    }

    /// Outside the bundled area, tops up the water from Overpass when online.
    private func topUpWater(baseScore: Int) async {
        guard !BundledMapData.covers(minLat: waterBox.minLat, maxLat: waterBox.maxLat,
                                     minLon: waterBox.minLon, maxLon: waterBox.maxLon),
              let fresh = await OverpassService.shared.fetchWaterbodies(
                  minLat: waterBox.minLat, maxLat: waterBox.maxLat,
                  minLon: waterBox.minLon, maxLon: waterBox.maxLon
              ) else { return }
        _ = try? appState.waterbodyRepository.insertFromOverpass(fresh)
        probableSpots = probableWater(baseScore: baseScore)
    }

    /// Each recorded fish in the species guide, with its own bite now and the
    /// reason for it, best bite first. Two sources naming the same species
    /// count once.
    private func bitingFish(from fish: [ObservedSpeciesRepository.FishResult],
                            weather w: WeatherService.WeatherData?) -> [BitingFish] {
        var records: [Int64: (species: Species, count: Int)] = [:]
        for result in fish {
            guard let sp = result.localSpecies else { continue }
            let count = max(records[sp.id]?.count ?? 0, result.observationCount)
            records[sp.id] = (sp, count)
        }
        let rows = records.values.map { entry -> BitingFish in
            let result = forecast(for: entry.species, weather: w)
            return BitingFish(species: entry.species, records: entry.count,
                              score: result.score, why: Self.why(result, species: entry.species))
        }
        return rows.sorted { ($0.score, $0.records) > ($1.score, $1.records) }
    }

    private func forecast(for species: Species, weather w: WeatherService.WeatherData?) -> ForecastEngine.ForecastResult {
        ForecastEngine.forecast(
            coordinate: coordinate,
            currentPressureHpa: w?.pressureHpa,
            pressureChange6h: w?.pressureChange6h,
            waterTempC: w?.measured?.waterTempC,
            windSpeedKmh: w?.measured?.windSpeedKmh,
            windDirection: w?.measured?.windDirectionDeg,
            species: species,
            isInSpawningZone: false
        )
    }

    /// The reason that is about this fish (its water temperature, or feeding
    /// after dark), else the strongest general one.
    private static func why(_ result: ForecastEngine.ForecastResult, species: Species) -> String {
        let own = result.reasons.first { $0.contains(species.commonName) }
        let line = own ?? result.reasons.first ?? BiteWindows.guidance(forScore: result.score)
        return ExploreFormat.sentence(line)
    }

    private func reverseGeocode(_ coord: CLLocationCoordinate2D) async -> String? {
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(loc)
            if let p = placemarks.first {
                let parts = [p.locality ?? p.name, p.administrativeArea].compactMap { $0 }
                return parts.isEmpty ? nil : parts.joined(separator: ", ")
            }
        } catch {
            return nil
        }
        return nil
    }

    /// Saved spots within 30 km, nearest first.
    private func savedSpotsNearby() -> [ScoredSpot] {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let spots = (try? appState.spotRepository.fetchNearby(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusKm: 50
        )) ?? []

        let scored: [ScoredSpot] = spots.compactMap { spot in
            let loc = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
            let distM = origin.distance(from: loc)
            guard distM < 30_000 else { return nil }
            let count = (try? appState.catchRepository.fetchForSpot(spot.id))?.count ?? 0
            return ScoredSpot(spot: spot, distanceMeters: distM, catchCount: count)
        }
        .sorted { $0.distanceMeters < $1.distanceMeters }
        return Array(scored.prefix(5))
    }

    /// About 50 km around the point.
    private var waterBox: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        let delta = 0.45
        return (coordinate.latitude - delta, coordinate.latitude + delta,
                coordinate.longitude - delta, coordinate.longitude + delta)
    }

    /// Real dams, lakes and rivers around the point from the water database
    /// (bundled and OpenStreetMap), not the user's saved spots.
    private func probableWater(baseScore: Int) -> [ProbableSpot] {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let box = waterBox
        let bodies = (try? appState.waterbodyRepository.fetchForRegion(
            minLat: box.minLat, maxLat: box.maxLat,
            minLon: box.minLon, maxLon: box.maxLon,
            minSurfaceAreaKm2: 0,
            includeNilArea: true,
            limit: 400
        )) ?? []
        // A saved water is listed under your spots instead.
        let saved = Set(((try? appState.spotRepository.fetchAll()) ?? []).compactMap(\.waterbodyId))

        return bodies
            .filter { wb in wb.id.map { !saved.contains($0) } ?? true }
            .map { wb -> (Waterbody, Double) in
                let d = origin.distance(from: CLLocation(latitude: wb.latitude, longitude: wb.longitude))
                return (wb, d)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(15)
            .map { wb, distM -> ProbableSpot in
                // Bite score for the area, slightly decayed by distance.
                let score = max(5, min(100, baseScore - Int(distM / 1000 / 3)))
                return ProbableSpot(
                    id: "waterbody-\(wb.id ?? 0)-\(wb.name)",
                    name: wb.name,
                    score: score,
                    reason: probableReason(for: wb),
                    distanceMeters: distM,
                    waterbody: wb
                )
            }
    }

    private func probableReason(for wb: Waterbody) -> String {
        let typeLabel = ExploreFormat.waterType(wb.type)
        if let area = wb.surfaceAreaKm2, area > 0 {
            return "\(typeLabel), \(ExploreFormat.area(area))"
        }
        return typeLabel
    }
}

// MARK: - Supporting Types

private struct BitingFish: Identifiable {
    let species: Species
    let records: Int
    let score: Int
    let why: String

    var id: Int64 { species.id }
}

private struct ScoredSpot: Identifiable {
    let spot: Spot
    let distanceMeters: Double
    let catchCount: Int

    var id: String { spot.id }

    var distanceString: String { Units.distance(m: distanceMeters) }
}

private struct ProbableSpot: Identifiable {
    let id: String
    let name: String
    let score: Int
    let reason: String
    let distanceMeters: Double
    let waterbody: Waterbody

    var distanceString: String { Units.distance(m: distanceMeters) }
}
