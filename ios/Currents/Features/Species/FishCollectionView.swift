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
                if loaded && !species.isEmpty {
                    SectionTitle("By rarity")
                        .padding(.top, DS.Space.s6)
                    rarityBreakdown
                }
                FilterChips(Filter.allCases, selection: $filter) { $0.rawValue }
                    .padding(.top, DS.Space.s6)
                if rarityFilter != nil || sort != SortMode.defaultMode {
                    activeOptions
                        .padding(.top, DS.Space.s2)
                }
                grid
                    .padding(.top, DS.Space.s4)
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
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
        }
        .padding(.horizontal, DS.gutter)
    }

    // MARK: - Rarity

    private struct RarityCount: Identifiable {
        let rarity: SpeciesRarity
        let found: Int
        let total: Int
        var id: SpeciesRarity { rarity }
    }

    /// Found and total per tier, rarest first, skipping empty tiers.
    private var rarityCounts: [RarityCount] {
        var totals: [SpeciesRarity: Int] = [:]
        var found: [SpeciesRarity: Int] = [:]
        for sp in species {
            totals[sp.rarity, default: 0] += 1
            if caughtIds.contains(sp.id) { found[sp.rarity, default: 0] += 1 }
        }
        return SpeciesRarity.allCases.reversed().compactMap { rarity -> RarityCount? in
            guard let total = totals[rarity], total > 0 else { return nil }
            return RarityCount(rarity: rarity, found: found[rarity] ?? 0, total: total)
        }
    }

    /// One labelled tile per tier: found of total. Tapping a tile filters the
    /// grid to that tier; tapping it again clears the filter.
    private var rarityBreakdown: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: 3)
        return LazyVGrid(columns: columns, spacing: DS.Space.s2) {
            ForEach(rarityCounts) { tier in
                let selected = rarityFilter == tier.rarity
                Button {
                    rarityFilter = selected ? nil : tier.rarity
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: tier.rarity.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tier.rarity.color)
                            Text(tier.rarity.label)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.dsText2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(tier.found)")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.dsText)
                                .contentTransition(.numericText())
                            Text("of \(tier.total.formatted())")
                                .font(.footnote)
                                .foregroundStyle(.dsText2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .monospacedDigit()
                    }
                    .padding(.horizontal, DS.Space.s3)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                            .strokeBorder(tier.rarity.color, lineWidth: 2)
                            .opacity(selected ? 1 : 0)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                }
                .buttonStyle(.dim)
                .animation(.easeOut(duration: DS.Motion.fast), value: selected)
                .accessibilityLabel("\(tier.rarity.label), \(tier.found) of \(tier.total) found")
                .accessibilityHint(selected ? "Shows every rarity" : "Shows only \(tier.rarity.label.lowercased()) species")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
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
        // Size from the column width alone. Without this the grid offers a
        // shared row height, a cell with more text lines leaves less of it for
        // the tile, and the square shrinks to a narrow pill.
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(found
            ? "\(species.fishdexNumber), \(species.commonName), \(count) caught"
            : "\(species.fishdexNumber), not found yet")
    }

    /// A square as wide as the column. The art sits in overlays, which can
    /// never change the tile's size, so every tile matches.
    private var art: some View {
        RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
            .fill(Color.dsFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if found {
                    species.artTint.opacity(DS.thumbTintOpacity(scheme))
                }
            }
            .overlay {
                FishdexArt(species: species, found: found)
                    .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
    }
}

/// The species art in colour when found, or as a flat silhouette when not.
private struct FishdexArt: View {
    let species: Species
    let found: Bool

    var body: some View {
        if UIImage(named: species.artworkAssetName) != nil {
            // The same picture either way, so found and not found tiles
            // fill the square identically.
            if found {
                Image(species.artworkAssetName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(species.artworkAssetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.dsText.opacity(0.16))
            }
        } else {
            Image(systemName: "fish.fill")
                .resizable()
                .scaledToFit()
                .padding(16)
                .foregroundStyle(found ? species.artTint : Color.dsText.opacity(0.16))
        }
    }
}
