import SwiftUI
import MapKit
import PhotosUI

// MARK: - Your spots

/// Every saved spot, best bite today first. Pushed from Explore; a spot
/// opens back on the map in its sheet.
struct SpotsListView: View {
    @Environment(AppState.self) private var appState
    @State private var spots: [Spot] = []
    @State private var catchCounts: [String: Int] = [:]
    @State private var topSpecies: [String: Species] = [:]
    /// The newest catch photo taken at each spot.
    @State private var latestPhoto: [String: String] = [:]
    /// Catches with a photo at each spot, for the collage picture.
    @State private var photoCounts: [String: Int] = [:]
    /// The spot whose picture is being picked from the library.
    @State private var pictureSpot: Spot?
    @State private var choosingPhoto = false
    @State private var pickerItem: PhotosPickerItem?
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
                        Button { appState.pendingDeepLink = MapLink.spot(spot) } label: {
                            row(spot)
                        }
                        .buttonStyle(.dsRow)
                        .contextMenu { pictureMenu(spot) }
                    }
                    if !searchText.isEmpty && filtered.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
            .padding(.bottom, 40)
            .pageWidth()
        }
        .detailScrollEdge()
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
        .photosPicker(isPresented: $choosingPhoto, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item, let spot = pictureSpot else { return }
            pickerItem = nil
            usePhoto(item, for: spot)
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
            if spot.cover != .map {
                // The picture the angler chose.
                PlaceSnapshotThumb(spot: spot)
            } else if let path = latestPhoto[spot.id] {
                PhotoThumbnail(path: path, size: 64, cornerRadius: DS.Radius.thumb) {
                    spotArt(spot)
                }
            } else {
                spotArt(spot)
            }
        } trailing: {
            if let score = scores[spot.id] {
                ScoreDisc(score: score, size: 40)
            }
        }
    }

    /// Without a catch photo: the most caught species, else the map.
    @ViewBuilder
    private func spotArt(_ spot: Spot) -> some View {
        if let sp = topSpecies[spot.id] {
            ThumbView(species: sp)
        } else {
            PlaceSnapshotThumb(spot: spot)
        }
    }

    // MARK: Picture

    /// The spot's picture from a long press on its row: the same choices as
    /// the edit form, saved straight away.
    private func pictureMenu(_ spot: Spot) -> some View {
        Menu {
            SpotPictureMenu(cover: Binding(get: { spot.cover }, set: { setCover($0, of: spot) }),
                            hasPhoto: spot.coverPhotoPath != nil,
                            catchPhotos: photoCounts[spot.id] ?? 0) {
                pictureSpot = spot
                choosingPhoto = true
            }
        } label: {
            Label("Picture", systemImage: "photo")
        }
    }

    private func setCover(_ cover: Spot.Cover, of spot: Spot, photo: String? = nil) {
        var updated = spot
        if let photo { updated.coverPhotoPath = photo }
        updated.cover = cover
        do {
            try appState.spotRepository.save(&updated)
        } catch {
            ToastCenter.shared.show("Could not change the picture", style: .error)
            return
        }
        if let i = spots.firstIndex(where: { $0.id == spot.id }) { spots[i] = updated }
    }

    /// Stores the picked photo and makes it the picture, removing the photo
    /// it replaces.
    private func usePhoto(_ item: PhotosPickerItem, for spot: Spot) {
        Task {
            guard let path = await SpotCovers.store(item, spotId: spot.id) else {
                ToastCenter.shared.show("Could not use that photo", style: .error)
                return
            }
            setCover(.photo, of: spot, photo: path)
            if let old = spot.coverPhotoPath, old != path { PhotoManager.delete(old) }
            ToastCenter.shared.show("Picture updated", icon: "photo")
        }
    }

    private func loadData() async {
        spots = (try? appState.spotRepository.fetchAll()) ?? []
        for spot in spots {
            let spotCatches = (try? appState.catchRepository.fetchForSpot(spot.id)) ?? []
            catchCounts[spot.id] = spotCatches.count
            let grouped = Dictionary(grouping: spotCatches.compactMap(\.species), by: \.id)
            topSpecies[spot.id] = grouped.values.max(by: { $0.count < $1.count })?.first
            latestPhoto[spot.id] = spotCatches.lazy.compactMap { $0.catchRecord.allPhotoPaths.first }.first
            photoCounts[spot.id] = spotCatches.filter { !$0.catchRecord.allPhotoPaths.isEmpty }.count
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

/// Dams, rivers and lakes around the angler, nearest first. Each opens on
/// the map in its sheet.
struct WaterListView: View {
    @Environment(AppState.self) private var appState
    @State private var waters: [(Waterbody, Double)] = []
    @State private var loaded = false
    @State private var filter: WaterFilter = .all
    /// Water saved as a spot, which opens as that spot.
    @State private var savedIds: Set<Int64> = []

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
                DetailHeader(over: "Within about 100 km", title: "Water",
                             subtitle: loaded && !waters.isEmpty ? "\(waters.count) dams, rivers and lakes, nearest first" : nil)
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
                        Text("Nothing mapped near you yet. Move the map over an area while online to load it.")
                    }
                    .padding(.top, DS.Space.s6)
                } else {
                    ForEach(Array(filtered.enumerated()), id: \.offset) { _, entry in
                        let (wb, distance) = entry
                        Button { appState.pendingDeepLink = MapLink.water(wb) } label: {
                            ArtRow(title: wb.name,
                                   subtitle: waterSubtitle(wb, distance: distance),
                                   chevron: true) {
                                PlaceSnapshotThumb(water: wb)
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
                    ExploreFootnote("From OpenStreetMap, kept on this phone.")
                }
            }
            .padding(.bottom, 40)
            .pageWidth()
        }
        .detailScrollEdge()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        await BundledMapData.importWaterIfNeeded(into: appState.db)
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
        savedIds = Set(((try? appState.spotRepository.fetchAll()) ?? []).compactMap(\.waterbodyId))
        loaded = true
    }

    private func waterSubtitle(_ wb: Waterbody, distance: Double) -> String {
        let base = "\(ExploreFormat.waterType(wb.type)), \(Units.distance(m: distance)) away"
        guard let id = wb.id, savedIds.contains(id) else { return base }
        return "Your spot, \(base.prefix(1).lowercased())\(base.dropFirst())"
    }
}

// MARK: - Fishing access and ramps

/// Public fishing access points and boat ramps near the angler, nearest
/// first. Each opens on the map in its sheet.
struct RampListView: View {
    @Environment(AppState.self) private var appState
    @StateObject private var rampService = BoatRampService.shared
    @State private var loading = false
    @State private var filter: PlaceFilter = .all

    enum PlaceFilter: String, CaseIterable, Hashable {
        case all = "All", access = "Fishing access", ramps = "Boat ramps"
    }

    private var origin: CLLocationCoordinate2D {
        appState.locationManager.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: -33.9, longitude: 18.4)
    }

    private var sorted: [(BoatRamp, Double)] {
        let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        return rampService.ramps
            .filter { ramp in
                switch filter {
                case .all: true
                case .access: ramp.kind == .access
                case .ramps: ramp.kind == .ramp
                }
            }
            .map { ($0, here.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lon))) }
            .sorted { $0.1 < $1.1 }
    }

    private var countLine: String? {
        let access = rampService.ramps.filter { $0.kind == .access }.count
        let ramps = rampService.ramps.count - access
        guard access + ramps > 0 else { return nil }
        return "\(access) fishing access \(access == 1 ? "point" : "points"), \(ramps) \(ramps == 1 ? "ramp" : "ramps")"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                DetailHeader(over: "From OpenStreetMap", title: "Access and ramps", subtitle: countLine)
                    .padding(.bottom, DS.Space.s3)

                if !rampService.ramps.isEmpty {
                    FilterChips(PlaceFilter.allCases, selection: $filter, title: { $0.rawValue })
                        .padding(.bottom, DS.Space.s3)
                }

                if rampService.ramps.isEmpty {
                    if loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, DS.Space.s8)
                    } else {
                        ContentUnavailableView {
                            Label("Nothing loaded here", systemImage: "figure.fishing")
                        } description: {
                            Text("Move the map over an area while online to load its fishing access and ramps.")
                        }
                        .padding(.top, DS.Space.s6)
                    }
                } else {
                    ForEach(Array(sorted.prefix(150).enumerated()), id: \.offset) { _, entry in
                        let (ramp, distance) = entry
                        Button {
                            appState.pendingDeepLink = MapLink.ramp(ramp)
                        } label: {
                            ArtRow(title: ramp.name,
                                   subtitle: "\(ramp.kind.label), \(Units.distance(m: distance)) away") {
                                PlaceSnapshotThumb(place: ramp)
                            }
                        }
                        .buttonStyle(.dsRow)
                    }
                    ExploreFootnote("Fees and access change. Check at the gate.")
                }
            }
            .padding(.bottom, 40)
            .pageWidth()
        }
        .detailScrollEdge()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard rampService.ramps.isEmpty else { return }
            loading = true
            await rampService.load(around: origin, latSpan: 0.5)
            loading = false
        }
    }
}
