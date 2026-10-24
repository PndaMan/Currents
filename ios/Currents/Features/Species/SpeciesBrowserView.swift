import SwiftUI
import CoreLocation

/// Wrapper to avoid `Int64` collisions in navigationDestination.
struct SpeciesNavID: Hashable {
    let id: Int64
}

/// The species guide: every species, split into in season and out of season
/// for the chosen month (and the fish whose season is not known), with
/// search, habitat filter and sort. Pushed from
/// Explore (or shown in a sheet with its own stack). Replaces the old Field
/// Guide and Seasons segments.
struct SpeciesBrowserView: View {
    @Environment(AppState.self) private var appState
    @Namespace private var zoomNamespace

    @State private var species: [Species] = []
    @State private var caughtIds: Set<Int64> = []
    @State private var loaded = false
    @State private var searchText = ""
    @State private var month: Int = SpeciesSeason.currentMonth
    @State private var habitat: HabitatFilter = .all
    @AppStorage("seasonalSortOrder") private var sortOrder: SortOrder = .match

    /// The estimated water through the year at the forecast's place, read on
    /// each load. Starts from the time zone's hemisphere until then.
    @State private var water = SpeciesSeason.waterYear(latitude: nil)
    /// The water `scoresById` was worked out for.
    @State private var scoredWater: WaterYear?
    /// Best match puts local fish first: fish on record at the waters of the
    /// angler's spots, and at waters near the forecast's place.
    @State private var spotSpeciesIds: Set<Int64> = []
    @State private var nearbySpeciesIds: Set<Int64> = []

    // Cached so filtering 1,500 species doesn't re-run on every frame.
    @State private var scoresById: [Int64: [Int]] = [:]
    @State private var inSeason: [Species] = []
    @State private var offSeason: [Species] = []
    @State private var unknownSeason: [Species] = []

    enum SortOrder: String, CaseIterable, Identifiable {
        case match = "Best match"
        case name = "Name"
        case temp = "Optimal temperature"
        var id: String { rawValue }

        static let defaultOrder: SortOrder = .match
    }

    enum HabitatFilter: String, CaseIterable, Hashable {
        case all = "All"
        case freshwater = "Freshwater"
        case marine = "Saltwater"
        case brackish = "Estuary"

        var habitat: Species.Habitat? {
            switch self {
            case .all: nil
            case .freshwater: .freshwater
            case .marine: .marine
            case .brackish: .brackish
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                DetailHeader(over: loaded ? SpeciesSeason.hemisphereName(southern: water.southern) : nil,
                             title: "Species guide", subtitle: subtitle)

                PFSearchField(prompt: "Search by name or family", text: $searchText)
                    .padding(.top, DS.Space.s4)

                monthChips
                    .padding(.top, DS.Space.s2)

                FilterChips(HabitatFilter.allCases, selection: $habitat.haptic()) { $0.rawValue }
                    .padding(.top, DS.Space.s1)

                if sortOrder != SortOrder.defaultOrder {
                    Chip("Sorted by \(sortOrder.rawValue.lowercased())", systemImage: "xmark", isSelected: true) {
                        sortOrder = SortOrder.defaultOrder
                    }
                    .accessibilityHint("Sorts by best match again")
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s3)
                }

                list
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .scrollDismissesKeyboard(.immediately)
        .detailTint(nil)
        .pageTitleFade("Species guide")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Section("Sort by") {
                        Picker("Sort by", selection: $sortOrder.haptic()) {
                            ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort")
                .accessibilityValue(sortOrder.rawValue)
            }
        }
        .navigationDestination(for: SpeciesRoute.self) { route in
            SpeciesDetailView(species: route.species,
                              zoom: SpeciesZoomSource(id: route.species.id, namespace: zoomNamespace))
        }
        .task { await load() }
        .onChange(of: month) { _, _ in recompute() }
        .onChange(of: searchText) { _, _ in recompute() }
        .onChange(of: habitat) { _, _ in recompute() }
        .onChange(of: sortOrder) { _, _ in recompute() }
    }

    /// Month chips, scrolled so the chosen month starts in view.
    private var monthChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(1...12, id: \.self) { m in
                        Chip(SpeciesSeason.shortMonths[m - 1], isSelected: m == month) {
                            month = m
                        }
                        .id(m)
                        .accessibilityLabel(SpeciesSeason.fullMonths[m - 1])
                    }
                }
                .padding(.horizontal, DS.gutter)
                .padding(.vertical, 4)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onAppear { proxy.scrollTo(month, anchor: .center) }
            .onChange(of: month) { _, m in
                withAnimation(DS.Motion.easeOut) { proxy.scrollTo(m, anchor: .center) }
            }
        }
    }

    /// "210 of 1,568 in season in October, water about 16°C."
    private var subtitle: String? {
        guard loaded else { return nil }
        let name = SpeciesSeason.fullMonths[month - 1]
        let temp = Units.temperature(water.temp(month))
        return "\(inSeasonTotal.formatted()) of \(species.count.formatted()) in season in \(name), water about \(temp)."
    }

    /// In season this month across the whole guide, ignoring search and
    /// habitat. Fish whose season is not known never count.
    private var inSeasonTotal: Int {
        species.reduce(0) { $0 + (SpeciesSeason.isInSeason($1, month: month, water: water) ? 1 : 0) }
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if !loaded {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else if species.isEmpty {
            ContentUnavailableView("No species data", systemImage: "fish",
                                   description: Text("Species will appear here once the guide has loaded."))
                .padding(.top, 40)
        } else if inSeason.isEmpty && offSeason.isEmpty && unknownSeason.isEmpty {
            ContentUnavailableView("No species found", systemImage: "magnifyingglass",
                                   description: Text("Try the common name, the family or the scientific name."))
                .padding(.top, 40)
        } else {
            if !inSeason.isEmpty {
                SectionTitle("In season in \(SpeciesSeason.fullMonths[month - 1])", detail: inSeason.count.formatted())
                    .padding(.top, DS.Space.s6)
                ForEach(inSeason) { sp in row(sp) }
            }
            if !offSeason.isEmpty {
                SectionTitle("Out of season", detail: offSeason.count.formatted())
                    .padding(.top, DS.Space.s6)
                ForEach(offSeason) { sp in row(sp) }
            }
            if !unknownSeason.isEmpty {
                SectionTitle("Season not known", detail: unknownSeason.count.formatted())
                    .padding(.top, DS.Space.s6)
                ForEach(unknownSeason) { sp in row(sp) }
            }
        }
    }

    private func row(_ sp: Species) -> some View {
        NavigationLink(value: SpeciesRoute(species: sp)) {
            ArtRow(over: caughtIds.contains(sp.id) ? "In your Fishdex" : nil,
                   title: sp.commonName,
                   subtitle: rowSubtitle(sp),
                   chevron: true) {
                ThumbView(species: sp, size: 52)
                    .matchedTransitionSource(id: sp.id, in: zoomNamespace)
            } trailing: {
                SeasonMiniBars(scores: scoresById[sp.id] ?? [], highlight: month, tint: sp.artTint)
            }
        }
        .buttonStyle(.dsRow)
    }

    private func rowSubtitle(_ sp: Species) -> String {
        [SpeciesSeason.habitatName(sp.habitat), SpeciesSeason.comfortText(sp, imperial: Units.isImperial)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    // MARK: - Data

    private func load() async {
        // The forecast's place and its water, read on every appear rather
        // than once, so the season follows the place Today forecasts for.
        let place = SpeciesSeason.forecastCoordinate(appState)
        let year = await SpeciesSeason.waterYear(appState)
        if species.isEmpty {
            species = (try? appState.speciesRepository.fetchAll()) ?? []
            FishdexNumbers.count(species)
        }
        if scoredWater != year || scoresById.count != species.count {
            var scores: [Int64: [Int]] = [:]
            scores.reserveCapacity(species.count)
            for sp in species { scores[sp.id] = SpeciesSeason.scores(sp, water: year) }
            scoresById = scores
            scoredWater = year
        }
        water = year
        caughtIds = (try? appState.speciesRepository.caughtSpeciesIds()) ?? []
        spotSpeciesIds = speciesAtSpots()
        nearbySpeciesIds = place.map { speciesNear($0) } ?? []
        recompute()
        loaded = true
    }

    /// Fish on record at the waters the angler's spots are on.
    private func speciesAtSpots() -> Set<Int64> {
        let spots = (try? appState.spotRepository.fetchAll()) ?? []
        var ids: Set<Int64> = []
        for waterId in Set(spots.compactMap(\.waterbodyId)) {
            if let water = (try? appState.waterbodyRepository.fetch(id: waterId)) ?? nil {
                ids.formUnion(water.decodedFishSpeciesIds)
            }
        }
        return ids
    }

    /// Fish on record at waters within about 100 km of the forecast's place:
    /// the bundled GBIF list and any records downloaded since.
    private func speciesNear(_ place: CLLocationCoordinate2D) -> Set<Int64> {
        let latDelta = 100 / 111.0
        let lonDelta = 100 / (111.0 * max(cos(place.latitude * .pi / 180), 0.1))
        let waters = (try? appState.waterbodyRepository.fetchForRegion(
            minLat: place.latitude - latDelta, maxLat: place.latitude + latDelta,
            minLon: place.longitude - lonDelta, maxLon: place.longitude + lonDelta,
            limit: 2000)) ?? []
        return Set(waters.flatMap(\.decodedFishSpeciesIds))
    }

    /// How near the angler a fish is: caught, then on record at their
    /// spots, then near the forecast's place, then not known nearby.
    private func localRank(_ sp: Species) -> Int {
        if caughtIds.contains(sp.id) { return 0 }
        if spotSpeciesIds.contains(sp.id) { return 1 }
        if nearbySpeciesIds.contains(sp.id) { return 2 }
        return 3
    }

    /// Recompute the in and out of season lists. Runs only when an input
    /// changes (month, search, habitat, sort, data), not on every render.
    private func recompute() {
        var result = species
        if let h = habitat.habitat {
            result = result.filter { $0.habitat == h }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter {
                $0.commonName.localizedCaseInsensitiveContains(query) ||
                $0.scientificName.localizedCaseInsensitiveContains(query) ||
                ($0.family ?? "").localizedCaseInsensitiveContains(query)
            }
        }
        let monthIndex = month - 1
        let score: (Species) -> Int = { sp in
            let s = scoresById[sp.id] ?? []
            return monthIndex < s.count ? s[monthIndex] : 0
        }
        let sorted: [Species]
        switch sortOrder {
        case .match:
            // Fish known near the angler lead, best scoring first, then
            // the rest of the world's fish by score.
            sorted = result.sorted {
                let rankA = localRank($0), rankB = localRank($1)
                let localA = rankA < 3, localB = rankB < 3
                if localA != localB { return localA }
                let a = score($0), b = score($1)
                if a != b { return a > b }
                if rankA != rankB { return rankA < rankB }
                return $0.commonName < $1.commonName
            }
        case .name:
            sorted = result.sorted { $0.commonName < $1.commonName }
        case .temp:
            sorted = result.sorted { ($0.optimalTempC ?? 0) < ($1.optimalTempC ?? 0) }
        }
        let known = sorted.filter { SpeciesSeason.knowsSeason($0) }
        inSeason = known.filter { SpeciesSeason.isInSeason($0, month: month, water: water) }
        offSeason = known.filter { !SpeciesSeason.isInSeason($0, month: month, water: water) }
        unknownSeason = sorted.filter { !SpeciesSeason.knowsSeason($0) }
    }
}
