import SwiftUI

/// The Fishdex: every species in the app as a numbered grid. Species you have
/// caught show in colour with their name and catch count; the rest are
/// silhouettes marked "Not found yet". Tapping any of them opens its page.
/// Searchable by name or number, filterable by found and habitat, sortable,
/// with a rarity filter in the toolbar menu.
struct FishCollectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True when pushed into an existing NavigationStack (Logbook >
    /// Fishdex). Standalone it supplies its own.
    var embedded: Bool = false
    /// Optional first row inside the scroll view.
    var header: AnyView? = nil

    @Namespace private var zoomNamespace
    @State private var species: [Species] = []
    @State private var countById: [Int64: Int] = [:]
    @State private var caughtIds: Set<Int64> = []
    @State private var loaded = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var filter: Filter = .all
    @State private var rarityFilter: SpeciesRarity?
    @AppStorage("collectionSortMode") private var sort: SortMode = .number

    enum SortMode: String, CaseIterable {
        case rarest = "Rarest"
        case number = "Number"
        case name = "Name"

        static let defaultMode: SortMode = .number
    }

    enum Filter: String, CaseIterable, Hashable {
        case all = "All"
        case found = "Found"
        case freshwater = "Freshwater"
        case saltwater = "Saltwater"
    }

    private let columns = [GridItem(.flexible(), spacing: 12, alignment: .top),
                           GridItem(.flexible(), spacing: 12, alignment: .top),
                           GridItem(.flexible(), alignment: .top)]

    private var foundCount: Int { caughtIds.intersection(Set(species.map(\.id))).count }

    private var filtered: [Species] {
        var result = species
        switch filter {
        case .all: break
        case .found: result = result.filter { caughtIds.contains($0.id) }
        case .freshwater: result = result.filter { $0.habitat == .freshwater }
        case .saltwater: result = result.filter { $0.habitat == .marine || $0.habitat == .brackish }
        }
        if let rarity = rarityFilter {
            result = result.filter { $0.rarity == rarity }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            let digits = query.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            result = result.filter {
                $0.commonName.localizedCaseInsensitiveContains(query) ||
                $0.scientificName.localizedCaseInsensitiveContains(query) ||
                (!digits.isEmpty && $0.fishdexNumber.contains(digits))
            }
        }
        switch sort {
        case .rarest:
            // Rarest first; within a tier, found ones first, then by name.
            result.sort {
                if $0.rarity != $1.rarity { return $0.rarity > $1.rarity }
                let lc = caughtIds.contains($0.id), rc = caughtIds.contains($1.id)
                if lc != rc { return lc && !rc }
                return $0.commonName < $1.commonName
            }
        case .number:
            result.sort { $0.id < $1.id }
        case .name:
            result.sort { $0.commonName < $1.commonName }
        }
        return result
    }

    var body: some View {
        if embedded { content } else { NavigationStack { content } }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let header { header }
                DetailHeader(over: "Fishdex",
                             title: loaded ? "\(foundCount.formatted()) of \(species.count.formatted())" : "Fishdex",
                             subtitle: loaded ? progressText : nil)
                    .contentTransition(.numericText())
                    .padding(.top, DS.Space.s2)
                progress
                    .padding(.top, DS.Space.s4)
                FilterChips(Filter.allCases, selection: $filter) { $0.rawValue }
                    .padding(.top, DS.Space.s5)
                if rarityFilter != nil || sort != SortMode.defaultMode {
                    activeOptions
                        .padding(.top, DS.Space.s2)
                }
                grid
                    .padding(.top, DS.Space.s4)
            }
            .padding(.bottom, DS.Space.s8)
        }
        .detailTint(Color.dsScoreGood)
        .speciesScrollTitle("Fishdex")
        .searchable(text: $searchText, prompt: "Search \(species.count.formatted()) species")
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
            ToolbarItem(placement: .primaryAction) { optionsMenu }
        }
        .sensoryFeedback(.selection, trigger: sort)
        .sensoryFeedback(.selection, trigger: rarityFilter)
        .navigationDestination(for: SpeciesRoute.self) { route in
            SpeciesDetailView(species: route.species,
                              zoom: SpeciesZoomSource(id: route.species.id, namespace: zoomNamespace))
        }
        // Runs on every appear, so coming back from a species page (where a
        // catch may have been logged) refreshes the counts.
        .task { await load() }
    }

    private var progressText: String {
        let pct = species.isEmpty ? 0 : Double(foundCount) / Double(species.count) * 100
        // One decimal so early progress isn't stuck at a flat 0 percent.
        return String(format: "%.1f%% of species found", pct)
    }

    // MARK: - Progress

    private var progress: some View {
        let fraction = species.isEmpty ? 0 : Double(foundCount) / Double(species.count)
        let fresh = species.filter { $0.habitat == .freshwater && caughtIds.contains($0.id) }.count
        let salt = species.filter { $0.habitat != .freshwater && $0.habitat != nil && caughtIds.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.dsFill2)
                    Capsule().fill(Color.dsScoreGood)
                        .frame(width: fraction > 0 ? max(8, geo.size.width * fraction) : 0)
                }
            }
            .frame(height: 8)
            .animation(reduceMotion ? nil : DS.Motion.softSpring, value: fraction)
            .accessibilityElement()
            .accessibilityLabel("Fishdex progress")
            .accessibilityValue(progressText)

            HStack(spacing: DS.Space.s4) {
                splitLabel(fresh, "freshwater")
                splitLabel(salt, "saltwater")
                Spacer(minLength: 0)
            }

            // Found per rarity tier.
            HStack(spacing: DS.Space.s2) {
                ForEach(SpeciesRarity.allCases.reversed(), id: \.self) { rarity in
                    let total = species.filter { $0.rarity == rarity }.count
                    if total > 0 {
                        let found = species.filter { $0.rarity == rarity && caughtIds.contains($0.id) }.count
                        VStack(spacing: 3) {
                            Image(systemName: rarity.symbol)
                                .font(.caption)
                                .foregroundStyle(rarity.color)
                            Text("\(found)/\(total)")
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.dsText2)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(rarity.label): \(found) of \(total) found")
                    }
                }
            }
            .padding(.vertical, DS.Space.s3)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        }
        .padding(.horizontal, DS.gutter)
    }

    private func splitLabel(_ count: Int, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .fontWeight(.bold)
                .foregroundStyle(.dsText)
            Text(label)
                .foregroundStyle(.dsText2)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Options

    private var optionsMenu: some View {
        Menu {
            Picker("Sort by", selection: $sort) {
                ForEach(SortMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Rarity", selection: $rarityFilter) {
                Text("All rarities").tag(SpeciesRarity?.none)
                ForEach(SpeciesRarity.allCases.reversed(), id: \.self) { rarity in
                    Label(rarity.label, systemImage: rarity.symbol).tag(SpeciesRarity?.some(rarity))
                }
            }
            Divider()
            Button {
                sort = SortMode.defaultMode
                rarityFilter = nil
            } label: {
                Label("Reset sort and rarity", systemImage: "arrow.uturn.backward")
            }
            .disabled(sort == SortMode.defaultMode && rarityFilter == nil)
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .accessibilityLabel("Sort and filter")
    }

    /// Shows the menu's non-default choices so state isn't hidden behind it.
    private var activeOptions: some View {
        HStack(spacing: 6) {
            if sort != SortMode.defaultMode {
                SpeciesTag(text: "Sorted by \(sort.rawValue.lowercased())", systemImage: "arrow.up.arrow.down")
            }
            if let rarity = rarityFilter {
                Button {
                    rarityFilter = nil
                } label: {
                    SpeciesTag(text: rarity.label, systemImage: "xmark", tint: rarity.color)
                }
                .buttonStyle(.dim)
                .accessibilityLabel("Remove \(rarity.label) filter")
            }
        }
        .padding(.horizontal, DS.gutter)
    }

    // MARK: - Grid

    @ViewBuilder
    private var grid: some View {
        let list = filtered
        if !loaded {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else if species.isEmpty {
            ContentUnavailableView("No species data", systemImage: "fish",
                                   description: Text("Species will appear here once the guide has loaded."))
        } else if list.isEmpty {
            if filter == .found && searchText.isEmpty && rarityFilter == nil {
                ContentUnavailableView("Nothing found yet", systemImage: "book.closed",
                                       description: Text("Log a catch and the species joins your Fishdex."))
            } else {
                ContentUnavailableView("No species found", systemImage: "magnifyingglass",
                                       description: Text("Try the common or scientific name, or a Fishdex number."))
            }
        } else {
            LazyVGrid(columns: columns, spacing: DS.Space.s5) {
                ForEach(list) { sp in
                    NavigationLink(value: SpeciesRoute(species: sp)) {
                        FishdexCell(species: sp, count: countById[sp.id] ?? 0,
                                    found: caughtIds.contains(sp.id), zoomNamespace: zoomNamespace)
                    }
                    .buttonStyle(.dim)
                }
            }
            .padding(.horizontal, DS.gutter)
        }
    }

    private func load() async {
        if species.isEmpty {
            species = (try? appState.speciesRepository.fetchAll()) ?? []
        }
        caughtIds = (try? appState.speciesRepository.caughtSpeciesIds()) ?? []
        let bests = (try? appState.catchRepository.personalBests()) ?? []
        var counts: [Int64: Int] = [:]
        for pb in bests { counts[pb.speciesId] = pb.totalCatches }
        countById = counts
        loaded = true
    }
}

// MARK: - Cell

private struct FishdexCell: View {
    let species: Species
    let count: Int
    let found: Bool
    let zoomNamespace: Namespace.ID
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            art
                .matchedTransitionSource(id: species.id, in: zoomNamespace)
                .padding(.bottom, 6)
            Text(species.fishdexNumber)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.dsText2)
            Text(found ? species.commonName : "Not found yet")
                .font(.subheadline.weight(found ? .semibold : .regular))
                .foregroundStyle(found ? Color.dsText : Color.dsText2)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if found {
                Text(count == 1 ? "1 caught" : "\(count) caught")
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(found
            ? "\(species.fishdexNumber), \(species.commonName), \(count) caught"
            : "\(species.fishdexNumber), not found yet")
    }

    private var art: some View {
        ZStack {
            Color.dsFill
            if found {
                species.artTint.opacity(DS.thumbTintOpacity(scheme))
            }
            FishdexArt(species: species, found: found)
                .padding(10)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
    }
}

/// The species art in colour when found, or as a flat silhouette when not.
private struct FishdexArt: View {
    let species: Species
    let found: Bool

    var body: some View {
        if found {
            SpeciesArtworkView(species: species, caught: true, size: 90, fillWidth: true)
        } else if UIImage(named: species.artworkAssetName) != nil {
            Image(species.artworkAssetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.dsText.opacity(0.16))
        } else {
            Image(systemName: "fish.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.dsText.opacity(0.16))
        }
    }
}
