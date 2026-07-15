import SwiftUI

/// The "Cooler" — a Pokédex-style collection of every species in the app.
///
/// Uncaught species appear as greyed-out silhouettes; catching one fills it
/// in with colour. Sortable by rarity (default) or catalog number, filterable
/// by rarity tier and caught state.
struct FishCollectionView: View {
    @Environment(AppState.self) private var appState

    @State private var species: [Species] = []
    @State private var caughtIds: Set<Int64> = []
    @State private var searchText = ""
    @AppStorage("collectionSortMode") private var sort: SortMode = .rarest
    @State private var rarityFilter: SpeciesRarity?
    @State private var showCaughtOnly = false
    @State private var selected: Species?
    // Observed + read in the body so the accent-tinted % + progress bar
    // re-tint immediately on a theme change (CurrentsTheme.accent alone reads
    // UserDefaults without creating a view dependency).
    @AppStorage("selectedTheme") private var selectedTheme = ThemeOption.ocean.rawValue
    private var accent: Color { (ThemeOption(rawValue: selectedTheme) ?? .ocean).primary }

    enum SortMode: String, CaseIterable {
        case rarest = "Rarest"
        case number = "Number"
        case name = "Name"

        static let defaultMode: SortMode = .rarest
    }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    private var filtered: [Species] {
        var result = species
        if let rarity = rarityFilter {
            result = result.filter { $0.rarity == rarity }
        }
        if showCaughtOnly {
            result = result.filter { caughtIds.contains($0.id) }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.commonName.localizedCaseInsensitiveContains(searchText) ||
                $0.scientificName.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sort {
        case .rarest:
            // Rarest first; within a tier, caught ones first, then by name.
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
        NavigationStack {
            ScrollView {
                VStack(spacing: CurrentsTheme.paddingM) {
                    progressHeader
                    controls
                    grid
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("Collection")
            .searchable(text: $searchText, prompt: "Search species")
            .sensoryFeedback(.selection, trigger: sort)
            .sensoryFeedback(.selection, trigger: rarityFilter)
            .sensoryFeedback(.selection, trigger: showCaughtOnly)
            // No .refreshable here — the pull gesture fought with cell taps and
            // sheet swipe-downs, causing phantom "refreshes". Data reloads when
            // the detail sheet closes instead.
            .sheet(item: $selected, onDismiss: {
                Task { await load() }
            }) { sp in
                NavigationStack {
                    SpeciesDetailView(species: sp)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { selected = nil }
                            }
                        }
                }
                .presentationDragIndicator(.visible)
            }
            .task { await load() }
        }
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        let total = species.count
        let caught = caughtIds.intersection(Set(species.map(\.id))).count
        let pct = total > 0 ? Double(caught) / Double(total) : 0
        return VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(caught) / \(total)")
                        .font(.title2.bold())
                        .monospacedDigit()
                    Text("species collected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // One decimal so early progress isn't stuck at a flat 0% —
                // with 1,500+ species you'd need ~16 to even reach 1%.
                Text(String(format: "%.1f%%", pct * 100))
                    .font(.title.bold())
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }
            ProgressView(value: pct)
                .tint(accent)

            // Rarity breakdown
            HStack(spacing: 10) {
                ForEach(SpeciesRarity.allCases.reversed(), id: \.self) { rarity in
                    let caughtInTier = species.filter { $0.rarity == rarity && caughtIds.contains($0.id) }.count
                    let totalInTier = species.filter { $0.rarity == rarity }.count
                    if totalInTier > 0 {
                        VStack(spacing: 3) {
                            Image(systemName: rarity.symbol)
                                .font(.caption2)
                                .foregroundStyle(rarity.color)
                            Text("\(caughtInTier)/\(totalInTier)")
                                .font(.system(size: 10, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .glassCard()
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 8) {
            // Sort + caught toggle
            HStack {
                Menu {
                    ForEach(SortMode.allCases, id: \.self) { mode in
                        Button {
                            sort = mode
                        } label: {
                            Label(mode.rawValue, systemImage: sort == mode ? "checkmark" : "")
                        }
                    }
                    Divider()
                    Button {
                        sort = SortMode.defaultMode
                    } label: {
                        Label("Default (\(SortMode.defaultMode.rawValue))", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(sort == SortMode.defaultMode)
                } label: {
                    Label("Sort: \(sort.rawValue)", systemImage: "arrow.up.arrow.down")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showCaughtOnly.toggle() }
                } label: {
                    Label("Caught only", systemImage: showCaughtOnly ? "checkmark.circle.fill" : "circle")
                        .font(.caption.bold())
                        .foregroundStyle(showCaughtOnly ? CurrentsTheme.accent : .secondary)
                }
            }

            // Rarity filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", isSelected: rarityFilter == nil) {
                        withAnimation(.easeInOut(duration: 0.15)) { rarityFilter = nil }
                    }
                    ForEach(SpeciesRarity.allCases.reversed(), id: \.self) { rarity in
                        FilterChip(title: rarity.label, isSelected: rarityFilter == rarity) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                rarityFilter = rarityFilter == rarity ? nil : rarity
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Grid

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(filtered) { sp in
                Button {
                    Haptics.tap()
                    selected = sp
                } label: {
                    CollectionCell(species: sp, caught: caughtIds.contains(sp.id))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        species = (try? appState.speciesRepository.fetchAll()) ?? []
        caughtIds = (try? appState.speciesRepository.caughtSpeciesIds()) ?? []
    }
}

// MARK: - Collection Cell

private struct CollectionCell: View {
    let species: Species
    let caught: Bool

    var body: some View {
        VStack(spacing: 6) {
            SpeciesArtworkView(species: species, caught: caught, size: 72, fillWidth: true)
                .frame(maxWidth: .infinity)
                .frame(height: 76)

            Text(caught ? species.commonName : "???")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(caught ? .primary : .secondary)

            Text(String(format: "#%04d", species.id))
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .topTrailing) {
            Image(systemName: species.rarity.symbol)
                .font(.system(size: 9))
                .foregroundStyle(species.rarity.color)
                .padding(6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(caught ? species.rarity.color.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
    }
}
