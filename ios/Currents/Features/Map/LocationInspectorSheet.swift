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
    @State private var isLoadingWater = true
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
                .pageWidth()
            }
            .detailScrollEdge()
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

        if weather != nil {
            GroupLabel("Conditions")
            ExploreConditions(weather: weather)
            if let reason = bite?.reasons.first {
                ExploreFootnote(ExploreFormat.sentence(reason))
            }
        }

        GroupLabel("Water nearby")
        if probableSpots.isEmpty {
            if isLoadingWater {
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
        if !ScreenshotSupport.isActive {
            await BundledMapData.importWaterIfNeeded(into: appState.db)
        }
        probableSpots = probableWater(baseScore: b.now)
        isLoadingWater = false

        // Outside the bundled area, top up from Overpass when online.
        if !BundledMapData.covers(minLat: waterBox.minLat, maxLat: waterBox.maxLat,
                                  minLon: waterBox.minLon, maxLon: waterBox.maxLon),
           let fresh = await OverpassService.shared.fetchWaterbodies(
               minLat: waterBox.minLat, maxLat: waterBox.maxLat,
               minLon: waterBox.minLon, maxLon: waterBox.maxLon
           ) {
            _ = try? appState.waterbodyRepository.insertFromOverpass(fresh)
            probableSpots = probableWater(baseScore: b.now)
        }

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
