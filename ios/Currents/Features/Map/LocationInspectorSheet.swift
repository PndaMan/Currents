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
    /// Closes the sheet and pushes a page on the Explore stack.
    var onOpen: (ExploreRoute) -> Void = { _ in }

    @State private var weather: WeatherService.WeatherData?
    @State private var bite: BiteSnapshot?
    @State private var placeName: String?
    @State private var nearbySpots: [ScoredSpot] = []
    @State private var probableSpots: [ProbableSpot] = []
    @State private var observedFish: [ObservedSpeciesRepository.FishResult] = []
    @State private var isLoading = true
    @State private var showingSaveAsSpot = false

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
            }
            .background(Color.dsElevated.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .sheet(isPresented: $showingSaveAsSpot) {
                AddSpotSheet(prefillCoordinate: coordinate)
                    .presentationDetents([.large])
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.dsElevated)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(placeName ?? (isUserLocation ? "Near you" : "Dropped pin"))
                .font(.title2.bold())
                .foregroundStyle(.dsText)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            Text(isUserLocation ? "Your location" : ExploreFormat.coords(coordinate))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.dsText2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s2)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let bite {
            BiteBlock(
                score: bite.now,
                title: "\(ExploreFormat.verdict(bite.now)) right now",
                detail: bite.best.map { "Best \(ExploreFormat.window($0, use24Hour: use24HourTime)), peaking at \($0.peakScore)." }
                    ?? (bite.reasons.first ?? "No strong window left today.")
            )
            .padding(.top, DS.Space.s4)
        }

        ActionTriple {
            Button {
                Haptics.tap()
                showingSaveAsSpot = true
            } label: {
                Label("Save spot", systemImage: "mappin.and.ellipse")
            }
            .buttonStyle(ActionTileStyle(.primary))
            DirectionsMenu(coordinate: coordinate, name: placeName ?? "Dropped pin") {
                ActionTileLabel("Directions", systemImage: "location.north.line")
            }
            ShareLink(item: mapsURL) {
                ActionTileLabel("Share", systemImage: "square.and.arrow.up")
            }
        }
        .padding(.top, DS.Space.s4)

        if !observedFish.isEmpty {
            GroupLabel(isUserLocation ? "What is biting near you" : "What is biting here")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DS.Space.s3) {
                    ForEach(Array(observedFish.prefix(10).enumerated()), id: \.offset) { _, fish in
                        fishTile(fish)
                    }
                }
                .padding(.horizontal, DS.gutter)
            }
            ExploreFootnote("Recorded within 10 km, from iNaturalist and GBIF observations.")
        }

        if let weather {
            GroupLabel("Conditions")
            KVRow("Air", Units.temperature(weather.temperatureC))
            if let wt = weather.waterTempC {
                KVRow("Water", Units.temperature(wt))
            }
            KVRow("Wind", Units.speed(kmh: weather.windSpeedKmh))
            KVRow("Pressure", pressureText(weather), divider: false)
            if let reason = bite?.reasons.first {
                ExploreFootnote(reason)
            }
        }

        GroupLabel("Water nearby")
        if probableSpots.isEmpty {
            if isLoading {
                HStack(spacing: DS.Space.s2) {
                    ProgressView()
                    Text("Looking for water").foregroundStyle(.dsText2)
                }
                .padding(.horizontal, DS.gutter)
            } else {
                Text("No mapped dams, rivers or lakes near this point. Try closer to water.")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .padding(.horizontal, DS.gutter)
            }
        } else {
            ForEach(probableSpots.prefix(6)) { p in
                Button {
                    onOpen(.waterbody(WaterbodyRef(p.waterbody)))
                } label: {
                    ArtRow(title: p.name, subtitle: "\(p.reason), \(p.distanceString)", chevron: true) {
                        ThumbView(systemImage: ExploreFormat.waterIcon(p.waterbody.type),
                                  tint: Color.exploreWater, size: 48)
                    } trailing: {
                        Text("\(p.score)")
                            .foregroundStyle(DS.scoreInk(p.score))
                    }
                }
                .buttonStyle(.dsRow)
            }
        }

        if !nearbySpots.isEmpty {
            GroupLabel("Your spots nearby")
            ForEach(nearbySpots) { entry in
                Button {
                    onOpen(.spot(SpotRef(entry.spot)))
                } label: {
                    ArtRow(title: entry.spot.name,
                           subtitle: "\(entry.catchCount) \(entry.catchCount == 1 ? "catch" : "catches"), \(entry.distanceString)",
                           chevron: true) {
                        ThumbView(systemImage: entry.spot.type.icon, tint: DS.accent, size: 48)
                    }
                }
                .buttonStyle(.dsRow)
            }
        }
    }

    private func fishTile(_ fish: ObservedSpeciesRepository.FishResult) -> some View {
        let tile = VStack(alignment: .leading, spacing: 6) {
            if let sp = fish.localSpecies {
                ThumbView(species: sp, size: 96)
            } else {
                ThumbView(systemImage: "fish", tint: .gray, size: 96)
            }
            Text(fish.commonName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.dsText)
                .lineLimit(2)
            Text("\(fish.observationCount) \(fish.observationCount == 1 ? "record" : "records")")
                .font(.footnote)
                .foregroundStyle(.dsText2)
        }
        .frame(width: 96, alignment: .leading)

        return Group {
            if let sp = fish.localSpecies {
                Button { onOpen(.species(sp)) } label: { tile }
                    .buttonStyle(.dim)
            } else {
                tile
            }
        }
    }

    private func pressureText(_ w: WeatherService.WeatherData) -> String {
        let base = "\(Int(w.pressureHpa.rounded())) hPa"
        let change = String(format: "%.1f", abs(w.pressureChange6h))
        if w.pressureChange6h > 0.3 { return "\(base), rising \(change) in 6 h" }
        if w.pressureChange6h < -0.3 { return "\(base), falling \(change) in 6 h" }
        return "\(base), steady"
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

        // Nearby user spots and probable water
        let (nearby, probable) = await computeSpotInsights(baseScore: b.now)
        nearbySpots = nearby
        probableSpots = probable
        observedFish = await fishTask
        isLoading = false
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

    private func computeSpotInsights(baseScore: Int) async -> ([ScoredSpot], [ProbableSpot]) {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        // Nearby saved spots, shown in "Your spots nearby".
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

        // Probable fishing water: real dams/lakes/rivers around the tap
        // (OpenStreetMap-backed waterbody DB), not the user's saved spots.
        let delta = 0.45 // about 50 km
        let minLat = coordinate.latitude - delta
        let maxLat = coordinate.latitude + delta
        let minLon = coordinate.longitude - delta
        let maxLon = coordinate.longitude + delta

        func cachedBodies() -> [Waterbody] {
            (try? appState.waterbodyRepository.fetchForRegion(
                minLat: minLat, maxLat: maxLat,
                minLon: minLon, maxLon: maxLon,
                minSurfaceAreaKm2: 0,
                includeNilArea: true,
                limit: 200
            )) ?? []
        }

        var bodies = cachedBodies()

        // Top up from Overpass when online so we surface as many dams as possible.
        if let fresh = await OverpassService.shared.fetchWaterbodies(
            minLat: minLat, maxLat: maxLat,
            minLon: minLon, maxLon: maxLon
        ) {
            _ = try? appState.waterbodyRepository.insertFromOverpass(fresh)
            bodies = cachedBodies()
        }

        let probable = bodies
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

        return (Array(scored.prefix(5)), Array(probable))
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
