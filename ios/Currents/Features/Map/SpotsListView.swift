import SwiftUI
import MapKit

// MARK: - Your spots

/// Every saved spot, best bite today first. Pushed from Explore.
struct SpotsListView: View {
    @Environment(AppState.self) private var appState
    @State private var spots: [Spot] = []
    @State private var catchCounts: [String: Int] = [:]
    @State private var topSpecies: [String: Species] = [:]
    @State private var scores: [String: Int] = [:]
    @State private var loaded = false
    @State private var showingAddSpot = false
    @State private var searchText = ""

    private var filtered: [Spot] {
        let base = searchText.isEmpty ? spots : spots.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.notes ?? "").localizedCaseInsensitiveContains(searchText)
        }
        return base.sorted { (scores[$0.id] ?? -1, $1.name) > (scores[$1.id] ?? -1, $0.name) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                DetailHeader(over: "Saved on this phone", title: "Your spots",
                             subtitle: spots.isEmpty ? nil : "\(spots.count) \(spots.count == 1 ? "spot" : "spots"), best bite today first")
                    .padding(.bottom, DS.Space.s4)

                if loaded && spots.isEmpty {
                    ContentUnavailableView {
                        Label("No spots yet", systemImage: "mappin.slash")
                    } description: {
                        Text("Long press anywhere on the map, or save a spot when you log a catch.")
                    } actions: {
                        Button("Add a spot") { showingAddSpot = true }
                            .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                    }
                    .padding(.top, DS.Space.s8)
                } else {
                    ForEach(filtered) { spot in
                        NavigationLink(value: ExploreRoute.spot(SpotRef(spot))) {
                            row(spot)
                        }
                        .buttonStyle(.dsRow)
                    }
                    if !searchText.isEmpty && filtered.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search your spots")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Haptics.tap()
                    showingAddSpot = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add spot")
            }
        }
        .sheet(isPresented: $showingAddSpot, onDismiss: {
            Task { await loadData() }
        }) {
            AddSpotSheet()
                .presentationDetents([.large])
        }
        .task {
            await loadData()
        }
    }

    private func row(_ spot: Spot) -> some View {
        let count = catchCounts[spot.id] ?? 0
        var parts = [ExploreFormat.spotType(spot), "\(count) \(count == 1 ? "catch" : "catches")"]
        if FeatureFlags.spotPrivacy, spot.isPrivate { parts.append("private") }
        return ArtRow(title: spot.name, subtitle: parts.joined(separator: ", "), chevron: true) {
            if let sp = topSpecies[spot.id] {
                ThumbView(species: sp)
            } else {
                ThumbView(systemImage: spot.type.icon, tint: DS.accent)
            }
        } trailing: {
            if let score = scores[spot.id] {
                ScoreDisc(score: score, size: 40)
            }
        }
    }

    private func loadData() async {
        spots = (try? appState.spotRepository.fetchAll()) ?? []
        for spot in spots {
            let spotCatches = (try? appState.catchRepository.fetchForSpot(spot.id)) ?? []
            catchCounts[spot.id] = spotCatches.count
            let grouped = Dictionary(grouping: spotCatches.compactMap(\.species), by: \.id)
            topSpecies[spot.id] = grouped.values.max(by: { $0.count < $1.count })?.first
        }
        loaded = true
        for spot in spots where scores[spot.id] == nil {
            let c = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
            let w = await WeatherService.shared.current(for: c)
            scores[spot.id] = ForecastEngine.forecast(
                coordinate: c,
                currentPressureHpa: w?.pressureHpa,
                pressureChange6h: w?.pressureChange6h,
                waterTempC: w?.waterTempC,
                windSpeedKmh: w?.windSpeedKmh,
                windDirection: w?.windDirectionDeg,
                species: nil,
                isInSpawningZone: false
            ).score
        }
    }
}

// MARK: - Water

/// Dams, rivers and lakes around the angler, nearest first.
struct WaterListView: View {
    @Environment(AppState.self) private var appState
    @State private var waters: [(Waterbody, Double)] = []
    @State private var loaded = false
    @State private var filter: WaterFilter = .all

    enum WaterFilter: String, CaseIterable, Hashable {
        case all = "All", dams = "Dams", rivers = "Rivers", lakes = "Lakes", coast = "Coast and estuaries"
    }

    private var filtered: [(Waterbody, Double)] {
        waters.filter { wb, _ in
            switch filter {
            case .all: true
            case .dams: wb.type == .dam
            case .rivers: wb.type == .river
            case .lakes: wb.type == .lake
            case .coast: wb.type == .coast || wb.type == .estuary
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                DetailHeader(over: "Within your offline region", title: "Water",
                             subtitle: loaded ? "\(waters.count) dams, rivers and lakes" : nil)
                    .padding(.bottom, DS.Space.s3)

                FilterChips(WaterFilter.allCases, selection: $filter, title: { $0.rawValue })
                    .padding(.bottom, DS.Space.s3)

                if !loaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, DS.Space.s8)
                } else if filtered.isEmpty {
                    ContentUnavailableView {
                        Label("No water found", systemImage: "water.waves.slash")
                    } description: {
                        Text("No mapped water near you yet. Move the map over an area while online to load it.")
                    }
                    .padding(.top, DS.Space.s6)
                } else {
                    ForEach(Array(filtered.enumerated()), id: \.offset) { _, entry in
                        let (wb, distance) = entry
                        NavigationLink(value: ExploreRoute.waterbody(WaterbodyRef(wb))) {
                            ArtRow(title: wb.name,
                                   subtitle: "\(ExploreFormat.waterType(wb.type)), \(Units.distance(m: distance)) away",
                                   chevron: true) {
                                ThumbView(systemImage: ExploreFormat.waterIcon(wb.type),
                                          tint: Color.exploreWater)
                            } trailing: {
                                if let area = wb.surfaceAreaKm2, area > 0 {
                                    Text(ExploreFormat.area(area))
                                        .font(.subheadline)
                                        .foregroundStyle(.dsText2)
                                }
                            }
                        }
                        .buttonStyle(.dsRow)
                    }
                    ExploreFootnote("From OpenStreetMap, saved on this phone as you browse the map.")
                }
            }
            .padding(.bottom, 40)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private func load() {
        let c = appState.locationManager.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: -33.9, longitude: 18.4)
        let origin = CLLocation(latitude: c.latitude, longitude: c.longitude)
        let bodies = (try? appState.waterbodyRepository.fetchForRegion(
            minLat: c.latitude - 1, maxLat: c.latitude + 1,
            minLon: c.longitude - 1, maxLon: c.longitude + 1,
            minSurfaceAreaKm2: 0,
            includeNilArea: true,
            limit: 200
        )) ?? []
        waters = bodies
            .map { ($0, origin.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
            .sorted { $0.1 < $1.1 }
        loaded = true
    }
}

// MARK: - Boat ramps

/// Public boat ramps and fishing access points near the angler.
struct RampListView: View {
    @Environment(AppState.self) private var appState
    @StateObject private var rampService = BoatRampService.shared
    @State private var selectedRamp: BoatRamp?
    @State private var loading = false

    private var origin: CLLocationCoordinate2D? { appState.locationManager.currentLocation?.coordinate }

    private var sorted: [(BoatRamp, Double?)] {
        rampService.ramps.map { ramp in
            let d = origin.map {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                    .distance(from: CLLocation(latitude: ramp.lat, longitude: ramp.lon))
            }
            return (ramp, d)
        }
        .sorted { ($0.1 ?? .greatestFiniteMagnitude) < ($1.1 ?? .greatestFiniteMagnitude) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                DetailHeader(over: "From OpenStreetMap", title: "Boat ramps",
                             subtitle: rampService.ramps.isEmpty ? nil : "\(rampService.ramps.count) ramps and access points")
                    .padding(.bottom, DS.Space.s4)

                if rampService.ramps.isEmpty {
                    if loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, DS.Space.s8)
                    } else {
                        ContentUnavailableView {
                            Label("No ramps loaded", systemImage: "sailboat")
                        } description: {
                            Text("Turn on boat ramps in map layers and move the map while online to load them.")
                        }
                        .padding(.top, DS.Space.s6)
                    }
                } else {
                    ForEach(Array(sorted.enumerated()), id: \.offset) { _, entry in
                        let (ramp, distance) = entry
                        Button {
                            selectedRamp = ramp
                        } label: {
                            ArtRow(title: ramp.name,
                                   subtitle: distance.map { "\(ramp.kind.label), \(Units.distance(m: $0)) away" } ?? ramp.kind.label) {
                                ThumbView(systemImage: ramp.kind.icon, tint: .teal)
                            }
                        }
                        .buttonStyle(.dsRow)
                    }
                    ExploreFootnote("Fees and access change. Check at the gate.")
                }
            }
            .padding(.bottom, 40)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedRamp) { ramp in
            RampDetailSheet(ramp: ramp)
        }
        .task {
            guard rampService.ramps.isEmpty, let origin else { return }
            loading = true
            await rampService.load(around: origin, latSpan: 0.5)
            loading = false
        }
    }
}
