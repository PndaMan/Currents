import SwiftUI

/// The Fishdex: every species in the app as a numbered grid, laid out like
/// the Achievements page beside it in the Logbook. Species you have caught
/// show in colour with their name and catch count; the rest are silhouettes
/// marked "Not found yet". Tapping any of them opens its page. A rarity tally
/// that doubles as a filter, an in-page search by name or number, found and
/// habitat chips, and sort and rarity in the toolbar menu.
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
    /// Names two species share, which get the scientific name in the cell.
    @State private var repeatedNames = RepeatedNames()
    @State private var loaded = false
    @State private var appeared = false
    @State private var searchText = ""
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
        case estuary = "Estuary"
    }

    private let columns = [GridItem(.flexible(), spacing: 10, alignment: .top),
                           GridItem(.flexible(), spacing: 10, alignment: .top),
                           GridItem(.flexible(), alignment: .top)]

    private var foundCount: Int { caughtIds.intersection(Set(species.map(\.id))).count }

    private var filtered: [Species] {
        var result = species
        switch filter {
        case .all: break
        case .found: result = result.filter { caughtIds.contains($0.id) }
        case .freshwater: result = result.filter { $0.habitat == .freshwater }
        case .saltwater: result = result.filter { $0.habitat == .marine }
        case .estuary: result = result.filter { $0.habitat == .brackish }
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
                DetailHeader(title: "Fishdex",
                             subtitle: loaded ? "\(foundCount.formatted()) of \(species.count.formatted()) found" : nil)
                    .contentTransition(.numericText())

                if loaded && !species.isEmpty {
                    progress
                        .padding(.horizontal, DS.gutter)
                        .padding(.top, DS.Space.s4)
                    rarityTally
                        .padding(.horizontal, DS.gutter)
                        .padding(.top, DS.Space.s5)
                }

                PFSearchField(prompt: species.isEmpty ? "Search species" : "Search \(species.count.formatted()) species",
                              text: $searchText)
                    .padding(.top, DS.Space.s6)
                FilterChips(Filter.allCases, selection: $filter) { $0.rawValue }
                    .padding(.top, DS.Space.s2)
                if rarityFilter != nil || sort != SortMode.defaultMode {
                    activeOptions
                        .padding(.top, DS.Space.s1)
                }
                grid
                    .padding(.top, DS.Space.s4)
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .scrollDismissesKeyboard(.immediately)
        .detailTint(nil)
        .pageTitleFade("Fishdex")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { optionsMenu }
        }
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
        return VStack(alignment: .leading, spacing: DS.Space.s2) {
            LogbookProgressBar(fraction: appeared ? fraction : 0, tint: .dsScoreGood)
                .animation(reduceMotion ? nil : DS.Motion.easeOut, value: appeared)
            HStack(spacing: DS.Space.s4) {
                splitLabel(fresh, "freshwater")
                splitLabel(salt, "saltwater")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fishdex progress")
        .accessibilityValue("\(progressText). \(fresh) freshwater, \(salt) saltwater.")
    }

    private func splitLabel(_ count: Int, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.dsText)
            Text(label)
                .foregroundStyle(.dsText2)
        }
        .font(.footnote)
    }

    // MARK: - Rarity

    private struct RarityCount: Identifiable {
        let rarity: SpeciesRarity
        let found: Int
        let total: Int
        var id: SpeciesRarity { rarity }
    }

    /// Found and total per tier, commonest first, skipping empty tiers.
    private var rarityCounts: [RarityCount] {
        var totals: [SpeciesRarity: Int] = [:]
        var found: [SpeciesRarity: Int] = [:]
        for sp in species {
            totals[sp.rarity, default: 0] += 1
            if caughtIds.contains(sp.id) { found[sp.rarity, default: 0] += 1 }
        }
        return SpeciesRarity.allCases.compactMap { rarity -> RarityCount? in
            guard let total = totals[rarity], total > 0 else { return nil }
            return RarityCount(rarity: rarity, found: found[rarity] ?? 0, total: total)
        }
    }

    /// Found of total for each rarity with a bar in its colour, three across,
    /// the same tally as the Achievements page. Tapping a tier filters the
    /// grid to it; tapping it again clears the filter.
    private var rarityTally: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(rarityCounts) { tier in
                let selected = rarityFilter == tier.rarity
                Button {
                    withAnimation(DS.Motion.softSpring) {
                        rarityFilter = selected ? nil : tier.rarity
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tier.rarity.label)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.dsText2)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text("\(tier.found) of \(tier.total.formatted())")
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(.dsText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        RarityBar(fraction: appeared ? Double(tier.found) / Double(tier.total) : 0,
                                  tint: tier.rarity.color)
                            .animation(reduceMotion ? nil : DS.Motion.easeOut, value: appeared)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    // The chosen tier stays bright and the others step back.
                    .opacity(rarityFilter == nil || selected ? 1 : 0.45)
                }
                .buttonStyle(.dim)
                .buttonHaptic(.selection)
                .accessibilityLabel("\(tier.rarity.label), \(tier.found) of \(tier.total) found")
                .accessibilityHint(selected ? "Shows every rarity" : "Shows only \(tier.rarity.label.lowercased()) species")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: - Options

    private var optionsMenu: some View {
        Menu {
            Section("Sort by") {
                Picker("Sort by", selection: $sort.haptic()) {
                    ForEach(SortMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            Section("Rarity") {
                Picker("Rarity", selection: $rarityFilter.haptic()) {
                    Text("All rarities").tag(SpeciesRarity?.none)
                    ForEach(SpeciesRarity.allCases, id: \.self) { rarity in
                        Text(rarity.label).tag(SpeciesRarity?.some(rarity))
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .accessibilityLabel("Sort and rarity")
        .accessibilityValue("\(sort.rawValue), \(rarityFilter?.label ?? "all rarities")")
    }

    /// The menu's non-default choices as removable chips, as the Logbook
    /// shows its active filter, so state is never hidden behind the menu.
    private var activeOptions: some View {
        HStack(spacing: 6) {
            if let rarity = rarityFilter {
                Chip(rarity.label, systemImage: "xmark", isSelected: true) {
                    withAnimation(DS.Motion.softSpring) { rarityFilter = nil }
                }
                .accessibilityLabel("Showing \(rarity.label.lowercased()) species")
                .accessibilityHint("Shows every rarity")
            }
            if sort != SortMode.defaultMode {
                Chip("Sorted by \(sort.rawValue.lowercased())", systemImage: "xmark", isSelected: true) {
                    sort = SortMode.defaultMode
                }
                .accessibilityHint("Sorts by number again")
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, 4)
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
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(list) { sp in
                    NavigationLink(value: SpeciesRoute(species: sp)) {
                        FishdexCell(species: sp, count: countById[sp.id] ?? 0,
                                    found: caughtIds.contains(sp.id),
                                    nameRepeats: repeatedNames.contains(sp),
                                    zoomNamespace: zoomNamespace)
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
            FishdexNumbers.count(species)
            repeatedNames = RepeatedNames(species)
        }
        caughtIds = (try? appState.speciesRepository.caughtSpeciesIds()) ?? []
        let bests = (try? appState.catchRepository.personalBests()) ?? []
        var counts: [Int64: Int] = [:]
        for pb in bests { counts[pb.speciesId] = pb.totalCatches }
        countById = counts
        loaded = true
        appeared = true
    }
}

// MARK: - Rarity bar

/// A rarity tier's found share. The track carries the tier's own hue, so the
/// bar reads as a bar on the tile's fill even while little is found; the
/// found part is the full colour, at least a dot wide once anything is.
private struct RarityBar: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 8

    var body: some View {
        Capsule()
            .fill(tint.opacity(0.2))
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    let share = CGFloat(min(1, max(0, fraction)))
                    Capsule()
                        .fill(tint)
                        .frame(width: share > 0 ? max(height, geo.size.width * share) : 0)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Cell

/// One Fishdex entry: square art, number, name and catch count. The art is
/// on its colour like every species thumbnail when found, and a flat
/// silhouette on the fill when not. A found fish whose common name another
/// species shares also shows its scientific name.
private struct FishdexCell: View {
    let species: Species
    let count: Int
    let found: Bool
    let nameRepeats: Bool
    let zoomNamespace: Namespace.ID
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            art
                .matchedTransitionSource(id: species.id, in: zoomNamespace)
                .padding(.bottom, 4)
            Text(species.fishdexNumber)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.dsText3)
            Text(found ? species.commonName : "Not found yet")
                .font(.footnote.weight(found ? .semibold : .medium))
                .foregroundStyle(found ? Color.dsText : Color.dsText3)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                .multilineTextAlignment(.leading)
            if found && nameRepeats {
                Text(species.scientificName)
                    .font(.caption)
                    .foregroundStyle(.dsText2)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                    .multilineTextAlignment(.leading)
            }
            if found {
                Text(count == 1 ? "1 caught" : "\(count) caught")
                    .font(.caption)
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
            ? "\(species.fishdexNumber), \(spokenName), \(count) caught"
            : "\(species.fishdexNumber), not found yet")
    }

    private var spokenName: String {
        nameRepeats ? "\(species.commonName), \(species.scientificName)" : species.commonName
    }

    /// A square as wide as the column. The art sits in overlays, which can
    /// never change the tile's size, so every tile matches.
    private var art: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background {
                if found {
                    ZStack {
                        Color.dsBackground
                        species.artTint.opacity(DS.thumbTintOpacity(scheme))
                    }
                } else {
                    Color.dsFill
                }
            }
            .overlay {
                FishdexArt(species: species, found: found)
                    .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
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
                .foregroundStyle(found ? DS.ink(species.artTint) : Color.dsText.opacity(0.16))
        }
    }
}
