import SwiftUI

/// Wrapper to avoid `Int64` collisions in navigationDestination.
struct SpeciesNavID: Hashable {
    let id: Int64
}

/// The species guide: every species, split into in season and out of season
/// for the chosen month, with search, habitat filter and sort. Pushed from
/// Explore (or shown in a sheet with its own stack). Replaces the old Field
/// Guide and Seasons segments.
struct SpeciesBrowserView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoomNamespace

    @State private var species: [Species] = []
    @State private var caughtIds: Set<Int64> = []
    @State private var loaded = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var month: Int = SpeciesSeason.currentMonth
    @State private var habitat: HabitatFilter = .all
    @AppStorage("seasonalSortOrder") private var sortOrder: SortOrder = .match

    // Cached so filtering 1,500 species doesn't re-run on every frame.
    @State private var scoresById: [Int64: [Int]] = [:]
    @State private var inSeason: [Species] = []
    @State private var offSeason: [Species] = []
    @State private var appeared = false

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
                DetailHeader(over: SpeciesSeason.hemisphereName, title: "Species guide", subtitle: subtitle)
                    .padding(.top, DS.Space.s2)

                monthChips
                    .padding(.top, DS.Space.s5)
                FilterChips(HabitatFilter.allCases, selection: $habitat) { $0.rawValue }
                    .padding(.top, DS.Space.s1)

                Label("Typical water in \(SpeciesSeason.fullMonths[month - 1]): \(Units.temperature(SpeciesSeason.waterTemp(for: month)))",
                      systemImage: "water.waves")
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s3)

                list
            }
            .padding(.bottom, DS.Space.s8)
        }
        .detailTint(DS.accent)
        .speciesScrollTitle("Species guide")
        .searchable(text: $searchText, prompt: "Search by name or family")
        .searchFocused($searchFocused)
        // Pulling past the top opens search with the keyboard up.
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top < -60
        } action: { wasPulled, isPulled in
            if isPulled, !wasPulled, !searchFocused {
                Haptics.tap()
                searchFocused = true
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort by", selection: $sortOrder) {
                        ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Button {
                        sortOrder = SortOrder.defaultOrder
                    } label: {
                        Label("Default sort (\(SortOrder.defaultOrder.rawValue.lowercased()))",
                              systemImage: "arrow.uturn.backward")
                    }
                    .disabled(sortOrder == SortOrder.defaultOrder)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort")
            }
        }
        .sensoryFeedback(.selection, trigger: sortOrder)
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
        .sensoryFeedback(.selection, trigger: month)
    }

    private var subtitle: String {
        guard loaded else { return "" }
        let month = SpeciesSeason.fullMonths[self.month - 1]
        return "\(species.count.formatted()) species, \(inSeasonTotal.formatted()) in season in \(month)"
    }

    /// In season this month across the whole guide, ignoring search and habitat.
    private var inSeasonTotal: Int {
        species.reduce(0) { $0 + (SpeciesSeason.isInSeason($1, month: month) ? 1 : 0) }
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
        } else if inSeason.isEmpty && offSeason.isEmpty {
            ContentUnavailableView("No species found", systemImage: "magnifyingglass",
                                   description: Text("Try the common name, the family or the scientific name."))
                .padding(.top, 40)
        } else {
            if !inSeason.isEmpty {
                groupLabel("In season in \(SpeciesSeason.fullMonths[month - 1])", count: inSeason.count)
                ForEach(Array(inSeason.enumerated()), id: \.element.id) { index, sp in
                    row(sp, index: index)
                }
            }
            if !offSeason.isEmpty {
                groupLabel("Out of season", count: offSeason.count)
                ForEach(Array(offSeason.enumerated()), id: \.element.id) { index, sp in
                    row(sp, index: inSeason.count + index)
                }
            }
        }
    }

    private func groupLabel(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text(count.formatted())
                .foregroundStyle(.dsText3)
        }
        .font(.subheadline)
        .foregroundStyle(.dsText2)
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s6)
        .padding(.bottom, DS.Space.s1)
        .accessibilityAddTraits(.isHeader)
    }

    private func row(_ sp: Species, index: Int) -> some View {
        let staggers = !reduceMotion && index < 12
        return NavigationLink(value: SpeciesRoute(species: sp)) {
            ArtRow(over: caughtIds.contains(sp.id) ? "In your Fishdex" : nil,
                   title: sp.commonName,
                   subtitle: rowSubtitle(sp)) {
                ThumbView(species: sp)
                    .matchedTransitionSource(id: sp.id, in: zoomNamespace)
            } trailing: {
                SeasonMiniBars(scores: scoresById[sp.id] ?? [], highlight: month, tint: sp.artTint)
            }
        }
        .buttonStyle(.dsRow)
        .opacity(appeared || !staggers ? 1 : 0)
        .offset(y: appeared || !staggers ? 0 : 14)
        .animation(staggers ? DS.Motion.easeOut.delay(Double(index) * 0.035) : nil, value: appeared)
    }

    private func rowSubtitle(_ sp: Species) -> String {
        [SpeciesSeason.habitatName(sp.habitat), SpeciesSeason.comfortText(sp, imperial: Units.isImperial)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    // MARK: - Data

    private func load() async {
        if species.isEmpty {
            species = (try? appState.speciesRepository.fetchAll()) ?? []
            var scores: [Int64: [Int]] = [:]
            scores.reserveCapacity(species.count)
            for sp in species { scores[sp.id] = SpeciesSeason.scores(sp) }
            scoresById = scores
        }
        caughtIds = (try? appState.speciesRepository.caughtSpeciesIds()) ?? []
        recompute()
        loaded = true
        if !appeared {
            // Let the first frame lay out before the rows rise in.
            try? await Task.sleep(for: .milliseconds(30))
            appeared = true
        }
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
            sorted = result.sorted { score($0) > score($1) }
        case .name:
            sorted = result.sorted { $0.commonName < $1.commonName }
        case .temp:
            sorted = result.sorted { ($0.optimalTempC ?? 0) < ($1.optimalTempC ?? 0) }
        }
        inSeason = sorted.filter { SpeciesSeason.isInSeason($0, month: month) }
        offSeason = sorted.filter { !SpeciesSeason.isInSeason($0, month: month) }
    }
}
