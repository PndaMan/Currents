import SwiftUI

/// Wrapper to avoid `Int64` collisions in navigationDestination.
struct SpeciesNavID: Hashable {
    let id: Int64
}

struct SpeciesBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var species: [Species] = []
    @State private var caughtIds: Set<Int64> = []
    @State private var searchText = ""
    @State private var selectedHabitat: Species.Habitat?
    @State private var layout: Layout = .grid

    enum Layout { case grid, list }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var filtered: [Species] {
        var result = species
        if let habitat = selectedHabitat {
            result = result.filter { $0.habitat == habitat }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.commonName.localizedCaseInsensitiveContains(searchText) ||
                $0.scientificName.localizedCaseInsensitiveContains(searchText) ||
                ($0.family ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        return result.sorted { $0.commonName < $1.commonName }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: CurrentsTheme.paddingM) {
                filterBar
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No species found",
                        systemImage: "fish",
                        description: Text("Try a different search or filter.")
                    )
                    .padding(.top, 40)
                } else if layout == .grid {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filtered) { sp in
                            NavigationLink { SpeciesDetailView(species: sp) } label: {
                                SpeciesGuideCard(species: sp, caught: caughtIds.contains(sp.id))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { sp in
                            NavigationLink { SpeciesDetailView(species: sp) } label: {
                                SpeciesGuideRow(species: sp, caught: caughtIds.contains(sp.id))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .searchable(text: $searchText, prompt: "Search species, family…")
        .navigationTitle("Species Guide")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        layout = layout == .grid ? .list : .grid
                    }
                } label: {
                    Image(systemName: layout == .grid ? "list.bullet" : "square.grid.2x2")
                }
            }
        }
        .task {
            species = (try? appState.speciesRepository.fetchAll()) ?? []
            caughtIds = (try? appState.speciesRepository.caughtSpeciesIds()) ?? []
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", isSelected: selectedHabitat == nil) {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedHabitat = nil }
                    }
                    ForEach(Species.Habitat.allCases, id: \.self) { habitat in
                        FilterChip(
                            title: habitat.rawValue.capitalized,
                            isSelected: selectedHabitat == habitat
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedHabitat = selectedHabitat == habitat ? nil : habitat
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Text("\(filtered.count) species")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                let caught = caughtIds.intersection(Set(filtered.map(\.id))).count
                if caught > 0 {
                    Text("\(caught) caught")
                        .font(.caption.bold())
                        .foregroundStyle(CurrentsTheme.accent)
                }
            }
        }
    }
}

// MARK: - Guide Card (grid)

struct SpeciesGuideCard: View {
    let species: Species
    let caught: Bool

    var body: some View {
        // The guide is a reference, so every fish is shown in full colour
        // whether or not it's been caught. Rarity shows as the small tier
        // symbol in the corner, and the card only gains a rarity-coloured
        // border once the species has actually been caught.
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                SpeciesArtworkView(species: species, caught: true, size: 96)
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
                    .background(.secondary.opacity(0.06))

                Image(systemName: species.rarity.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .padding(6)
                    .foregroundStyle(species.rarity.color)

                if caught {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.white, CurrentsTheme.accent)
                        .padding(6)
                        .offset(y: 22)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(species.commonName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(species.scientificName)
                    .font(.caption2)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let habitat = species.habitat {
                        Text(habitat.rawValue.capitalized)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if let family = species.family {
                        Text("· \(family)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(caught ? species.rarity.color.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
    }
}

// MARK: - Guide Row (list)

struct SpeciesGuideRow: View {
    let species: Species
    let caught: Bool

    var body: some View {
        HStack(spacing: 12) {
            SpeciesArtworkView(species: species, caught: true, size: 48)
                .frame(width: 48, height: 48)
                .background(.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(species.commonName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text(species.scientificName)
                    .font(.caption2)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: species.rarity.symbol)
                    .font(.caption2.bold())
                    .foregroundStyle(species.rarity.color)
                if caught {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(CurrentsTheme.accent)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
